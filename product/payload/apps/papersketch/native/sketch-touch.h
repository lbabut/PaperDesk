#ifndef PAPER_SKETCH_TOUCH_H
#define PAPER_SKETCH_TOUCH_H
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
#include <algorithm>
#include <cmath>
#include <cstring>

// Non-grabbing contact geometry. Capacitive pressure is a contact proxy, not
// a force measurement. Unavailable/stale/multiple contacts use safe defaults.
struct PaperTouch {
    struct Sample{double x=0,y=0,major=0,minor=0,pressure=-1,angle=0;long long time=0;};
    std::array<Sample,256> samples{};unsigned head=0,count=0;
    std::mutex mutex;std::atomic<bool> stopping{false},enabled{false};std::thread thread;
    static long long now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
    explicit PaperTouch(bool start=true){if(start)thread=std::thread([this]{readLoop();});}
    ~PaperTouch(){stopping=true;if(thread.joinable())thread.join();}
    void activate(){std::lock_guard<std::mutex> lock(mutex);head=count=0;enabled=true;}
    void pause(){enabled=false;std::lock_guard<std::mutex> lock(mutex);head=count=0;}
    void push(Sample value){
        if(!std::isfinite(value.x)||!std::isfinite(value.y))return;
        value.time=now();std::lock_guard<std::mutex> lock(mutex);samples[head]=value;head=(head+1)%samples.size();count=std::min<unsigned>(count+1,samples.size());
    }
    Sample match(double x,double y){
        std::lock_guard<std::mutex> lock(mutex);Sample result;double best=36;auto t=now();
        for(unsigned n=0;n<count;n++){const auto &s=samples[(head+samples.size()-1-n)%samples.size()];if(t-s.time>250)break;double dx=s.x-x,dy=s.y-y,d=dx*dx+dy*dy;if(d<best){result=s;best=d;if(d<.04)break;}}
        return result;
    }
    void readLoop(){
        int fd=open("/dev/input/event2",O_RDONLY|O_NONBLOCK|O_CLOEXEC);char name[128]={0};
        if(fd<0)return;if(ioctl(fd,EVIOCGNAME(sizeof name),name)<0||!strstr(name,"pt_mt")){close(fd);return;}
        input_absinfo ax{},ay{},ap{},ao{};
        ioctl(fd,EVIOCGABS(ABS_MT_POSITION_X),&ax);ioctl(fd,EVIOCGABS(ABS_MT_POSITION_Y),&ay);
        bool pressure=ioctl(fd,EVIOCGABS(ABS_MT_PRESSURE),&ap)==0&&ap.maximum>ap.minimum;
        bool orientation=ioctl(fd,EVIOCGABS(ABS_MT_ORIENTATION),&ao)==0&&ao.maximum>ao.minimum;
        if(ax.maximum<=ax.minimum||ay.maximum<=ay.minimum){close(fd);return;}
        struct Contact{int id=-1,x=0,y=0,major=0,minor=0,p=0,angle=0;};
        std::array<Contact,32> contactSlots{};int slot=0;bool dropped=false;pollfd item{fd,POLLIN,0};
        while(!stopping){
            if(poll(&item,1,50)<=0)continue;input_event events[128];int bytes=read(fd,events,sizeof events);
            for(int i=0;i<bytes/int(sizeof(input_event));i++){
                auto e=events[i];
                if(e.type==EV_SYN&&e.code==SYN_DROPPED){dropped=true;for(auto &s:contactSlots)s=Contact{};continue;}
                if(dropped){if(e.type==EV_SYN&&e.code==SYN_REPORT)dropped=false;continue;}
                if(e.type==EV_ABS){
                    if(e.code==ABS_MT_SLOT){slot=e.value;continue;}if(slot<0||slot>=int(contactSlots.size()))continue;
                    auto &s=contactSlots[slot];
                    if(e.code==ABS_MT_TRACKING_ID){s=Contact{};s.id=e.value;}
                    else if(e.code==ABS_MT_POSITION_X)s.x=e.value;else if(e.code==ABS_MT_POSITION_Y)s.y=e.value;
                    else if(e.code==ABS_MT_TOUCH_MAJOR)s.major=e.value;else if(e.code==ABS_MT_TOUCH_MINOR)s.minor=e.value;
                    else if(e.code==ABS_MT_PRESSURE)s.p=e.value;else if(e.code==ABS_MT_ORIENTATION)s.angle=e.value;
                }
                if(e.type==EV_SYN&&e.code==SYN_REPORT&&enabled){
                    Contact *single=nullptr;int active=0;for(auto &s:contactSlots)if(s.id>=0){single=&s;active++;}
                    if(active!=1)continue;
                    double sx=1404.0/(ax.maximum-ax.minimum),sy=1872.0/(ay.maximum-ay.minimum);
                    double q=pressure&&single->p>=ap.minimum?std::clamp(double(single->p-ap.minimum)/(ap.maximum-ap.minimum),0.0,1.0):-1;
                    double angle=orientation?std::clamp(double(single->angle)/std::max(1,std::max(std::abs(ao.minimum),std::abs(ao.maximum))),-1.0,1.0)*1.5707963267948966:0;
                    push({(single->x-ax.minimum)*sx,1872-(single->y-ay.minimum)*sy,
                          single->major>0?std::clamp(single->major*std::max(sx,sy),4.0,80.0):0,
                          single->minor>0?std::clamp(single->minor*std::min(sx,sy),4.0,80.0):0,q,-angle});
                }
            }
        }close(fd);
    }
};
#endif
