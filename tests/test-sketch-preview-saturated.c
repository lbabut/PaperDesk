// Differential check against the frozen pre-fast-path segment implementation.
#define PAPERSKETCH_BATCH_TEST
#include "../product/payload/apps/papersketch/native/papersketch-ink.c"
#include <assert.h>

static void reference(float x0,float y0,float x1,float y1,float w,uint32_t ink,int box[4]) {
    float minimum=arm.fine?.5f:.75f;
    float r=w/2<minimum?minimum:w/2;
    int bx0=clampi((int)((x0<x1?x0:x1)-r),arm.x,arm.x+arm.w-1);
    int by0=clampi((int)((y0<y1?y0:y1)-r),arm.y,arm.y+arm.h-1);
    int bx1=clampi((int)((x0>x1?x0:x1)+r+1),arm.x,arm.x+arm.w-1);
    int by1=clampi((int)((y0>y1?y0:y1)+r+1),arm.y,arm.y+arm.h-1);
    float dx=x1-x0,dy=y1-y0,len2=dx*dx+dy*dy;
    for(int y=by0;y<=by1;y++)for(int x=bx0;x<=bx1;x++) {
        float px=x+.5f-x0,py=y+.5f-y0;
        float t=len2>0?(px*dx+py*dy)/len2:0;
        t=t<0?0:t>1?1:t;
        float ex=px-t*dx,ey=py-t*dy;
        if(ex*ex+ey*ey>r*r)continue;
        int gray=ink&255;
        if(arm.fine&&(arm.tool==4||arm.tool==5))gray=sketchCharcoalPreviewGray(gray,1-(ex*ex+ey*ey)/(r*r),x-arm.x,y-arm.y);
        if(arm.fine&&!arm.erase&&!((arm.tool==4||arm.tool==5)?sketchPreviewDotExact(gray,x,y):sketchPreviewDot(gray,x,y)))continue;
        surf.px[y*surf.ps+x]=arm.fine&&!arm.erase?0xff000000u:ink;
        surf.mk[y*surf.ms+x]=0xff;
    }
    if(arm.fine&&!arm.erase&&x1>=arm.x&&x1<arm.x+arm.w&&y1>=arm.y&&y1<arm.y+arm.h) {
        int tx=(int)x1,ty=(int)y1;surf.px[ty*surf.ps+tx]=0xff000000u;surf.mk[ty*surf.ms+tx]=255;
    }
    box[0]=bx0;box[1]=by0;box[2]=bx1;box[3]=by1;
}
static uint32_t seed=20261125;
static uint32_t random_u(void){seed^=seed<<13;seed^=seed>>17;seed^=seed<<5;return seed;}
int main(void) {
    enum{W=80,H=80,N=W*H};
    uint32_t a[N],b[N];unsigned char ma[N],mb[N];
    surf.ps=surf.ms=W;int cases=0;
    // Deliberately collide cache rows/columns, including negative coordinates.
    // Changing gray/edge must never reuse a shade instead of immutable grain.
    for(int i=0;i<120000;i++) {
        int x=(int)(random_u()%4096)-2048,y=(int)(random_u()%4096)-2048;
        float edge=(random_u()%10001)/10000.f;int gray=random_u()%256;
        assert(cached_charcoal_gray(gray,edge,x,y)==sketchCharcoalPreviewGray(gray,edge,x,y));
        assert(cached_charcoal_gray(gray,edge,x,y)==sketchCharcoalPreviewGray(gray,edge,x,y));
        assert(cached_charcoal_gray(255-gray,1-edge,x,y)==sketchCharcoalPreviewGray(255-gray,1-edge,x,y));
    }
    for(int mode=0;mode<3;mode++)for(int tool=0;tool<=8;tool++)for(int series=0;series<24;series++) {
        arm.fine=mode!=0;arm.erase=mode==2;arm.tool=tool;
        arm.x=series%9;arm.y=series%7;arm.w=W-arm.x-series%11;arm.h=H-arm.y-series%13;
        for(int i=0;i<N;i++) {
            unsigned state=random_u()%5;
            a[i]=state<3?0xff000000u:state==3?0xffffffffu:random_u();
            ma[i]=(unsigned char)(state==0?255:state==1?0:random_u());
        }
        memcpy(b,a,sizeof a);memcpy(mb,ma,sizeof ma);
        for(int step=0;step<12;step++) {
            float x0=(int)(random_u()%120)-20+(random_u()%10)/10.f;
            float y0=(int)(random_u()%120)-20+(random_u()%10)/10.f;
            float x1=step%3?x0+(int)(random_u()%21)-10:x0;
            float y1=step%3?y0+(int)(random_u()%21)-10:y0;
            float width=(random_u()%960+1)/10.f;uint32_t ink=random_u();
            int ba[4],bb[4];surf.px=a;surf.mk=ma;reference(x0,y0,x1,y1,width,ink,ba);
            surf.px=b;surf.mk=mb;segment(x0,y0,x1,y1,width,ink,bb);
            assert(!memcmp(a,b,sizeof a));assert(!memcmp(ma,mb,sizeof ma));assert(!memcmp(ba,bb,sizeof ba));cases++;
            // External repaint or mask clear must invalidate the shortcut.
            int at=random_u()%N;a[at]=b[at]=random_u();ma[at]=mb[at]=(unsigned char)random_u();
        }
    }
    printf("PASS %d differential segments: pixels, masks, boxes, clipping, pale tips, external repaint, fine/nonfine/eraser\n",cases);
    return 0;
}
