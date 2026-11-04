// Live pen ink and eraser through xochitl's own pen path while Paper Sketch arms it
// (reMarkable 2, OS 3.29.0.153 only). Paper Sketch rewrites ARM_FILE every second while a drawing
// canvas is up: "on x y w h size eraserTool eraseRadius" (screen px) or "off". A stale file
// (Paper Sketch gone) counts as off. Both are only a preview: Paper Sketch still draws, erases and keeps
// the real strokes, and draws the rubbed area again when the eraser lifts.
// "fine x y w h size tool p0 p1 p2" is a bounded pen-only silhouette for the
// material engine. The GUI repaints its exact pixels after release; this buffer
// is never a source for saved artwork. Unknown xochitl builds stay disabled.
#define _GNU_SOURCE
#include <dirent.h>
#include <ctype.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <link.h>
#include <linux/input.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "sketch-preview-shade.h"

#define ARM_FILE "/tmp/papersketch-ink"
#define ARM_STALE_S 3       // s without a heartbeat from Paper Sketch: off
#define ARM_CHECK_MS 200
#define SCREEN_W 1404
#define SCREEN_H 1872
static const unsigned char BUILD_ID[20] = { 0xc1,0xa6,0x69,0x8e,0xc0,0x51,0x2d,0xdd,0x88,0xc2,
                                            0xba,0x5c,0xa7,0x13,0x39,0x09,0x88,0x97,0x80,0x56 };
// xochitl 3.29.0.153 offsets from its load base
#define OFF_FB_INSTANCE    0x164f79c // EPFramebuffer* singleton
#define OFF_UPDATE_BLOCKS  0x81093c  // updateInBlocks(fb**, const QRegion&, waveform, pixelMode, flags, label)
#define FB_IMAGE 0x58                 // QImage, RGB32
#define FB_IMAGE_PTR 0x64             // QImage*, the current image (0 = the one at FB_IMAGE)
#define FB_MASK 0x68                  // QImage, Grayscale8: the pen draws only where this is set
#define WAVE_DU 1
#define PIXEL_PEN 8
#define FLAG_FASTDRAW 2

typedef void (*UpdateFn)(void **fb, const void *region, int waveform, int pixelMode, int flags, const char *label);
typedef void (*RegionCtor)(void *self, int x, int y, int w, int h, int type);
typedef void (*RegionDtor)(void *self);
typedef int (*ImgInt)(const void *img);
typedef const unsigned char *(*ImgBits)(const void *img);

static uintptr_t base;
static int build_ok;
static int backend_ready;
static RegionCtor rctor;
static RegionDtor rdtor;
static ImgInt format, width, height, stride;
static ImgBits bits;

static struct { int on, x, y, w, h, erase, fine, tool; float size, eraseR, anchors[3], strength; } arm;
static long long first_update_ms, contact_ms;
static long max_report_to_submit_ms, max_submit_us;
static int report_clock_monotonic;
static unsigned fine_strokes;
static int preview_active,preview_box[4];

// Where to draw this stroke: the screen image and the pen mask
static struct { char *fb; uint32_t *px; unsigned char *mk; int ps, ms; } surf;

