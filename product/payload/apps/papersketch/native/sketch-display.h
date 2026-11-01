#ifndef PAPER_SKETCH_DISPLAY_H
#define PAPER_SKETCH_DISPLAY_H
#include <cstdint>
inline uint32_t paperDisplayPixel(uint32_t pixel,int x,int y){
 static constexpr unsigned char bayer[8][8]={
  {0,48,12,60,3,51,15,63},{32,16,44,28,35,19,47,31},
  {8,56,4,52,11,59,7,55},{40,24,36,20,43,27,39,23},
  {2,50,14,62,1,49,13,61},{34,18,46,30,33,17,45,29},
  {10,58,6,54,9,57,5,53},{42,26,38,22,41,25,37,21}};
 const int gray=(pixel>>16)&255,threshold=bayer[y&7][x&7]*4+2;
 return gray>threshold?0xffffffffu:0xff000000u;
}
inline void paperDisplayPatch(const uint32_t* source,int sourceStride,uint32_t* optical,uint32_t* display,int tileStride,int x0,int y0,int width,int height,int originX,int originY,bool fast){
 for(int y=y0;y<y0+height;y++){
  const auto src=source+y*sourceStride;
  auto raw=optical+y*tileStride,out=display+y*tileStride;
  for(int x=x0;x<x0+width;x++){uint32_t p=src[x];raw[x]=p;out[x]=fast?paperDisplayPixel(p,originX+x,originY+y):p;}
 }
}
#endif
