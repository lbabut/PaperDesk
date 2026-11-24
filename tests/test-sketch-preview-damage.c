// Offline screen-space replay of the *unchanged* native preview implementation.
// No framebuffer, event device, xochitl, persisted artwork or predictions used.
#define PAPERSKETCH_BATCH_TEST
#include "../product/payload/apps/papersketch/native/papersketch-ink.c"
#include <assert.h>

static uint32_t image[SCREEN_W*SCREEN_H];
static unsigned char marks[SCREEN_W*SCREEN_H];
struct Damage { unsigned long long submitted, tight, touched, segment_boxes;
    int updates, max_width, max_height, samples; };

static unsigned long long area(const int b[4]) {
    return (unsigned long long)(b[2]-b[0]+1)*(b[3]-b[1]+1);
}
static void record(struct Damage *d,const int b[4]) {
    int tight[4]={SCREEN_W,SCREEN_H,-1,-1};
    unsigned long long count=0;
    for(int y=b[1];y<=b[3];y++)for(int x=b[0];x<=b[2];x++){
        int at=y*SCREEN_W+x;
        if(!marks[at])continue;
        assert(marks[at]==255);
        if(x<tight[0])tight[0]=x;if(y<tight[1])tight[1]=y;
        if(x>tight[2])tight[2]=x;if(y>tight[3])tight[3]=y;
        count++;marks[at]=0;
    }
    // Each fine segment has an in-bounds tip; empty submissions are a bug.
    assert(count>0);
    unsigned long long submitted=area(b),bounded=area(tight);
    assert(count<=bounded&&bounded<=submitted);
    d->updates++;d->submitted+=submitted;d->tight+=bounded;d->touched+=count;
    if(b[2]-b[0]+1>d->max_width)d->max_width=b[2]-b[0]+1;
    if(b[3]-b[1]+1>d->max_height)d->max_height=b[3]-b[1]+1;
}
static void submit(struct Damage *d,struct PreviewBatch *batch,long t,int force){
    int prior=batch->updates,box[4];memcpy(box,batch->box,sizeof box);
    flush_batch(batch,t,force);
    if(batch->updates!=prior){assert(batch->updates==prior+1);record(d,box);}
}
static void point(int shape,int i,float *x,float *y){
    int pass=i/60,step=i%60;
    // Same 21x60 serpentine topology as device/papersketch-input-driver.c,
    // but idealized screen coordinates, not captured/quantized evdev data.
    if(shape==0){*x=120+960*pass/20;*y=900+300*(pass%2?59-step:step)/59;}
    else if(shape==1){*x=120+960*i/1259.f;*y=500+900*i/1259.f;}
    else if(shape==2){*x=600;*y=1000;}
    else {*x=i%2?1080:120;*y=i%2?1400:500;}
}
static unsigned long long digest(void){
    unsigned long long hash=14695981039346656037ull;
    for(unsigned i=0;i<SCREEN_W*SCREEN_H;i++)for(unsigned shift=0;shift<32;shift+=8)
        hash=(hash^((image[i]>>shift)&255))*1099511628211ull;
    return hash;
}
static void replay(int shape,int tool,int interval){
    memset(image,255,sizeof image);memset(marks,0,sizeof marks);
    surf.px=image;surf.mk=marks;surf.ps=surf.ms=SCREEN_W;backend_ready=1;
    char permit[128];snprintf(permit,sizeof permit,"fine 0 0 %d %d 38 %d .15 .5 .95",SCREEN_W,SCREEN_H,tool);
    parse_arm(permit);assert(arm.on);
    struct Damage d={0};struct PreviewBatch batch={0};batch.last_ms=-PREVIEW_INTERVAL_MS;
    float lx=0,ly=0;
    int samples=shape==3?60:1260; // Bound the deliberately full-canvas stress case.
    for(int i=0;i<samples;i++){
        float x,y;point(shape,i,&x,&y);
        float p=(512+3072*(i%60)/59)/4095.f;
        unsigned gray=sketchPreviewGray(tool,fine_pressure(p));
        int b[4];segment(i?lx:x,i?ly:y,x,y,fine_width(p),0xff000000u|gray*0x010101u,b);
        d.segment_boxes+=area(b);d.samples++;
        merge_batch(&batch,b);submit(&d,&batch,i*interval,0);
        lx=x;ly=y;
    }
    submit(&d,&batch,samples*interval,1);
    assert(!batch.dirty&&d.samples==samples);
    assert(d.updates==(((samples-1)*interval)/PREVIEW_INTERVAL_MS)+2);
    for(unsigned i=0;i<sizeof marks;i++)assert(marks[i]==0); // No touched pixel missed by submitted regions.
    const char *names[]={"serpentine","diagonal","stationary","adversarial_jumps"};
    printf("{\"shape\":\"%s\",\"tool\":%d,\"interval_ms\":%d,\"samples\":%d,\"submissions\":%d,\"segment_box_pixels\":%llu,\"submitted_box_pixels\":%llu,\"tight_touched_box_pixels\":%llu,\"touched_pixels_per_batch_sum\":%llu,\"max_width\":%d,\"max_height\":%d,\"image_fnv64\":\"%016llx\"}\n",
        names[shape],tool,interval,d.samples,d.updates,d.segment_boxes,d.submitted,d.tight,d.touched,d.max_width,d.max_height,digest());
}
static void bench(void){
    memset(image,255,sizeof image);memset(marks,0,sizeof marks);
    surf.px=image;surf.mk=marks;surf.ps=surf.ms=SCREEN_W;backend_ready=1;
    parse_arm("fine 0 0 1404 1872 38 5 .15 .5 .95");assert(arm.on);
    struct timespec begin,end;clock_gettime(CLOCK_MONOTONIC,&begin);
    unsigned long long boxes=0;
    for(int repeat=0;repeat<4;repeat++){
        float lx=0,ly=0;
        for(int i=0;i<1260;i++){
            float x,y;point(0,i,&x,&y);
            float p=(512+3072*(i%60)/59)/4095.f;
            unsigned gray=sketchPreviewGray(5,fine_pressure(p));int b[4];
            segment(i?lx:x,i?ly:y,x,y,fine_width(p),0xff000000u|gray*0x010101u,b);
            boxes+=area(b);lx=x;ly=y;
        }
    }
    clock_gettime(CLOCK_MONOTONIC,&end);
    double elapsed=(end.tv_sec-begin.tv_sec)+(end.tv_nsec-begin.tv_nsec)/1e9;
    printf("{\"segments\":5040,\"seconds\":%.9f,\"segment_box_pixels\":%llu,\"image_fnv64\":\"%016llx\"}\n",elapsed,boxes,digest());
}
static void fidelity(void){
    unsigned rng=20261124;unsigned long long hash=14695981039346656037ull,total=0;
    surf.px=image;surf.mk=marks;surf.ps=surf.ms=128;backend_ready=1;
    for(int test=0;test<1024;test++){
        int tool=test%10;char permit[128];
        if(tool<6||tool==8)snprintf(permit,sizeof permit,"fine 16 16 96 96 %d %d .15 .5 .95",1+test%96,tool);
        else snprintf(permit,sizeof permit,"on 16 16 96 96 38 %d 12",tool==7);
        parse_arm(permit);assert(arm.on);
        for(int i=0;i<128*128;i++){image[i]=0xff777777u;marks[i]=17;}
        float xy[4];for(int i=0;i<4;i++){rng=rng*1664525u+1013904223u;xy[i]=(rng%640)/4.f-16;}
        uint32_t ink=0xff000000u|((test*29)%256)*0x010101u;int box[4];
        segment(xy[0],xy[1],xy[2],xy[3],1+test%96,ink,box);
        for(int y=0;y<128;y++)for(int x=0;x<128;x++){
            int i=y*128+x;
            if(marks[i]==255){
                assert(x>=16&&x<112&&y>=16&&y<112);
                assert(x>=box[0]&&x<=box[2]&&y>=box[1]&&y<=box[3]);total++;
            }else assert(marks[i]==17&&image[i]==0xff777777u);
            for(unsigned shift=0;shift<32;shift+=8)hash=(hash^((image[i]>>shift)&255))*1099511628211ull;
            hash=(hash^marks[i])*1099511628211ull;
        }
    }
    printf("{\"cases\":1024,\"touched_pixels\":%llu,\"pixels_masks_fnv64\":\"%016llx\"}\n",total,hash);
}
int main(int argc,char **argv){
    if(argc==2&&!strcmp(argv[1],"--bench")){bench();return 0;}
    if(argc==2&&!strcmp(argv[1],"--fidelity")){fidelity();return 0;}
    if(argc!=1)return 2;
    // Independent exact rectangle fixture for accounting (inclusive bounds).
    struct Damage fixture={0};int b[4]={2,3,6,8};
    marks[4*SCREEN_W+3]=marks[6*SCREEN_W+5]=255;
    record(&fixture,b);
    assert(fixture.submitted==30&&fixture.tight==9&&fixture.touched==2);
    for(int shape=0;shape<4;shape++)for(int tool=1;tool<=5;tool+=4)
        for(int interval=2;interval<=4;interval+=2)replay(shape,tool,interval);
    return 0;
}
