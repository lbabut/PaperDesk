// Preview shades sampled from upright size-3 lines on fresh plain paper.
// Compile with -DGENERATE_PREVIEW_SHADE to print the LUT initializer.
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#ifndef GENERATE_PREVIEW_SHADE
#include "../product/payload/apps/papersketch/native/sketch-preview-shade.h"
#include "../product/payload/apps/papersketch/native/sketch-display.h"
#endif
#include <cassert>
#include <cstdio>
int main(){
 for(int tool=0;tool<6;tool++){
#ifdef GENERATE_PREVIEW_SHADE
  printf("    {");
#endif
  for(int step=0;step<=16;step++){
   double p=step/16.;PaperMaterial m;m.init(256,96);
   std::vector<uint32_t> mass(256*96),image(mass.size(),0xffffffffu);
   std::vector<uint16_t> finger(82*81);
   for(int y=12;y<90;y+=12){
    m.segment(mass.data(),image.data(),finger.data(),tool,3,0,1,20,y,p,20,y,p,0);
    m.segment(mass.data(),image.data(),finger.data(),tool,3,0,1,20,y,p,230,y,p,1);
   }
   double sum=0;int count=0;
   for(auto pixel:image)if(pixel!=0xffffffffu){sum+=pixel&255;count++;}
   int gray=count?int(std::lround(sum/count)):255;
#ifdef GENERATE_PREVIEW_SHADE
   printf("%s%d",step?",":"",gray);
#else
   assert(std::abs(int(sketchPreviewGray(tool,float(p)))-gray)<=1);
   if(step)assert(sketchPreviewGray(tool,float(p))<=sketchPreviewGray(tool,float(p-1/16.)));
   assert(sketchPreviewGray(8,float(p))==0);
#endif
  }
#ifdef GENERATE_PREVIEW_SHADE
  puts("},");
#endif
 }
#ifndef GENERATE_PREVIEW_SHADE
 for(int gray=0;gray<256;gray++)for(int y=0;y<8;y++)for(int x=0;x<8;x++){
  unsigned g=std::min(gray,223);unsigned pixel=0xff000000u|g*0x010101u;
  assert(bool(sketchPreviewDot(gray,x,y))==(paperDisplayPixel(pixel,x,y)==0xff000000u));
 }
 int low=255,high=0;
 for(int y=0;y<64;y++)for(int x=0;x<64;x++){
  int center=sketchCharcoalPreviewGray(80,1,x,y),edge=sketchCharcoalPreviewGray(80,.1f,x,y);
  assert(center>=80&&center<=255&&edge>center);
  assert(center==sketchCharcoalPreviewGray(80,1,x,y));
  low=std::min(low,center);high=std::max(high,center);
 }
 assert(high-low>40);
 for(int y=0;y<8;y++)for(int x=0;x<8;x++){assert(!sketchPreviewDotExact(255,x,y));assert(sketchPreviewDotExact(0,x,y));}
 puts("PASS: all six preview shades match fresh-paper material samples at 17 pressure anchors; ink stays opaque");
#endif
}
