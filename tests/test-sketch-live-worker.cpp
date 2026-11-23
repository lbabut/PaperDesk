#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <future>
static void equal(SketchRaster &a,SketchRaster &b){
 assert(a.opticalDigest()==b.opticalDigest());assert(a.material==b.material&&a.finger==b.finger);
 assert(a.physics.burnish==b.physics.burnish&&a.physics.tooth==b.physics.tooth&&a.physics.ink==b.physics.ink&&a.physics.wear==b.physics.wear&&a.physics.untilNext==b.physics.untilNext);
}
int main(int argc,char **argv){QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 SketchRaster a(nullptr,dir.filePath("async")),b(nullptr,dir.filePath("sync"));a.setDeferredLiveEnabled(true);
 for(int stroke=0;stroke<4;stroke++){
  a.begin();b.begin();
  for(int i=0;i<320;i++){
   double x=120+2*i,y=700+90*std::sin(i*.2),p=.15+.8*(i%41)/40.,tx=.85*std::sin(i*.01),ty=.35;
   assert(a.advancePenInput(4+stroke%2,38,1,x,y,p,i==0,tx,ty)==b.advancePenInput(4+stroke%2,38,1,x,y,p,i==0,tx,ty));
   if(i==113){assert(a.saveCache(stroke,"midstroke")&&a.flushSaves());equal(a,b);}
  }
  a.finish();b.finish();equal(a,b);assert(!a.researchLive&&!a.researchWorker);
 }
 a.begin();b.begin();assert(a.advancePenInput(5,38,1,230,300,.8,true,.8,.3));assert(b.advancePenInput(5,38,1,230,300,.8,true,.8,.3));
 assert(a.save(dir.filePath("active.png")));equal(a,b);assert(QImage(dir.filePath("active.png"))==b.image);
 a.sharpen(5);b.sharpen(5);equal(a,b);a.finish();b.finish();
 a.begin(true);b.begin(true);a.advance(7,64,1,200,300,.7,true);b.advance(7,64,1,200,300,.7,true);assert(!a.researchLive);a.cancel();b.cancel();equal(a,b);
 a.begin();a.advancePenInput(5,38,1,300,400,.8,true,.8,.3);a.resetWhite();b.resetWhite();equal(a,b);
 a.begin();a.advancePenInput(5,38,1,300,400,.8,true,.8,.3);a.release();assert(a.image.isNull()&&!a.researchLive&&!a.researchWorker);
 // A deliberately stalled worker must not block the owner's completion poll
 // or falsely finalize a stroke. Keep an exact synchronous reference.
 a.resetWhite();b.resetWhite();a.begin();b.begin();
 a.advancePenInput(5,38,1,200,200,.8,true,.8,.3);b.advancePenInput(5,38,1,200,200,.8,true,.8,.3);
 std::promise<void> entered,release;auto gate=release.get_future().share();
 assert(a.researchWorker->trySubmit([&]{entered.set_value();gate.wait();}));entered.get_future().wait();
 a.advancePenInput(5,38,1,220,210,.9,false,.8,.3);b.advancePenInput(5,38,1,220,210,.9,false,.8,.3);
 QElapsedTimer elapsed;elapsed.start();for(int i=0;i<100;i++)assert(!a.tryFinish());assert(elapsed.elapsed()<50);
 assert(a.researchLive&&a.completionError().isEmpty());release.set_value();a.researchWorker->drain();
 assert(a.tryFinish());b.finish();equal(a,b);assert(!a.researchLive);
 const auto profile=a.deferredStats();
 assert(profile.value("profile_schema").toInt()==1&&profile.value("samples").toInt()==2);
 assert(profile.value("finish_polls").toULongLong()==101);
 assert(profile.value("worker_transport_calls").toULongLong()>=1);
 assert(profile.value("worker_transport_bytes").toULongLong()>0);
 assert(profile.value("worker_segment_us").toULongLong()>=profile.value("worker_segment_max_us").toULongLong());
 assert(profile.value("stop_total_us").toULongLong()>=profile.value("commit_buffers_us").toULongLong()+profile.value("commit_physics_us").toULongLong()+profile.value("cleanup_us").toULongLong());
 {
  SketchRaster failed(nullptr,dir.filePath("failed"));failed.setDeferredLiveEnabled(true);failed.begin();
  failed.advancePenInput(5,38,1,200,200,.8,true,.8,.3);
  assert(failed.researchWorker->trySubmit([]{throw std::runtime_error("injected worker fault");}));
  try{failed.researchWorker->drain();assert(false);}catch(const std::runtime_error&){}
  assert(!failed.tryFinish()&&!failed.completionError().isEmpty());
  auto path=dir.filePath("must-not-exist.png");assert(!failed.save(path)&&!QFile::exists(path));
  assert(!failed.saveCache(0,"partial")&&!failed.saveNotebook("{}",0,"partial"));
  assert(!failed.exportPng("partial").value("ok").toBool()&&!failed.exportPdf("partial").value("ok").toBool());
 } // Destruction after a worker failure must not throw or terminate.
 puts("PASS actual advancePenInput async: exact material/lifecycle plus nonblocking completion of stalled worker");
}
