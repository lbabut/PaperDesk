#ifndef PAPER_SKETCH_SHADING_RATE_H
#define PAPER_SKETCH_SHADING_RATE_H
#include <string.h>
static inline int sketch_shading_interval_us(const char *pattern){
 if(!strcmp(pattern,"shade-fast")||!strcmp(pattern,"shade-tilt-fast"))return 2000;
 if(!strcmp(pattern,"shade")||!strcmp(pattern,"shade-tilt"))return 4000;
 return 0;
}
#endif
