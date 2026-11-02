#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <iostream>
struct Board{
 PaperMaterial p;std::vector<uint32_t> m,image;std::vector<uint16_t> f;
 Board():m(320*320),image(320*320,0xffffffffu),f(82*81){p.init(320,320);}
 void line(int tool,double pressure,int size=2){p.segment(m.data(),image.data(),f.data(),tool,size,0,1,60,160,pressure,60,160,pressure,0);p.segment(m.data(),image.data(),f.data(),tool,size,0,1,60,160,pressure,260,160,pressure,1);}
};
int main(){
 Board light,firm;light.line(8,.08);firm.line(8,.95);assert(light.image==firm.image&&light.p.ink==firm.p.ink);assert(light.p.hasInk);
 assert(light.image[160*320+160]==0xff000000u);assert(light.image[156*320+160]==0xffffffffu);
 assert(std::all_of(light.m.begin(),light.m.end(),[](uint32_t v){return v==0;}));
 auto before=light.image;light.line(7,1,64);assert(light.image==before);
 light.line(6,1,50);assert(light.image==before);
 light.p.kneaded=true;light.line(6,1,50);assert(light.image==before);
 Board tilted;tilted.p.tiltX=.9;tilted.p.tiltY=.8;tilted.p.wear.fill(1);tilted.p.setPaperKind(2);tilted.line(8,.7);assert(tilted.image==firm.image);
 Board sparse,dense;sparse.line(8,.6,3);dense.p.segment(dense.m.data(),dense.image.data(),dense.f.data(),8,3,0,1,60,160,.6,60,160,.6,0);
 for(int x=61;x<=260;x++)dense.p.segment(dense.m.data(),dense.image.data(),dense.f.data(),8,3,0,1,x-1,160,.6,x,160,.6,1);
 assert(sparse.image==dense.image&&sparse.p.ink==dense.p.ink);
 for(int size:{1,2,40,80}){Board edge;edge.p.segment(edge.m.data(),edge.image.data(),edge.f.data(),8,size,0,1,0,0,.2,0,0,.2,0);edge.p.segment(edge.m.data(),edge.image.data(),edge.f.data(),8,size,0,1,0,0,.2,319,319,.9,1);assert(edge.p.hasInk);}
 Board zero;zero.line(8,0);assert(!zero.p.hasInk);
 std::cout<<"PASS rapidograph: constant width/blackness, no pressure/tilt/tooth/wear response, persistent ink under smudge and erasers, event-resampling invariance and bounded maximum footprint"<<std::endl;
}
