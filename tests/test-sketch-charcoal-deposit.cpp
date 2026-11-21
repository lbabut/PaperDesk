#define PaperMaterial BaselineMaterial
#define PaperMaterialRows BaselineRows
#include "fixtures/sketch-material-before-charcoal-deposit.h"
#undef PaperMaterial
#undef PaperMaterialRows
#undef PAPER_SKETCH_MATERIAL_H
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <cstdio>
template<class P>struct Sheet{
 P p;std::vector<uint32_t>m=std::vector<uint32_t>(320*200),im=std::vector<uint32_t>(320*200,0xffffffffu);std::vector<uint16_t>f=std::vector<uint16_t>(82*81);
 Sheet(){p.init(320,200);}
 void line(int t,int size,double force,double y=100){p.segment(m.data(),im.data(),f.data(),t,size,0,1,30,y,force,30,y,force,0);p.segment(m.data(),im.data(),f.data(),t,size,0,1,30,y,force,290,y,force,1);}
 double gray(){double n=0;for(int y=96;y<=104;y++)for(int x=130;x<190;x++)n+=im[y*320+x]&255;return n/540;}
 uint64_t total(){uint64_t n=0;for(auto v:m)n+=(v>>16)+(v&65535);for(auto v:f)n+=v;return n;}
};
int main(){
 // No graphite, ink or eraser drift is permitted by a charcoal-only change.
 for(int paper=0;paper<3;paper++)for(int tool:{0,1,2,3,8})for(double force:{.1,.5,.95}){
  Sheet<BaselineMaterial>a;Sheet<PaperMaterial>b;a.p.setPaperKind(paper);b.p.setPaperKind(paper);
  for(int i=0;i<5;i++){a.line(tool,24,force,65+i*14);b.line(tool,24,force,65+i*14);}
  assert(a.im==b.im&&a.m==b.m&&a.f==b.f&&a.p.burnish==b.p.burnish&&a.p.ink==b.p.ink&&a.p.wear==b.p.wear);
  for(bool kneaded:{false,true}){a.p.kneaded=kneaded;b.p.kneaded=kneaded;a.line(6,40,.8);b.line(6,40,.8);assert(a.im==b.im&&a.m==b.m);}
 }
 for(int paper=0;paper<3;paper++)for(int tool:{4,5})for(int size:{24,64}){
  Sheet<PaperMaterial>s;s.p.setPaperKind(paper);double previous=255,first=0,eighth=0;
  for(int layer=0;layer<20;layer++){s.line(tool,size,.65);double gray=s.gray();assert(gray<=previous);previous=gray;if(!layer)first=gray;if(layer==7)eighth=gray;
   for(auto m:s.m)assert((m>>16)+(m&65535)<=65535);
  }
  printf("paper=%d tool=%d size=%d gray1=%.2f gray8=%.2f gray20=%.2f\n",paper,tool,size,first,eighth,previous);fflush(stdout);
  assert(first>35&&first<220);assert(eighth<first*.65);assert(previous<40);
  auto before=s.total();s.line(7,64,.7);assert(s.total()==before);
  s.p.kneaded=true;before=s.total();s.line(6,48,.8);assert(s.total()<before);
 }
 Sheet<PaperMaterial>white;white.line(4,24,0);white.line(5,64,0);assert(white.total()==0);
 puts("PASS exact graphite/ink/eraser compatibility; 12 twenty-layer cases; deepening blacks; bounded pigment; conservative smudge; kneaded lift; zero-pressure no-op");
}
