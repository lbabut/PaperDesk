#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>

#include "qtfb-client.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cerrno>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <fcntl.h>
#include <map>
#include <memory>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <utility>
#include <vector>

namespace {
constexpr int W = 1404;
constexpr int H = 1872;
constexpr int BAR_H = 112;
constexpr int RDP_H = H - BAR_H;
constexpr int ACTION_H = 68;
constexpr int ACTION_Y = 22;
constexpr int CLOSE_X = 1210;
constexpr int CLOSE_W = 176;
constexpr int SHORTCUTS_X = 980;
constexpr int SHORTCUTS_W = 216;

struct App;
struct PaperContext {
    rdpContext context;
    App* app;
};

enum class Mode { Login, Connecting, Remote, Error };

struct Profile {
    std::string host;
    std::string user;
    std::string domain;
    std::string password;
    int port = 3389;
};

struct App {
    qtfb::ClientConnection fb;
    Mode mode = Mode::Login;
    Profile profile;
    int field = 0;
    bool shift = false;
    bool shortcutsOpen = false;
    bool running = true;
    bool mouseDown = false;
    int mouseTouchId = -1;
    float mouseStartX = 0.0f;
    float mouseStartY = 0.0f;
    int mouseLastX = 0;
    int mouseLastY = 0;
    std::chrono::steady_clock::time_point lastMouseMove = std::chrono::steady_clock::now();
    float zoom = 1.0f;
    float viewX = 0.0f;
    float viewY = 0.0f;
    std::map<int,std::pair<float,float>> touches;
    bool pinchActive = false;
    bool gestureConsumed = false;
    bool panCandidate = false;
    bool panActive = false;
    int panId = -1;
    float panStartX = 0.0f;
    float panStartY = 0.0f;
    float panStartViewX = 0.0f;
    float panStartViewY = 0.0f;
    float pinchDistance = 1.0f;
    float pinchStartZoom = 1.0f;
    float pinchAnchorX = 0.0f;
    float pinchAnchorY = 0.0f;
    bool dirty = false;
    int dirtyX1 = W;
    int dirtyY1 = RDP_H;
    int dirtyX2 = 0;
    int dirtyY2 = 0;
    std::chrono::steady_clock::time_point lastFrame = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point dirtySince = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point lastDirty = std::chrono::steady_clock::now();
    bool cleanRefreshPending = false;
    std::chrono::steady_clock::time_point cleanRefreshDue = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point lastCleanRefresh =
        std::chrono::steady_clock::now() - std::chrono::seconds(10);
    std::string status = "ENTER CONNECTION DETAILS";
    bool launchedFromNativeLogin = false;
    freerdp* rdp = nullptr;

