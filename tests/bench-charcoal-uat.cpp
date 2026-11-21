#define PaperMaterial OldMaterial
#define PaperMaterialRows OldRows
#include "fixtures/sketch-material-before-charcoal-deposit.h"
#undef PaperMaterial
#undef PaperMaterialRows
#undef PAPER_SKETCH_MATERIAL_H
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <chrono>
#include <cstdio>
template<class E> long long run(int tool,int size){
 E e;e.init(1200,1600);std::vector<uint32_t>m(1200*1600),im(m.size(),0xffffffffu);std::vector<uint16_t>f(82*81);
 auto start=std::chrono::steady_clock::now();double px=200,py=800;
 for(int i=0;i<400;i++){int pass=i/40,step=i%40;double x=200+700.*pass/9,y=700+450.*(pass%2?39-step:step)/39;
 e.segment(m.data(),im.data(),f.data(),tool,size,0,1,px,py,.65,x,y,.65,i?1:0);px=x;py=y;}
 return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
}
int main(){for(int tool:{4,5})for(int size:{8,24,48,80}){
 auto a=run<OldMaterial>(tool,size),b=run<PaperMaterial>(tool,size);
 printf("tool=%d size=%d old_us=%lld uat_us=%lld ratio=%.3f\n",tool,size,a,b,double(b)/a);fflush(stdout);
}}
