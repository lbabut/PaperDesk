#define PAPERSKETCH_BATCH_TEST
#include "../product/payload/apps/papersketch/native/papersketch-ink.c"
#include <assert.h>
int main(void) {
    struct PreviewBatch batch={0};batch.last_ms=-PREVIEW_INTERVAL_MS;
    for(long t=0;t<2000;t+=2) {
        int box[4]={(int)(t/2)%100,100,(int)(t/2)%100+2,104};
        merge_batch(&batch,box);flush_batch(&batch,t,0);
    }
    assert(batch.updates==125);
    assert(batch.dirty);
    flush_batch(&batch,2000,1);
    assert(batch.updates==126 && !batch.dirty);
    flush_batch(&batch,2000,1);assert(batch.updates==126);
    int a[4]={40,50,60,70},b[4]={10,90,20,100};
    merge_batch(&batch,a);merge_batch(&batch,b);
    assert(batch.box[0]==10 && batch.box[1]==50 && batch.box[2]==60 && batch.box[3]==100);
    flush_batch(&batch,2001,0);assert(batch.dirty);
    flush_batch(&batch,2001,1);assert(!batch.dirty && batch.updates==127);
    backend_ready=1;
    parse_arm("fine 10 20 200 300 3 1 .15 .5 .95");assert(arm.on&&arm.fine&&arm.tool==1);
    assert(fine_width(1)==3&&fine_width(.1f)<fine_width(.9f));
    parse_arm("fine 10 20 200 300 3 8 .15 .5 .95");assert(arm.on&&fine_width(.1f)==3);
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
    puts("PASS: fine-preview capability/permit bounds, pressure and ink widths, invalid permits and clipped native pixels");
    puts("PASS: 1000 reports coalesced to 126 updates; final tail and union bounds preserved");
    return 0;
}
