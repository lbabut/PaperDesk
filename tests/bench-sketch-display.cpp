#include "../product/payload/apps/papersketch/native/sketch-display.h"
#include <vector>
#include <chrono>
#include <iostream>
#include <cassert>
struct Result{std::vector<uint32_t> optical,display;double ms;};
Result run(int w,int h,int frames,bool incremental){
 const int side=128;std::vector<uint32_t> source(side*side,0xffffffffu);
 Result r{source,source,0};auto start=std::chrono::steady_clock::now();
 for(int frame=0;frame<frames;frame++){
  int left=(frame*17)%(side-w+1),top=(frame*11)%(side-h+1);
  for(int y=top;y<top+h;y++)for(int x=left;x<left+w;x++)source[y*side+x]=0xff000000u|uint32_t((frame*13+x+y)&255)*0x010101u;
  if(incremental)paperDisplayPatch(source.data(),side,r.optical.data(),r.display.data(),side,left,top,w,h,256,384,true);
  else{
   r.optical=source;r.display=r.optical;
   for(int y=0;y<side;y++)for(int x=0;x<side;x++)r.display[y*side+x]=paperDisplayPixel(r.display[y*side+x],256+x,384+y);
  }
 }
 r.ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return r;
}
int main(){
 constexpr int frames=2000;std::cout<<"{\"execution\":\"standalone CPU display benchmark; no screen latency measurement\",\"cases\":[";
 for(int c=0;c<2;c++){
  int w=c?48:8,h=c?48:64;auto old=run(w,h,frames,false),updated=run(w,h,frames,true);
  assert(old.optical==updated.optical&&old.display==updated.display);
  if(c)std::cout<<",";
  std::cout<<"{\"name\":\""<<(c?"wide-tool":"narrow-ink")<<"\",\"frames\":"<<frames<<",\"baseline_ms\":"<<old.ms<<",\"incremental_ms\":"<<updated.ms<<",\"speedup\":"<<old.ms/updated.ms<<",\"identical\":true,\"baseline_pixels_per_frame\":16384,\"updated_pixels_per_frame\":"<<w*h<<"}";
 }
 std::cout<<"]}\n";
}
