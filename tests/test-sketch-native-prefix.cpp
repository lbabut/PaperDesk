#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
struct State {
 bool active=false;unsigned contact=0;int tool=4,raw=0,changed=0,starts=0,ends=0,gaps=0,summarized=0;
 double x=0,y=0,p=0,low=0,high=0;
};
static void metadata(State&s,double x,double y,double p){s.x=std::floor(std::clamp(x,0.,1200.)*10+.5)/10;s.y=std::floor(std::clamp(y,0.,1600.)*10+.5)/10;s.p=std::floor(p*100+.5)/100;s.low=std::min(s.low,s.p);s.high=std::max(s.high,s.p);s.changed++;}
static void pump(SketchRaster&b,State&s,bool prefix,int selected){
 while(b.penSamples.inputPending()){
  auto events=prefix&&s.active?b.takePenBatch(s.tool,38,1,s.contact):b.takePenInput();
  for(auto value:events){auto e=value.toList();int phase=e[0].toInt();
   if(phase==5){assert(s.active&&e[8].toUInt()==s.contact);s.raw+=e[1].toInt();s.summarized+=e[1].toInt();if(e[2].toInt()){s.changed+=e[2].toInt();s.x=e[3].toDouble();s.y=e[4].toDouble();s.p=e[5].toDouble();s.low=std::min(s.low,e[6].toDouble());s.high=std::max(s.high,e[7].toDouble());}continue;}
   if(phase==4){if(s.active)b.finish();s.active=false;s.contact=0;s.gaps++;continue;}
   if(phase==1){if(s.active)b.finish();s.active=true;s.starts++;s.contact=e[7].toUInt();s.tool=e[6].toBool()?6:selected;b.begin(false,e[6].toBool());s.raw++;s.changed++;s.x=e[1].toDouble();s.y=e[2].toDouble();s.p=e[3].toDouble();s.low=s.high=s.p;b.advancePenInput(s.tool,38,1,s.x,s.y,s.p,true,e[4].toDouble(),e[5].toDouble());continue;}
   if(!s.active||s.contact!=e[7].toUInt())continue;
   if(phase==3){b.finish();s.active=false;s.contact=0;s.ends++;continue;}
   s.raw++;if(b.advancePenInput(s.tool,38,1,e[1].toDouble(),e[2].toDouble(),e[3].toDouble(),false,e[4].toDouble(),e[5].toDouble()))metadata(s,e[1].toDouble(),e[2].toDouble(),e[3].toDouble());
  }
 }
}
static void equal(SketchRaster&a,SketchRaster&b,const State&x,const State&y){
 assert(a.image==b.image&&a.material==b.material&&a.finger==b.finger);
 assert(a.physics.burnish==b.physics.burnish&&a.physics.wear==b.physics.wear&&a.physics.ink==b.physics.ink);
 assert(x.active==y.active&&x.contact==y.contact&&x.raw==y.raw&&x.changed==y.changed&&x.starts==y.starts&&x.ends==y.ends&&x.gaps==y.gaps);
 assert(x.x==y.x&&x.y==y.y&&x.p==y.p&&x.low==y.low&&x.high==y.high);
 // The explicit discontinuity increments the reader's gap/overflow counter.
 assert(a.penInputStats()[1].toUInt()==unsigned(x.gaps)&&b.penInputStats()[1].toUInt()==unsigned(y.gaps));
 assert(a.penInputStats()[2].toUInt()==0&&b.penInputStats()[2].toUInt()==0);
}
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;
 for(int tool:{1,4,5,6,8}){
  SketchRaster a(nullptr,dir.path()+"/a"),b(nullptr,dir.path()+"/b");State x,y;
  a.penSamples.pause();b.penSamples.pause();a.penSamples.enableInput(true);b.penSamples.enableInput(true);
  auto frame=[&](double px,double py,double p,bool down,bool eraser=false){a.penSamples.frame(px,py,p,10,.3,-.8,eraser,down);b.penSamples.frame(px,py,p,10,.3,-.8,eraser,down);};
  for(int i=0;i<600;i++)frame(120+i*.8,500+70*std::sin(i*.07),i?(.0137+(i%19)*.047):0,true);
  frame(599*.8+120,500+70*std::sin(599*.07),0,false);
  for(int i=0;i<40;i++){frame(100+i*10,700,.6,true,i%3==0);frame(100+i*10,700,0,false,i%3==0);}
  pump(a,x,true,tool);pump(b,y,false,tool);equal(a,b,x,y);assert(x.summarized>500&&x.raw==640&&x.starts==41&&x.ends==41);
  for(int i=0;i<72;i++)frame(400+i*.1,800,.7,true);
  pump(a,x,true,tool);pump(b,y,false,tool);equal(a,b,x,y);
  a.penSamples.discontinuity();b.penSamples.discontinuity();pump(a,x,true,tool);pump(b,y,false,tool);equal(a,b,x,y);assert(x.gaps==1&&!x.active);
  frame(400,800,0,false);frame(450,850,.3,true);frame(450,850,0,false);pump(a,x,true,tool);pump(b,y,false,tool);equal(a,b,x,y);
 }
 puts("PASS native prefix: exact pigment/image/wear/ink and endpoint/count/pressure metadata; boundaries, eraser transitions, gaps, no loss");
}
