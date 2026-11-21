#define PaperMaterial ReferenceMaterial
#define PaperMaterialRows ReferenceRows
#include "fixtures/sketch-material-before-ellipse-bounds.h"
#undef PaperMaterial
#undef PaperMaterialRows
#undef PAPER_SKETCH_MATERIAL_H
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <chrono>
#include <cstdio>

template<class E> struct Surface {
 E e;std::vector<uint32_t> m,im;std::vector<uint16_t> f;
 Surface(int n):m(n*n),im(n*n,0xffffffffu),f(82*81){e.init(n,n);}
};
static void equal(const Surface<ReferenceMaterial>&a,const Surface<PaperMaterial>&b){
 assert(a.m==b.m&&a.im==b.im&&a.f==b.f);
 assert(a.e.tooth==b.e.tooth&&a.e.burnish==b.e.burnish&&a.e.ink==b.e.ink);
 assert(a.e.wear==b.e.wear&&a.e.untilNext==b.e.untilNext&&a.e.hasInk==b.e.hasInk);
 assert(a.e.kneadedLift==b.e.kneadedLift&&a.e.kneadedContact==b.e.kneadedContact);
}
static void correctness(){
 Surface<ReferenceMaterial>a(96);Surface<PaperMaterial>b(96);int index=0;
 for(int paper=0;paper<3;paper++)for(int variant=0;variant<2;variant++){
  a.e.setPaperKind(paper);b.e.setPaperKind(paper);a.e.kneaded=b.e.kneaded=variant;
  for(int tool=0;tool<9;tool++)for(double size:{1.,7.,24.,48.,80.})
  for(double angle:{0.,.25,.77,1.6,2.9,4.2})for(double p:{0.,.03,.2,.65,1.}){
   double tilt=index%3==0?0:.95,x=(index%7)*20.-12.125,y=(index%5)*25.-4.375;
   a.e.tiltX=b.e.tiltX=tilt*std::cos(angle);a.e.tiltY=b.e.tiltY=tilt*std::sin(angle);
   a.e.contactAspect=b.e.contactAspect=2;a.e.contactAngle=b.e.contactAngle=angle;
   a.e.dab(a.m.data(),a.im.data(),a.f.data(),tool,size,0,.8,x,y,p);
   b.e.dab(b.m.data(),b.im.data(),b.f.data(),tool,size,0,.8,x,y,p);equal(a,b);index++;
  }
 }
 printf("PASS exact state after %d dabs: all tools, pressure/angle/size, edges, papers and erasers\n",index);fflush(stdout);
}
template<class E> static long long run(Surface<E>&s,int tool,double tilt){
 auto start=std::chrono::steady_clock::now();double px=50,py=50,pp=.2;
 for(int i=0;i<300;i++){
  double x=40+(i%30)*8,y=50+(i/30)*22,p=.1+(i%19)*.045;
  s.e.tiltX=tilt;s.e.tiltY=tilt*.15;s.e.contactAspect=2;s.e.contactAngle=.3;
  s.e.segment(s.m.data(),s.im.data(),s.f.data(),tool,tool==1?12:38,0,.8,px,py,pp,x,y,p,i?1:0);
  px=x;py=y;pp=p;
 }
 return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
}
int main(){
 correctness();
 for(int repeat=0;repeat<2;repeat++)for(int tool:{1,4,5,7})for(double tilt:{0.,.5,.95}){
  Surface<ReferenceMaterial>a(320);Surface<PaperMaterial>b(320);long long oldTime,newTime;
  if(repeat%2){newTime=run(b,tool,tilt);oldTime=run(a,tool,tilt);}
  else {oldTime=run(a,tool,tilt);newTime=run(b,tool,tilt);}
  equal(a,b);
  printf("{\"repeat\":%d,\"tool\":%d,\"tilt\":%.2f,\"old_us\":%lld,\"new_us\":%lld,\"ratio\":%.4f}\n",repeat,tool,tilt,oldTime,newTime,double(newTime)/oldTime);fflush(stdout);
 }
}