    App() : fb(qtfb::getIDFromAppload(), FBFMT_RM2FB) {
        fb.setRefreshMode(REFRESH_MODE_UI);
        std::memset(fb.shm, 0xff, fb.shmSize);
    }
};

App* g_app = nullptr;

static const std::map<char, std::array<uint8_t, 7>>& glyphs() {
    static const std::map<char, std::array<uint8_t, 7>> g = {
        {' ',{0,0,0,0,0,0,0}}, {'-',{0,0,0,31,0,0,0}}, {'.',{0,0,0,0,0,12,12}},
        {':',{0,12,12,0,12,12,0}}, {'/',{1,2,4,8,16,0,0}}, {'_',{0,0,0,0,0,0,31}},
        {'*',{0,21,14,31,14,21,0}}, {'@',{14,17,23,21,23,16,14}},
        {'0',{14,17,19,21,25,17,14}}, {'1',{4,12,4,4,4,4,14}}, {'2',{14,17,1,2,4,8,31}},
        {'3',{30,1,1,14,1,1,30}}, {'4',{2,6,10,18,31,2,2}}, {'5',{31,16,16,30,1,1,30}},
        {'6',{14,16,16,30,17,17,14}}, {'7',{31,1,2,4,8,8,8}}, {'8',{14,17,17,14,17,17,14}},
        {'9',{14,17,17,15,1,1,14}},
        {'A',{14,17,17,31,17,17,17}}, {'B',{30,17,17,30,17,17,30}},
        {'C',{14,17,16,16,16,17,14}}, {'D',{30,17,17,17,17,17,30}},
        {'E',{31,16,16,30,16,16,31}}, {'F',{31,16,16,30,16,16,16}},
        {'G',{14,17,16,23,17,17,15}}, {'H',{17,17,17,31,17,17,17}},
        {'I',{14,4,4,4,4,4,14}}, {'J',{7,2,2,2,18,18,12}},
        {'K',{17,18,20,24,20,18,17}}, {'L',{16,16,16,16,16,16,31}},
        {'M',{17,27,21,21,17,17,17}}, {'N',{17,25,21,19,17,17,17}},
        {'O',{14,17,17,17,17,17,14}}, {'P',{30,17,17,30,16,16,16}},
        {'Q',{14,17,17,17,21,18,13}}, {'R',{30,17,17,30,20,18,17}},
        {'S',{15,16,16,14,1,1,30}}, {'T',{31,4,4,4,4,4,4}},
        {'U',{17,17,17,17,17,17,14}}, {'V',{17,17,17,17,17,10,4}},
        {'W',{17,17,17,21,21,21,10}}, {'X',{17,17,10,4,10,17,17}},
        {'Y',{17,17,10,4,4,4,4}}, {'Z',{31,1,2,4,8,16,31}}
        ,{'a',{0,0,14,1,15,17,15}}, {'b',{16,16,30,17,17,17,30}},
        {'c',{0,0,14,17,16,17,14}}, {'d',{1,1,15,17,17,17,15}},
        {'e',{0,0,14,17,31,16,14}}, {'f',{6,9,8,28,8,8,8}},
        {'g',{0,0,15,17,15,1,14}}, {'h',{16,16,30,17,17,17,17}},
        {'i',{4,0,12,4,4,4,14}}, {'j',{2,0,6,2,2,18,12}},
        {'k',{16,16,18,20,24,20,18}}, {'l',{12,4,4,4,4,4,14}},
        {'m',{0,0,26,21,21,17,17}}, {'n',{0,0,30,17,17,17,17}},
        {'o',{0,0,14,17,17,17,14}}, {'p',{0,0,30,17,30,16,16}},
        {'q',{0,0,15,17,15,1,1}}, {'r',{0,0,22,25,16,16,16}},
        {'s',{0,0,15,16,14,1,30}}, {'t',{8,8,28,8,8,9,6}},
        {'u',{0,0,17,17,17,19,13}}, {'v',{0,0,17,17,17,10,4}},
        {'w',{0,0,17,17,21,21,10}}, {'x',{0,0,17,10,4,10,17}},
        {'y',{0,0,17,17,15,1,14}}, {'z',{0,0,31,2,4,8,31}}
    };
    return g;
}

inline uint16_t gray565(uint8_t v) {
    return static_cast<uint16_t>(((v >> 3) << 11) | ((v >> 2) << 5) | (v >> 3));
}

void fill(App& a, int x, int y, int w, int h, uint8_t gray) {
    x = std::max(0, x); y = std::max(0, y);
    w = std::min(w, W - x); h = std::min(h, H - y);
    auto* p = reinterpret_cast<uint16_t*>(a.fb.shm);
    const uint16_t c = gray565(gray);
    for (int yy = y; yy < y + h; ++yy)
        std::fill(p + yy * W + x, p + yy * W + x + w, c);
}

void rect(App& a, int x, int y, int w, int h, uint8_t gray, int t = 3) {
    fill(a,x,y,w,t,gray); fill(a,x,y+h-t,w,t,gray);
    fill(a,x,y,t,h,gray); fill(a,x+w-t,y,t,h,gray);
}

void roundedFill(App& a, int x, int y, int w, int h, int radius, uint8_t gray) {
    radius = std::max(0, std::min(radius, std::min(w, h) / 2));
    for (int row = 0; row < h; ++row) {
        int inset = 0;
        if (row < radius) {
            const int dy = radius - row - 1;
            inset = radius - static_cast<int>(std::sqrt(std::max(0, radius * radius - dy * dy)));
        } else if (row >= h - radius) {
            const int dy = row - (h - radius);
            inset = radius - static_cast<int>(std::sqrt(std::max(0, radius * radius - dy * dy)));
        }
        fill(a, x + inset, y + row, w - 2 * inset, 1, gray);
    }
}

void text(App& a, int x, int y, const std::string& s, int scale = 4, uint8_t gray = 0) {
    auto* p = reinterpret_cast<uint16_t*>(a.fb.shm);
    const uint16_t c = gray565(gray);
    int cx = x;
    for (unsigned char raw : s) {
        char ch = static_cast<char>(raw);
        auto it = glyphs().find(ch);
        const auto& bits = (it == glyphs().end()) ? glyphs().at(' ') : it->second;
        for (int row = 0; row < 7; ++row)
            for (int col = 0; col < 5; ++col)
                if (bits[row] & (1 << (4-col)))
                    for (int sy=0; sy<scale; ++sy)
                        for (int sx=0; sx<scale; ++sx) {
                            int px=cx+col*scale+sx, py=y+row*scale+sy;
                            if (px>=0 && px<W && py>=0 && py<H) p[py*W+px]=c;
                        }
        cx += 6*scale;
    }
}

void button(App& a, int x, int y, int w, int h, const std::string& label, bool dark=false) {
    constexpr int radius = 8;
    constexpr int border = 3;
    constexpr int scale = 3;
    roundedFill(a,x,y,w,h,radius,0);
    roundedFill(a,x+border,y+border,w-2*border,h-2*border,radius-border,dark?24:255);
    int tw = static_cast<int>(label.size()) * 6 * scale;
    text(a,x+(w-tw)/2,y+(h-7*scale)/2,label,scale,dark?255:0);
}

void headerTitle(App& a, const std::string& status) {
    fill(a,0,0,W,BAR_H,0);
    text(a,28,18,"PAPERDESK / REMOTE ACCESS",2,255);
    text(a,28,53,"REMOTE DESKTOP",4,255);
    if (!status.empty()) text(a,430,57,status,3,220);
}

std::string& activeField(App& a) {
    if (a.field == 0) return a.profile.host;
    if (a.field == 1) return a.profile.user;
    return a.profile.password;
}

void drawLogin(App& a,bool complete=false) {
    fill(a,0,0,W,H,255);
    headerTitle(a,"CONNECTION PROFILE");
    button(a,CLOSE_X,ACTION_Y,CLOSE_W,ACTION_H,"CLOSE");
    const char* names[]={"SERVER","USERNAME","PASSWORD"};
    int ys[]={300,520,740};
    for(int i=0;i<3;++i) {
        text(a,75,ys[i],names[i],4,80);
        fill(a,70,ys[i]+55,1264,115,250);
        rect(a,70,ys[i]+55,1264,115,i==a.field?0:120,i==a.field?7:3);
        std::string v = i==0?a.profile.host:(i==1?a.profile.user:std::string(a.profile.password.size(),'*'));
        text(a,95,ys[i]+92,v,5);
    }
    button(a,870,900,464,120,"CONNECT",true);
    text(a,75,1015,a.status,3,70);
    if(complete) {
        a.fb.sendCompleteUpdate();
        a.fb.requestFullRefresh();
    } else a.fb.sendPartialUpdate(0,250,W,940);
}

void drawConnecting(App& a) {
    fill(a,0,0,W,H,255);
    headerTitle(a,"CONNECTING...");
    button(a,CLOSE_X,ACTION_Y,CLOSE_W,ACTION_H,"CLOSE");
    text(a,72,210,"CONNECTING TO REMOTE COMPUTER...",5,0);
    text(a,72,300,a.profile.host,4,70);
    text(a,72,390,"PLEASE WAIT",4,70);
    a.fb.sendCompleteUpdate();
    a.fb.requestFullRefresh();
}

void drawBar(App& a) {
    headerTitle(a,a.status);
    button(a,SHORTCUTS_X,ACTION_Y,SHORTCUTS_W,ACTION_H,"SHORTCUTS");
    button(a,CLOSE_X,ACTION_Y,CLOSE_W,ACTION_H,"CLOSE");
    a.fb.sendPartialUpdate(0,0,W,BAR_H);
}

const std::array<const char*,9> shortcutLabels={
    "CTRL+C","CTRL+V","CTRL+X","CTRL+A","ALT+TAB","CTRL+ALT+DEL","WIN","ESC","TAB"
};

void drawShortcuts(App& a) {
    fill(a,0,BAR_H,W,RDP_H,255);
    text(a,70,155,"KEYBOARD SHORTCUTS",7);
    text(a,72,235,"TAP A SHORTCUT TO SEND IT TO THE REMOTE COMPUTER",3,70);
    constexpr int left=70, top=330, gap=22, bw=406, bh=145;
    for(int i=0;i<9;++i) {
        const int col=i%3,row=i/3;
        button(a,left+col*(bw+gap),top+row*(bh+gap),bw,bh,shortcutLabels[i]);
    }
    button(a,440,900,524,125,"BACK",true);
    a.fb.sendPartialUpdate(0,BAR_H,W,RDP_H);
}

void drawError(App& a, const std::string& message) {
    a.mode=Mode::Error; a.status=message;
    fill(a,0,0,W,H,255);
    headerTitle(a,"CONNECTION FAILED");
    button(a,CLOSE_X,ACTION_Y,CLOSE_W,ACTION_H,"CLOSE");
    text(a,70,190,"CONNECTION FAILED",6);
    text(a,70,235,message,4,80);
    button(a,70,360,520,120,"BACK",true);
    a.fb.sendCompleteUpdate();
}

std::string hexEncode(const std::string& value) {
    static constexpr char digits[]="0123456789abcdef";
    std::string result;
    result.reserve(value.size()*2);
    for(unsigned char ch:value) {
        result.push_back(digits[ch>>4]);
        result.push_back(digits[ch&0x0f]);
    }
    return result;
}

int hexDigit(char ch) {
    if(ch>='0'&&ch<='9') return ch-'0';
    if(ch>='a'&&ch<='f') return ch-'a'+10;
    if(ch>='A'&&ch<='F') return ch-'A'+10;
    return -1;
}

bool hexDecode(const std::string& value,std::string& result) {
    if(value.size()%2) return false;
    std::string decoded;
    decoded.reserve(value.size()/2);
    for(size_t i=0;i<value.size();i+=2) {
        int hi=hexDigit(value[i]),lo=hexDigit(value[i+1]);
        if(hi<0||lo<0) return false;
        decoded.push_back(static_cast<char>((hi<<4)|lo));
    }
    result=std::move(decoded);
    return true;
}

bool saveProfile(const Profile& p) {
    constexpr const char* dir="/home/root/.config/paperrdp";
    constexpr const char* path="/home/root/.config/paperrdp/profile";
    constexpr const char* temp="/home/root/.config/paperrdp/profile.tmp";
    if(::mkdir("/home/root/.config",0700)<0 && errno!=EEXIST) return false;
    if(::mkdir(dir,0700)<0 && errno!=EEXIST) return false;
    ::chmod(dir,0700);
    const int fd=::open(temp,O_WRONLY|O_CREAT|O_TRUNC,0600);
    if(fd<0) return false;
    const std::string data="host="+p.host+"\nuser="+p.user+"\ndomain="+p.domain+
                           "\nport="+std::to_string(p.port)+"\npassword_hex="+hexEncode(p.password)+"\n";
    size_t written=0;
    while(written<data.size()) {
        const ssize_t n=::write(fd,data.data()+written,data.size()-written);
        if(n<=0) { ::close(fd); ::unlink(temp); return false; }
        written+=static_cast<size_t>(n);
    }
    bool ok=::fsync(fd)==0;
    if(::close(fd)<0) ok=false;
    if(!ok) { ::unlink(temp); return false; }
    if(::rename(temp,path)<0) { ::unlink(temp); return false; }
    ::chmod(path,0600);
    return true;
}

void loadProfile(Profile& p) {
    std::ifstream f("/home/root/.config/paperrdp/profile");
    std::string line;
    while(std::getline(f,line)) {
        auto pos=line.find('='); if(pos==std::string::npos) continue;
        auto k=line.substr(0,pos), v=line.substr(pos+1);
        if(k=="host") p.host=v; else if(k=="user") p.user=v; else if(k=="domain") p.domain=v;
        else if(k=="port") p.port=std::max(1,std::atoi(v.c_str()));
        else if(k=="password_hex") hexDecode(v,p.password);
    }
}

BOOL beginPaint(rdpContext* c) {
    if (!c || !c->gdi || !c->gdi->primary || !c->gdi->primary->hdc || !c->gdi->primary->hdc->hwnd) return FALSE;
    c->gdi->primary->hdc->hwnd->invalid->null = TRUE;
    return TRUE;
}

BOOL endPaint(rdpContext* c) {
    auto* pc=reinterpret_cast<PaperContext*>(c); App& a=*pc->app;
    auto* gdi=c->gdi;
    if(!gdi || !gdi->primary || !gdi->primary->hdc || !gdi->primary->hdc->hwnd) return TRUE;
    HGDI_WND wnd=gdi->primary->hdc->hwnd;
    if(!wnd->invalid || wnd->invalid->null) return TRUE;

    auto addDirty=[&a](int x,int y,int w,int h) {
        if(w<=0 || h<=0) return;
        x=std::clamp(x,0,W); y=std::clamp(y,0,RDP_H);
        int x2=std::clamp(x+w,0,W), y2=std::clamp(y+h,0,RDP_H);
        if(x2<=x || y2<=y) return;
        const auto now=std::chrono::steady_clock::now();
        if(!a.dirty) a.dirtySince=now;
        a.lastDirty=now;
        a.dirtyX1=std::min(a.dirtyX1,x); a.dirtyY1=std::min(a.dirtyY1,y);
        a.dirtyX2=std::max(a.dirtyX2,x2); a.dirtyY2=std::max(a.dirtyY2,y2);
        a.dirty=true;
    };
    if(wnd->ninvalid>0 && wnd->cinvalid) {
        for(INT32 i=0;i<wnd->ninvalid;++i) {
            const GDI_RGN& r=wnd->cinvalid[i]; addDirty(r.x,r.y,r.w,r.h);
        }
    } else addDirty(wnd->invalid->x,wnd->invalid->y,wnd->invalid->w,wnd->invalid->h);
    return TRUE;
}

void flushRemoteFrame(App& a, bool force=false) {
    if(a.shortcutsOpen) return;
    if(!a.dirty || !a.rdp || !a.rdp->context || !a.rdp->context->gdi) return;
    auto now=std::chrono::steady_clock::now();
    if(!force) {
        // FreeRDP often delivers one desktop frame as a rapid sequence of
        // horizontal bands.  Publishing every band lets the e-ink controller
        // scan a half-old, half-new shared buffer.  Wait for a short quiet
        // period and cap the wait so genuinely continuous changes still show.
        // Large desktop changes are deliberately much slower: QTFB/e-ink can
        // display them reliably, but cannot consume several full frames per
        // second without composing pieces of different frames on screen.
        const int dirtyW=std::max(0,a.dirtyX2-a.dirtyX1);
        const int dirtyH=std::max(0,a.dirtyY2-a.dirtyY1);
        const bool largeFrame=static_cast<int64_t>(dirtyW)*dirtyH>
                              static_cast<int64_t>(W)*RDP_H/3;
        const auto minFrameGap=largeFrame ? std::chrono::milliseconds(1400)
                                          : std::chrono::milliseconds(300);
        const auto quietPeriod=largeFrame ? std::chrono::milliseconds(260)
                                          : std::chrono::milliseconds(120);
        const auto maxLatency=largeFrame ? std::chrono::milliseconds(2200)
                                         : std::chrono::milliseconds(900);
        if(now-a.lastFrame<minFrameGap) return;
        const bool burstSettled=now-a.lastDirty>=quietPeriod;
        const bool maxLatencyReached=now-a.dirtySince>=maxLatency;
        if(!burstSettled && !maxLatencyReached) return;
    }
    auto* gdi=a.rdp->context->gdi;
    if(!gdi->primary_buffer) return;
    const float vx=a.viewX, vy=a.viewY, z=a.zoom;
    const float visibleW=W/z, visibleH=RDP_H/z;
    const int sx1=std::clamp<int>(std::floor(std::max<float>(a.dirtyX1,vx)),0,gdi->width);
    const int sy1=std::clamp<int>(std::floor(std::max<float>(a.dirtyY1,vy)),0,gdi->height);
    const int sx2=std::clamp<int>(std::ceil(std::min<float>(a.dirtyX2,vx+visibleW)),sx1,gdi->width);
    const int sy2=std::clamp<int>(std::ceil(std::min<float>(a.dirtyY2,vy+visibleH)),sy1,gdi->height);
    const int dx1=std::clamp<int>(std::floor((sx1-vx)*z),0,W);
    const int dy1=std::clamp<int>(std::floor((sy1-vy)*z),0,RDP_H);
    const int dx2=std::clamp<int>(std::ceil((sx2-vx)*z),dx1,W);
    const int dy2=std::clamp<int>(std::ceil((sy2-vy)*z),dy1,RDP_H);
    auto* dst=reinterpret_cast<uint16_t*>(a.fb.shm);
    int changedX1=W, changedY1=RDP_H, changedX2=0, changedY2=0;
    for(int dy=dy1;dy<dy2;++dy) {
        int sy=std::clamp<int>(vy+dy/z,0,gdi->height-1);
        uint16_t* out=dst+(dy+BAR_H)*W+dx1;
        for(int dx=dx1;dx<dx2;++dx,++out) {
            int sx=std::clamp<int>(vx+dx/z,0,gdi->width-1);
            const uint8_t* src=gdi->primary_buffer+sy*gdi->stride+sx*4;
            const uint8_t lum=static_cast<uint8_t>((77*src[2]+150*src[1]+29*src[0])>>8);
            const uint16_t pixel=gray565(lum);
            if(*out!=pixel) {
                *out=pixel;
                changedX1=std::min(changedX1,dx); changedY1=std::min(changedY1,dy);
                changedX2=std::max(changedX2,dx+1); changedY2=std::max(changedY2,dy+1);
            }
        }
    }
    if(changedX2>changedX1 && changedY2>changedY1) {
        a.fb.sendPartialUpdate(changedX1,changedY1+BAR_H,
                               changedX2-changedX1,changedY2-changedY1);
    }
    a.dirty=false; a.dirtyX1=W; a.dirtyY1=RDP_H; a.dirtyX2=0; a.dirtyY2=0;
    a.lastFrame=now;
}

void maybeCleanRefresh(App& a) {
    if(!a.cleanRefreshPending || a.mouseDown || a.dirty || std::chrono::steady_clock::now()<a.cleanRefreshDue) return;
    // UPDATE_ALL publishes the complete current framebuffer.  The explicit
    // refresh then clears e-ink ghosting left by the fast partial waveform.
    a.fb.sendCompleteUpdate();
    a.fb.requestFullRefresh();
    a.cleanRefreshPending=false;
    a.lastCleanRefresh=std::chrono::steady_clock::now();
}

BOOL resizeDesktop(rdpContext* c) {
    return gdi_resize(c->gdi, freerdp_settings_get_uint32(c->settings,FreeRDP_DesktopWidth),
                      freerdp_settings_get_uint32(c->settings,FreeRDP_DesktopHeight));
}

BOOL postConnect(freerdp* instance) {
    if(!gdi_init(instance,PIXEL_FORMAT_BGRA32)) return FALSE;
    instance->context->update->BeginPaint=beginPaint;
    instance->context->update->EndPaint=endPaint;
    instance->context->update->DesktopResize=resizeDesktop;
    auto* pc=reinterpret_cast<PaperContext*>(instance->context);
    App& a=*pc->app;
    a.mode=Mode::Remote; a.status="CONNECTED";
    // Remove the login form from the shared framebuffer before remote paint
    // starts, then clean once immediately and once after the desktop settles.
    fill(a,0,BAR_H,W,RDP_H,255);
    drawBar(a);
    a.fb.sendCompleteUpdate();
    a.fb.requestFullRefresh();
    a.lastCleanRefresh=std::chrono::steady_clock::now();
    a.fb.setRefreshMode(REFRESH_MODE_UFAST);
    a.cleanRefreshPending=true;
    a.cleanRefreshDue=a.lastCleanRefresh+std::chrono::milliseconds(1200);
    return TRUE;
}

void postDisconnect(freerdp* instance) { if(instance) gdi_free(instance); }
DWORD acceptCertificate(freerdp*,const char*,UINT16,const char*,const char*,const char*,const char*,DWORD) { return 2; }
DWORD acceptChangedCertificate(freerdp*,const char*,UINT16,const char*,const char*,const char*,const char*,const char*,const char*,const char*,DWORD) { return 2; }

BOOL contextNew(freerdp*, rdpContext* c) { reinterpret_cast<PaperContext*>(c)->app=g_app; return TRUE; }

uint32_t qtToScan(int key) {
    static const std::map<int,uint32_t> m={
        {'A',0x1e},{'B',0x30},{'C',0x2e},{'D',0x20},{'E',0x12},{'F',0x21},{'G',0x22},{'H',0x23},
        {'I',0x17},{'J',0x24},{'K',0x25},{'L',0x26},{'M',0x32},{'N',0x31},{'O',0x18},{'P',0x19},
        {'Q',0x10},{'R',0x13},{'S',0x1f},{'T',0x14},{'U',0x16},{'V',0x2f},{'W',0x11},{'X',0x2d},
        {'Y',0x15},{'Z',0x2c},
        {0x01000004,0x1c}, // Qt::Key_Return
        {0x01000005,0x1c}, // Qt::Key_Enter (system keyboard)
        {0x01000003,0x0e},{0x20,0x39},{0x01000000,0x01},
        {0x01000020,0x2a},{0x01000021,0x1d},{0x01000023,0x38},
        {'1',0x02},{'2',0x03},{'3',0x04},{'4',0x05},{'5',0x06},{'6',0x07},{'7',0x08},{'8',0x09},{'9',0x0a},{'0',0x0b}
    };
    auto it=m.find(key); return it==m.end()?0:it->second;
}

uint32_t specialKeyToScan(int key) {
    // AppLoad versions in the wild use three different representations for
    // non-printing keys: Qt::Key values, X11 keysyms and ASCII control codes.
    // Normalise all of them before deciding whether an event is Unicode.
    switch(key) {
        case 0x01000003: // Qt::Key_Backspace
        case 0xff08:     // XK_BackSpace
        case 0x08:       // ASCII BS
        case 0x7f:       // DEL, emitted as backspace by some VKB layouts
            return 0x0e;
        case 0x01000004: // Qt::Key_Return
        case 0x01000005: // Qt::Key_Enter
        case 0xff0d:     // XK_Return
        case 0x0a:       // ASCII LF
        case 0x0d:       // ASCII CR
            return 0x1c;
        default:
            return 0;
    }
}

void remoteKey(App& a,int key,bool down) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    uint32_t scan=specialKeyToScan(key);
    if(!scan) scan=qtToScan(key);
    if(scan) freerdp_input_send_keyboard_event_ex(a.rdp->context->input,down,FALSE,scan);
}

