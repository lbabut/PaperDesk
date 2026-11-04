
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <cstdio>
struct Surface{
 PaperMaterial p;std::vector<uint32_t> mass,image;std::vector<uint16_t> finger;
 Surface(int fixed,int loose):mass(128*128,(uint32_t(fixed)<<16)|loose),image(128*128),finger(82*81){p.init(128,128);p.kneaded=true;std::fill(image.begin(),image.end(),0xff000000u|uint32_t(p.optical[fixed+loose])*0x010101u);}
 void dab(double pressure,int index){p.segment(mass.data(),image.data(),finger.data(),6,48,0,1,64,64,pressure,64,64,pressure,index);}
 int gray()const{return image[64*128+64]&255;}
};
int main(){
 const int fixed[]={65000,18000,3000,1200},loose[]={0,2000,12000,18800};
 printf("{\"cases\":[");
 for(int media=0;media<4;media++){
  Surface s(fixed[media],loose[media]);int before=s.gray();auto seed=s.mass;s.dab(0,0);assert(s.mass==seed);
  s.dab(.05,1);int light=s.gray();s.dab(.4,1);int medium=s.gray();s.dab(1,1);int firm=s.gray();
  assert(before<=light&&light<medium&&medium<firm&&firm>=before+20);
  auto held=s.mass;for(int i=0;i<100;i++)s.dab(1,1);assert(s.mass==held);
  s.dab(1,0);int repeat=s.gray();assert(repeat>firm+1);
  printf("%s{\"media\":%d,\"before\":%d,\"light\":%d,\"medium\":%d,\"firm\":%d,\"second_dab\":%d}",media?",":"",media,before,light,medium,firm,repeat);
 }
 puts("],\"passed\":true}");
}
