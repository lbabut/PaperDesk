// Actual experimental SketchRaster backend. Private files/buffers only;
// hardware pen/touch readers explicitly disabled. No GUI/window or injection.
#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtCore/QCoreApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <cstdio>

static void equal(SketchRaster &a,SketchRaster &b){
 assert(a.image==b.image&&a.material==b.material&&a.finger==b.finger);
 assert(a.physics.burnish==b.physics.burnish&&a.physics.tooth==b.physics.tooth&&
        a.physics.ink==b.physics.ink&&a.physics.wear==b.physics.wear&&a.physics.untilNext==b.physics.untilNext&&
        a.physics.kneadedLift==b.physics.kneadedLift&&a.physics.kneadedContact==b.physics.kneadedContact);
}
int main(int argc,char **argv){
 QCoreApplication app(argc,argv);
 const bool paced=argc>1&&QString::fromLatin1(argv[1])=="paced";
 const bool drain=argc>1&&QString::fromLatin1(argv[1])=="blocking";
 const bool seeded=argc>2&&QString::fromLatin1(argv[2])=="seeded";
 const int count=1260;
 QTemporaryDir folder(QDir::tempPath()+"/sketch-worker-stage-XXXXXX");assert(folder.isValid());
 auto make=[&](const char *name){QString path=folder.filePath(name);return std::make_unique<SketchRaster>(nullptr,path,path+"/exports",path+"/permit",false);};
 auto owner=make("async"),reference=make("sync");owner->resetWhite();reference->resetWhite();
 assert(!owner->penSamples.thread.joinable()&&!reference->penSamples.thread.joinable());
 owner->setDeferredSeededTilesEnabled(seeded);
 owner->setDeferredLiveEnabled(true);owner->begin();reference->begin();
 QElapsedTimer clock;clock.start();qint64 submitMaxUs=0;
 for(int i=0;i<count;i++){
  double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  if(paced){
   const qint64 target=qint64(i)*2000000;
   while(clock.nsecsElapsed()<target){QCoreApplication::processEvents();std::this_thread::sleep_for(std::chrono::microseconds(100));}
  }
  QElapsedTimer one;one.start();assert(owner->advancePenInput(5,38,1,x,y,p,i==0,0,-.8));
  submitMaxUs=std::max(submitMaxUs,one.nsecsElapsed()/1000);
  if(i%24==0)QCoreApplication::processEvents();
 }
 const qint64 submittedUs=clock.nsecsElapsed()/1000;
 assert(owner->publishDeferredResearch());
 int polls=0;
 if(drain)owner->finish();
 else while(!owner->tryFinish()){
  owner->pollDeferredResearch();QCoreApplication::processEvents();polls++;
  assert(clock.elapsed()<60000);std::this_thread::sleep_for(std::chrono::milliseconds(1));
 }
 const qint64 completedUs=clock.nsecsElapsed()/1000;
 auto stats=owner->deferredStageStats();
 assert(stats["worker_material"].toMap()["calls"].toULongLong()==count);
 assert(stats["worker_publish"].toMap()["calls"].toULongLong()==54);
 assert(stats["final_copy"].toMap()["calls"].toULongLong()==1);
 assert(stats["worker_close"].toMap()["calls"].toULongLong()==1);
 assert(!owner->researchLive&&!owner->researchWorker);
 for(int i=0;i<count;i++){
  double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  assert(reference->advancePenInput(5,38,1,x,y,p,i==0,0,-.8));
 }
 reference->finish();equal(*owner,*reference);
 QVariantMap result{{"mode",paced?"absolute_500hz":drain?"burst_blocking_finish":"burst_poll_finish"},
  {"seeded_tiles",seeded},{"samples",count},{"submitted_us",submittedUs},{"completed_us",completedUs},
  {"after_last_submission_us",completedUs-submittedUs},{"max_submit_us",submitMaxUs},
  {"finish_polls",polls},{"stages",stats},{"exact_state",true},
  {"hardware_readers",false},{"gui_test",false},{"optical_timing",false}};
 auto output=QJsonDocument::fromVariant(result).toJson(QJsonDocument::Compact);puts(output.constData());
 // A new stroke must get a fresh counter owner; retain old snapshot for checks.
 const auto previous=std::atomic_load(&owner->latency);owner->begin();
 assert(owner->deferredStageStats()["worker_material"].toMap()["calls"].toULongLong()==0);
 assert(previous->workerMaterial.calls.load()==count);
 owner->finish();
}
