#ifndef PAPERSKETCH_DETAIL_PATTERN_H
#define PAPERSKETCH_DETAIL_PATTERN_H
/* A 200x200 drawing-pixel patch: 10x10 circles, diameters 4/6/8px,
 * each surrounded by four separate 3px diagonal hatches. Coordinates
 * are normalized to [0,10000], independent of digitizer rotation. */
#define DETAIL_CONTACTS 500
#define DETAIL_SAMPLES 3700
static int detail_length(int stroke) { return stroke%5==0?17:5; }
static void detail_point(int stroke,int sample,int *x,int *y) {
 static const int cosine[17]={1000,924,707,383,0,-383,-707,-924,-1000,-924,-707,-383,0,383,707,924,1000};
 static const int sine[17]={0,383,707,924,1000,924,707,383,0,-383,-707,-924,-1000,-924,-707,-383,0};
 int circle=stroke/5,kind=stroke%5,radius=100+50*(circle%3);
 int cx=500+(circle%10)*1000,cy=500+(circle/10)*1000;
 if(!kind){*x=cx+radius*cosine[sample]/1000;*y=cy+radius*sine[sample]/1000;}
 else {
  int ox=kind==1?radius+150:kind==2?-radius-150:0;
  int oy=kind==3?radius+150:kind==4?-radius-150:0;
  *x=cx+ox-75+150*sample/4;*y=cy+oy-75+150*sample/4;
 }
}
#endif
