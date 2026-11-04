// Frozen 4.2.7 kernel is intentional: compare full physical state, not just
// the optimized formula against a restatement of itself.
#define PaperMaterial ReferenceMaterial
#include "fixtures/sketch-material-4.2.7.h"
#undef PaperMaterial
#undef PAPER_SKETCH_MATERIAL_H
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <cstring>

template<class Engine> struct Surface {
    Engine engine;
    std::vector<uint32_t> mass, image;
    std::vector<uint16_t> finger;
    Surface(int w=160,int h=160):mass(w*h),image(w*h,0xffffffffu),finger(82*81){engine.init(w,h);}
    void dab(int tool,double size,double p,int i){
        engine.dab(mass.data(),image.data(),finger.data(),tool,size,i%3?0:150,.8,
                   80+(i%7-3)*3.125,80+(i%5-2)*4.0625,p);
    }
};
static void equal(const Surface<ReferenceMaterial>&a,const Surface<PaperMaterial>&b){
    assert(a.mass==b.mass && a.image==b.image && a.finger==b.finger);
    assert(a.engine.burnish==b.engine.burnish && a.engine.wear==b.engine.wear);
    assert(a.engine.ink==b.engine.ink && a.engine.hasInk==b.engine.hasInk);
    assert(a.engine.kneadedLift==b.engine.kneadedLift && a.engine.kneadedContact==b.engine.kneadedContact);
    assert(a.engine.untilNext==b.engine.untilNext);
}
static void correctness(){
    Surface<ReferenceMaterial>a;Surface<PaperMaterial>b;
    // Reuse each engine across paper, tool, pressure and radius changes, and
    // layers over both unburnished and deliberately polished paper.
    for(int paper=0;paper<3;paper++)for(int variant=0;variant<2;variant++){
        a.engine.setPaperKind(paper);b.engine.setPaperKind(paper);
        a.engine.kneaded=b.engine.kneaded=variant;
        a.engine.tiltX=b.engine.tiltX=variant?.7:0;
        a.engine.tiltY=b.engine.tiltY=variant?-.4:0;
        a.engine.contactAspect=b.engine.contactAspect=1.6;
        a.engine.contactAngle=b.engine.contactAngle=.4;
        for(int tool=0;tool<9;tool++)if(tool!=4&&tool!=5&&!(variant&&tool==6))for(double size:{1.,7.,23.,24.,25.,48.,80.}){
            for(int i=0;i<24;i++){
                const double pressures[]={0.,.006,.3,.6,.60000001,.65,1.,.3};
                double p=pressures[i%8];a.dab(tool,size,p,i);b.dab(tool,size,p,i);equal(a,b);
            }
            for(int i=0;i<16;i++){
                double p=.01+.99*i/15,x=30+i*6.125,y=25+(i%3)*24.0625;
                a.engine.segment(a.mass.data(),a.image.data(),a.finger.data(),tool,size,0,1,24,80,.65,x,y,p,i);
                b.engine.segment(b.mass.data(),b.image.data(),b.finger.data(),tool,size,0,1,24,80,.65,x,y,p,i);equal(a,b);
            }
        }
    }
    // Mixed polish/tooth pairs, including after a cached pressure hit.
    for(int tool=0;tool<4;tool++)for(double p:{.006,.3,.6,.65,1.}){
        for(size_t i=0;i<a.mass.size();i++){
            a.engine.burnish[i]=b.engine.burnish[i]=uint8_t(i/256);
            a.engine.tooth[i]=b.engine.tooth[i]=uint8_t(i);
        }
        a.dab(tool,80,p,0);b.dab(tool,80,p,0);equal(a,b);
    }
    puts("PASS cached vs frozen 4.2.7: exact optical/pigment/finger/burnish/wear/ink and sampler state");
}
template<class E> static long long shade(Surface<E>&s,int tool,double size,double pressure,bool varying){
    auto start=std::chrono::steady_clock::now();double px=200,py=800,ap=pressure;
    for(int i=0;i<1200;i++){
        int pass=i/60,step=i%60;double x=200+780.0*pass/19,y=800+450.0*(pass%2?59-step:step)/59;
        double p=varying?.1+.85*(i%61)/60:pressure;
        s.engine.segment(s.mass.data(),s.image.data(),s.finger.data(),tool,size,0,1,px,py,ap,x,y,p,i?1:0);
        px=x;py=y;ap=p;
    }
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
}
int main(int argc,char**){
    correctness();if(argc==1)return 0;
    for(int tool:{1})for(double size:{7.,24.,48.,80.})for(int variant=0;variant<3;variant++){
        long long oldTime=0,newTime=0;
        for(int repeat=0;repeat<3;repeat++){
            Surface<ReferenceMaterial>a(1200,1600);Surface<PaperMaterial>b(1200,1600);
            const double p=variant==0?.3:.65;
            if(repeat%2){newTime+=shade(b,tool,size,p,variant==2);oldTime+=shade(a,tool,size,p,variant==2);}
            else {oldTime+=shade(a,tool,size,p,variant==2);newTime+=shade(b,tool,size,p,variant==2);}
            equal(a,b);
        }
        printf("{\"tool\":%d,\"size\":%.0f,\"pressure_mode\":%d,\"before_us\":%lld,\"after_us\":%lld,\"speedup\":%.4f}\n",tool,size,variant,oldTime,newTime,double(oldTime)/newTime);fflush(stdout);
    }
}
