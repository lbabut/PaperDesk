#include "sketch-deferred-prototype.h"
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <future>
#include <chrono>
#include <cstdio>
struct Surface{
 PaperMaterial e;std::vector<uint32_t> mass,image;std::vector<uint16_t> finger;
 Surface():mass(320*320),image(mass.size(),0xffffffffu),finger(82*81){e.init(320,320);e.tiltX=.85;e.tiltY=.35;e.contactAspect=2;e.contactAngle=.3;}
};
int main(){
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
 Surface reference,deferred;DeferredMaterialPrototype queue(2048);long long enqueueMax=0;int applied=0;
 auto start=std::chrono::steady_clock::now();double px=30,py=30,pp=.55;
 for(int i=0;i<1260;i++){
  double t=i/1259.,x=30+250*t,y=30+250*t+8*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  auto before=std::chrono::steady_clock::now();
  assert(queue.trySubmit([&,px,py,pp,x,y,p,i]{deferred.e.segment(deferred.mass.data(),deferred.image.data(),deferred.finger.data(),5,38,0,1,px,py,pp,x,y,p,i);applied++;}));
  enqueueMax=std::max(enqueueMax,(long long)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-before).count());
  px=x;py=y;pp=p;
 }
 queue.drain();assert(applied==1260);
 // Enqueue the whole burst before running the reference; do not hide worker
 // backlog by spending synchronous reference time between submissions.
 px=30;py=30;pp=.55;
 for(int i=0;i<1260;i++){
  double t=i/1259.,x=30+250*t,y=30+250*t+8*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  reference.e.segment(reference.mass.data(),reference.image.data(),reference.finger.data(),5,38,0,1,px,py,pp,x,y,p,i);
  px=x;py=y;pp=p;
 }
 assert(reference.mass==deferred.mass&&reference.image==deferred.image&&reference.finger==deferred.finger);
 assert(reference.e.tooth==deferred.e.tooth&&reference.e.burnish==deferred.e.burnish&&reference.e.ink==deferred.e.ink);
 assert(reference.e.wear==deferred.e.wear&&reference.e.untilNext==deferred.e.untilNext&&reference.e.hasInk==deferred.e.hasInk);
 assert(reference.e.kneadedLift==deferred.e.kneadedLift&&reference.e.kneadedContact==deferred.e.kneadedContact);
 printf("PASS FIFO,saturation/refusal/retry,error barrier,1260 exact samples and full state; submit_max_us=%lld wall_us=%lld\n",enqueueMax,(long long)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count());
}
