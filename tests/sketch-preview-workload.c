// Standalone CPU benchmark: no _xovi_construct(), device access or show().
// Includes the actual preview implementation; buffers are private heap memory.
#define PAPERSKETCH_BATCH_TEST
#include "../product/payload/apps/papersketch/native/papersketch-ink.c"
#include <inttypes.h>

struct Point { int x, y, pressure; };
static double elapsed(struct timespec a, struct timespec b) {
    return (b.tv_sec-a.tv_sec)*1000.0+(b.tv_nsec-a.tv_nsec)/1000000.0;
}
static uint64_t digest(void) {
    uint64_t h=UINT64_C(14695981039346656037);
    for(int i=0;i<SCREEN_W*SCREEN_H;i++) {
        h^=surf.px[i];h*=UINT64_C(1099511628211);
        h^=surf.mk[i];h*=UINT64_C(1099511628211);
    }
    return h;
}
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    FILE *f=fopen(argv[1],"r");if(!f)return 3;
    char line[256];int count,index,ax,ay,pmin,pmax;long long duration;
    if(!fgets(line,sizeof line,f)||sscanf(line,"SKETCH_PREVIEW_TRACE_V1 %d %d %lld",&count,&index,&duration)!=3||
       count<1||count>1000000||duration<=0)return 4;
    backend_ready=1;
    if(!fgets(line,sizeof line,f))return 4;
    parse_arm(line);if(!arm.on||!arm.fine)return 4;
    if(fscanf(f,"%d %d %d %d",&ax,&ay,&pmin,&pmax)!=4||ax<=0||ay<=0||pmax<=pmin)return 4;
    struct Point *points=calloc((size_t)count,sizeof *points);if(!points)return 5;
    for(int i=0;i<count;i++)if(fscanf(f,"%d %d %d",&points[i].x,&points[i].y,&points[i].pressure)!=3||
        points[i].x<0||points[i].x>ax||points[i].y<0||points[i].y>ay||
        points[i].pressure<=pmin||points[i].pressure>pmax)return 4;
    char extra;if(fscanf(f," %c",&extra)==1)return 4;fclose(f);
    surf.px=malloc(SCREEN_W*SCREEN_H*sizeof *surf.px);surf.mk=calloc(SCREEN_W*SCREEN_H,1);
    if(!surf.px||!surf.mk)return 5;
    surf.ps=surf.ms=SCREEN_W;
    uint64_t first_digest=0;
    for(int run=0;run<3;run++) {
        memset(surf.px,255,SCREEN_W*SCREEN_H*sizeof *surf.px);memset(surf.mk,0,SCREEN_W*SCREEN_H);
        int painted=0,have_last=0;float lx=0,ly=0;
        struct timespec a,z,wa,wz;
        clock_gettime(CLOCK_MONOTONIC,&wa);clock_gettime(CLOCK_THREAD_CPUTIME_ID,&a);
        for(int i=0;i<count;i++) {
            float sx=points[i].y*(float)SCREEN_W/ay,sy=(ax-points[i].x)*(float)SCREEN_H/ax;
            if(sx<arm.x||sx>=arm.x+arm.w||sy<arm.y||sy>=arm.y+arm.h){have_last=0;continue;}
            float p=(points[i].pressure-pmin)/(float)(pmax-pmin);int b[4];
            unsigned gray=sketchPreviewGray(arm.tool,fine_pressure(p));
            if(arm.tool!=8)gray=(unsigned)(255-(255-gray)*arm.strength+.5f);
            segment(have_last?lx:sx,have_last?ly:sy,sx,sy,fine_width(p),0xff000000u|gray*0x010101u,b);
            painted++;lx=sx;ly=sy;have_last=1;
        }
        clock_gettime(CLOCK_THREAD_CPUTIME_ID,&z);clock_gettime(CLOCK_MONOTONIC,&wz);
        uint64_t hash=digest();if(run&&hash!=first_digest)return 6;first_digest=hash;
        printf("{\"contact\":%d,\"run\":%d,\"reports\":%d,\"painted\":%d,\"tool\":%d,\"cpu_ms\":%.6f,\"wall_ms\":%.6f,\"recorded_duration_ms\":%.3f,\"buffer_digest\":\"%016" PRIx64 "\"}\n",
            index,run,count,painted,arm.tool,elapsed(a,z),elapsed(wa,wz),duration/1000.0,hash);
    }
    free(points);free(surf.px);free(surf.mk);return 0;
}
