#define _DEFAULT_SOURCE
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>
static volatile sig_atomic_t stopped;
static void stop_signal(int s){(void)s;stopped=1;}
static long long ms(void){struct timespec t;clock_gettime(CLOCK_REALTIME,&t);return (long long)t.tv_sec*1000+t.tv_nsec/1000000;}
static int event(int fd,int type,int code,int value){struct input_event e={0};e.type=type;e.code=code;e.value=value;return write(fd,&e,sizeof e)==sizeof e;}
static void release(int fd,int finger){
 if(finger){event(fd,EV_ABS,ABS_MT_SLOT,0);event(fd,EV_ABS,ABS_MT_TRACKING_ID,-1);event(fd,EV_KEY,BTN_TOUCH,0);event(fd,EV_KEY,BTN_TOOL_FINGER,0);}
 else{event(fd,EV_ABS,ABS_PRESSURE,0);event(fd,EV_KEY,BTN_TOUCH,0);event(fd,EV_KEY,BTN_TOOL_PEN,0);}
 event(fd,EV_SYN,SYN_REPORT,0);
}
int main(int argc,char **argv){
 if((argc!=6 && argc!=7) || (strcmp(argv[1],"finger") && strcmp(argv[1],"pen")))return 2;
 const char *pattern=argc==7?argv[6]:"";
 int shading=!strcmp(pattern,"shade"),tap=!strcmp(pattern,"tap"),tilt=!strcmp(pattern,"tilt"),upright=!strcmp(pattern,"upright"),contact=!strcmp(pattern,"contact");
 int calibration=!strcmp(pattern,"calibration-light")?1:!strcmp(pattern,"calibration-normal")?2:!strcmp(pattern,"calibration-firm")?3:0;
 if(argc==7&&!shading&&!tap&&!tilt&&!upright&&!contact&&!calibration)return 2;
 if((shading||tilt||upright||calibration)&&strcmp(argv[1],"pen"))return 2;
 if(contact&&strcmp(argv[1],"finger"))return 2;
 int finger=!strcmp(argv[1],"finger");const char *path=finger?"/dev/input/event2":"/dev/input/event1";
 int fd=open(path,O_RDWR|O_NONBLOCK);if(fd<0){perror(path);return 3;}
 struct stat st;if(fstat(fd,&st)||!S_ISCHR(st.st_mode)||major(st.st_rdev)!=13||minor(st.st_rdev)!=(finger?66:65)){close(fd);return 4;}
 unsigned char keys[KEY_MAX/8+1]={0};ioctl(fd,EVIOCGKEY(sizeof keys),keys);
 if(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8))){fputs("Input is busy\n",stderr);close(fd);return 5;}
 if(finger){int slots[33]={ABS_MT_TRACKING_ID};if(ioctl(fd,EVIOCGMTSLOTS(sizeof slots),slots)==0)for(int i=1;i<33;i++)if(slots[i]>=0){fputs("Touch contact is active\n",stderr);close(fd);return 5;}}
 struct input_absinfo tilt_x={0},tilt_y={0},pen_pressure={0},touch_major={0},touch_minor={0},touch_pressure={0};
 int has_tilt_x=!finger&&ioctl(fd,EVIOCGABS(ABS_TILT_X),&tilt_x)==0;
 int has_tilt_y=!finger&&ioctl(fd,EVIOCGABS(ABS_TILT_Y),&tilt_y)==0;
 if(!finger)ioctl(fd,EVIOCGABS(ABS_PRESSURE),&pen_pressure);
 if(finger){ioctl(fd,EVIOCGABS(ABS_MT_TOUCH_MAJOR),&touch_major);ioctl(fd,EVIOCGABS(ABS_MT_TOUCH_MINOR),&touch_minor);ioctl(fd,EVIOCGABS(ABS_MT_PRESSURE),&touch_pressure);}
 int x0=atoi(argv[2]),y0=atoi(argv[3]),x1=atoi(argv[4]),y1=atoi(argv[5]);
 int maxx=finger?1403:20966,maxy=finger?1871:15725;
 if(x0<0||x0>maxx||x1<0||x1>maxx||y0<0||y0>maxy||y1<0||y1>maxy){close(fd);return 6;}
 signal(SIGINT,stop_signal);signal(SIGTERM,stop_signal);
 long long started=ms();
 if(finger){event(fd,EV_ABS,ABS_MT_SLOT,0);event(fd,EV_ABS,ABS_MT_TRACKING_ID,(int)(started%65535));event(fd,EV_KEY,BTN_TOUCH,1);event(fd,EV_KEY,BTN_TOOL_FINGER,1);}
 else{event(fd,EV_KEY,BTN_TOOL_RUBBER,0);event(fd,EV_KEY,BTN_TOOL_PEN,1);event(fd,EV_KEY,BTN_TOUCH,1);event(fd,EV_ABS,ABS_PRESSURE,2048);}
 int ok=1;
 int samples=tap?2:shading?1260:61;
 for(int i=0;i<samples && !stopped;i++){
  int pass=i/60,step=i%60;
  int x=shading?x0+(x1-x0)*pass/20:x0+(x1-x0)*i/60;
  int y=shading?y0+(y1-y0)*(pass%2?59-step:step)/59:y0+(y1-y0)*i/60;
  // A fresh Qt reader has empty slot coordinates. Force both axes to change:
  // the kernel suppresses repeated ABS values left by a previous diagnostic run.
  if(finger && i==0){x=x<maxx?x+1:x-1;y=y<maxy?y+1:y-1;}
  if(finger){
   if(contact){
    int major=touch_major.maximum>60?60:touch_major.maximum,minor=touch_minor.maximum>30?30:touch_minor.maximum;
    int pressure=touch_pressure.minimum+(touch_pressure.maximum-touch_pressure.minimum)/2;
    ok&=event(fd,EV_ABS,ABS_MT_TOUCH_MAJOR,major-(i==0&&major>0));
    ok&=event(fd,EV_ABS,ABS_MT_TOUCH_MINOR,minor-(i==0&&minor>0));
    ok&=event(fd,EV_ABS,ABS_MT_PRESSURE,pressure-(i==0&&pressure>0));
   }
   ok&=event(fd,EV_ABS,ABS_MT_POSITION_X,x);ok&=event(fd,EV_ABS,ABS_MT_POSITION_Y,y);
  }
  else{
   int pressure=shading?512+3072*step/59:512+3072*i/60;
   if(calibration||tilt||upright){double fraction=calibration==1?.12:calibration==2?.45:calibration==3?.85:.55;pressure=pen_pressure.minimum+(int)((pen_pressure.maximum-pen_pressure.minimum)*fraction);}
   if(has_tilt_x)ok&=event(fd,EV_ABS,ABS_TILT_X,tilt?(int)(tilt_x.maximum*.8):0);
   if(has_tilt_y)ok&=event(fd,EV_ABS,ABS_TILT_Y,0);
   ok&=event(fd,EV_ABS,ABS_PRESSURE,pressure);ok&=event(fd,EV_ABS,ABS_X,x);ok&=event(fd,EV_ABS,ABS_Y,y);
  }
  ok&=event(fd,EV_SYN,SYN_REPORT,0);if(!ok)break;usleep(tap?40000:shading?4000:16000);
 }
 release(fd,finger);
 if(has_tilt_x)event(fd,EV_ABS,ABS_TILT_X,tilt_x.value);
 if(has_tilt_y)event(fd,EV_ABS,ABS_TILT_Y,tilt_y.value);
 if(has_tilt_x||has_tilt_y)event(fd,EV_SYN,SYN_REPORT,0);
 long long released=ms();close(fd);
 printf("{\"mode\":\"%s\",\"contact_ms\":%lld,\"release_ms\":%lld,\"writes_ok\":%s}\n",argv[1],started,released,ok && !stopped?"true":"false");
 return ok && !stopped?0:7;
}
