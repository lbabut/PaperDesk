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
#include <cstdint>
#include <algorithm>
struct PaperPen {
 struct Sample{double x=0,y=0,p=-1;long long time=0;uint64_t id=0;unsigned contact=0;};
 std::array<Sample,2048> samples{};unsigned head=0,count=0;uint64_t serial=0;std::mutex mutex;
 std::atomic<bool> stop{false},enabled{true},ready{false},nearby{false};std::thread thread;
 static long long now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 PaperPen(){thread=std::thread([this]{readLoop();});}
 ~PaperPen(){stop=true;thread.join();}
 void activate(){std::lock_guard<std::mutex> lock(mutex);head=0;count=0;nearby=false;enabled=true;}
 void pause(){enabled=false;nearby=false;std::lock_guard<std::mutex> lock(mutex);head=0;count=0;}
 void push(double x,double y,double p,unsigned contact=1){
  std::lock_guard<std::mutex> lock(mutex);samples[head]={x,y,p,now(),++serial,contact};head=(head+1)%samples.size();if(count<samples.size())count++;
 }
 // Match pressure to the delivered screen position, rather than sampling a
 // newer pressure after Qt has queued the older movement event.
 Sample match(double x,double y){
  std::lock_guard<std::mutex> lock(mutex);double best=9.0;Sample result;auto time=now();
  for(unsigned k=0;k<count;k++){const auto &s=samples[(head+samples.size()-1-k)%samples.size()];if(time-s.time>1000)break;
   double dx=s.x-x,dy=s.y-y,d=dx*dx+dy*dy;if(d<best){best=d;result=s;if(d<.04)break;}
  }return result;
 }
 double at(double x,double y){return match(x,y).p;}
 unsigned between(uint64_t after,const Sample &end,std::array<Sample,64>&out){
  std::lock_guard<std::mutex> lock(mutex);unsigned n=0;
  for(unsigned k=0;k<count;k++){const auto &s=samples[(head+samples.size()-1-k)%samples.size()];
   if(s.id>end.id)continue;if(s.id<=after||s.contact!=end.contact||end.time-s.time>250)break;
   out[n++]=s;if(n==out.size())break;
  }
  std::reverse(out.begin(),out.begin()+n);return n;
 }
 void readLoop(){
  int fd=open("/dev/input/event1",O_RDONLY|O_NONBLOCK|O_CLOEXEC);char name[128]={0};
  if(fd<0)return;if(ioctl(fd,EVIOCGNAME(sizeof name),name)<0||!strstr(name,"Wacom")){close(fd);return;}
  input_absinfo ax{},ay{},ap{};ioctl(fd,EVIOCGABS(ABS_X),&ax);ioctl(fd,EVIOCGABS(ABS_Y),&ay);ioctl(fd,EVIOCGABS(ABS_PRESSURE),&ap);
  if(ax.maximum<=ax.minimum||ay.maximum<=ay.minimum||ap.maximum<=ap.minimum){close(fd);return;}
  int x=ax.value,y=ay.value,p=ap.value,touch=0;bool penTool=false,rubberTool=false,dropping=false;unsigned char keys[KEY_MAX/8+1]={0};ioctl(fd,EVIOCGKEY(sizeof keys),keys);
  touch=!!(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8)));penTool=!!(keys[BTN_TOOL_PEN/8]&(1<<(BTN_TOOL_PEN%8)));rubberTool=!!(keys[BTN_TOOL_RUBBER/8]&(1<<(BTN_TOOL_RUBBER%8)));
  unsigned contact=1;ready=true;pollfd item{fd,POLLIN,0};
  while(!stop){if(poll(&item,1,50)<=0)continue;input_event events[128];int bytes=read(fd,events,sizeof events);
   for(int i=0;i<bytes/(int)sizeof *events;i++){auto &e=events[i];
    if(e.type==EV_SYN&&e.code==SYN_DROPPED){dropping=true;continue;}
    if(dropping){
     if(e.type!=EV_SYN||e.code!=SYN_REPORT)continue;
     ioctl(fd,EVIOCGABS(ABS_X),&ax);ioctl(fd,EVIOCGABS(ABS_Y),&ay);ioctl(fd,EVIOCGABS(ABS_PRESSURE),&ap);
     x=ax.value;y=ay.value;p=ap.value;ioctl(fd,EVIOCGKEY(sizeof keys),keys);touch=!!(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8)));
     penTool=!!(keys[BTN_TOOL_PEN/8]&(1<<(BTN_TOOL_PEN%8)));rubberTool=!!(keys[BTN_TOOL_RUBBER/8]&(1<<(BTN_TOOL_RUBBER%8)));
     contact++;dropping=false;
    }
    if(e.type==EV_ABS){if(e.code==ABS_X)x=e.value;else if(e.code==ABS_Y)y=e.value;else if(e.code==ABS_PRESSURE)p=e.value;}
    if(e.type==EV_KEY){if(e.code==BTN_TOUCH){if(!touch&&e.value)contact++;touch=e.value;}else if(e.code==BTN_TOOL_PEN)penTool=e.value;else if(e.code==BTN_TOOL_RUBBER)rubberTool=e.value;}
    if(e.type==EV_SYN&&e.code==SYN_REPORT&&enabled){
     nearby=penTool||rubberTool;
     if(touch&&p>ap.minimum)push((y-ay.minimum)*1404.0/(ay.maximum-ay.minimum),(ax.maximum-x)*1872.0/(ax.maximum-ax.minimum),(p-ap.minimum)/double(ap.maximum-ap.minimum),contact);
    }
   }
  }close(fd);ready=false;
 }
};
#endif