static int find_main(struct dl_phdr_info *info, size_t size, void *data) {
    (void)size; (void)data;
    base = info->dlpi_addr;
    for (int i = 0; i < info->dlpi_phnum; i++) {
        const ElfW(Phdr) *ph = &info->dlpi_phdr[i];
        if (ph->p_type != PT_NOTE) continue;
        const unsigned char *p = (const unsigned char *)(base + ph->p_vaddr), *end = p + ph->p_memsz;
        while (p + 12 <= end) {
            uint32_t namesz = *(uint32_t *)p, descsz = *(uint32_t *)(p + 4), type = *(uint32_t *)(p + 8);
            const unsigned char *desc = p + 12 + ((namesz + 3) & ~3u);
            if (type == 3 && descsz == 20 && !memcmp(desc, BUILD_ID, 20)) build_ok = 1; // NT_GNU_BUILD_ID
            p = desc + ((descsz + 3) & ~3u);
        }
    }
    return 1; // the first entry is the program itself
}

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static long long realtime_ms(void) {
    struct timespec ts;clock_gettime(CLOCK_REALTIME,&ts);
    return (long long)ts.tv_sec*1000+ts.tv_nsec/1000000;
}
static void status_file(void) {
#ifdef PAPERSKETCH_BATCH_TEST
    return;
#endif
    char tmp[128];snprintf(tmp,sizeof tmp,"/tmp/papersketch-ink-status.%d",getpid());
    int fd=open(tmp,O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW,0600);
    if(fd<0)return;
    dprintf(fd,"{\"ready\":%s,\"pid\":%d,\"time_ms\":%lld,\"armed\":%s,\"fine_preview\":true,\"wide_preview\":true,\"tip_marker\":true,\"shade_strength\":true,\"preview_interval_ms\":8,\"report_clock_monotonic\":%s,\"max_report_to_submit_ms\":%ld,\"max_submit_us\":%ld,\"contact_ms\":%lld,\"first_update_ms\":%lld,\"fine_strokes\":%u,\"active\":%s,\"box\":[%d,%d,%d,%d]}\n",
            backend_ready?"true":"false",getpid(),realtime_ms(),arm.on?"true":"false",report_clock_monotonic?"true":"false",max_report_to_submit_ms,max_submit_us,contact_ms,first_update_ms,fine_strokes,preview_active?"true":"false",preview_box[0],preview_box[1],preview_box[2],preview_box[3]);
    close(fd);rename(tmp,"/tmp/papersketch-ink-status");
}
static void parse_arm(const char *buf) {
    int n=0;arm.fine=0;arm.strength=1;
    if(buf){
        if(!strncmp(buf,"fine ",5)){
            arm.fine=1;arm.erase=0;arm.eraseR=0;
            int end=0;
            n=sscanf(buf,"fine %d %d %d %d %f %d %f %f %f%n",&arm.x,&arm.y,&arm.w,&arm.h,
                     &arm.size,&arm.tool,&arm.anchors[0],&arm.anchors[1],&arm.anchors[2],&end);
            if(n==9){
                const char *tail=buf+end;while(isspace((unsigned char)*tail))tail++;
                if(*tail){char extra;n=sscanf(tail,"%f %c",&arm.strength,&extra)==1?10:0;}
            }
            if((n!=9 && n!=10) || !isfinite(arm.strength) || arm.strength<.05f || arm.strength>1 || !((arm.tool>=0&&arm.tool<6)||arm.tool==8) || arm.size>96 ||
               !isfinite(arm.anchors[0])||!isfinite(arm.anchors[1])||!isfinite(arm.anchors[2])||
               arm.anchors[0]<.001f||arm.anchors[2]>1||arm.anchors[1]-arm.anchors[0]<.04f||
               arm.anchors[2]-arm.anchors[1]<.04f||arm.anchors[2]-arm.anchors[0]<.15f)n=0;
        }else{
            n=sscanf(buf,"on %d %d %d %d %f %d %f",&arm.x,&arm.y,&arm.w,&arm.h,&arm.size,&arm.erase,&arm.eraseR);
            if(n<7){arm.erase=0;arm.eraseR=0;}
        }
    }
    arm.on=backend_ready&&n>=5&&arm.x>=0&&arm.y>=0&&arm.w>0&&arm.h>0&&
        arm.x<=SCREEN_W-arm.w&&arm.y<=SCREEN_H-arm.h&&isfinite(arm.size)&&arm.size>0&&arm.size<=160&&
        isfinite(arm.eraseR)&&arm.eraseR>=0&&arm.eraseR<=80;
}

static void read_arm(void) {
    struct stat st;
    char buf[128] = "";
    arm.on = 0;
    if (lstat(ARM_FILE, &st) < 0 || !S_ISREG(st.st_mode) || st.st_uid!=0 || time(NULL) - st.st_mtime > ARM_STALE_S) {status_file();return;}
    FILE *f = fopen(ARM_FILE, "r");
    if (!f) return;
    if(fgets(buf,sizeof buf,f))parse_arm(buf);
    fclose(f);status_file();
}

