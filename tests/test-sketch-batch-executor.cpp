#include "../product/payload/apps/papersketch/native/sketch-batch-research.h"
#include <cassert>
#include <future>
#include <cstdio>
int main(){
 std::vector<int> seen;std::vector<size_t> sizes;
 SketchBatchResearchExecutor<int> worker(5,3,[&](const auto &batch){sizes.push_back(batch.size());for(int x:batch)seen.push_back(x);});
 std::promise<void> entered,release;auto gate=release.get_future().share();
 assert(worker.trySubmit([&]{entered.set_value();gate.wait();}));entered.get_future().wait();
 for(int i=0;i<5;i++)assert(worker.trySubmitCommand(i));
 assert(!worker.trySubmitCommand(5)&&!worker.isIdle());
 release.set_value();worker.drain();assert((seen==std::vector<int>{0,1,2,3,4}));assert((sizes==std::vector<size_t>{3,2}));
 assert(worker.trySubmit([&]{assert(seen.size()==5);seen.push_back(50);}));
 assert(worker.trySubmitCommand(6));worker.drain();assert((seen==std::vector<int>{0,1,2,3,4,50,6}));
 worker.close();assert(!worker.trySubmitCommand(7));
 // A batch exception is retained and all later queued work is refused/dropped;
 // no control job may publish the partial result after failure.
 bool published=false;std::promise<void> started,go;auto wait=go.get_future().share();
 SketchBatchResearchExecutor<int> failed(8,3,[](const auto &){throw std::runtime_error("batch injected failure");});
 assert(failed.trySubmit([&]{started.set_value();wait.wait();}));started.get_future().wait();
 assert(failed.trySubmitCommand(1));assert(failed.trySubmit([&]{published=true;}));
 go.set_value();try{failed.drain();assert(false);}catch(const std::runtime_error&){}
 assert(!published&&!failed.trySubmitCommand(2));
 try{failed.isIdle();assert(false);}catch(const std::runtime_error&){}
 failed.close();
 puts("PASS bounded batches, FIFO barriers, refusal, drain, close and fail-closed publication");
}
