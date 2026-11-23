// Research-only actor. NOT linked into the app: display snapshots, lifecycle,
// save/undo barriers and Qt ownership require separate integration.
#pragma once
#include <condition_variable>
#include <deque>
#include <exception>
#include <functional>
#include <mutex>
#include <thread>
#include <stdexcept>
class DeferredMaterialPrototype {
 std::mutex mutex;
 std::condition_variable ready,idle;
 std::deque<std::function<void()>> queue;
 const size_t limit;
 bool stopping=false,active=false;
 std::exception_ptr failure;
 std::thread worker;
 void run(){
  std::unique_lock<std::mutex> lock(mutex);
  for(;;){
   ready.wait(lock,[&]{return stopping||!queue.empty();});
   if(queue.empty()&&stopping)return;
   auto job=std::move(queue.front());queue.pop_front();active=true;
   lock.unlock();
   try{job();}catch(...){lock.lock();if(!failure)failure=std::current_exception();lock.unlock();}
   lock.lock();active=false;if(queue.empty())idle.notify_all();
  }
 }
public:
 explicit DeferredMaterialPrototype(size_t capacity):limit(capacity),worker([this]{run();}){}
 DeferredMaterialPrototype(const DeferredMaterialPrototype&)=delete;
 ~DeferredMaterialPrototype(){
  {std::lock_guard<std::mutex> lock(mutex);stopping=true;}
  ready.notify_one();worker.join();
 }
 // Refusal is explicit: caller retains the sample and must retry/pause input.
 // This prototype does not define production overflow recovery.
 bool trySubmit(std::function<void()> job){
  std::lock_guard<std::mutex> lock(mutex);
  if(stopping||failure||queue.size()>=limit)return false;
  queue.push_back(std::move(job));ready.notify_one();return true;
 }
 void drain(){
  std::unique_lock<std::mutex> lock(mutex);idle.wait(lock,[&]{return queue.empty()&&!active;});
  if(failure)std::rethrow_exception(failure);
 }
};
