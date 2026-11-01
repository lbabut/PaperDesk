#include "../product/payload/apps/papersketch/native/sketch-touch.h"
#include <cassert>
int main(){
    PaperTouch touch;touch.activate();touch.push({100,200,52,28,.4,.3});
    auto sample=touch.match(100,200);assert(sample.major==52&&sample.minor==28&&sample.pressure==.4);
    assert(touch.match(200,300).time==0);
    for(int i=0;i<500;i++)touch.push({double(i),300,40,20,.7,0});
    assert(touch.count==256&&touch.match(499,300).major==40);
    touch.pause();assert(touch.match(499,300).time==0);
}
