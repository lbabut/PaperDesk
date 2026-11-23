#include "sketch-deferred-prototype.h"
#include "sketch-dirty-tiles-prototype.h"
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <future>
#include <chrono>
#include <cstdio>
#include <atomic>
struct Surface{
 PaperMaterial e;std::vector<uint32_t> mass,image;std::vector<uint16_t> finger;
 Surface(int width,int height):mass(width*height),image(mass.size(),0xffffffffu),finger(82*81){e.init(width,height);e.tiltX=.85;e.tiltY=.35;e.contactAspect=2;e.contactAngle=.3;}
};
int main(int argc,char**){
 const int width=argc>1?1200:320,height=argc>1?1600:320;
 {bool rejected=false;try{DirtyTilesPrototype invalid(1,1,0);}catch(const std::invalid_argument&){rejected=true;}assert(rejected);}
 {DirtyTilesPrototype tiles(259,257);std::vector<uint32_t> image(259*257,0xffffffffu),canvas=image;
  image[0]=0;assert(tiles.publish(1,image));auto retained=tiles.take();assert(retained.tiles.size()==1);
  image[258]=123;assert(tiles.publish(2,image));image.back()=456;assert(tiles.publish(3,image));
  auto combined=tiles.take();assert(combined.revision==3&&combined.tiles.size()==2);
  tiles.apply(retained,canvas);tiles.apply(combined,canvas);assert(canvas==image);
  assert(!tiles.publish(3,image));assert(tiles.publish(4,image));assert(tiles.take().tiles.empty());
  assert((*retained.tiles.begin()->second)[0]==0);assert(tiles.tileCount()==9);
  assert(tiles.beginPage(2));assert(!tiles.beginPage(2));std::fill(canvas.begin(),canvas.end(),0xffffffffu);
  assert(!tiles.apply(retained,canvas,2));assert(canvas[0]==0xffffffffu);
  assert(!tiles.markRect(1,0,0,258,256));assert(!tiles.publishForPage(1,99,image));
  std::fill(image.begin(),image.end(),0xffffffffu);image.back()=789;
  assert(tiles.markRect(2,258,256,258,256));auto inspected=tiles.inspectedTiles;
  assert(tiles.publishForPage(2,1,image));assert(tiles.inspectedTiles==inspected+1);
  auto nextPage=tiles.take();assert(nextPage.page==2&&nextPage.revision==1&&nextPage.tiles.size()==1);
  assert(tiles.apply(nextPage,canvas,2)&&canvas==image);
 }
 {DirtyTilesPrototype tiles(64,64,16);std::vector<uint32_t> image(4096,0xffffffffu),canvas=image;std::atomic<bool> finished{false};
  std::thread writer([&]{for(int n=1;n<=1000;n++){image[(n*17)%4096]=n;assert(tiles.publish(n,image));}finished=true;});
  uint64_t revision=0;
  while(!finished.load()){auto batch=tiles.take();if(batch.revision){assert(batch.revision>revision);revision=batch.revision;tiles.apply(batch,canvas);}}
  writer.join();auto tail=tiles.take();if(tail.revision){assert(tail.revision>revision);tiles.apply(tail,canvas);}assert(canvas==image);
 }
 MaterialSnapshotMailbox<std::vector<int>> mailbox;
 assert(!mailbox.latest());assert(mailbox.publish(1,std::vector<int>(128,1)));
 auto retained=mailbox.latest();assert(!mailbox.publish(1,std::vector<int>(128,99)));
 std::atomic<bool> done{false};
 std::thread producer([&]{for(int i=2;i<=1000;i++)assert(mailbox.publish(i,std::vector<int>(128,i)));done=true;});
 uint64_t last=0;int reads=0;
 do{auto f=mailbox.latest();assert(f->revision>=last);last=f->revision;
  for(int v:f->data)assert(v==int(f->revision));reads++;
 }while(!done.load());producer.join();assert(reads>0);
 assert(mailbox.latest()->revision==1000&&retained->revision==1&&retained->data[0]==1);
 int accepted=0;
 {DeferredMaterialPrototype q(128);for(int i=0;i<100;i++)assert(q.trySubmit([&]{accepted++;}));
  q.close();assert(accepted==100);assert(!q.trySubmit([]{}));q.close();q.drain();}
 // Controlled saturation: no unbounded queue, no silent loss, retry in FIFO order.
 std::promise<void> entered,release;auto gate=release.get_future().share();std::vector<int> order;
 {DeferredMaterialPrototype q(2);
  assert(q.trySubmit([&]{entered.set_value();gate.wait();order.push_back(0);}));entered.get_future().wait();
  assert(q.trySubmit([&]{order.push_back(1);}));assert(q.trySubmit([&]{order.push_back(2);}));
  assert(!q.trySubmit([&]{order.push_back(99);}));release.set_value();q.drain();
  assert(q.trySubmit([&]{order.push_back(3);}));q.drain();}
 assert((order==std::vector<int>{0,1,2,3}));
 {DeferredMaterialPrototype q(2);assert(q.trySubmit([]{throw std::runtime_error("test");}));
  bool threw=false;try{q.drain();}catch(const std::runtime_error&){threw=true;}assert(threw);assert(!q.trySubmit([]{}));}
 Surface reference(width,height),deferred(width,height);DeferredMaterialPrototype queue(2048);long long enqueueMax=0;int applied=0;
 MaterialSnapshotMailbox<std::vector<uint32_t>> display;
 DirtyTilesPrototype dirtyTiles(width,height);
 auto start=std::chrono::steady_clock::now();double px=30,py=30,pp=.55;
 for(int i=0;i<1260;i++){
  double t=i/1259.,x=30+(width-70)*t,y=30+(height-70)*t+8*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  auto before=std::chrono::steady_clock::now();
  assert(queue.trySubmit([&,px,py,pp,x,y,p,i]{
   // Same conservative endpoint footprint bounds as advancePenInput(), before segment.
   double radius=std::max(deferred.e.footprintRadius(5,38,pp),deferred.e.footprintRadius(5,38,p))+3;
   assert(dirtyTiles.markRect(1,int(std::floor(std::min(px,x)-radius)),int(std::floor(std::min(py,y)-radius)),int(std::ceil(std::max(px,x)+radius)),int(std::ceil(std::max(py,y)+radius))));
   deferred.e.segment(deferred.mass.data(),deferred.image.data(),deferred.finger.data(),5,38,0,1,px,py,pp,x,y,p,i);applied++;
   if((i+1)%64==0||i==1259){assert(display.publish(i+1,deferred.image));assert(dirtyTiles.publishForPage(1,i+1,deferred.image));}
  }));
  enqueueMax=std::max(enqueueMax,(long long)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-before).count());
  px=x;py=y;pp=p;
 }
 queue.drain();assert(applied==1260);
 auto saved=display.latest();assert(saved&&saved->revision==1260&&saved->data==deferred.image);
 auto delta=dirtyTiles.take();std::vector<uint32_t> reconstructed(width*height,0xffffffffu);dirtyTiles.apply(delta,reconstructed);
 assert(delta.revision==1260&&reconstructed==deferred.image&&delta.tiles.size()<=dirtyTiles.tileCount());
 queue.close();assert(!queue.trySubmit([]{}));
 // Enqueue the whole burst before running the reference; do not hide worker
 // backlog by spending synchronous reference time between submissions.
 px=30;py=30;pp=.55;
 for(int i=0;i<1260;i++){
  double t=i/1259.,x=30+(width-70)*t,y=30+(height-70)*t+8*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  reference.e.segment(reference.mass.data(),reference.image.data(),reference.finger.data(),5,38,0,1,px,py,pp,x,y,p,i);
  px=x;py=y;pp=p;
 }
 assert(reference.mass==deferred.mass&&reference.image==deferred.image&&reference.finger==deferred.finger);
 assert(reference.e.tooth==deferred.e.tooth&&reference.e.burnish==deferred.e.burnish&&reference.e.ink==deferred.e.ink);
 assert(reference.e.wear==deferred.e.wear&&reference.e.untilNext==deferred.e.untilNext&&reference.e.hasInk==deferred.e.hasInk);
 assert(reference.e.kneadedLift==deferred.e.kneadedLift&&reference.e.kneadedContact==deferred.e.kneadedContact);
 printf("PASS renderer-bounds tiles,page epochs/stale rejection,full reconstruction,close/barrier,FIFO,1260 exact samples/full state; surface=%dx%d full_scan_tiles=%zu inspected_tiles=%llu tile_bytes=%llu final_pending_tiles=%zu submit_max_us=%lld wall_us=%lld\n",width,height,dirtyTiles.tileCount()*20,(unsigned long long)dirtyTiles.inspectedTiles,(unsigned long long)dirtyTiles.copiedBytes,delta.tiles.size(),enqueueMax,(long long)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count());
}
