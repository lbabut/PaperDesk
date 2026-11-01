#define PaperMaterial ReferenceMaterial
#include "fixtures/sketch-material-v41-before-saturation.h"
#undef PaperMaterial
#undef PAPER_SKETCH_MATERIAL_H
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <chrono>
#include <cstdio>
#include <cassert>
#include <numeric>

template<class Material> struct Fixture {
    static constexpr int W=1200,H=1600;
    Material p;
    std::vector<uint32_t> mass=std::vector<uint32_t>(W*H), image=std::vector<uint32_t>(W*H,0xffffffffu);
    std::vector<uint16_t> finger=std::vector<uint16_t>(82*81);
    Fixture(){p.init(W,H);}
    void reset(bool saturated){
        std::fill(mass.begin(),mass.end(),saturated?((uint32_t(30000)<<16)|35535):0);
        unsigned gray=saturated?p.optical[65535]:255;
        std::fill(image.begin(),image.end(),0xff000000u|gray*0x010101u);
        std::fill(finger.begin(),finger.end(),0);p.resetSurface();p.wear.fill(0);p.untilNext=0;
    }
    long long trajectory(int tool,bool saturated){
        reset(saturated);
        auto start=std::chrono::steady_clock::now();
        double ax=120,ay=900,ap=512/4095.0;
        p.segment(mass.data(),image.data(),finger.data(),tool,38,0,1,ax,ay,ap,ax,ay,ap,0);
        for(int i=1;i<1260;++i){
            int pass=i/60,step=i%60;
            double x=120+960*pass/20,y=900+300*(pass%2?59-step:step)/59;
            double pressure=(512+3072*step/59)/4095.0;
            p.segment(mass.data(),image.data(),finger.data(),tool,38,0,1,ax,ay,ap,x,y,pressure,1);
            ax=x;ay=y;ap=pressure;
        }
        return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
    }
};
int main(int argc,char **argv){
    (void)argv;
    Fixture<ReferenceMaterial> reference;Fixture<PaperMaterial> optimized;
    for(int paper=0;paper<3;++paper)for(int tool=0;tool<=7;++tool)for(bool saturated:{false,true}){
        reference.p.setPaperKind(paper);optimized.p.setPaperKind(paper);
        reference.p.tiltX=optimized.p.tiltX=.7;reference.p.tiltY=optimized.p.tiltY=-.3;
        reference.p.contactAspect=optimized.p.contactAspect=1.7;
        reference.p.contactAngle=optimized.p.contactAngle=.4;
        reference.p.kneaded=optimized.p.kneaded=tool==6&&paper==2;
        reference.trajectory(tool,saturated);optimized.trajectory(tool,saturated);
        assert(reference.mass==optimized.mass&&reference.image==optimized.image&&reference.finger==optimized.finger);
        assert(reference.p.burnish==optimized.p.burnish&&reference.p.wear==optimized.p.wear&&reference.p.untilNext==optimized.p.untilNext);
    }
    if(argc>1){puts("{\"bitwise_all_8_tools_3_papers_tilt_finger_kneaded\":true,\"trajectories_compared\":48}");return 0;}
    reference.p.setPaperKind(0);optimized.p.setPaperKind(0);
    reference.p.tiltX=optimized.p.tiltX=reference.p.tiltY=optimized.p.tiltY=0;
    reference.p.contactAspect=optimized.p.contactAspect=1;
    reference.p.contactAngle=optimized.p.contactAngle=0;
    reference.p.kneaded=optimized.p.kneaded=false;
    for(bool saturated:{false,true}){
        std::vector<long long> before,after;
        for(int run=0;run<9;++run){
            long long a,b;
            if(run%2){b=optimized.trajectory(4,saturated);a=reference.trajectory(4,saturated);}
            else{a=reference.trajectory(4,saturated);b=optimized.trajectory(4,saturated);}
            before.push_back(a);after.push_back(b);
        }
        auto rawBefore=before,rawAfter=after;
        std::sort(before.begin(),before.end());std::sort(after.begin(),after.end());
        printf("{\"bitwise_all_8_tools_3_papers_tilt_finger_kneaded\":true,\"trajectories_compared\":48,\"saturated\":%s,\"reference_median_us\":%lld,\"candidate_median_us\":%lld,\"change_percent\":%.2f,\"reference_runs_us\":[",
            saturated?"true":"false",before[4],after[4],100*(double(after[4])/before[4]-1));
        for(size_t i=0;i<rawBefore.size();++i)printf("%s%lld",i?",":"",rawBefore[i]);
        std::fputs("],\"candidate_runs_us\":[",stdout);
        for(size_t i=0;i<rawAfter.size();++i)printf("%s%lld",i?",":"",rawAfter[i]);
        std::puts("]}");
    }
}