// Find the screen image and pen mask, and check they are what this build is known to have
static int open_surface(void) {
    char *fb = *(char **)(base + OFF_FB_INSTANCE);
    if (!fb) return 0;
    void *img = *(void **)(fb + FB_IMAGE_PTR);
    if (!img) img = fb + FB_IMAGE;
    void *mask = fb + FB_MASK;
    if (format(img) != 4 || width(img) != SCREEN_W || height(img) != SCREEN_H || format(mask) != 24
        || width(mask) != SCREEN_W || height(mask) != SCREEN_H) {
        fprintf(stderr, "[papersketch-native] unexpected screen layout (fmt %d/%d), not drawing\n", format(img), format(mask));
        return 0;
    }
    surf.fb = fb;
    surf.px = (uint32_t *)bits(img);
    surf.mk = (unsigned char *)bits(mask);
    surf.ps = stride(img) / 4;
    surf.ms = stride(mask);
    return 1;
}

static int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// Paint a round-ended segment of width w, clipped to the armed canvas; returns its box
static void segment(float x0, float y0, float x1, float y1, float w, uint32_t ink, int box[4]) {
    float minimum=arm.fine?.5f:.75f;
    float r = w / 2 < minimum ? minimum : w / 2;
    int bx0 = clampi((int)((x0 < x1 ? x0 : x1) - r), arm.x, arm.x + arm.w - 1);
    int by0 = clampi((int)((y0 < y1 ? y0 : y1) - r), arm.y, arm.y + arm.h - 1);
    int bx1 = clampi((int)((x0 > x1 ? x0 : x1) + r + 1), arm.x, arm.x + arm.w - 1);
    int by1 = clampi((int)((y0 > y1 ? y0 : y1) + r + 1), arm.y, arm.y + arm.h - 1);
    float dx = x1 - x0, dy = y1 - y0, len2 = dx * dx + dy * dy;
    for (int y = by0; y <= by1; y++)
        for (int x = bx0; x <= bx1; x++) {
            float px = x + 0.5f - x0, py = y + 0.5f - y0;
            float t = len2 > 0 ? (px * dx + py * dy) / len2 : 0;
            t = t < 0 ? 0 : t > 1 ? 1 : t;
            float ex = px - t * dx, ey = py - t * dy;
            if (ex * ex + ey * ey > r * r) continue;
            // DU pen mode is binary. Leave skipped pixels and their masks
            // untouched so pale previews cannot erase existing artwork.
            if(arm.fine && !arm.erase && !sketchPreviewDot(ink&255,x,y))continue;
            surf.px[y * surf.ps + x] = arm.fine && !arm.erase ? 0xff000000u : ink;
            surf.mk[y * surf.ms + x] = 0xFF;
        }
    // A sparse pale Bayer cell can miss an entire subpixel-sized nib. Keep
    // exactly one physical pixel at the latest tip visible, independently of
    // shade. The body remains tool-shaded; release repairs exact material.
    if(arm.fine && !arm.erase && x1>=arm.x && x1<arm.x+arm.w && y1>=arm.y && y1<arm.y+arm.h){
        int tx=(int)x1,ty=(int)y1;
        surf.px[ty*surf.ps+tx]=0xff000000u;surf.mk[ty*surf.ms+tx]=255;
    }
    box[0] = bx0; box[1] = by0; box[2] = bx1; box[3] = by1;
}

static void show(const int b[4]) {
#ifdef PAPERSKETCH_BATCH_TEST
    (void)b;return;
#else
    void *region[2] = {0};
    void *fbHolder = surf.fb;
    rctor(region, b[0], b[1], b[2] - b[0] + 1, b[3] - b[1] + 1, 0);
    ((UpdateFn)(base + OFF_UPDATE_BLOCKS))(&fbHolder, region, WAVE_DU, PIXEL_PEN, FLAG_FASTDRAW, " - papersketch ink");
    rdtor(region);
#endif
}


