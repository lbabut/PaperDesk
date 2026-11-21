#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <thread>
int main(int argc,char **argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;
 SketchRaster r(nullptr,dir.path());r.penSamples.pause();r.penSamples.enableInput(true);
 int deliveries=0;unsigned samples=0,ends=0;
 QObject::connect(&r,&SketchRaster::penInputReady,[&]{
  deliveries++;
  auto events=r.takePenInput();assert(!events.isEmpty()&&events.size()<=24);
  for(auto v:events){auto e=v.toList();if(e[0].toInt()==3)ends++;else samples++;}
 });
 // One burst across many closed contacts must preserve all events while
 // duplicate producer/continuation notifications are coalesced.
 for(unsigned c=1;c<=100;c++){
  r.penSamples.frame(100,200,.1,c,0,0,false,true);
  r.penSamples.frame(101,201,.8,c,0,0,false,true);
  r.penSamples.frame(101,201,0,c,0,0,false,false);
 }
 for(int i=0;i<1000;i++)r.notifyPenInput();
 assert(r.penWakeQueued.load());
 for(int i=0;i<100&&r.penSamples.inputPending();i++)QCoreApplication::processEvents();
 QCoreApplication::processEvents();
 assert(samples==200&&ends==100&&deliveries==13&&!r.penSamples.inputPending());
 assert(!r.penWakeQueued.load());
 // A later contact must rearm after draining, including reader-thread wakes.
 std::thread producer([&]{r.penSamples.frame(200,300,.7,101,0,0,false,true);r.penSamples.frame(200,300,0,101,0,0,false,false);for(int i=0;i<1000;i++)r.notifyPenInput();});producer.join();
 QCoreApplication::processEvents();QCoreApplication::processEvents();
 assert(samples==201&&ends==101&&deliveries==14&&!r.penWakeQueued.load());
 // Empty stale callbacks must not invoke QML and must not lose a future wake.
 r.notifyPenInput();QCoreApplication::processEvents();assert(deliveries==14&&!r.penWakeQueued.load());
 r.penSamples.frame(300,400,.5,102,0,0,false,true);
 r.penSamples.pause();QCoreApplication::processEvents();assert(deliveries==14&&!r.penWakeQueued.load());
 r.penSamples.enableInput(true);r.penSamples.frame(300,400,0,102,0,0,false,false);
 r.penSamples.frame(301,401,.5,103,0,0,false,true);r.penSamples.frame(301,401,0,103,0,0,false,false);
 QCoreApplication::processEvents();assert(deliveries==15&&samples==202&&ends==102);
 assert(r.penInputStats()[1].toULongLong()==0);
 puts("PASS coalesced producer/continuation wakes, full contacts, rearm, empty callbacks and pause");
}
