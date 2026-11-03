#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <QtCore/QThread>
int main(int argc,char **argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;
 SketchRaster batched(nullptr,dir.path()+"/batched"),reference(nullptr,dir.path()+"/reference");
 batched.penSamples.pause();reference.penSamples.pause();batched.penSamples.enableInput(true);
 reference.begin();
 for(int i=0;i<600;i++){
  double x=150+i*.8,y=500+100*std::sin(i*.045),p=i?.65:0;
  batched.penSamples.frame(x,y,p,10,.2,-.1,false,true);
  reference.advancePenInput(1,5,1,x,y,p,i==0,.2,-.1);
 }
 batched.penSamples.frame(150+599*.8,500+100*std::sin(599*.045),0,10,.2,-.1,false,false);
 reference.finish();QThread::msleep(20);unsigned points=0,ends=0;
 while(batched.penSamples.inputPending()){
  const auto batch=batched.takePenInput();assert(batch.size()<=32);
  for(const auto &value:batch){
   auto e=value.toList();int phase=e[0].toInt();
   if(phase==1)batched.begin();
   if(phase==3){batched.finish();ends++;continue;}
   batched.advancePenInput(1,5,1,e[1].toDouble(),e[2].toDouble(),e[3].toDouble(),phase==1,e[4].toDouble(),e[5].toDouble());points++;
  }
 }
 assert(points==600&&ends==1&&batched.image==reference.image&&batched.material==reference.material);
 auto queue=batched.penQueueLatencyStats();
 assert(queue["samples"].toULongLong()==601&&queue["max_ms"].toULongLong()>=20);
 assert(queue["p95_upper_ms"].toULongLong()<=queue["max_ms"].toULongLong());
 assert(queue["batches"].toUInt()==19&&queue["empty_batches"].toUInt()==0);
 batched.takePenInput();assert(batched.penQueueLatencyStats()["empty_batches"].toUInt()==1);
 SketchRaster::PenQueueTiming tail;tail.record(-10);tail.record(2000);tail.record(4000);
 assert(tail.percentile(50)==4000&&tail.maxMs==4000&&tail.totalMs==6000);
 batched.resetPenQueueLatencyStats();assert(batched.penQueueLatencyStats()["samples"].toUInt()==0);
 // Overlay controls are excluded before GUI queuing, so a layout toggle
 // cannot reinterpret a delayed control tap as artwork.
 batched.penSamples.setInputExclusion(100,100,56,56);
 batched.penSamples.frame(110,110,.8,20,0,0,false,true);
 batched.penSamples.frame(200,200,.8,20,0,0,false,true);
 batched.penSamples.frame(200,200,0,20,0,0,false,false);
 assert(batched.takePenInput().isEmpty());
 batched.penSamples.frame(156,110,.8,21,0,0,false,true); // half-open edge is artwork
 batched.penSamples.frame(156,110,0,21,0,0,false,false);
 assert(batched.takePenInput().size()==2);
 batched.penSamples.setInputExclusion(0,0,0,0);
 // All short contacts leave a dot, despite a zero-pressure down and subpixel travel.
 batched.resetWhite();
 for(int i=0;i<80;i++){
  double x=100+(i%20)*20,y=100+(i/20)*20;
  batched.begin();batched.advancePenInput(1,3,1,x,y,0,true,0,0);
  batched.advancePenInput(1,3,1,x+.125,y,.8,false,0,0);batched.finish();
  assert(qGray(batched.image.pixel(int(x),int(y)))<250);
 }
 // Tiny reversals contribute distance instead of disappearing behind a .35px gate.
 batched.resetWhite();batched.begin();batched.advancePenInput(4,2,1,300,300,.4,true,0,0);
 int initial=qGray(batched.image.pixel(300,300));
 for(int i=0;i<400;i++)batched.advancePenInput(4,2,1,300+(i%2?.1:0),300,.4,false,0,0);
 batched.finish();assert(qGray(batched.image.pixel(300,300))<initial-5);
 puts("PASS complete 600-point curved path after GUI stall, 80 tiny contacts and subpixel reversals");
}
