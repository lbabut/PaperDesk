// Opt-in research executor. Batch only already queued commands; never wait to
// fill a batch. Control jobs are ordered barriers. No input is superseded.
#pragma once
#include "sketch-deferred-research.h"
#include <algorithm>
#include <vector>
#include <optional>
template<class Command> class SketchBatchResearchExecutor {
 struct Entry {std::optional<Command> command;std::function<void()> control;};
 std::mutex mutex;
 std::condition_variable ready,idle;
 std::deque<Entry> queue;
 size_t limit,batchLimit;
 bool stopping=false,active=false;
 std::exception_ptr failure;
 std::function<void(const std::vector<Command>&)> process;
 std::function<void()> idleNotify;
 std::thread worker;
 void run(){
  std::unique_lock<std::mutex> lock(mutex);
  for(;;){
   ready.wait(lock,[&]{return stopping||!queue.empty();});
   if(queue.empty()&&stopping)return;
   std::vector<Command> batch;std::function<void()> control;active=true;
   // Allocation is also inside the failure boundary: no silent worker exit.
   try{
    if(queue.front().command){
     batch.reserve(batchLimit);
     while(!queue.empty()&&queue.front().command&&batch.size()<batchLimit){
      batch.push_back(std::move(*queue.front().command));queue.pop_front();
     }
    }else{control=std::move(queue.front().control);queue.pop_front();}
    lock.unlock();if(control)control();else process(batch);lock.lock();
   }catch(...){
    if(!lock.owns_lock())lock.lock();
    if(!failure)failure=std::current_exception();
    queue.clear();stopping=true;
   }
   active=false;
   if(queue.empty()){
    idle.notify_all();
    // Notify outside the lock: the receiver may poll isIdle. The GUI callback
    // is queued, never a synchronous call into the owner from this thread.
    lock.unlock();
    try{if(idleNotify)idleNotify();}catch(...){
     lock.lock();if(!failure)failure=std::current_exception();queue.clear();stopping=true;idle.notify_all();lock.unlock();
    }
    lock.lock();
   }
  }
 }
 bool submit(Entry entry){
  std::lock_guard<std::mutex> lock(mutex);
  if(stopping||failure||queue.size()>=limit)return false;
  queue.push_back(std::move(entry));ready.notify_one();return true;
 }
public:
 SketchBatchResearchExecutor(size_t capacity,size_t batchSize,std::function<void(const std::vector<Command>&)> callback,std::function<void()> notify={})
 :limit(capacity),batchLimit(std::max(size_t(1),batchSize)),process(std::move(callback)),idleNotify(std::move(notify)),worker([this]{run();}){}
 SketchBatchResearchExecutor(const SketchBatchResearchExecutor&)=delete;
 ~SketchBatchResearchExecutor(){close();}
 bool trySubmitCommand(Command command){return submit({std::move(command),{}});}
 bool trySubmit(std::function<void()> control){return submit({{},std::move(control)});}
 bool isIdle(){std::lock_guard<std::mutex> lock(mutex);if(failure)std::rethrow_exception(failure);return queue.empty()&&!active;}
 void drain(){std::unique_lock<std::mutex> lock(mutex);idle.wait(lock,[&]{return queue.empty()&&!active;});if(failure)std::rethrow_exception(failure);}
 void close(){{std::lock_guard<std::mutex> lock(mutex);stopping=true;}ready.notify_one();if(worker.joinable())worker.join();}
};
