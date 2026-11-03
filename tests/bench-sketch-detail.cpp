// Standalone tablet CPU benchmark; never opens input devices, user files or the display.
#define PaperMaterial ReferenceMaterial
#include "fixtures/sketch-material-4.2.7.h"
#undef PaperMaterial
#undef PAPER_SKETCH_MATERIAL_H
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include "device/papersketch-detail-pattern.h"
#include <chrono>
#include <cstdio>
#include <cassert>
#include <sys/resource.h>
template<class M> struct Surface {
 M e;std::vector<uint32_t> mass,image;std::vector<uint16_t> finger;
 Surface():mass(1200*1600),image(1200*1600,0xffffffffu),finger(82*81){e.init(1200,1600);}
 long long run(int tool,int rounds){
  auto start=std::chrono::steady_clock::now();
  for(int r=0;r<rounds;r++)for(int stroke=0;stroke<DETAIL_CONTACTS;stroke++){
   e.untilNext=0;double px=0,py=0;
   for(int i=0;i<detail_length(stroke);i++){
    int u,v;detail_point(stroke,i,&u,&v);double x=200+u*.02,y=650+v*.02;
    if(!i){px=x;py=y;}
    e.segment(mass.data(),image.data(),finger.data(),tool,3,0,1,px,py,.65,x,y,.65,i?1:0);px=x;py=y;
   }
  }
  return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
 }
};
int main(){setpriority(PRIO_PROCESS,0,19);for(int tool:{1,4})for(int r=0;r<3;r++){
 Surface<ReferenceMaterial>a;Surface<PaperMaterial>b;
 long long oldus,newus;
 if(r%2){newus=b.run(tool,5);oldus=a.run(tool,5);}else{oldus=a.run(tool,5);newus=b.run(tool,5);}
 bool exact=a.mass==b.mass&&a.image==b.image&&a.finger==b.finger&&a.e.burnish==b.e.burnish&&a.e.wear==b.e.wear&&a.e.ink==b.e.ink;
 printf("{\"tool\":%d,\"repeat\":%d,\"contacts\":2500,\"samples\":18500,\"reference_us\":%lld,\"current_us\":%lld,\"exact\":%s}\n",tool,r,oldus,newus,exact?"true":"false");fflush(stdout);if(!exact)return 1;
}}
