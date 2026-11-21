#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include "../product/payload/apps/papersketch/native/sketch-preview-shade.h"
#include <cassert>
#include <cstdio>
struct Sample{double core,paintedMean;int painted;};
Sample sample(int tool,double force){
 PaperMaterial m;m.init(256,96);std::vector<uint32_t> mass(256*96),image(mass.size(),0xffffffffu);std::vector<uint16_t>finger(82*81);
 for(int y=12;y<90;y+=12){m.segment(mass.data(),image.data(),finger.data(),tool,3,0,1,20,y,force,20,y,force,0);m.segment(mass.data(),image.data(),finger.data(),tool,3,0,1,20,y,force,230,y,force,1);}
 double core=0,painted=0;int n=0,count=0;
 for(int y=12;y<90;y+=12)for(int x=32;x<220;x++){core+=image[y*256+x]&255;n++;}
 for(auto pixel:image)if(pixel!=0xffffffffu){painted+=pixel&255;count++;}
 return {core/n,count?painted/count:255,count};
}
int main(){
 for(int tool:{4,5}){
  auto a=sample(tool,15./16),b=sample(tool,1);
  assert(b.painted>a.painted);assert(b.paintedMean>a.paintedMean); // Reproduce the original failure.
  assert(b.core<a.core);assert(sketchPreviewGray(tool,1)<sketchPreviewGray(tool,15.f/16));
  double prior=255,maxError=0;
  for(int step=0;step<=128;step++){
   double force=step/128.,actual=sample(tool,force).core;
   assert(actual<=prior+.05);prior=actual;
   double error=std::abs(sketchPreviewGray(tool,float(force))-actual);maxError=std::max(maxError,error);
   assert(error<4); // Includes LUT interpolation and integer quantization.
  }
  printf("tool=%d original-painted-count=%d->%d old-mean=%.2f->%.2f fixed-core=%.2f->%.2f max-interpolation-error=%.3f\n",tool,a.painted,b.painted,a.paintedMean,b.paintedMean,a.core,b.core,maxError);
 }
 puts("PASS fixed cohort remains monotonic across 129 pressure points for both charcoals; original sampling defect reproduced");
}
