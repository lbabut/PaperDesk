#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtCore/QCoreApplication>
#include <QtCore/QTemporaryDir>
#include <future>
#include <cassert>
#include <cstdio>
int main(int argc,char **argv){
 QCoreApplication app(argc,argv);QTemporaryDir folder;assert(folder.isValid());
 SketchRaster board(nullptr,folder.path(),folder.filePath("exports"),folder.filePath("permit"),false);
 board.resetWhite();assert(!board.penSamples.thread.joinable());
 assert(board.setDeferredResearchEnabled(true));
 std::promise<void> entered,resume;auto gate=resume.get_future().share();
 assert(board.researchWorker->trySubmit([&]{entered.set_value();gate.wait();}));entered.get_future().wait();
 auto original=std::atomic_load(&board.latency);
 assert(board.submitDeferredResearch(5,38,1,200,200,.7,220,210,.8,0));
 auto next=std::make_shared<SketchLatency>();std::atomic_store(&board.latency,next);
 resume.set_value();assert(board.flushDeferredResearch());
 assert(original->workerMaterial.calls==1&&original->workerPublish.calls==1);
 assert(next->workerMaterial.calls==0&&next->workerPublish.calls==0);
 board.pollDeferredResearch();
 assert(next->ownerTake.calls==1&&next->ownerApply.calls==1&&next->ownerNotify.calls==1);
 board.stopDeferredResearch();
 assert(next->workerClose.calls==1&&next->finalCopy.calls==0); // Detached lane never commits live pixels.
 board.setDeferredLiveEnabled(true);board.begin();
 assert(board.advancePenInput(5,38,1,200,200,.8,true,0,-.8));
 board.finish();auto stats=board.deferredStageStats();
 assert(stats["worker_material"].toMap()["calls"].toULongLong()==1);
 assert(stats["initial_copy"].toMap()["calls"].toULongLong()==1);
 assert(stats["final_copy"].toMap()["calls"].toULongLong()==1);
 assert(stats["final_drain"].toMap()["calls"].toULongLong()==1);
 assert(stats["worker_close"].toMap()["calls"].toULongLong()==1);
 board.begin();assert(board.deferredStageStats()["worker_material"].toMap()["calls"].toULongLong()==0);board.finish();
 puts("PASS stage scopes retain accepted worker owner across reset, separated transport/commit, hardware readers disabled");
}
