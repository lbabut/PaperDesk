// Isolated Qt raster-window harness, NOT production Sketch or a tablet app.
#include "sketch-deferred-prototype.h"
#include "sketch-dirty-tiles-prototype.h"
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <QtGui/QGuiApplication>
#include <QtGui/QWindow>
#include <QtGui/QBackingStore>
#include <QtGui/QPainter>
#include <QtCore/QTimer>
#include <QtCore/QElapsedTimer>
#include <atomic>
#include <cassert>
#include <cstdio>
struct Surface{
 PaperMaterial e;std::vector<uint32_t> m,im;std::vector<uint16_t> f;
 Surface():m(1200*1600),im(m.size(),0xffffffffu),f(82*81){e.init(1200,1600);e.tiltX=.85;e.tiltY=.35;e.contactAspect=2;e.contactAngle=.3;}
};
struct Sample{double ax,ay,ap,x,y,p;int i;};
int main(int argc,char **argv){
 QGuiApplication app(argc,argv);bool sync=app.arguments().contains("--sync"),paced=app.arguments().contains("--paced"),batch24=app.arguments().contains("--batch24");
 Surface actual,reference;DirtyTilesPrototype tiles(1200,1600);DeferredMaterialPrototype worker(2048);
 std::vector<Sample> samples;double px=120,py=900,pp=.55;
 for(int i=0;i<1260;i++){double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;samples.push_back({px,py,pp,x,y,p,i});px=x;py=y;pp=p;}
 QWindow window;window.setSurfaceType(QSurface::RasterSurface);window.resize(1200,1600);window.create();window.show();
 QBackingStore backing(&window);backing.resize(window.size());
 std::vector<uint32_t> canvas(1200*1600,0xffffffffu);std::atomic<bool> done{false};
 int applied=0,submitted=0,frames=0;uint64_t displayed=0;bool measuring=false;QElapsedTimer clock;
 qint64 lastBeat=0,maxGap=0,submitMax=0,started=0,finished=0;QTimer heartbeat,publisher,feed;
 auto paint=[&]{auto batch=tiles.take();if(!batch.revision)return;
  assert(tiles.apply(batch,canvas,1));QRegion damage;
  for(auto &entry:batch.tiles){int tx=entry.first%10,ty=entry.first/10;damage+=QRect(tx*128,ty*128,std::min(128,1200-tx*128),std::min(128,1600-ty*128));}
  if(!damage.isEmpty()){
   backing.beginPaint(damage);QPainter painter(backing.paintDevice());
   QImage image(reinterpret_cast<const uchar*>(canvas.data()),1200,1600,1200*4,QImage::Format_RGB32);
   for(const auto &rect:damage)painter.drawImage(rect,image,rect);
   painter.end();backing.endPaint();backing.flush(damage);frames++;
  }displayed=batch.revision;
 };
 auto compute=[&](Sample s){
  double radius=std::max(actual.e.footprintRadius(5,38,s.ap),actual.e.footprintRadius(5,38,s.p))+3;
  tiles.markRect(1,int(std::floor(std::min(s.ax,s.x)-radius)),int(std::floor(std::min(s.ay,s.y)-radius)),int(std::ceil(std::max(s.ax,s.x)+radius)),int(std::ceil(std::max(s.ay,s.y)+radius)));
  actual.e.segment(actual.m.data(),actual.im.data(),actual.f.data(),5,38,0,1,s.ax,s.ay,s.ap,s.x,s.y,s.p,s.i);applied++;
  // Batch publication work; GUI independently consumes latest tiles at16ms.
  if((s.i+1)%24==0||s.i==1259)assert(tiles.publishForPage(1,s.i+1,actual.im));
  if(s.i==1259)done=true;
 };
 QObject::connect(&heartbeat,&QTimer::timeout,[&]{if(measuring){qint64 now=clock.nsecsElapsed();maxGap=std::max(maxGap,now-lastBeat);lastBeat=now;}});
 QObject::connect(&publisher,&QTimer::timeout,[&]{if(!measuring)return;paint();if(done.load()&&displayed==1260){
  finished=clock.nsecsElapsed();maxGap=std::max(maxGap,finished-lastBeat);measuring=false;app.quit();
 }});
 auto submit=[&](Sample s){qint64 before=clock.nsecsElapsed();if(sync)compute(s);else assert(worker.trySubmit([&,s]{compute(s);}));submitMax=std::max(submitMax,clock.nsecsElapsed()-before);submitted++;};
 QObject::connect(&feed,&QTimer::timeout,[&]{for(int n=0;n<(batch24?24:1)&&submitted<1260;n++)submit(samples[submitted]);if(submitted==1260)feed.stop();});
 clock.start();heartbeat.setTimerType(Qt::PreciseTimer);heartbeat.start(1);publisher.setTimerType(Qt::PreciseTimer);publisher.start(16);
 QTimer::singleShot(100,[&]{measuring=true;started=lastBeat=clock.nsecsElapsed();if(paced||batch24){feed.setTimerType(Qt::PreciseTimer);feed.start(batch24?0:2);}else for(auto s:samples)submit(s);});
 QTimer::singleShot(20000,[&]{fprintf(stderr,"timeout\n");app.exit(2);});
 int rc=app.exec();worker.drain();worker.close();assert(rc==0&&submitted==1260&&applied==1260&&displayed==1260&&canvas==actual.im);
 for(auto s:samples)reference.e.segment(reference.m.data(),reference.im.data(),reference.f.data(),5,38,0,1,s.ax,s.ay,s.ap,s.x,s.y,s.p,s.i);
 assert(actual.m==reference.m&&actual.im==reference.im&&actual.f==reference.f&&actual.e.tooth==reference.e.tooth&&actual.e.burnish==reference.e.burnish&&actual.e.ink==reference.e.ink&&actual.e.wear==reference.e.wear&&actual.e.untilNext==reference.e.untilNext&&actual.e.kneadedLift==reference.e.kneadedLift&&actual.e.kneadedContact==reference.e.kneadedContact&&actual.e.hasInk==reference.e.hasInk);
 printf("{\"mode\":\"%s\",\"input\":\"%s\",\"samples\":1260,\"max_event_gap_ms\":%.3f,\"max_submit_ms\":%.3f,\"completion_ms\":%.3f,\"frames\":%d,\"exact_state\":true,\"production_app\":false}\n",sync?"sync":"actor",batch24?"batch24_zero_timer":paced?"relative_timer_2ms":"burst",maxGap/1e6,submitMax/1e6,(finished-started)/1e6,frames);
}
