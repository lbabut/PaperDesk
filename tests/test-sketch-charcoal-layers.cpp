
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <cstdio>
struct Surface{
 PaperMaterial p;std::vector<uint32_t> mass,image;std::vector<uint16_t> finger;
 Surface():mass(1000*160),image(1000*160,0xffffffffu),finger(82*81){p.init(1000,160);}
 void pass(int tool,int size){p.segment(mass.data(),image.data(),finger.data(),tool,size,0,1,100,80,.5,100,80,.5,0);p.segment(mass.data(),image.data(),finger.data(),tool,size,0,1,100,80,.5,900,80,.5,1);}
 double mean()const{double sum=0;int count=0;for(int y=76;y<=84;y++)for(int x=480;x<544;x++){sum+=image[y*1000+x]&255;count++;}return sum/count;}
};
int main(){
 bool comma=false;printf("{\"cases\":[");
 for(int paper=0;paper<3;paper++)for(int size:{48,80}){
  double first[2]={0,0};
  for(int tool:{4,5}){
   Surface s;s.p.setPaperKind(paper);double previous=255,levels[5];
   for(int layer=0;layer<5;layer++){s.pass(tool,size);levels[layer]=s.mean();assert(levels[layer]<previous-.5);previous=levels[layer];}
   first[tool-4]=levels[0];assert(levels[4]<levels[0]-25);
   if(comma)printf(",");comma=true;printf("{\"paper\":%d,\"size\":%d,\"tool\":%d,\"gray\":[",paper,size,tool);
   for(int i=0;i<5;i++)printf("%s%.3f",i?",":"",levels[i]);printf("]}");fflush(stdout);
  }
  assert(first[1]<first[0]-20);
 }
 puts("],\"passed\":true}");
}
