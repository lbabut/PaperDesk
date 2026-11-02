#ifndef SKETCH_HEADER
#define SKETCH_HEADER "../product/payload/apps/papersketch/native/sketch-material.h"
#endif
#include SKETCH_HEADER
#include <cassert>
#include <iostream>
struct Sheet {
 PaperMaterial p;std::vector<uint32_t> m,image;std::vector<uint16_t> finger;
 Sheet():m(320*320),image(320*320,0xffffffffu),finger(82*81){p.init(320,320);}
 void stroke(int tool,double a,double b,double c,double d,double force,int size){
  p.segment(m.data(),image.data(),finger.data(),tool,size,0,1,a,b,force,a,b,force,0);
  p.segment(m.data(),image.data(),finger.data(),tool,size,0,1,a,b,force,c,d,force,1);
 }
 uint64_t total(){uint64_t n=0;for(auto v:m)n+=(v>>16)+(v&65535);for(auto v:finger)n+=v;return n;}
 uint64_t transported(){uint64_t n=0;for(int y=120;y<=200;y++)for(int x=178;x<240;x++){auto v=m[y*320+x];n+=(v>>16)+(v&65535);}return n;}
 double core(){double n=0;int c=0;for(int y=148;y<=172;y++)for(int x=156;x<=164;x++){n+=image[y*320+x]&255;c++;}return n/c;}
};
int main(){
 for(int tool:{1,3,4}){
  uint64_t previous=0;
  for(double force:{.04,.13,.4,.88}){
   Sheet s;s.stroke(tool,160,80,160,240,.8,24);auto mass=s.total();double before=s.core();
   s.stroke(7,100,160,240,160,force,64);
   assert(s.total()==mass);auto moved=s.transported();assert(moved>0);
#ifndef SKETCH_COMPARE_BASELINE
   if(force==.13){double minimum=tool==1?15:tool==3?40:60;assert(s.core()-before>minimum);}
#endif
   assert(moved>previous);previous=moved;
   std::cout<<tool<<','<<force<<','<<before<<','<<s.core()<<','<<moved<<std::endl;
  }
 }
 Sheet white;white.stroke(7,40,160,280,160,.88,64);assert(white.total()==0);
}
