#ifndef PAPER_SKETCH_PROGRESSIVE_H
#define PAPER_SKETCH_PROGRESSIVE_H
#include "sketch-material.h"
#include <QtGui/QImage>
#include <QtGui/QRegion>
#include <QtCore/QRectF>
#include <condition_variable>
#include <atomic>
#include <chrono>
#include <deque>
#include <map>
#include <cstring>
#include <mutex>
#include <thread>
#ifdef __linux__
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

// One stroke owns its exact state on one worker. Only immutable tile copies
// cross to the GUI. The synchronous renderer and persisted format are unchanged.
class SketchProgressive {
public:
 struct Point { int tool; double size,strength,x,y,p,tx,ty; bool first; uint64_t id=0; };
 struct Delivery { std::map<int,QImage> tiles; uint64_t through=0; };
 PaperMaterial physics;
 QImage image,material,finger;
 uint64_t submitted=0;
 size_t peakQueue=0;
 std::atomic<long long> workerUs{0},initializationUs{0};
private:
 const uint32_t *initialImage;
 int initialStride;
 std::array<bool,130> loaded{};
 struct Undo {QImage material;std::vector<uint8_t> burnish;};
 std::map<int,Undo> undo;
 std::array<double,6> originalWear;
 double originalPhase=0;
 void loadTiles(const QRect &r){
  if(r.isEmpty())return;
  for(int y=r.top()/128;y<=r.bottom()/128;++y)for(int x=r.left()/128;x<=r.right()/128;++x){
   int key=y*10+x;if(loaded[key])continue;loaded[key]=true;
   auto tile=QRect(x*128,y*128,128,128).intersected(image.rect());
   Undo before;before.material=material.copy(tile);before.burnish.resize(tile.width()*tile.height());
   for(int row=0;row<tile.height();++row){
    // Only an untouched tile is read from the GUI's stable pixel storage.
    // A tile is published after this copy, and is never read here again.
    std::memcpy(image.scanLine(tile.y()+row)+tile.x()*4,initialImage+(tile.y()+row)*initialStride+tile.x(),tile.width()*4);
    std::memcpy(before.burnish.data()+row*tile.width(),physics.burnish.data()+(tile.y()+row)*1200+tile.x(),tile.width());
   }
   undo[key]=std::move(before);
  }
 }
 std::mutex mutex;
 std::condition_variable wake,space;
 std::deque<Point> queue;
 Delivery pending;
 bool closing=false;
 std::thread thread;
 double lastX=0,lastY=0,lastP=0;
 bool waiting=true;
 QRect render(const Point &v){
  double x=std::clamp(v.x,0.0,1200.0),y=std::clamp(v.y,0.0,1600.0),p=std::clamp(v.p,0.0,1.0);
  bool first=v.first;if(first)waiting=true;
  double dx=x-lastX,dy=y-lastY;
  if(!first&&!waiting&&dx*dx+dy*dy<.35*.35)return {};
  physics.tiltX=v.tx;physics.tiltY=v.ty;physics.contactAspect=1;physics.contactAngle=0;
  if(waiting){if(p<=0){lastX=x;lastY=y;lastP=p;return {};}first=true;waiting=false;}
  double ax=first?x:lastX,ay=first?y:lastY,ap=first?p:lastP;
  double radius=std::max(physics.footprintRadius(v.tool,v.size,ap),physics.footprintRadius(v.tool,v.size,p))+3;
  auto dirty=QRectF(QPointF(std::min(ax,x)-radius,std::min(ay,y)-radius),QPointF(std::max(ax,x)+radius,std::max(ay,y)+radius)).toAlignedRect().intersected(image.rect());
  loadTiles(dirty);
  physics.segment(reinterpret_cast<uint32_t*>(material.bits()),reinterpret_cast<uint32_t*>(image.bits()),reinterpret_cast<uint16_t*>(finger.bits()),v.tool,v.size,0,v.strength,ax,ay,ap,x,y,p,first?0:1);
  lastX=x;lastY=y;lastP=p;return dirty;
 }
 void run(){
#ifdef __linux__
  // Keep input/paint callbacks ahead of background material work under load.
  (void)setpriority(PRIO_PROCESS,pid_t(syscall(SYS_gettid)),5);
#endif
  // GUI backing pixels survive until join; each tile is read before publication.
  auto initAt=std::chrono::steady_clock::now();
  material.detach();finger.detach();
  initializationUs=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-initAt).count();
  for(;;){
   std::deque<Point> batch;
   {std::unique_lock<std::mutex> lock(mutex);wake.wait(lock,[this]{return closing||!queue.empty();});
    if(queue.empty()&&closing)break;
    for(int i=0;i<8&&!queue.empty();++i){batch.push_back(queue.front());queue.pop_front();}}
   space.notify_all();QRegion dirty;
   auto workAt=std::chrono::steady_clock::now();
   for(const auto &v:batch)dirty+=render(v);
   workerUs+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-workAt).count();
   std::map<int,QImage> tiles;
   // Tile snapshots bound outstanding result memory to one page, even if the
   // GUI is busy. Newer snapshots replace older snapshots of the same tile.
   for(const auto &r:dirty){if(r.isEmpty())continue;
    for(int y=r.top()/128;y<=r.bottom()/128;++y)for(int x=r.left()/128;x<=r.right()/128;++x){
     int key=y*10+x;if(!tiles.count(key))tiles[key]=image.copy(QRect(x*128,y*128,128,128).intersected(image.rect()));}}
   {std::lock_guard<std::mutex> lock(mutex);for(auto &v:tiles)pending.tiles[v.first]=std::move(v.second);pending.through=batch.back().id;}
  }
 }
public:
 SketchProgressive(PaperMaterial &&p,QImage &&m,QImage &&f,const uint32_t *base,int stride):physics(std::move(p)),image(1200,1600,QImage::Format_RGB32),material(std::move(m)),finger(std::move(f)),initialImage(base),initialStride(stride),originalWear(physics.wear),originalPhase(physics.untilNext){thread=std::thread([this]{run();});}
 void restore(){
  close();
  for(const auto &v:undo){int x=(v.first%10)*128,y=(v.first/10)*128,w=v.second.material.width(),h=v.second.material.height();
   for(int row=0;row<h;++row){std::memcpy(material.scanLine(y+row)+x*4,v.second.material.constScanLine(row),w*4);std::memcpy(physics.burnish.data()+(y+row)*1200+x,v.second.burnish.data()+row*w,w);}}
  physics.wear=originalWear;physics.untilNext=originalPhase;
 }
 ~SketchProgressive(){close();}
 double endX()const{return lastX;} double endY()const{return lastY;} double endP()const{return lastP;} bool awaiting()const{return waiting;}
 uint64_t push(Point p){
  std::unique_lock<std::mutex> lock(mutex);
  // Never drop or reorder input. Backpressure is a bounded overload fallback.
  space.wait(lock,[this]{return queue.size()<512;});
  p.id=++submitted;queue.push_back(p);peakQueue=std::max(peakQueue,queue.size());wake.notify_one();return p.id;
 }
 Delivery take(){std::lock_guard<std::mutex> lock(mutex);Delivery out=std::move(pending);pending=Delivery();return out;}
 void close(){if(!thread.joinable())return;{std::lock_guard<std::mutex> lock(mutex);closing=true;}wake.notify_all();thread.join();}
};
#endif