void sendUnicode(App& a,uint16_t ch);
void sendShortcut(App& a,int index);

void remoteInputKey(App& a,int rawKey,bool down) {
    constexpr int shortcutPrefix=0x02ff0000;
    if((rawKey&0xffff0000)==shortcutPrefix) {
        if(down) sendShortcut(a,rawKey&0xff);
        return;
    }
    const bool encodedUnicode=(rawKey&0xFF000000)==0x02000000;
    const int key=encodedUnicode ? rawKey&0xFFFF : rawKey;
    if(specialKeyToScan(key)) {
        remoteKey(a,key,down);
    } else if(encodedUnicode) {
        // A Unicode helper sends its own press/release pair.  Ignore the
        // corresponding VKB release packet so printable characters stay
        // single keystrokes.
        if(down) sendUnicode(a,static_cast<uint16_t>(key));
    } else {
        remoteKey(a,key,down);
    }
}

void sendChord(App& a,const std::vector<std::pair<uint32_t,bool>>& keys) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    for(const auto& key:keys)
        freerdp_input_send_keyboard_event_ex(a.rdp->context->input,TRUE,key.second,key.first);
    for(auto it=keys.rbegin();it!=keys.rend();++it)
        freerdp_input_send_keyboard_event_ex(a.rdp->context->input,FALSE,it->second,it->first);
}

