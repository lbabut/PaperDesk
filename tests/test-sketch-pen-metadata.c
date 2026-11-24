#define _POSIX_C_SOURCE 200809L
#include <linux/input.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
#include <string.h>
#include <assert.h>
#include <sys/ioctl.h>
static int mode;
static int probe_open(const char *path,int flags,...){
    assert((flags&O_ACCMODE)==O_RDONLY);
    if(!strcmp(path,"/dev/input/event1"))return 3;
    assert(!strcmp(path,"/tmp/papersketch-ink"));return 4;
}
static int probe_close(int fd){assert(fd==3||fd==4);return 0;}
static ssize_t probe_read(int fd,void *buf,size_t count){
    assert(fd==4); /* No consuming events from the pen. */
    const char *s="fine 126 184 1152 1538 62.4 5 0.15 0.5 0.95 1";
    assert(strlen(s)<count);memcpy(buf,s,strlen(s));return strlen(s);
}
static int probe_ioctl(int fd,unsigned long request,...){
    assert(fd==3);va_list ap;va_start(ap,request);void *p=va_arg(ap,void*);va_end(ap);
    if(request==EVIOCGNAME(128)){strcpy(p,mode==1?"Wrong device":"Wacom I2C Digitizer");return 0;}
    if(request==EVIOCGKEY(KEY_MAX/8+1)){memset(p,0,KEY_MAX/8+1);return 0;}
    const unsigned codes[]={ABS_X,ABS_Y,ABS_PRESSURE,ABS_TILT_X,ABS_TILT_Y};
    for(int i=0;i<5;i++)if(request==EVIOCGABS(codes[i])){
        if(mode==2)return -1;
        struct input_absinfo a={0};a.minimum=i>=3?-9000:0;
        a.maximum=i==0?20967:i==1?15725:i==2?4095:9000;
        memcpy(p,&a,sizeof a);return 0;
    }
    assert(!"Unexpected ioctl or attempted device modification");return -1;
}
#define open probe_open
#define close probe_close
#define read probe_read
#define ioctl probe_ioctl
#define main probe_main
#include "../scripts/sketch-pen-metadata.c"
#undef main
int main(int argc,char **argv){(void)argv;mode=argc-1;return probe_main();}
