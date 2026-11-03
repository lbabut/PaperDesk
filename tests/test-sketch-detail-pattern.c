#include <assert.h>
#include <stdlib.h>
#include "device/papersketch-detail-pattern.h"
int main(void) {
 int samples=0,circles=0,hatches=0;
 for(int stroke=0;stroke<DETAIL_CONTACTS;stroke++){
  int firstx=0,firsty=0,previousx=-1,previousy=-1;
  for(int i=0;i<detail_length(stroke);i++){
   int x,y;detail_point(stroke,i,&x,&y);
   assert(x>=0&&x<=10000&&y>=0&&y<=10000);
   if(i==0){firstx=x;firsty=y;}
   else assert(x!=previousx||y!=previousy);
   if(stroke%5==0){
    int cx=500+(stroke/5%10)*1000,cy=500+(stroke/50)*1000;
    int radius=100+50*(stroke/5%3),rr=(x-cx)*(x-cx)+(y-cy)*(y-cy);
    /* Integer quantization stays within 2 normalized units of a circle. */
    assert(rr>=(radius-2)*(radius-2)&&rr<=(radius+2)*(radius+2));
   }
   previousx=x;previousy=y;samples++;
  }
  if(stroke%5==0){assert(firstx==previousx&&firsty==previousy);circles++;}
  else {assert(abs(previousx-firstx)==150&&abs(previousy-firsty)==150);hatches++;}
 }
 assert(circles==100&&hatches==400&&samples==DETAIL_SAMPLES);
 return 0;
}