void sendShortcut(App& a,int index) {
    switch(index) {
        case 0: sendChord(a,{{0x1d,false},{0x2e,false}}); break; // Ctrl+C
        case 1: sendChord(a,{{0x1d,false},{0x2f,false}}); break; // Ctrl+V
        case 2: sendChord(a,{{0x1d,false},{0x2d,false}}); break; // Ctrl+X
        case 3: sendChord(a,{{0x1d,false},{0x1e,false}}); break; // Ctrl+A
        case 4: sendChord(a,{{0x38,false},{0x0f,false}}); break; // Alt+Tab
        case 5: sendChord(a,{{0x1d,false},{0x38,false},{0x4f,true}}); break; // Ctrl+Alt+End -> remote Ctrl+Alt+Del
        case 6: sendChord(a,{{0x5b,true}}); break; // Windows
        case 7: sendChord(a,{{0x01,false}}); break; // Escape
        case 8: sendChord(a,{{0x0f,false}}); break; // Tab
    }
}

void sendUnicode(App& a,uint16_t ch) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    freerdp_input_send_unicode_keyboard_event(a.rdp->context->input,0,static_cast<UINT16>(ch));
    freerdp_input_send_unicode_keyboard_event(a.rdp->context->input,KBD_FLAGS_RELEASE,static_cast<UINT16>(ch));
}

