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
#include <limits>
#include <deque>
#include <vector>
#include <functional>
struct PaperPen {
 struct Sample{double x=0,y=0,p=-1;long long time=0;uint64_t id=0;unsigned contact=0;double tiltX=0,tiltY=0;bool eraser=false;};
 struct MatchDiagnostics {
  uint64_t calls=0,misses=0,stalePositionMisses=0;
  unsigned samplesAtMiss=0;
  long long nearestMissAge=-1,youngestMissAge=-1,maxStaleAge=-1;
  double nearestMissDistance=-1;
 } matchStats;
 struct InputEvent { Sample sample; int phase=0; }; // 1 down, 2 sample, 3 up, 4 gap
 std::deque<InputEvent> input;std::function<void()> inputWake;
 bool inputEnabled=false,frameDown=false;unsigned frameContact=0,inputContact=0;
 double viewX=0,viewY=0,viewSX=1,viewSY=1,contactX=0,contactY=0,contactSX=1,contactSY=1;
 void setViewport(double x,double y,double sx,double sy){if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(sx)||!std::isfinite(sy)||sx<=0||sy<=0)return;std::lock_guard<std::mutex> lock(mutex);viewX=x;viewY=y;viewSX=sx;viewSY=sy;}
 uint64_t inputReceived=0,inputOverflows=0;static constexpr size_t inputCapacity=8192;
 double excludeX=0,excludeY=0,excludeW=0,excludeH=0;
 void setInputExclusion(double x,double y,double w,double h){
  std::lock_guard<std::mutex> lock(mutex);
  if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(w)||!std::isfinite(h)||w<=0||h<=0){excludeW=excludeH=0;return;}
  excludeX=x;excludeY=y;excludeW=w;excludeH=h;
 }
 void setInputWake(std::function<void()> wake){std::lock_guard<std::mutex> lock(mutex);inputWake=std::move(wake);}
 void enableInput(bool value){std::lock_guard<std::mutex> lock(mutex);if(inputEnabled==value)return;inputEnabled=value;input.clear();inputContact=0;}
 std::vector<InputEvent> takeInput(size_t limit=64){
  std::lock_guard<std::mutex> lock(mutex);std::vector<InputEvent> result;result.reserve(std::min(limit,input.size()));
  while(!input.empty()&&result.size()<limit){result.push_back(input.front());input.pop_front();}return result;
 }
 bool inputPending()const{std::lock_guard<std::mutex> lock(mutex);return !input.empty();}
 std::array<uint64_t,3> inputStats()const{std::lock_guard<std::mutex> lock(mutex);return {inputReceived,inputOverflows,input.size()};}
 void frame(double x,double y,double p,unsigned contact,double tx,double ty,bool eraser,bool down){
  if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(p))return;
  std::function<void()> wake;
  {
   std::lock_guard<std::mutex> lock(mutex);
   Sample sample{x,y,p,now(),++serial,contact,std::clamp(tx,-1.0,1.0),std::clamp(ty,-1.0,1.0),eraser};
   if(down){samples[head]=sample;head=(head+1)%samples.size();if(count<samples.size())count++;}
   bool first=down&&(!frameDown||contact!=frameContact);
   int phase=0;
   if(inputEnabled){
    if(first){
     bool inside=x>=viewX&&y>=viewY&&x<viewX+1200*viewSX&&y<viewY+1600*viewSY;
     if(excludeW>0&&excludeH>0&&x>=excludeX&&y>=excludeY&&x<excludeX+excludeW&&y<excludeY+excludeH)inside=false;
     inputContact=inside?contact:0;phase=inside?1:0;
     contactX=viewX;contactY=viewY;contactSX=viewSX;contactSY=viewSY;
    }
    else if(inputContact==contact&&inputContact)phase=down?2:3;
    if(phase){
     if(input.size()==inputCapacity){
      // Explicit loss boundary: never join a stroke across an overrun.
      input.clear();inputContact=0;inputOverflows++;phase=0;
      InputEvent boundary{};boundary.phase=4;input.push_back(boundary);wake=inputWake;
     }else{
      bool empty=input.empty();Sample point=sample;point.x=(x-contactX)/contactSX;point.y=(y-contactY)/contactSY;input.push_back({point,phase});inputReceived++;
      if(empty)wake=inputWake;
     }
    }
   }
   if(!down)inputContact=0;
   frameDown=down;frameContact=contact;
  }
  if(wake)wake();
 }
 void observeFrame(bool down,unsigned contact){std::lock_guard<std::mutex> lock(mutex);frameDown=down;frameContact=contact;}
 void discontinuity(){std::function<void()> wake;{std::lock_guard<std::mutex> lock(mutex);input.clear();inputContact=0;frameDown=true;inputOverflows++;if(inputEnabled){InputEvent boundary{};boundary.phase=4;input.push_back(boundary);wake=inputWake;}}if(wake)wake();}
 std::array<Sample,2048> samples{};unsigned head=0,count=0;uint64_t serial=0;mutable std::mutex mutex;
 std::atomic<bool> stop{false},enabled{true},ready{false},nearby{false},eraserNearby{false};std::thread thread;
 static long long now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 PaperPen(){thread=std::thread([this]{readLoop();});}
 void shutdown(){stop=true;if(thread.joinable())thread.join();}
 ~PaperPen(){shutdown();}
 void activate(){std::lock_guard<std::mutex> lock(mutex);head=0;count=0;input.clear();inputContact=0;nearby=false;eraserNearby=false;enabled=true;}
 void pause(){enabled=false;nearby=false;eraserNearby=false;std::lock_guard<std::mutex> lock(mutex);head=0;count=0;input.clear();inputContact=0;inputEnabled=false;}
 void resetMatchDiagnostics(){std::lock_guard<std::mutex> lock(mutex);matchStats=MatchDiagnostics{};}
 MatchDiagnostics matchDiagnostics()const{std::lock_guard<std::mutex> lock(mutex);return matchStats;}
 void push(double x,double y,double p,unsigned contact=1,double tiltX=0,double tiltY=0,bool eraser=false){
  if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(p)||!std::isfinite(tiltX)||!std::isfinite(tiltY))return;
  std::lock_guard<std::mutex> lock(mutex);samples[head]={x,y,p,now(),++serial,contact,std::clamp(tiltX,-1.0,1.0),std::clamp(tiltY,-1.0,1.0),eraser};head=(head+1)%samples.size();if(count<samples.size())count++;
 }
 // Match pressure to the delivered screen position, rather than sampling a
 // newer pressure after Qt has queued the older movement event.
 Sample match(double x,double y){
  std::lock_guard<std::mutex> lock(mutex);double best=9.0;Sample result;auto time=now();matchStats.calls++;
  for(unsigned k=0;k<count;k++){const auto &s=samples[(head+samples.size()-1-k)%samples.size()];if(time-s.time>1000)break;
   double dx=s.x-x,dy=s.y-y,d=dx*dx+dy*dy;if(d<best){best=d;result=s;if(d<.04)break;}
  }
  if(result.p<0){
   matchStats.misses++;matchStats.samplesAtMiss=count;
   matchStats.youngestMissAge=count?time-samples[(head+samples.size()-1)%samples.size()].time:-1;
   matchStats.nearestMissAge=-1;matchStats.nearestMissDistance=-1;
   double nearest=std::numeric_limits<double>::infinity();
   // Diagnostics alone inspect the bounded ring beyond the matching TTL.
   // Matching behavior and the accepted sample remain exactly unchanged.
   for(unsigned k=0;k<count;k++){
    const auto &s=samples[(head+samples.size()-1-k)%samples.size()];
    double dx=s.x-x,dy=s.y-y,d=dx*dx+dy*dy;
    if(d<nearest){nearest=d;matchStats.nearestMissAge=time-s.time;}
   }
   if(count)matchStats.nearestMissDistance=std::sqrt(nearest);
   if(nearest<9.0&&matchStats.nearestMissAge>1000){
    matchStats.stalePositionMisses++;
    matchStats.maxStaleAge=std::max(matchStats.maxStaleAge,matchStats.nearestMissAge);
   }
  }
  return result;
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
  input_absinfo ax{},ay{},ap{},atx{},aty{};ioctl(fd,EVIOCGABS(ABS_X),&ax);ioctl(fd,EVIOCGABS(ABS_Y),&ay);ioctl(fd,EVIOCGABS(ABS_PRESSURE),&ap);
  bool hasTiltX=ioctl(fd,EVIOCGABS(ABS_TILT_X),&atx)==0&&atx.maximum>atx.minimum,hasTiltY=ioctl(fd,EVIOCGABS(ABS_TILT_Y),&aty)==0&&aty.maximum>aty.minimum;
  int tiltX=atx.value,tiltY=aty.value;
  auto normalized=[](int value,const input_absinfo &axis){double span=std::max(std::abs(double(axis.minimum)),std::abs(double(axis.maximum)));return span>0?std::clamp(value/span,-1.0,1.0):0.0;};
  if(ax.maximum<=ax.minimum||ay.maximum<=ay.minimum||ap.maximum<=ap.minimum){close(fd);return;}
  int x=ax.value,y=ay.value,p=ap.value,touch=0;bool penTool=false,rubberTool=false,dropping=false;unsigned char keys[KEY_MAX/8+1]={0};ioctl(fd,EVIOCGKEY(sizeof keys),keys);
  touch=!!(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8)));penTool=!!(keys[BTN_TOOL_PEN/8]&(1<<(BTN_TOOL_PEN%8)));rubberTool=!!(keys[BTN_TOOL_RUBBER/8]&(1<<(BTN_TOOL_RUBBER%8)));
  unsigned contact=1;observeFrame(touch!=0,contact);ready=true;pollfd item{fd,POLLIN,0};
  while(!stop){if(poll(&item,1,50)<=0)continue;input_event events[128];int bytes=read(fd,events,sizeof events);
   for(int i=0;i<bytes/(int)sizeof *events;i++){auto &e=events[i];
    if(e.type==EV_SYN&&e.code==SYN_DROPPED){discontinuity();dropping=true;continue;}
    if(dropping){
     if(e.type!=EV_SYN||e.code!=SYN_REPORT)continue;
     ioctl(fd,EVIOCGABS(ABS_X),&ax);ioctl(fd,EVIOCGABS(ABS_Y),&ay);ioctl(fd,EVIOCGABS(ABS_PRESSURE),&ap);
     x=ax.value;y=ay.value;p=ap.value;ioctl(fd,EVIOCGKEY(sizeof keys),keys);touch=!!(keys[BTN_TOUCH/8]&(1<<(BTN_TOUCH%8)));
     if(hasTiltX){ioctl(fd,EVIOCGABS(ABS_TILT_X),&atx);tiltX=atx.value;}if(hasTiltY){ioctl(fd,EVIOCGABS(ABS_TILT_Y),&aty);tiltY=aty.value;}
     penTool=!!(keys[BTN_TOOL_PEN/8]&(1<<(BTN_TOOL_PEN%8)));rubberTool=!!(keys[BTN_TOOL_RUBBER/8]&(1<<(BTN_TOOL_RUBBER%8)));
     contact++;observeFrame(touch!=0,contact);dropping=false;
    }
    if(e.type==EV_ABS){if(e.code==ABS_X)x=e.value;else if(e.code==ABS_Y)y=e.value;else if(e.code==ABS_PRESSURE)p=e.value;else if(e.code==ABS_TILT_X)tiltX=e.value;else if(e.code==ABS_TILT_Y)tiltY=e.value;}
    if(e.type==EV_KEY){if(e.code==BTN_TOUCH){if(!touch&&e.value)contact++;touch=e.value;}else if(e.code==BTN_TOOL_PEN)penTool=e.value;else if(e.code==BTN_TOOL_RUBBER)rubberTool=e.value;}
    if(e.type==EV_SYN&&e.code==SYN_REPORT){
     if(!enabled){observeFrame(touch!=0,contact);continue;}
     nearby=penTool||rubberTool;eraserNearby=rubberTool;
     frame((y-ay.minimum)*1404.0/(ay.maximum-ay.minimum),(ax.maximum-x)*1872.0/(ax.maximum-ax.minimum),std::clamp((p-ap.minimum)/double(ap.maximum-ap.minimum),0.0,1.0),contact,hasTiltY?normalized(tiltY,aty):0,hasTiltX?-normalized(tiltX,atx):0,rubberTool,touch!=0);
    }
   }
  }close(fd);ready=false;
 }
};
#endif
