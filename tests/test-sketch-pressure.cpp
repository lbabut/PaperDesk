#include "../product/payload/apps/papersketch/native/sketch-pressure.h"
#include <cassert>
#include <limits>
int main(){
    PaperPressure p;assert(p.map(.25)==.25);p.start();
    p.collect(std::numeric_limits<double>::quiet_NaN());p.collect(0);assert(p.samples[0].empty());
    assert(!p.next());
    for(int stage=0;stage<3;stage++){
        for(int i=0;i<40;i++)p.collect(.08+stage*.35+(i%3)*.001);
        if(stage<2)assert(p.next());
    }
    std::array<double,3>a;assert(p.candidate(a));p.anchors=a;p.calibrated=true;p.cancel();
    assert(std::abs(p.map(a[0])-.15)<1e-9&&std::abs(p.map(a[1])-.5)<1e-9&&std::abs(p.map(a[2])-.95)<1e-9);
    double previous=-1;for(int i=0;i<=10000;i++){double v=p.map(i/10000.0);assert(v>=previous&&v>=0&&v<=1);previous=v;}
    auto old=p.anchors;p.start();for(int stage=0;stage<3;stage++){for(int i=0;i<20;i++)p.collect(.5);if(stage<2)assert(p.next());}
    assert(!p.candidate(a));p.cancel();assert(p.anchors==old&&p.calibrated);
    assert(!PaperPressure::valid({0,.4,.8})&&!PaperPressure::valid({.2,.3,.31}));
}