char keyAt(int x,int y) {
    const int top=1050,gap=8,kh=145;
    const std::vector<std::string> rows={"1234567890.-","QWERTYUIOP@","ASDFGHJKL","ZXCVBNM"};
    for(size_t r=0;r<rows.size();++r) {
        int n=rows[r].size(),margin=(r==3?120:30),kw=(W-2*margin-(n-1)*gap)/n;
        if(y>=top+int(r)*(kh+gap)&&y<top+int(r)*(kh+gap)+kh) {
            int i=(x-margin)/(kw+gap); if(x>=margin&&i>=0&&i<n&&x<margin+i*(kw+gap)+kw) return rows[r][i];
        }
    }
    return 0;
}

void editChar(App& a,char ch) {
    auto& v=activeField(a);
    if(ch=='\b') { if(!v.empty()) v.pop_back(); }
    else if(ch && v.size()<60) v.push_back(a.shift?static_cast<char>(std::toupper(ch)):static_cast<char>(std::tolower(ch)));
}

void processLoginTouch(App& a,int x,int y) {
    if(x>=CLOSE_X&&y>=ACTION_Y&&y<ACTION_Y+ACTION_H) { a.running=false; return; }
    if(x>=870&&y>=900&&y<1020) {
        if(a.profile.host.empty()||a.profile.user.empty()) a.status="SERVER AND USERNAME ARE REQUIRED";
        else { saveProfile(a.profile); a.mode=Mode::Connecting; a.status="CONNECTING..."; drawLogin(a); return; }
    } else if(y>=355&&y<470) a.field=0;
    else if(y>=575&&y<690) a.field=1;
    else if(y>=795&&y<900) a.field=2;
    drawLogin(a);
}

