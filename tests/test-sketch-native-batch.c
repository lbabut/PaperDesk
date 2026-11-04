#define PAPERSKETCH_BATCH_TEST
#include "../product/payload/apps/papersketch/native/papersketch-ink.c"
#include <assert.h>
int main(void) {
    struct PreviewBatch batch={0};batch.last_ms=-PREVIEW_INTERVAL_MS;
    for(long t=0;t<2000;t+=2) {
        int box[4]={(int)(t/2)%100,100,(int)(t/2)%100+2,104};
        merge_batch(&batch,box);flush_batch(&batch,t,0);
    }
    assert(batch.updates==250);
    assert(batch.dirty);
    flush_batch(&batch,2000,1);
    assert(batch.updates==251 && !batch.dirty);
    flush_batch(&batch,2000,1);assert(batch.updates==251);
    int a[4]={40,50,60,70},b[4]={10,90,20,100};
    merge_batch(&batch,a);merge_batch(&batch,b);
    assert(batch.box[0]==10 && batch.box[1]==50 && batch.box[2]==60 && batch.box[3]==100);
    flush_batch(&batch,2001,0);assert(batch.dirty);
    flush_batch(&batch,2001,1);assert(!batch.dirty && batch.updates==252);
    batch.last_ms=100;batch.dirty=1;
    assert(preview_poll_timeout(&batch,102,1)==6);
    assert(preview_poll_timeout(&batch,108,1)==0);
    assert(preview_poll_timeout(&batch,120,1)==0);
    batch.dirty=0;assert(preview_poll_timeout(&batch,120,0)==ARM_CHECK_MS);
    backend_ready=1;
    parse_arm("fine 10 20 200 300 3 1 .15 .5 .95");assert(arm.on&&arm.fine&&arm.tool==1);
    assert(fine_width(1)==3&&fine_width(.1f)<fine_width(.9f));
    parse_arm("fine 10 20 200 300 3 8 .15 .5 .95");assert(arm.on&&fine_width(.1f)==3);
    parse_arm("fine 10 20 200 300 8 2 .15 .5 .95 .8");assert(arm.on&&fabsf(arm.strength-.8f)<.00001f);
    parse_arm("fine 10 20 200 300 8 2 .15 .5 .95");assert(arm.on&&arm.strength==1);
    const char *badStrength[]={"nan","inf","-.1","0",".01","1.1","junk",".8 junk"};
    for(unsigned i=0;i<sizeof badStrength/sizeof *badStrength;i++){
        char command[128];snprintf(command,sizeof command,"fine 10 20 200 300 8 2 .15 .5 .95 %s",badStrength[i]);
        parse_arm(command);assert(!arm.on);
    }
    parse_arm("fine 10 20 200 300 96 4 .15 .5 .95 .8");assert(arm.on&&arm.fine&&fine_width(1)==96);
    const char *invalid[]={"off","fine 10 20 200 300 nan 1 .15 .5 .95","fine 10 20 200 300 3 7 .15 .5 .95","fine 10 20 200 300 3 6 .15 .5 .95","fine 10 20 200 300 3 1 .5 .4 .95","fine 1400 20 200 300 3 1 .15 .5 .95","fine 10 20 200 300 99 1 .15 .5 .95"};
    for(unsigned i=0;i<sizeof invalid/sizeof *invalid;i++){parse_arm(invalid[i]);assert(!arm.on);}
    backend_ready=0;parse_arm("fine 10 20 200 300 3 1 .15 .5 .95");assert(!arm.on);
    backend_ready=1;parse_arm("on 1 2 20 30 8 1 3");assert(arm.on&&!arm.fine&&arm.erase);
    uint32_t pixels[32*32];unsigned char mask[32*32];
    for(int i=0;i<32*32;i++){pixels[i]=0xffffffffu;mask[i]=0;}
    surf.px=pixels;surf.mk=mask;surf.ps=surf.ms=32;
    parse_arm("fine 4 4 16 16 3 1 .15 .5 .95");int box[4];
    segment(-100,-100,100,100,3,0xff000000u,box);int dark=0;
    for(int y=0;y<32;y++)for(int x=0;x<32;x++){
        if(x<4||x>=20||y<4||y>=20){assert(pixels[y*32+x]==0xffffffffu&&mask[y*32+x]==0);}
        else if(pixels[y*32+x]==0xff000000u){assert(mask[y*32+x]==255);dark++;}
    }
    assert(dark>0);
    // Pale provisional ink must leave every skipped pixel and mask untouched.
    for(int i=0;i<32*32;i++){pixels[i]=0xff777777u;mask[i]=17;}
    segment(4,12,20,12,32,0xffaaaaaau,box);int shadeDots=0;
    for(int y=4;y<20;y++)for(int x=4;x<20;x++){
        int at=y*32+x;
        if(sketchPreviewDot(170,x,y)){assert(pixels[at]==0xff000000u&&mask[at]==255);shadeDots++;}
        else assert(pixels[at]==0xff777777u&&mask[at]==17);
    }
    assert(shadeDots==88); // 22/64 coverage, all four Bayer cells.
    uint32_t once[32*32];memcpy(once,pixels,sizeof once);
    segment(4,12,20,12,32,0xffaaaaaau,box);
    assert(!memcmp(once,pixels,sizeof once)); // No temporal darkening.
    segment(4,12,20,12,32,0xffffffffu,box); // Almost invisible pressure: faint guide, never white paint.
    for(int y=4;y<20;y++)for(int x=4;x<20;x++)assert(pixels[y*32+x]!=0xffffffffu);
    segment(4,12,20,12,32,0xff000000u,box);
    for(int y=4;y<20;y++)for(int x=4;x<20;x++)assert(pixels[y*32+x]==0xff000000u);
    // Every subpixel phase of a very pale thin tip has a visible latest pixel.
    for(int width=1;width<=3;width++)for(int y=0;y<32;y++)for(int x=0;x<32;x++){
        memset(pixels,255,sizeof pixels);memset(mask,0,sizeof mask);
        float sx=5+x*.25f,sy=5+y*.25f;
        segment(sx,sy,sx,sy,width,0xffdfdfdfu,box);
        int tx=(int)sx,ty=(int)sy;
        assert(pixels[ty*32+tx]==0xff000000u&&mask[ty*32+tx]==255);
        assert(tx>=box[0]&&tx<=box[2]&&ty>=box[1]&&ty<=box[3]);
    }
    puts("PASS: 3072 pale thin-tip phases visible; pending flush uses remaining 8ms deadline");
    parse_arm("on 4 4 16 16 3 1 3");
    segment(4,12,20,12,32,0xffffffffu,box);
    for(int y=4;y<20;y++)for(int x=4;x<20;x++)assert(pixels[y*32+x]==0xffffffffu);
    puts("PASS: pale guide density, stable screen pattern, existing pigment/mask preservation, opaque ink and legacy eraser");
    uint32_t widePixels[128*128];unsigned char wideMask[128*128];
    memset(widePixels,255,sizeof widePixels);memset(wideMask,0,sizeof wideMask);
    surf.px=widePixels;surf.mk=wideMask;surf.ps=surf.ms=128;
    parse_arm("fine 16 16 96 96 96 4 .15 .5 .95");
    segment(0,0,127,127,96,0xff000000u,box);int wideDark=0;
    for(int y=0;y<128;y++)for(int x=0;x<128;x++){
        int at=y*128+x;
        if(x<16||x>=112||y<16||y>=112)assert(widePixels[at]==0xffffffffu&&wideMask[at]==0);
        else if(widePixels[at]==0xff000000u){assert(wideMask[at]==255);wideDark++;}
    }
    assert(wideDark>7000&&box[0]==16&&box[1]==16&&box[2]==111&&box[3]==111);
    puts("PASS: maximum wide preview clips pixels and mask to canvas");
    puts("PASS: fine-preview capability/permit bounds, pressure and ink widths, invalid permits and clipped native pixels");
    puts("PASS: 1000 reports coalesced to 251 updates; final tail and union bounds preserved");
    return 0;
}
