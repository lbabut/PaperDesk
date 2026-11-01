#include "../product/payload/apps/papersketch/native/sketch-display.h"
#include <cassert>
#include <cmath>
int main(){
 int previous=-1;
 for(int gray=0;gray<256;gray++){
  int whites=0;
  for(int y=0;y<8;y++)for(int x=0;x<8;x++){
   auto p=paperDisplayPixel(0xff000000u|gray*0x10101u,x,y);
   assert(p==0xff000000u||p==0xffffffffu);
   assert(p==paperDisplayPixel(0xff000000u|gray*0x10101u,x+128,y+128));
   whites+=p==0xffffffffu;
  }
  assert(whites>=previous);previous=whites;
  assert(std::abs(whites*255.0/64-gray)<3);
 }
 assert(paperDisplayPixel(0xffffffffu,0,0)==0xffffffffu);
 assert(paperDisplayPixel(0xff000000u,7,7)==0xff000000u);
}
