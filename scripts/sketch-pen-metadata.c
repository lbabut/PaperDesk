/* Read-only snapshot. No event reads, grabs, injection or device configuration. */
#define _POSIX_C_SOURCE 200809L
#include <linux/input.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <stdint.h>

static int64_t clock_us(clockid_t id) {
    struct timespec t;
    if (clock_gettime(id, &t)) return -1;
    return (int64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000;
}
static void json_string(const char *s) {
    putchar('"');
    for (const unsigned char *p=(const unsigned char *)s; *p; ++p) {
        if (*p=='"' || *p=='\\') printf("\\%c", *p);
        else if (*p<32 || *p>=127) printf("\\u%04x", *p);
        else putchar(*p);
    }
    putchar('"');
}
int main(void) {
    const unsigned codes[]={ABS_X,ABS_Y,ABS_PRESSURE,ABS_TILT_X,ABS_TILT_Y};
    struct input_absinfo axes[5]; char name[128]={0}, permit[242]={0};
    unsigned char keys[KEY_MAX/8+1]={0};
    int64_t start=clock_us(CLOCK_REALTIME), mono=clock_us(CLOCK_MONOTONIC);
    int fd=open("/dev/input/event1",O_RDONLY|O_NONBLOCK|O_CLOEXEC);
    if (fd<0) { perror("open pen"); return 2; }
    if (ioctl(fd,EVIOCGNAME(sizeof name),name)<0 || strcmp(name,"Wacom I2C Digitizer")) {
        fprintf(stderr,"Unexpected pen device\n");close(fd);return 2;
    }
    for(unsigned i=0;i<5;i++) {
        if(ioctl(fd,EVIOCGABS(codes[i]),&axes[i])<0 || axes[i].maximum<=axes[i].minimum) {
            fprintf(stderr,"Missing or invalid required pen axis\n");close(fd);return 2;
        }
    }
    if(ioctl(fd,EVIOCGKEY(sizeof keys),keys)<0) { perror("read pen key state");close(fd);return 2; }
    close(fd);
    /* Preview geometry is rounded, NOT the exact native input transform. */
    fd=open("/tmp/papersketch-ink",O_RDONLY|O_CLOEXEC);
    ssize_t length=fd<0?-1:read(fd,permit,241);
    if(fd>=0)close(fd);
    if(length>240) { fprintf(stderr,"Oversized preview permit\n");return 2; }
    int64_t end=clock_us(CLOCK_REALTIME);
    if(start<0 || mono<0 || end<start) { fprintf(stderr,"Invalid snapshot clock\n");return 2; }
    printf("{\"schema\":1,\"device\":\"/dev/input/event1\",\"read_only\":true,"
        "\"start_realtime_us\":%lld,\"start_monotonic_us\":%lld,\"end_realtime_us\":%lld,"
        "\"atomic_input_snapshot\":false,\"exact_viewport\":false,\"axes\":[",
        (long long)start,(long long)mono,(long long)end);
    for(unsigned i=0;i<5;i++) {
        const struct input_absinfo *a=&axes[i];
        printf("%s{\"code\":%u,\"value\":%d,\"minimum\":%d,\"maximum\":%d,"
            "\"fuzz\":%d,\"flat\":%d,\"resolution\":%d}",i?",":"",codes[i],
            a->value,a->minimum,a->maximum,a->fuzz,a->flat,a->resolution);
    }
    printf("],\"touch\":%s,\"pen\":%s,\"rubber\":%s,\"preview_permit\":",
        (keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8)))?"true":"false",
        (keys[BTN_TOOL_PEN/8]&(1<<(BTN_TOOL_PEN%8)))?"true":"false",
        (keys[BTN_TOOL_RUBBER/8]&(1<<(BTN_TOOL_RUBBER%8)))?"true":"false");
    if(length>=0) { permit[length]=0;json_string(permit); } else printf("null");
    puts("}");return 0;
}