#define PREVIEW_INTERVAL_MS 8
#define PERMIT_CHECK_MS 16
struct PreviewBatch {int box[4],dirty,updates;long last_ms,update_us;long long oldest_report_ms;};
static int preview_poll_timeout(const struct PreviewBatch *batch,long now,int stroke) {
    if(batch->dirty)return clampi(PREVIEW_INTERVAL_MS-(int)(now-batch->last_ms),0,PREVIEW_INTERVAL_MS);
    return stroke?PREVIEW_INTERVAL_MS:ARM_CHECK_MS;
}
static void merge_batch(struct PreviewBatch *batch,const int box[4]) {
    if(!batch->dirty) {memcpy(batch->box,box,sizeof batch->box);batch->dirty=1;return;}
    if(box[0]<batch->box[0])batch->box[0]=box[0];
    if(box[1]<batch->box[1])batch->box[1]=box[1];
    if(box[2]>batch->box[2])batch->box[2]=box[2];
    if(box[3]>batch->box[3])batch->box[3]=box[3];
}
static void flush_batch(struct PreviewBatch *batch,long now,int force) {
    if(!batch->dirty || (!force && now-batch->last_ms<PREVIEW_INTERVAL_MS))return;
    struct timespec a,z;clock_gettime(CLOCK_MONOTONIC,&a);
    if(!batch->updates)first_update_ms=realtime_ms();
    if(batch->oldest_report_ms>0){
        long age=(long)(now_ms()-batch->oldest_report_ms);
        if(age>max_report_to_submit_ms)max_report_to_submit_ms=age;
    }
    show(batch->box);
    clock_gettime(CLOCK_MONOTONIC,&z);
    batch->update_us+=(z.tv_sec-a.tv_sec)*1000000L+(z.tv_nsec-a.tv_nsec)/1000;
    long us=(z.tv_sec-a.tv_sec)*1000000L+(z.tv_nsec-a.tv_nsec)/1000;
    if(us>max_submit_us)max_submit_us=us;
    batch->updates++;batch->dirty=0;batch->oldest_report_ms=0;batch->last_ms=now;
    if(batch->updates==1)status_file();
}

// A cheap visible silhouette only. The material engine remains authoritative.
static float fine_pressure(float p) {
    const float x[]={0,arm.anchors[0],arm.anchors[1],arm.anchors[2],1},y[]={0,.15f,.5f,.95f,1};
    for(int i=1;i<5;i++)if(p<=x[i]){p=x[i]>x[i-1]?y[i-1]+(p-x[i-1])*(y[i]-y[i-1])/(x[i]-x[i-1]):y[i];break;}
    return fminf(1,fmaxf(0,p));
}
static float fine_width(float p) {
    if(arm.tool==8)return arm.size;
    p=fine_pressure(p);
    const float minimum[]={.22f,.20f,.18f,.16f,.35f,.40f},exponent[]={.90f,1.05f,1.15f,1.20f,.80f,.70f};
    return arm.size*(minimum[arm.tool]+(1-minimum[arm.tool])*powf(fminf(1,fmaxf(0,p)),exponent[arm.tool]));
}

#define HAS_BIT(bits, n) ((bits)[(n) / 8] >> ((n) % 8) & 1)

