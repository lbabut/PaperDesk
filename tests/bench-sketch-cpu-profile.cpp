#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <chrono>
#include <cstdio>
#include <cstring>

static uint64_t digest(const void *ptr, size_t size, uint64_t hash=1469598103934665603ULL) {
    auto bytes=static_cast<const unsigned char*>(ptr);
    for(size_t i=0;i<size;++i) hash=(hash^bytes[i])*1099511628211ULL;
    return hash;
}
template<class T> static uint64_t hashVector(const std::vector<T>&v,uint64_t h) {
    return digest(v.data(),v.size()*sizeof(T),h);
}
int main(){
    for(int tool: {1,4,5,6,7,8}) {
        PaperMaterial e;e.init(320,320);
        std::vector<uint32_t> mass(320*320),image(mass.size(),0xffffffffu);
        std::vector<uint16_t> finger(82*81);
        // Eraser/finger run on existing pigment, not an empty sheet.
        if(tool>=6)for(int i=0;i<20;++i)e.segment(mass.data(),image.data(),finger.data(),4,48,0,1,30,30+i*12,.7,290,30+i*12,.7,i?1:0);
        auto start=std::chrono::steady_clock::now();double px=60,py=60,pp=.3;
        for(int i=0;i<300;++i){double x=40+(i%30)*8,y=50+(i/30)*22,p=.1+(i%19)*.045;
            e.tiltX=(i%7)*.12;e.tiltY=(i%5)*.09;
            e.segment(mass.data(),image.data(),finger.data(),tool,tool==1?12:38,0,.8,px,py,pp,x,y,p,i?1:0);
            px=x;py=y;pp=p;
        }
        auto us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
        uint64_t h=hashVector(mass,1469598103934665603ULL);
        h=hashVector(image,h);h=hashVector(finger,h);h=hashVector(e.burnish,h);h=hashVector(e.ink,h);
        h=digest(e.wear.data(),e.wear.size()*sizeof(double),h);
        printf("{\"tool\":%d,\"us\":%lld,\"digest\":\"%016llx\"}\n",tool,(long long)us,(unsigned long long)h);fflush(stdout);
    }
}
