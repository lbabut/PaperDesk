#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
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
 reference.finish();unsigned points=0,ends=0;
 while(batched.penSamples.inputPending()){
  for(const auto &value:batched.takePenInput()){
   auto e=value.toList();int phase=e[0].toInt();
   if(phase==1)batched.begin();
   if(phase==3){batched.finish();ends++;continue;}
   batched.advancePenInput(1,5,1,e[1].toDouble(),e[2].toDouble(),e[3].toDouble(),phase==1,e[4].toDouble(),e[5].toDouble());points++;
  }
 }
 assert(points==600&&ends==1&&batched.image==reference.image&&batched.material==reference.material);
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
