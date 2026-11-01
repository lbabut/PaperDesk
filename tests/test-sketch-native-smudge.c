#include "../product/payload/apps/papersketch/native/sketch-smudge.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
int main(void) {
    int w=248,h=128;uint8_t *data=malloc((size_t)w*h*4);assert(data);
    memset(data,255,(size_t)w*h*4);
    for(int y=0;y<h;y++)for(int x=116;x<132;x++)data[(y*w+x)*4]=data[(y*w+x)*4+1]=data[(y*w+x)*4+2]=0;
    struct timespec a,b;clock_gettime(CLOCK_MONOTONIC,&a);
    assert(sk_smudge(data,w,h,64,64,184,64,64,1));
    clock_gettime(CLOCK_MONOTONIC,&b);
    int core=data[(64*w+124)*4],beside=data[(64*w+151)*4];
    assert(core==166 && beside==94 && data[0]==255);
    printf("PASS native smudge: core=%d beside=%d time=%.3f ms\n",core,beside,(b.tv_sec-a.tv_sec)*1000.0+(b.tv_nsec-a.tv_nsec)/1000000.0);
    memset(data,255,(size_t)w*h*4);assert(sk_smudge(data,w,h,64,64,184,64,64,1));
    for(int i=0;i<w*h*4;i++)assert(data[i]==255);
    free(data);return 0;
}
