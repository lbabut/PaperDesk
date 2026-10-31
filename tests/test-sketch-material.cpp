#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <numeric>
struct Fixture{
 PaperMaterial p;std::vector<uint32_t> m,img;std::vector<uint16_t> finger;
 Fixture():m(320*320),img(320*320,0xffffffffu),finger(82*81){p.init(320,320);}
 void line(int tool,double ax,double ay,double bx,double by,double pressure=1,int size=24){p.segment(m.data(),img.data(),finger.data(),tool,size,0,1,ax,ay,pressure,ax,ay,pressure,0);p.segment(m.data(),img.data(),finger.data(),tool,size,0,1,ax,ay,pressure,bx,by,pressure,1);}
 uint64_t mass(){uint64_t sum=0;for(auto v:m)sum+=(v>>16)+(v&65535);for(auto v:finger)sum+=v;return sum;}
 uint64_t loose(){uint64_t sum=0;for(auto v:m)sum+=v&65535;return sum;}
 int gray(int x,int y){return img[y*320+x]&255;}
};
int main(){
 Fixture tiny;tiny.line(1,160,160,160,160,1,1);assert(tiny.mass()>0);
 Fixture white;white.line(7,60,160,260,160,.7,64);assert(white.mass()==0&&white.gray(160,160)==255);
 Fixture hb,coal;hb.line(1,160,80,160,240);coal.line(4,160,80,160,240);assert(coal.loose()>hb.loose()*2);
 auto sum=coal.mass();int core=coal.gray(160,160);coal.line(7,100,160,240,160,1,64);assert(coal.mass()==sum);assert(coal.gray(160,160)>core);assert(coal.gray(195,160)<255);
 Fixture light,heavy;light.line(4,160,80,160,240);heavy=light;light.line(7,100,160,240,160,.1,64);heavy.line(7,100,160,240,160,1,64);assert(heavy.gray(160,160)>light.gray(160,160));
 sum=hb.mass();hb.line(6,160,80,160,240,1,40);assert(hb.mass()<sum/2);
 Fixture sparse,dense;sparse.line(1,60,160,260,160,1,20);
 dense.p.segment(dense.m.data(),dense.img.data(),dense.finger.data(),1,20,0,1,60,160,1,60,160,1,0);
 for(int x=62;x<=260;x+=2)dense.p.segment(dense.m.data(),dense.img.data(),dense.finger.data(),1,20,0,1,x-2,160,1,x,160,1,1);
 assert(sparse.m==dense.m);
 std::vector<long> timing;Fixture speed;speed.line(4,160,20,160,300);
 for(int i=0;i<500;i++){double x=80+(i%100)*1.5;auto t=std::chrono::steady_clock::now();speed.p.segment(speed.m.data(),speed.img.data(),speed.finger.data(),7,64,0,1,x,160,.7,x+1.5,160,.7,1);timing.push_back(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-t).count());}
 std::sort(timing.begin(),timing.end());
 printf("{\"passed\":true,\"charcoal_core_before\":%d,\"charcoal_core_after\":%d,\"transported_gray\":%d,\"mass_conserved\":true,\"resampling_invariant\":true,\"smudge_p50_us\":%ld,\"smudge_p95_us\":%ld,\"smudge_max_us\":%ld}\\n",core,coal.gray(160,160),coal.gray(195,160),timing[250],timing[475],timing[499]);
}
