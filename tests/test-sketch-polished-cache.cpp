#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <cstdio>
#include <limits>
static void check(PaperMaterial::PolishedContactCache &cache,int tool,double p,double capacity){
 cache.prepare(tool,p,capacity);
 for(int burnish=0;burnish<256;burnish++)for(int tooth=0;tooth<256;tooth++){
  const auto &response=PaperMaterial::grainResponses()[burnish*256+tooth];
  double polish=burnish*(1.0/255.0);
  double contact=std::clamp((1.05*p+.15-response.grain*.5)*2.0,0.0,1.0);
  int expected=std::max(1,int(capacity*PaperMaterial::capacityResponse(tool,response.capacity)*(1-.22*polish)));
  for(int repeat=0;repeat<2;repeat++){
   const auto &actual=cache.get(uint8_t(burnish),uint8_t(tooth));
   assert(actual.contact==contact&&actual.capacity==expected);
  }
 }
}
int main(){
 PaperMaterial::PolishedContactCache cache;
 for(int tool:{4,5,4})for(double p:{.01,.2,.6,.6000000001,.91,1.})
  check(cache,tool,p,(tool==4?54000.:65535.)*(.12+.88*p));
 // Same pressure/tool but changed capacity must invalidate as well.
 check(cache,4,.6,12345.123);
 cache.epoch=std::numeric_limits<uint32_t>::max();check(cache,5,.7,55555.5);
 assert(cache.epoch==1);
 auto *mainCache=&PaperMaterial::polishedContactCache();
 std::thread other([&]{assert(&PaperMaterial::polishedContactCache()!=mainCache);check(PaperMaterial::polishedContactCache(),5,.9,60000.);});other.join();
 puts("PASS exact all65536 keys, collisions, reuse, pressure/tool/capacity invalidation, epoch rollover and thread isolation");
}
