#define _POSIX_C_SOURCE 200809L
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
static volatile sig_atomic_t stop;
static void stopped(int s){(void)s;stop=1;}
static int emit(int fd,int type,int code,int value){struct input_event e={0};e.type=type;e.code=code;e.value=value;return write(fd,&e,sizeof e)==sizeof e;}
static long long ms(clockid_t c){struct timespec t;clock_gettime(c,&t);return (long long)t.tv_sec*1000+t.tv_nsec/1000000;}
struct point{int x,y;};struct action{int time,index,down;};
static int cmp(const void*a,const void*b){const struct action*x=a,*y=b;return x->time!=y->time?x->time-y->time:x->down-y->down;}
int main(int argc,char**argv){
 if(argc<3||argc>5)return 2;
 int interval=atoi(argv[1]),hold=atoi(argv[2]);
 int slotCount=argc>=4?atoi(argv[3]):2, grouped=argc>=5?atoi(argv[4]):0;
 if(slotCount<1||slotCount>2||(slotCount==1&&hold>interval)||(grouped!=0&&grouped!=1))return 2;
 if(interval<20||interval>500||hold<10||hold>=2*interval)return 2;
 struct point p[200];int n=0,x,y;
 while(scanf("%d%d",&x,&y)==2){if(n>=200||x<0||x>1403||y<0||y>1871)return 2;p[n++]=(struct point){x,y};}
 if(!n||n*interval>60000)return 2;
 int fd=open("/dev/input/event2",O_RDWR|O_NONBLOCK);if(fd<0)return 3;
 struct stat st;if(fstat(fd,&st)||!S_ISCHR(st.st_mode)||major(st.st_rdev)!=13||minor(st.st_rdev)!=66){close(fd);return 4;}
 unsigned char keys[KEY_MAX/8+1]={0};int slots[33]={ABS_MT_TRACKING_ID};
 if(ioctl(fd,EVIOCGKEY(sizeof keys),keys)<0 || ioctl(fd,EVIOCGMTSLOTS(sizeof slots),slots)<0){close(fd);return 5;}
 if(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8))){close(fd);return 5;}
 for(int i=1;i<33;i++)if(slots[i]>=0){close(fd);return 5;}
 // Prime the idle slot selection before contacts: the kernel suppresses an
 // unchanged ABS_MT_SLOT, whereas a freshly started reader needs its baseline.
 for(int slot=1;slot>=0;slot--){emit(fd,EV_ABS,ABS_MT_SLOT,slot);emit(fd,EV_ABS,ABS_MT_TRACKING_ID,-1);emit(fd,EV_SYN,SYN_REPORT,0);}
 signal(SIGINT,stopped);signal(SIGTERM,stopped);
 struct action a[600];for(int i=0;i<n;i++){a[3*i]=(struct action){i*interval,i,1};a[3*i+1]=(struct action){i*interval+(hold/2<8?hold/2:8),i,2};a[3*i+2]=(struct action){i*interval+hold,i,0};}qsort(a,3*n,sizeof a[0],cmp);
 long long base=ms(CLOCK_MONOTONIC)+20,start=ms(CLOCK_REALTIME)+20;int active[2]={0},ok=1,downs=0;
 for(int i=0;i<3*n&&!stop&&ok;i++){
  long long at=base+a[i].time;struct timespec ts={at/1000,(at%1000)*1000000};
  while(clock_nanosleep(CLOCK_MONOTONIC,TIMER_ABSTIME,&ts,0)==EINTR&&!stop){}
  if(stop)break;
  int slot=a[i].index%slotCount;ok&=emit(fd,EV_ABS,ABS_MT_SLOT,slot);
  if(a[i].down==1){
   if(active[slot]){ok=0;break;}active[slot]=1;downs++;
   ok&=emit(fd,EV_ABS,ABS_MT_POSITION_X,p[a[i].index].x);ok&=emit(fd,EV_ABS,ABS_MT_POSITION_Y,p[a[i].index].y);
   ok&=emit(fd,EV_ABS,ABS_MT_PRESSURE,120);ok&=emit(fd,EV_ABS,ABS_MT_TOUCH_MAJOR,12);ok&=emit(fd,EV_ABS,ABS_MT_TOUCH_MINOR,8);
   ok&=emit(fd,EV_ABS,ABS_MT_TRACKING_ID,1000+(int)(start%30000)+a[i].index);
  }else if(a[i].down==2){
   // Real contacts report more than one sensor frame, even while stationary.
   // A one-pixel/pressure update avoids kernel suppression of identical data.
   ok&=emit(fd,EV_ABS,ABS_MT_POSITION_X,p[a[i].index].x+(p[a[i].index].x<1403?1:-1));
   ok&=emit(fd,EV_ABS,ABS_MT_PRESSURE,121);
  }else{active[slot]=0;ok&=emit(fd,EV_ABS,ABS_MT_TRACKING_ID,-1);}
  if(!grouped||i+1==3*n||a[i+1].time!=a[i].time){
   ok&=emit(fd,EV_KEY,BTN_TOUCH,active[0]||active[1]);ok&=emit(fd,EV_KEY,BTN_TOOL_FINGER,active[0]||active[1]);ok&=emit(fd,EV_SYN,SYN_REPORT,0);
  }
 }
 for(int i=0;i<2;i++){emit(fd,EV_ABS,ABS_MT_SLOT,i);emit(fd,EV_ABS,ABS_MT_TRACKING_ID,-1);}
 emit(fd,EV_KEY,BTN_TOUCH,0);emit(fd,EV_KEY,BTN_TOOL_FINGER,0);emit(fd,EV_SYN,SYN_REPORT,0);close(fd);
 printf("{\"presses\":%d,\"interval_ms\":%d,\"hold_ms\":%d,\"started_ms\":%lld,\"ended_ms\":%lld,\"writes_ok\":%s}\n",downs,interval,hold,start,ms(CLOCK_REALTIME),ok&&!stop?"true":"false");return ok&&!stop?0:7;
}