void redrawZoomedView(App& a);

void processRemoteTouch(App& a,int x,int y) {
    if(y<BAR_H) {
        if(x>=CLOSE_X) a.running=false;
        else if(x>=SHORTCUTS_X&&x<SHORTCUTS_X+SHORTCUTS_W) {
            a.shortcutsOpen=!a.shortcutsOpen;
            if(a.shortcutsOpen) drawShortcuts(a); else redrawZoomedView(a);
        }
        return;
    }
    if(a.shortcutsOpen) {
        constexpr int left=70, top=330, gap=22, bw=406, bh=145;
        if(y>=900&&y<1025&&x>=440&&x<964) {
            a.shortcutsOpen=false; redrawZoomedView(a); return;
        }
        for(int i=0;i<9;++i) {
            const int col=i%3,row=i/3;
            const int bx=left+col*(bw+gap),by=top+row*(bh+gap);
            if(x>=bx&&x<bx+bw&&y>=by&&y<by+bh) {
                sendShortcut(a,i);
                a.shortcutsOpen=false;
                redrawZoomedView(a);
                return;
            }
        }
        return;
    }
    int rx=std::clamp<int>(a.viewX+x/a.zoom,0,W-1);
    int ry=std::clamp<int>(a.viewY+(y-BAR_H)/a.zoom,0,RDP_H-1);
    freerdp_input_send_mouse_event(a.rdp->context->input,PTR_FLAGS_MOVE|PTR_FLAGS_DOWN|PTR_FLAGS_BUTTON1,rx,ry);
    freerdp_input_send_mouse_event(a.rdp->context->input,PTR_FLAGS_BUTTON1,rx,ry);
}

void redrawZoomedView(App& a) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->gdi) return;
    const float maxX=std::max(0.0f,float(W)-W/a.zoom);
    const float maxY=std::max(0.0f,float(RDP_H)-RDP_H/a.zoom);
    a.viewX=std::clamp(a.viewX,0.0f,maxX); a.viewY=std::clamp(a.viewY,0.0f,maxY);
    a.dirty=true;
    a.dirtyX1=std::max(0,int(std::floor(a.viewX)));
    a.dirtyY1=std::max(0,int(std::floor(a.viewY)));
    a.dirtyX2=std::min(W,int(std::ceil(a.viewX+W/a.zoom)));
    a.dirtyY2=std::min(RDP_H,int(std::ceil(a.viewY+RDP_H/a.zoom)));
    flushRemoteFrame(a,true);
    a.status="CONNECTED  "+std::to_string(int(std::lround(a.zoom*100)))+"%";
    drawBar(a);
}

void remoteMouse(App& a,UINT16 flags,int x,int y) {
    const int rx=std::clamp<int>(a.viewX+x/a.zoom,0,W-1);
    const int ry=std::clamp<int>(a.viewY+(y-BAR_H)/a.zoom,0,RDP_H-1);
    freerdp_input_send_mouse_event(a.rdp->context->input,flags,rx,ry);
}

void releaseRemoteMouse(App& a,int x,int y) {
    if(!a.mouseDown) return;
    remoteMouse(a,PTR_FLAGS_MOVE,x,y);
    remoteMouse(a,PTR_FLAGS_BUTTON1,x,y);
    a.mouseDown=false;
    a.mouseTouchId=-1;
    a.cleanRefreshPending=true;
    a.cleanRefreshDue=std::chrono::steady_clock::now()+std::chrono::milliseconds(1100);
}

