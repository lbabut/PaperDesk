#ifndef PAPER_SKETCH_MATERIAL_H
#define PAPER_SKETCH_MATERIAL_H
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
// Pigment is stored as two 16-bit masses per paper pixel: fixed and loose.
// The fingertip is a second, persistent mass map. Exchange conserves pigment.
struct PaperMaterial {
    int width=0,height=0;std::vector<uint8_t> tooth;
    uint8_t optical[65536]{};uint16_t inverse[256]{};double untilNext=0;
    static uint32_t hash(uint32_t x,uint32_t y){uint32_t n=x*374761393u+y*668265263u+0x9e3779b9u;n=(n^(n>>13))*1274126177u;return n^(n>>16);}
    void init(int w,int h){
        if(width==w&&height==h)return;width=w;height=h;tooth.resize(w*h);
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            int fine=hash(x,y)&255,coarse=hash(x/4,y/4)&255,fiber=hash(x/2,y/9)&255;
            tooth[y*w+x]=(fine*3+coarse*2+fiber)/6;
        }
        for(int i=0;i<65536;i++)optical[i]=(uint8_t)std::lround(255*std::exp(-i/14000.0));
        for(int i=0;i<256;i++)inverse[i]=(uint16_t)std::min(65535.0,std::round(-std::log(std::max(1,i)/255.0)*14000));
    }
    void import(const uint32_t* image,uint32_t* mass){
        for(int i=0;i<width*height;i++){int total=inverse[image[i]&255],fixed=total*7/10;mass[i]=(uint32_t(fixed)<<16)|(total-fixed);}
    }
    void dab(uint32_t* mass,uint32_t* image,uint16_t* finger,int tool,double size,double tone,double strength,double cx,double cy,double pressure){
        double p=std::clamp(pressure,0.04,1.0),radius=tool==7?std::max(6.0,size*.5*(.65+.35*p)):std::max(.8,size*(.18+.82*p)*.5);
        int x0=std::max(0,(int)std::floor(cx-radius)),x1=std::min(width-1,(int)std::ceil(cx+radius));
        int y0=std::max(0,(int)std::floor(cy-radius)),y1=std::min(height-1,(int)std::ceil(cy+radius));
        const double doses[]={6000,12000,16000,22000,20000,24000};
        const double fixedFraction[]={.94,.78,.58,.38,.14,.08};
        const double capacities[]={18000,30000,40000,55000,65000,65535};
        double rr=radius*radius;
        for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++){
            double dx=x+.5-cx,dy=y+.5-cy,edge=1-(dx*dx+dy*dy)/rr;if(edge<=0)continue;
            edge*=edge;int at=y*width+x;uint32_t packed=mass[at];int fixed=packed>>16,loose=packed&65535;
            double grain=tooth[at]/255.0;
            if(tool==7){
                int fx=std::clamp((int)std::lround(dx)+40,0,80),fy=std::clamp((int)std::lround(dy)+40,0,80),fi=fy*82+fx;
                int held=finger[fi],room=65535-held;
                int pickLoose=std::min({loose,room,(int)std::lround(loose*.13*p*strength*edge)});
                int pickFixed=std::min({fixed,room-pickLoose,(int)std::lround(fixed*.012*p*p*strength*edge)});
                loose-=pickLoose;fixed-=pickFixed;held+=pickLoose+pickFixed;
                int deposit=std::min(65535-fixed-loose,(int)std::lround(held*.16*p*strength*edge));
                loose+=deposit;held-=deposit;finger[fi]=held;
            }else if(tool==6){
                double contact=edge*strength*(.15+.85*p);
                loose-=std::min(loose,(int)std::lround(loose*contact*.65));
                fixed-=std::min(fixed,(int)std::lround(fixed*contact*.28));
            }else{
                double contact=std::clamp((p+.2-grain*(tool<4?.7:.5))*2.0,0.0,1.0);
                double valley=std::clamp((.9-grain)/.7,0.0,1.0);
                int capacity=(int)(capacities[tool]*(.08+.92*valley*valley));
                int room=std::max(0,capacity-fixed-loose);
                double amount=doses[tool]*strength*p*edge*contact*(1-tone/255.0)*(room/double(capacity));
                int added=std::min(room,(int)std::lround(amount));
                int bonded=(int)std::lround(added*fixedFraction[tool]);fixed+=bonded;loose+=added-bonded;
            }
            mass[at]=(uint32_t(fixed)<<16)|loose;int gray=optical[fixed+loose];
            image[at]=0xff000000u|uint32_t(gray)*0x010101u;
        }
        if(tool==7){
            // Friction mixes neighboring fingertip cells. Pairwise exchange keeps
            // total pigment exact and prevents the sampling lattice making combs.
            int lo=std::max(0,40-(int)std::ceil(radius)),hi=std::min(80,40+(int)std::ceil(radius));
            for(int y=lo;y<=hi;y++)for(int x=lo;x<=hi;x++){
                int i=y*82+x;
                if(x<hi){int flow=(int(finger[i])-int(finger[i+1]))/4;finger[i]-=flow;finger[i+1]+=flow;}
                if(y<hi){int flow=(int(finger[i])-int(finger[i+82]))/4;finger[i]-=flow;finger[i+82]+=flow;}
            }
        }
    }
    void segment(uint32_t* mass,uint32_t* image,uint16_t* finger,int tool,double size,double tone,double strength,double ax,double ay,double ap,double bx,double by,double bp,int index){
        if(!index){untilNext=0;dab(mass,image,finger,tool,size,tone,strength,bx,by,bp);return;}
        double dx=bx-ax,dy=by-ay,length=std::hypot(dx,dy);if(length<.001)return;
        double spacing=std::clamp(size*.10,.65,2.0),travel=untilNext>0?untilNext:spacing;
        while(travel<=length){double t=travel/length;dab(mass,image,finger,tool,size,tone,strength,ax+dx*t,ay+dy*t,ap+(bp-ap)*t);travel+=spacing;}
        untilNext=travel-length;
    }
};
#endif
