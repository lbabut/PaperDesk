#ifndef PAPERSKETCH_SMUDGE_H
#define PAPERSKETCH_SMUDGE_H
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
static double sk_clamp(double v,double a,double b){return v<a?a:v>b?b:v;}
static int sk_smudge(uint8_t *data,int w,int h,double ax,double ay,double bx,double by,double size,double strength) {
    double dx=bx-ax,dy=by-ay,len2=dx*dx+dy*dy;
    if(len2<0.01)return 1;
    size_t n=(size_t)w*h;
    float *gray=(float*)malloc(n*sizeof(float)),*horizontal=(float*)malloc(n*sizeof(float)),*blur=(float*)malloc(n*sizeof(float));
    if(!gray || !horizontal || !blur){free(gray);free(horizontal);free(blur);return 0;}
    for(size_t i=0;i<n;i++)gray[i]=data[i*4];
    double r=sk_clamp(size/2,6,40),distance=sqrt(len2),ux=dx/distance,uy=dy/distance;
    int br=(int)floor(r*0.18+0.5);if(br<1)br=1;
    int diameter=br*2+1;
    for(int y=0;y<h;y++){
        int row=y*w;double sum=0;
        for(int k=-br;k<=br;k++)sum+=gray[row+(int)sk_clamp(k,0,w-1)];
        for(int x=0;x<w;x++){
            horizontal[row+x]=sum/diameter;
            sum+=gray[row+(int)sk_clamp(x+br+1,0,w-1)]-gray[row+(int)sk_clamp(x-br,0,w-1)];
        }
    }
    for(int x=0;x<w;x++){
        double sum=0;for(int k=-br;k<=br;k++)sum+=horizontal[(int)sk_clamp(k,0,h-1)*w+x];
        for(int y=0;y<h;y++){
            blur[y*w+x]=sum/diameter;
            sum+=horizontal[(int)sk_clamp(y+br+1,0,h-1)*w+x]-horizontal[(int)sk_clamp(y-br,0,h-1)*w+x];
        }
    }
    double shift=distance<r*0.8?distance:r*0.8,radius2=r*r,opacity=sk_clamp(strength,0.05,1)*0.65;
    for(int y=0;y<h;y++)for(int x=0;x<w;x++){
        double px=x-ax,py=y-ay,t=sk_clamp((px*dx+py*dy)/len2,0,1),ex=px-t*dx,ey=py-t*dy;
        double falloff=1-(ex*ex+ey*ey)/radius2;if(falloff<=0)continue;falloff*=falloff;
        double fx=sk_clamp(x-ux*shift*falloff,0,w-1),fy=sk_clamp(y-uy*shift*falloff,0,h-1);
        int ix=(int)fx,iy=(int)fy,jx=ix+1<w?ix+1:ix,jy=iy+1<h?iy+1:iy;
        double mx=fx-ix,my=fy-iy;
        double transported=(blur[iy*w+ix]*(1-mx)+blur[iy*w+jx]*mx)*(1-my)+(blur[jy*w+ix]*(1-mx)+blur[jy*w+jx]*mx)*my;
        int at=y*w+x;double mix=opacity*falloff;
        uint8_t v=(uint8_t)floor(gray[at]*(1-mix)+transported*mix+0.5);
        data[at*4]=data[at*4+1]=data[at*4+2]=v;data[at*4+3]=255;
    }
    free(gray);free(horizontal);free(blur);return 1;
}


#endif