void processTouchPacket(App& a,const qtfb::UserInputContents& u) {
    const bool press=u.inputType==INPUT_TOUCH_PRESS;
    const bool move=u.inputType==INPUT_TOUCH_UPDATE;
    const bool release=u.inputType==INPUT_TOUCH_RELEASE;
    if(!press&&!move&&!release) return;

    if(press || move) a.touches[u.devId]={float(u.x),float(u.y)};
    if(press && a.touches.size()==1 && u.y>=BAR_H && !a.shortcutsOpen
       && a.zoom<=1.001f && a.mouseTouchId<0 && !a.gestureConsumed) {
        a.mouseTouchId=u.devId;
        a.mouseStartX=float(u.x);
        a.mouseStartY=float(u.y);
        a.mouseLastX=u.x;
        a.mouseLastY=u.y;
        a.lastMouseMove=std::chrono::steady_clock::now();
    }
    if(move && a.mouseTouchId==u.devId && a.touches.size()==1) {
        const float dx=float(u.x)-a.mouseStartX,dy=float(u.y)-a.mouseStartY;
        const auto now=std::chrono::steady_clock::now();
        if(!a.mouseDown && dx*dx+dy*dy>64.0f) {
            remoteMouse(a,PTR_FLAGS_MOVE|PTR_FLAGS_DOWN|PTR_FLAGS_BUTTON1,
                        int(a.mouseStartX),int(a.mouseStartY));
            a.mouseDown=true;
            a.lastMouseMove=now-std::chrono::milliseconds(55);
        }
        if(a.mouseDown && now-a.lastMouseMove>=std::chrono::milliseconds(55)) {
            remoteMouse(a,PTR_FLAGS_MOVE,u.x,u.y);
            a.mouseLastX=u.x;
            a.mouseLastY=u.y;
            a.lastMouseMove=now;
        }
    }
    if(press && a.touches.size()==1 && u.y>=BAR_H && a.zoom>1.001f) {
        a.panCandidate=true;
        a.panActive=false;
        a.panId=u.devId;
        a.panStartX=float(u.x);
        a.panStartY=float(u.y);
        a.panStartViewX=a.viewX;
        a.panStartViewY=a.viewY;
    }
    if(press && a.touches.size()==2) {
        if(a.mouseDown) releaseRemoteMouse(a,a.mouseLastX,a.mouseLastY);
        a.mouseTouchId=-1;
        a.panCandidate=false;
        a.panActive=false;
        a.panId=-1;
        auto it=a.touches.begin(); auto p1=it++->second; auto p2=it->second;
        if(p1.second>=BAR_H && p2.second>=BAR_H) {
            const float dx=p2.first-p1.first,dy=p2.second-p1.second;
            a.pinchDistance=std::max(20.0f,std::sqrt(dx*dx+dy*dy));
            a.pinchStartZoom=a.zoom;
            const float cx=(p1.first+p2.first)*0.5f,cy=(p1.second+p2.second)*0.5f-BAR_H;
            a.pinchAnchorX=a.viewX+cx/a.zoom; a.pinchAnchorY=a.viewY+cy/a.zoom;
            a.pinchActive=true; a.gestureConsumed=true;
        }
    }
    if(move && !a.pinchActive && a.panCandidate && a.panId==u.devId && a.touches.size()==1) {
        const float dx=float(u.x)-a.panStartX,dy=float(u.y)-a.panStartY;
        if(!a.panActive && dx*dx+dy*dy>18.0f*18.0f) {
            a.panActive=true;
            a.gestureConsumed=true;
        }
        if(a.panActive) {
            a.viewX=a.panStartViewX-dx/a.zoom;
            a.viewY=a.panStartViewY-dy/a.zoom;
            a.viewX=std::clamp(a.viewX,0.0f,std::max(0.0f,float(W)-W/a.zoom));
            a.viewY=std::clamp(a.viewY,0.0f,std::max(0.0f,float(RDP_H)-RDP_H/a.zoom));
            // Do not publish intermediate pan frames.  A single coherent
            // frame is drawn on release below; live 320 ms redraws overflowed
            // the e-ink queue and produced duplicated/torn desktop halves.
        }
    }
    if((move||release) && a.pinchActive && a.touches.size()>=2) {
        if(move) a.touches[u.devId]={float(u.x),float(u.y)};
        auto it=a.touches.begin(); auto p1=it++->second; auto p2=it->second;
        const float dx=p2.first-p1.first,dy=p2.second-p1.second;
        const float dist=std::max(20.0f,std::sqrt(dx*dx+dy*dy));
        a.zoom=std::clamp(a.pinchStartZoom*dist/a.pinchDistance,1.0f,3.0f);
        const float cx=(p1.first+p2.first)*0.5f,cy=(p1.second+p2.second)*0.5f-BAR_H;
        a.viewX=a.pinchAnchorX-cx/a.zoom; a.viewY=a.pinchAnchorY-cy/a.zoom;
        a.viewX=std::clamp(a.viewX,0.0f,std::max(0.0f,float(W)-W/a.zoom));
        a.viewY=std::clamp(a.viewY,0.0f,std::max(0.0f,float(RDP_H)-RDP_H/a.zoom));
    }
    if(release) {
        const bool wasGesture=a.gestureConsumed;
        const bool finishPan=a.panActive && a.panId==u.devId;
        const bool finishMouse=a.mouseTouchId==u.devId;
        if(finishMouse) {
            if(a.mouseDown) releaseRemoteMouse(a,u.x,u.y);
            else { processRemoteTouch(a,u.x,u.y); a.mouseTouchId=-1; }
        }
        if(a.panId==u.devId) {
            a.panCandidate=false;
            a.panActive=false;
            a.panId=-1;
        }
        a.touches.erase(u.devId);
        if(a.pinchActive && a.touches.size()<2) { a.pinchActive=false; redrawZoomedView(a); }
        else if(finishPan) redrawZoomedView(a);
        else if(!finishMouse && !wasGesture && !a.gestureConsumed) processRemoteTouch(a,u.x,u.y);
        if(a.touches.empty()) a.gestureConsumed=false;
    }
}

void pollInput(App& a) {
    qtfb::ServerMessage msg{};
    while(a.fb.pollServerPacket(msg)) {
        if(msg.type!=MESSAGE_USERINPUT) continue;
        const auto& u=msg.userInput;
        if(a.mode==Mode::Remote && (u.inputType==INPUT_TOUCH_PRESS || u.inputType==INPUT_TOUCH_UPDATE || u.inputType==INPUT_TOUCH_RELEASE)) {
            processTouchPacket(a,u);
            continue;
        }
        if(u.inputType==INPUT_TOUCH_RELEASE || u.inputType==INPUT_PEN_RELEASE) {
            if(a.mode==Mode::Login) processLoginTouch(a,u.x,u.y);
            else if(a.mode==Mode::Error) {
                if(u.x>=CLOSE_X&&u.y>=ACTION_Y&&u.y<ACTION_Y+ACTION_H) a.running=false;
                else if(u.x<650&&u.y>=330&&u.y<520) {
                    if(a.launchedFromNativeLogin) a.running=false;
                    else {a.mode=Mode::Login;a.status="ENTER CONNECTION DETAILS";drawLogin(a,true);}
                }
            } else if(a.mode==Mode::Remote) processRemoteTouch(a,u.x,u.y);
        } else if(u.inputType==INPUT_BTN_PRESS || u.inputType==INPUT_VKB_PRESS) {
            if(a.mode==Mode::Login) {
                int k=u.x;
                if((k&0xFF000000)==0x02000000) {
                    const int ch=k&0xFFFF;
                    if(ch>=32&&ch<127) editChar(a,static_cast<char>(ch));
                } else if(k==0x01000020) a.shift=true;
                else if(k==0x01000003 || k==0x01000007 || k==8 || k==127) editChar(a,'\b');
                else if(k==0x01000004) { if(a.field<2) ++a.field; }
                else if(k>=32&&k<127) editChar(a,static_cast<char>(k));
                drawLogin(a);
            } else if(a.mode==Mode::Remote) {
                remoteInputKey(a,u.x,true);
            }
        } else if(u.inputType==INPUT_BTN_RELEASE||u.inputType==INPUT_VKB_RELEASE) {
            if(a.mode==Mode::Login && u.x==0x01000020) a.shift=false;
            else if(a.mode==Mode::Remote) remoteInputKey(a,u.x,false);
        }
    }
}

