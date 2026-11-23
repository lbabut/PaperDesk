// CPU-only deterministic material profile; no device, input or filesystem I/O.
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <chrono>
#include <cstdio>
int main(){
 PaperMaterial e;e.init(1200,1600);
 std::vector<uint32_t> mass(1200*1600),image(mass.size(),0xffffffffu);
 std::vector<uint16_t> finger(82*81);
 e.tiltX=.85;e.tiltY=.35;e.contactAspect=2;e.contactAngle=.3;
 auto start=std::chrono::steady_clock::now();
 for(int pass=0;pass<12;pass++){
  double px=120,py=900,pp=.55;
  for(int i=0;i<1260;i++){
   double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;
   e.segment(mass.data(),image.data(),finger.data(),5,38,0,1,px,py,pp,x,y,p,i);
   px=x;py=y;pp=p;
  }
 }
 unsigned long long digest=1469598103934665603ull;
 for(size_t i=0;i<mass.size();i++){digest=(digest^mass[i])*1099511628211ull;digest=(digest^image[i])*1099511628211ull;}
 printf("wall_us=%lld digest=%llu\n",(long long)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count(),digest);
}
