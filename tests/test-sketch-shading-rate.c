#include "device/papersketch-shading-rate.h"
#include <assert.h>
int main(void){
 assert(sketch_shading_interval_us("shade")==4000);
 assert(sketch_shading_interval_us("shade-tilt")==4000);
 assert(sketch_shading_interval_us("shade-fast")==2000);
 assert(sketch_shading_interval_us("shade-tilt-fast")==2000);
 assert(sketch_shading_interval_us("typo")==0);
 assert(sketch_shading_interval_us("micro-loop")==0);
}