static int open_pen(void) {
    DIR *dir = opendir("/dev/input");
    struct dirent *e;
    int found = -1;
    while (dir && found < 0 && (e = readdir(dir))) {
        if (strncmp(e->d_name, "event", 5)) continue;
        char path[64];
        unsigned char abs_bits[ABS_MAX / 8 + 1] = {0}, key_bits[KEY_MAX / 8 + 1] = {0};
        snprintf(path, sizeof path, "/dev/input/%s", e->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;
        ioctl(fd, EVIOCGBIT(EV_ABS, sizeof abs_bits), abs_bits);
        ioctl(fd, EVIOCGBIT(EV_KEY, sizeof key_bits), key_bits);
        if (HAS_BIT(abs_bits, ABS_PRESSURE) && HAS_BIT(key_bits, BTN_TOOL_PEN)) found = fd; else close(fd);
    }
    if (dir) closedir(dir);
    return found;
}

static void *pen_loop(void *arg) {
    (void)arg;
    int pen = open_pen();
    if (pen < 0) { fprintf(stderr, "[papersketch-native] pen not found\n"); return NULL; }
    int event_clock=CLOCK_MONOTONIC;
    report_clock_monotonic=ioctl(pen,EVIOCSCLOCKID,&event_clock)==0;
    struct input_absinfo ax = {0}, ay = {0}, ap = {0};
    ioctl(pen, EVIOCGABS(ABS_X), &ax);
    ioctl(pen, EVIOCGABS(ABS_Y), &ay);
    ioctl(pen, EVIOCGABS(ABS_PRESSURE), &ap);
    if (ax.maximum <= 0 || ay.maximum <= 0 || ap.maximum <= ap.minimum) { fprintf(stderr, "[papersketch-native] odd pen ranges\n"); return NULL; }
    fprintf(stderr, "[papersketch-native] ready: pen x 0..%d y 0..%d pressure ..%d\n", ax.maximum, ay.maximum, ap.maximum);

    int rx = 0, ry = 0, rp = 0, touch = 0, rubber = 0;
    int contact_checked=0,blocked_contact=0;
    int stroke = 0, have_last = 0, sbox[4] = {0}, samples = 0;
    struct PreviewBatch batch={0};
    float lx = 0, ly = 0;
    long last_arm = 0, t_stroke = 0;
    struct pollfd pfd = { pen, POLLIN, 0 };
    for (;;) {
        if (!backend_ready && open_surface()) {backend_ready=1;fprintf(stderr,"[papersketch-native] framebuffer layout verified\n");}
        int timeout=preview_poll_timeout(&batch,now_ms(),stroke);
        poll(&pfd, 1, timeout);
        long t = now_ms();
        if (t - last_arm >= (stroke&&arm.fine?PERMIT_CHECK_MS:ARM_CHECK_MS)) { read_arm(); last_arm = t; }
        if(stroke && !arm.on) {
            for(int y=sbox[1];y<=sbox[3];y++)memset(surf.mk+y*surf.ms+sbox[0],0,sbox[2]-sbox[0]+1);
            stroke=0;preview_active=0;have_last=0;batch.dirty=0;status_file();
        }
        struct input_event ev[64];
        ssize_t n = read(pen, ev, sizeof ev);
        for (ssize_t i = 0; i < n / (ssize_t)sizeof *ev; i++) {
            struct input_event *e = &ev[i];
            if(e->type==EV_SYN&&e->code==SYN_DROPPED){
                blocked_contact=1;arm.on=0;
                if(stroke){for(int y=sbox[1];y<=sbox[3];y++)memset(surf.mk+y*surf.ms+sbox[0],0,sbox[2]-sbox[0]+1);}
                stroke=0;preview_active=0;have_last=0;batch.dirty=0;status_file();continue;
            }
            if(e->type==EV_KEY&&e->code==BTN_TOUCH&&!e->value)blocked_contact=0;
            if (e->type == EV_ABS) {
                if (e->code == ABS_X) rx = e->value;
                else if (e->code == ABS_Y) ry = e->value;
                else if (e->code == ABS_PRESSURE) rp = e->value;
            } else if (e->type == EV_KEY) {
                if (e->code == BTN_TOUCH) touch = e->value != 0;
                else if (e->code == BTN_TOOL_RUBBER) rubber = e->value != 0;
            } else if (e->type == EV_SYN && e->code == SYN_REPORT) {
                // Check the latest UI permit before each new contact. Never
                // inherit a stale toolbar/dialog/page permit from the 200ms poll.
                if(touch&&!contact_checked){read_arm();contact_checked=1;}
                if(!touch)contact_checked=0;
                int erasing = rubber || arm.erase;
                if (touch && !blocked_contact && arm.on && rp>ap.minimum && (!erasing || (!arm.fine&&arm.eraseR>0))) {
                    if (!stroke) {
                        if (!open_surface()) { arm.on = 0; continue; }
                        stroke = 1;preview_active=1; samples=0;first_update_ms=0;max_report_to_submit_ms=0;max_submit_us=0;contact_ms=realtime_ms();if(arm.fine)fine_strokes++; memset(&batch,0,sizeof batch);t_stroke = now_ms();batch.last_ms=t_stroke-PREVIEW_INTERVAL_MS;
                        sbox[0] = SCREEN_W; sbox[1] = SCREEN_H; sbox[2] = sbox[3] = 0;
                    }
                    // The panel's portrait frame: x along the digitizer's y, y against its x
                    float sx = ry * (float)SCREEN_W / ay.maximum, sy = (ax.maximum - rx) * (float)SCREEN_H / ax.maximum;
                    if (sx >= arm.x && sx < arm.x + arm.w && sy >= arm.y && sy < arm.y + arm.h) {
                        float p = (rp - ap.minimum) / (float)(ap.maximum - ap.minimum);
                        int b[4];
                        if (erasing) segment(have_last ? lx : sx, have_last ? ly : sy, sx, sy, 2 * arm.eraseR*(0.18f+0.82f*fminf(1,fmaxf(0,p))), 0xFFFFFFFFu, b);
                        else if(arm.fine){
                            unsigned gray=sketchPreviewGray(arm.tool,fine_pressure(p));
                            if(arm.tool!=8)gray=(unsigned)(255-(255-gray)*arm.strength+.5f);
                            segment(have_last?lx:sx,have_last?ly:sy,sx,sy,fine_width(p),
                                    0xff000000u|gray*0x010101u,b);
                        }
                        else segment(have_last ? lx : sx, have_last ? ly : sy, sx, sy, arm.size*(0.18f+0.82f*fminf(1,fmaxf(0,p))), 0xFF000000u, b);
                        if(!batch.dirty && report_clock_monotonic)
                            batch.oldest_report_ms=(long long)e->time.tv_sec*1000+e->time.tv_usec/1000;
                        merge_batch(&batch,b);flush_batch(&batch,now_ms(),0);samples++;
                        if (b[0] < sbox[0]) sbox[0] = b[0];
                        if (b[1] < sbox[1]) sbox[1] = b[1];
                        if (b[2] > sbox[2]) sbox[2] = b[2];
                        if (b[3] > sbox[3]) sbox[3] = b[3];
                        lx = sx; ly = sy; have_last = 1;
                    } else have_last = 0;
                } else if (stroke && (!touch || !arm.on || (arm.fine&&rubber) || rp<=ap.minimum)) {
                    flush_batch(&batch,now_ms(),1);
                    // The mask is the pen's scratch: clear what this stroke marked
                    for (int y = sbox[1]; y <= sbox[3]; y++) memset(surf.mk + y * surf.ms + sbox[0], 0, sbox[2] - sbox[0] + 1);
                    fprintf(stderr, "[papersketch-native] stroke: %d samples, %d updates, %ld us per update call, %ld ms\n",
                            samples,batch.updates,batch.updates?batch.update_us/batch.updates:0,now_ms()-t_stroke);
                    memcpy(preview_box,sbox,sizeof preview_box);preview_active=0;
                    stroke = 0; have_last = 0;status_file();
                }
            }
        }
        if(stroke && arm.on)flush_batch(&batch,now_ms(),0);
    }
    return NULL;
}

void _xovi_construct(void) {
    dl_iterate_phdr(find_main, NULL);
    if (!build_ok) { status_file();fprintf(stderr, "[papersketch-native] unknown xochitl build, staying off\n"); return; }
    rctor = (RegionCtor)dlsym(RTLD_DEFAULT, "_ZN7QRegionC1EiiiiNS_10RegionTypeE");
    rdtor = (RegionDtor)dlsym(RTLD_DEFAULT, "_ZN7QRegionD1Ev");
    format = (ImgInt)dlsym(RTLD_DEFAULT, "_ZNK6QImage6formatEv");
    width = (ImgInt)dlsym(RTLD_DEFAULT, "_ZNK6QImage5widthEv");
    height = (ImgInt)dlsym(RTLD_DEFAULT, "_ZNK6QImage6heightEv");
    stride = (ImgInt)dlsym(RTLD_DEFAULT, "_ZNK6QImage12bytesPerLineEv");
    bits = (ImgBits)dlsym(RTLD_DEFAULT, "_ZNK6QImage4bitsEv");
    if (!rctor || !rdtor || !format || !width || !height || !stride || !bits) { fprintf(stderr, "[papersketch-native] Qt symbols missing, staying off\n"); return; }
    status_file();
    pthread_t t;
    pthread_create(&t, NULL, pen_loop, NULL);
    pthread_detach(t);
}
