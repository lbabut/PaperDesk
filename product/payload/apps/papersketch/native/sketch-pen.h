#ifndef PAPER_SKETCH_PEN_H
#define PAPER_SKETCH_PEN_H
#include <linux/input.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <array>
#include <atomic>
#include <mutex>
#include <thread>
#include <chrono>
#include <cstring>
#include <cmath>
struct PaperPen {
 struct Sample{double x,y,p;long long time;};
 std::array<Sample,2048> samples{};unsigned head=0,count=0;std::mutex mutex;
 std::atomic<bool> stop{false},enabled{true},ready{false},nearby{false};std::thread thread;
 static long long now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 PaperPen(){thread=std::thread([this]{readLoop();});}
 ~PaperPen(){stop=true;thread.join();}
 void activate(){std::lock_guard<std::mutex> lock(mutex);head=0;count=0;enabled=true;}
 void pause(){enabled=false;nearby=false;std::lock_guard<std::mutex> lock(mutex);head=0;count=0;}
 void push(double x,double y,double p){
  std::lock_guard<std::mutex> lock(mutex);samples[head]={x,y,p,now()};head=(head+1)%samples.size();if(count<samples.size())count++;
 }
 // Match pressure to the delivered screen position, rather than sampling a
 // newer pressure after Qt has queued the older movement event.
 double at(double x,double y){
  std::lock_guard<std::mutex> lock(mutex);double best=9.0,value=-1;auto time=now();
  for(unsigned k=0;k<count;k++){const auto &s=samples[(head+samples.size()-1-k)%samples.size()];if(time-s.time>1000)break;
   double dx=s.x-x,dy=s.y-y,d=dx*dx+dy*dy;if(d<best){best=d;value=s.p;if(d<.04)break;}
  }return value;
 }
 void readLoop(){
  int fd=open("/dev/input/event1",O_RDONLY|O_NONBLOCK|O_CLOEXEC);char name[128]={0};
  if(fd<0)return;if(ioctl(fd,EVIOCGNAME(sizeof name),name)<0||!strstr(name,"Wacom")){close(fd);return;}
  input_absinfo ax{},ay{},ap{};ioctl(fd,EVIOCGABS(ABS_X),&ax);ioctl(fd,EVIOCGABS(ABS_Y),&ay);ioctl(fd,EVIOCGABS(ABS_PRESSURE),&ap);
  if(ax.maximum<=ax.minimum||ay.maximum<=ay.minimum||ap.maximum<=ap.minimum){close(fd);return;}
  int x=ax.value,y=ay.value,p=ap.value,touch=0,range=0;unsigned char keys[KEY_MAX/8+1]={0};ioctl(fd,EVIOCGKEY(sizeof keys),keys);
  touch=!!(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8)));range=!!(keys[BTN_TOOL_PEN/8]&(1<<(BTN_TOOL_PEN%8)));
  ready=true;pollfd item{fd,POLLIN,0};
  while(!stop){if(poll(&item,1,50)<=0)continue;input_event events[128];int bytes=read(fd,events,sizeof events);
   for(int i=0;i<bytes/(int)sizeof *events;i++){auto &e=events[i];
    if(e.type==EV_SYN&&e.code==SYN_DROPPED){
     ioctl(fd,EVIOCGABS(ABS_X),&ax);ioctl(fd,EVIOCGABS(ABS_Y),&ay);ioctl(fd,EVIOCGABS(ABS_PRESSURE),&ap);
     x=ax.value;y=ay.value;p=ap.value;ioctl(fd,EVIOCGKEY(sizeof keys),keys);touch=!!(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8)));continue;
    }
    if(e.type==EV_ABS){if(e.code==ABS_X)x=e.value;else if(e.code==ABS_Y)y=e.value;else if(e.code==ABS_PRESSURE)p=e.value;}
    if(e.type==EV_KEY){if(e.code==BTN_TOUCH)touch=e.value;else if(e.code==BTN_TOOL_PEN||e.code==BTN_TOOL_RUBBER)range=e.value;}
    if(e.type==EV_SYN&&e.code==SYN_REPORT&&enabled){
     nearby=range!=0;
     if(touch&&p>ap.minimum)push((y-ay.minimum)*1404.0/(ay.maximum-ay.minimum),(ax.maximum-x)*1872.0/(ax.maximum-ax.minimum),(p-ap.minimum)/double(ap.maximum-ap.minimum));
    }
   }
  }close(fd);ready=false;
 }
};
#endif