#ifdef PAPERDESK_E2E
void pollAutomation(App& a,int fd,std::string& pending) {
    char chunk[256];
    for(;;) {
        const ssize_t count=::read(fd,chunk,sizeof(chunk));
        if(count>0) pending.append(chunk,static_cast<size_t>(count));
        else break;
    }
    for(;;) {
        const auto end=pending.find('\n');
        if(end==std::string::npos) break;
        const std::string line=pending.substr(0,end);
        pending.erase(0,end+1);
        int x=0,y=0,key=0;
        if(std::sscanf(line.c_str(),"tap %d %d",&x,&y)==2 && a.mode==Mode::Remote)
            processRemoteTouch(a,x,y);
        else if(std::sscanf(line.c_str(),"key %d",&key)==1 && a.mode==Mode::Remote) {
            remoteInputKey(a,key,true);
            remoteInputKey(a,key,false);
        }
    }
}
#endif

bool connectRdp(App& a) {
    freerdp* r=freerdp_new(); if(!r) return false;
    a.rdp=r; r->ContextSize=sizeof(PaperContext); r->ContextNew=contextNew;
    if(!freerdp_context_new(r)) {freerdp_free(r);a.rdp=nullptr;return false;}
    r->PostConnect=postConnect; r->PostDisconnect=postDisconnect;
    r->VerifyCertificateEx=acceptCertificate; r->VerifyChangedCertificateEx=acceptChangedCertificate;
    auto* s=r->context->settings;
    bool ok=true;
    ok &= freerdp_settings_set_string(s,FreeRDP_ServerHostname,a.profile.host.c_str());
    ok &= freerdp_settings_set_uint32(s,FreeRDP_ServerPort,a.profile.port);
    ok &= freerdp_settings_set_string(s,FreeRDP_Username,a.profile.user.c_str());
    ok &= freerdp_settings_set_string(s,FreeRDP_Password,a.profile.password.c_str());
    if(!a.profile.domain.empty()) ok &= freerdp_settings_set_string(s,FreeRDP_Domain,a.profile.domain.c_str());
    ok &= freerdp_settings_set_uint32(s,FreeRDP_DesktopWidth,W);
    ok &= freerdp_settings_set_uint32(s,FreeRDP_DesktopHeight,RDP_H);
    ok &= freerdp_settings_set_uint32(s,FreeRDP_ColorDepth,16);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AutoAcceptCertificate,TRUE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AudioPlayback,FALSE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AudioCapture,FALSE);
    if(!ok || !freerdp_connect(r)) {
        freerdp_context_free(r); freerdp_free(r); a.rdp=nullptr; return false;
    }
    return true;
}

void disconnectRdp(App& a) {
    if(!a.rdp) return;
    freerdp_disconnect(a.rdp);
    freerdp_context_free(a.rdp); freerdp_free(a.rdp); a.rdp=nullptr;
}

void signalHandler(int) { if(g_app) g_app->running=false; }
}

int main(int argc,char** argv) {
    std::signal(SIGTERM,signalHandler); std::signal(SIGINT,signalHandler); std::signal(SIGPIPE,SIG_IGN);
    App app; g_app=&app; loadProfile(app.profile);
#ifdef PAPERDESK_E2E
    int automationFd=-1;
    std::string automationPending;
    if(const char* path=std::getenv("PAPERDESK_TEST_INPUT_FIFO"))
        automationFd=::open(path,O_RDWR|O_NONBLOCK);
#endif
    bool autoConnect=false;
    for(int i=1;i<argc;++i) {
        const std::string arg=argv[i];
        auto takeValue=[&](std::string& out) {
            if(i+1>=argc) return false;
            out=argv[++i];
            autoConnect=true;
            return true;
        };
        if(arg=="--host") takeValue(app.profile.host);
        else if(arg=="--user") takeValue(app.profile.user);
        else if(arg=="--password-hex") {
            std::string encoded;
            if(takeValue(encoded)) hexDecode(encoded,app.profile.password);
        } else if(arg=="--port" && i+1<argc) {
            app.profile.port=std::max(1,std::atoi(argv[++i]));
            autoConnect=true;
        } else if(arg=="--connect") autoConnect=true;
    }
    // The editable login belongs to the native QML front-end.  AppLoad can
    // still expose this external engine as a direct entry, so make that path
    // reuse the saved profile instead of falling back to the framebuffer
    // login and its legacy drawn keyboard.
    if(!autoConnect && !app.profile.host.empty() && !app.profile.user.empty())
        autoConnect=true;
    if(autoConnect) {
        app.launchedFromNativeLogin=true;
        saveProfile(app.profile);
        app.mode=Mode::Connecting;
        app.status="CONNECTING...";
        drawConnecting(app);
    } else {
        app.launchedFromNativeLogin=true;
        drawError(app,"OPEN PAPERDESK AND CHOOSE RDP");
    }
    while(app.running) {
        pollInput(app);
#ifdef PAPERDESK_E2E
        if(automationFd>=0) pollAutomation(app,automationFd,automationPending);
#endif
        if(app.mode==Mode::Connecting) {
            if(!connectRdp(app)) drawError(app,"CONNECTION OR LOGIN ERROR");
        } else if(app.mode==Mode::Remote && app.rdp) {
            if(!freerdp_check_event_handles(app.rdp->context)) {disconnectRdp(app);app.fb.setRefreshMode(REFRESH_MODE_UI);drawError(app,"CONNECTION WAS INTERRUPTED");}
            else { flushRemoteFrame(app); maybeCleanRefresh(app); }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(12));
    }
    disconnectRdp(app);
#ifdef PAPERDESK_E2E
    if(automationFd>=0) ::close(automationFd);
#endif
    if(!app.profile.password.empty()) std::fill(app.profile.password.begin(),app.profile.password.end(),'\0');
    return 0;
}
