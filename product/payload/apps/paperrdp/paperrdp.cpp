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
constexpr int PHYSICAL_W = 1404;
constexpr int PHYSICAL_H = 1872;
// Logical dimensions are selected once, before constructing App. QTFB keeps
// its firmware-compatible portrait surface; only this client's pixels rotate.
int W = PHYSICAL_W;
int H = PHYSICAL_H;
constexpr int BAR_H = 112;
int RDP_H = H - BAR_H;
constexpr int ACTION_H = 68;
constexpr int ACTION_Y = 22;
int CLOSE_X = W - 194;
constexpr int CLOSE_W = 176;
int SHORTCUTS_X = W - 424;
constexpr int SHORTCUTS_W = 216;
// Smaller tiles keep cursor, typing and window-decoration updates local.  The
// old 176 px grid made a one-pixel change rescan more than 30k output pixels.
constexpr int DAMAGE_TILE_W = 88;
constexpr int DAMAGE_TILE_H = 88;
int DAMAGE_COLS = (W + DAMAGE_TILE_W - 1) / DAMAGE_TILE_W;
int DAMAGE_ROWS = (RDP_H + DAMAGE_TILE_H - 1) / DAMAGE_TILE_H;
int DAMAGE_TILE_COUNT = DAMAGE_COLS * DAMAGE_ROWS;
constexpr int SPARSE_FRAME_MIN_GAP_MS = 80;
constexpr int SPARSE_FRAME_QUIET_MS = 35;
constexpr int SPARSE_FRAME_MAX_LATENCY_MS = 160;
constexpr int DENSE_FRAME_MIN_GAP_MS = 700;
constexpr int DENSE_FRAME_QUIET_MS = 100;
constexpr int DENSE_FRAME_MAX_LATENCY_MS = 900;
constexpr int CLEAN_REFRESH_IDLE_MS = 4500;
constexpr int CLEAN_REFRESH_MIN_GAP_MS = 15000;

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
    int scalePercent = 100;
    int colorDepth = 16;
    bool landscape = false;
};

void configureOrientation(bool landscape) {
    W = landscape ? PHYSICAL_H : PHYSICAL_W;
    H = landscape ? PHYSICAL_W : PHYSICAL_H;
    RDP_H = H - BAR_H;
    CLOSE_X = W - 194;
    SHORTCUTS_X = W - 424;
    DAMAGE_COLS = (W + DAMAGE_TILE_W - 1) / DAMAGE_TILE_W;
    DAMAGE_ROWS = (RDP_H + DAMAGE_TILE_H - 1) / DAMAGE_TILE_H;
    DAMAGE_TILE_COUNT = DAMAGE_COLS * DAMAGE_ROWS;
}

struct ScreenRect { int x, y, w, h; };

ScreenRect physicalRect(bool landscape, ScreenRect r) {
    return landscape ? ScreenRect{PHYSICAL_W-r.y-r.h, r.x, r.h, r.w} : r;
}

std::pair<float,float> logicalPoint(bool landscape, float x, float y) {
    return landscape ? std::make_pair(y, PHYSICAL_W-1-x) : std::make_pair(x,y);
}

// Iterate physical rows for cache-friendly QTFB writes. Only damaged rectangles
// are transposed, not the complete desktop on each cursor/typing update.
void rotateRect(const uint16_t* source, uint16_t* target, ScreenRect logical) {
    const ScreenRect p=physicalRect(true,logical);
    for(int py=p.y; py<p.y+p.h; ++py)
        for(int px=p.x; px<p.x+p.w; ++px)
            target[py*PHYSICAL_W+px]=source[(PHYSICAL_W-1-px)*PHYSICAL_H+py];
}

Profile profileForStorage(const Profile& session, bool rememberPassword) {
    Profile stored=session;
    if(!rememberPassword) stored.password.clear();
    return stored;
}

#ifdef PAPERDESK_RDP_TESTING
// Memory-only framebuffer: regression tests never contact AppLoad or a device.
struct TestFramebuffer {
    std::vector<unsigned char> storage=std::vector<unsigned char>(PHYSICAL_W*PHYSICAL_H*2);
    unsigned char* shm=storage.data();
    size_t shmSize=storage.size();
    int updates=0, fullRefreshes=0;
    void setRefreshMode(int) {}
    void sendPartialUpdate(int,int,int,int) { ++updates; }
    void sendCompleteUpdate() { ++updates; }
    void requestFullRefresh() { ++fullRefreshes; }
    bool pollServerPacket(qtfb::ServerMessage&) { return false; }
};
#endif

enum class TwoFingerMode { None, Pending, Scroll, Pinch };

struct App {
#ifdef PAPERDESK_RDP_TESTING
    TestFramebuffer fb;
#else
    qtfb::ClientConnection fb;
#endif
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
    bool pendingTap = false;
    int pendingTapX = 0;
    int pendingTapY = 0;
    std::chrono::steady_clock::time_point pendingTapSince = std::chrono::steady_clock::now();
    int doubleTapTouchId = -1;
    bool doubleClickSecondPending = false;
    int doubleClickX = 0;
    int doubleClickY = 0;
    std::chrono::steady_clock::time_point doubleClickSecondDue =
        std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point mousePressSince = std::chrono::steady_clock::now();
    bool rightClickSent = false;
    int viewportHeight = RDP_H;
    float zoom = 1.0f;
    float viewX = 0.0f;
    float viewY = 0.0f;
    std::map<int,std::pair<float,float>> touches;
    bool pinchActive = false;
    TwoFingerMode twoFingerMode = TwoFingerMode::None;
    float gestureStartCx=0, gestureStartCy=0, gestureLastCy=0;
    float wheelRemainder=0;
    int pendingWheel=0;
    bool gestureViewChanged=false;
    bool gestureSamplePending=false;
    std::chrono::steady_clock::time_point gestureSampleDue=std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point lastWheel=std::chrono::steady_clock::now();
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
    std::vector<uint8_t> dirtyTiles = std::vector<uint8_t>(DAMAGE_TILE_COUNT,0);
    std::vector<uint16_t> landscapePixels;
    int dirtyTileCount = 0;
    std::chrono::steady_clock::time_point lastFrame = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point dirtySince = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point lastDirty = std::chrono::steady_clock::now();
    bool cleanRefreshPending = false;
    std::chrono::steady_clock::time_point cleanRefreshDue = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point lastCleanRefresh =
        std::chrono::steady_clock::now() - std::chrono::seconds(20);
    std::string status = "ENTER CONNECTION DETAILS";
    bool launchedFromNativeLogin = false;
    bool rememberPassword = true;
    bool certificateChanged = false;
    freerdp* rdp = nullptr;

    explicit App(const Profile& selected) :
#ifndef PAPERDESK_RDP_TESTING
        fb(qtfb::getIDFromAppload(), FBFMT_RM2FB),
#endif
        profile(selected) {
        fb.setRefreshMode(REFRESH_MODE_UI);
        std::memset(fb.shm, 0xff, fb.shmSize);
        if(profile.landscape) landscapePixels.assign(PHYSICAL_W*PHYSICAL_H,0xffff);
    }

    uint16_t* pixels() {
        return profile.landscape ? landscapePixels.data() : reinterpret_cast<uint16_t*>(fb.shm);
    }
    void update(int x,int y,int w,int h) {
        x=std::clamp(x,0,W); y=std::clamp(y,0,H);
        w=std::clamp(w,0,W-x); h=std::clamp(h,0,H-y);
        if(w==0 || h==0) return;
        const ScreenRect logical{x,y,w,h};
        if(profile.landscape) rotateRect(pixels(),reinterpret_cast<uint16_t*>(fb.shm),logical);
        const ScreenRect p=physicalRect(profile.landscape,logical);
        fb.sendPartialUpdate(p.x,p.y,p.w,p.h);
    }
    void publish() {
        if(profile.landscape) rotateRect(pixels(),reinterpret_cast<uint16_t*>(fb.shm),{0,0,W,H});
        fb.sendCompleteUpdate();
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
    auto* p = a.pixels();
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
    auto* p = a.pixels();
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
        a.publish();
        a.fb.requestFullRefresh();
    } else a.update(0,250,W,940);
}

void drawConnecting(App& a) {
    fill(a,0,0,W,H,255);
    headerTitle(a,"CONNECTING...");
    button(a,CLOSE_X,ACTION_Y,CLOSE_W,ACTION_H,"CLOSE");
    text(a,72,210,"CONNECTING TO REMOTE COMPUTER...",5,0);
    text(a,72,300,a.profile.host,4,70);
    text(a,72,390,"PLEASE WAIT",4,70);
    a.publish();
    a.fb.requestFullRefresh();
}

void drawBar(App& a) {
    headerTitle(a,a.status);
    button(a,SHORTCUTS_X,ACTION_Y,SHORTCUTS_W,ACTION_H,"SHORTCUTS");
    button(a,CLOSE_X,ACTION_Y,CLOSE_W,ACTION_H,"CLOSE");
    a.update(0,0,W,BAR_H);
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
    a.update(0,BAR_H,W,RDP_H);
}

bool canRetry(const App& a) {
    return a.mode==Mode::Error && !a.certificateChanged &&
           !a.profile.host.empty() && !a.profile.user.empty();
}
bool requestRetry(App& a);
void drawError(App& a, const std::string& message) {
    a.mode=Mode::Error; a.status=message;
    fill(a,0,0,W,H,255);
    headerTitle(a,"CONNECTION FAILED");
    button(a,CLOSE_X,ACTION_Y,CLOSE_W,ACTION_H,"CLOSE");
    text(a,70,190,"CONNECTION FAILED",6);
    text(a,70,235,message,4,80);
    if(canRetry(a)) button(a,70,360,520,120,"RETRY",true);
    button(a,650,360,520,120,"CLOSE");
    a.publish();
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

int normalizeScalePercent(int value) {
    if(value==50 || value==75 || value==100) return value;
    return 100;
}

int normalizeColorDepth(int value) {
    if(value==8 || value==16 || value==24) return value;
    return 16;
}

bool parsePort(const std::string& value,int& port) {
    if(value.empty() || value.size()>5) return false;
    char* end=nullptr;
    errno=0;
    const long parsed=std::strtol(value.c_str(),&end,10);
    if(errno!=0 || !end || *end!='\0' || parsed<1 || parsed>65535) return false;
    port=static_cast<int>(parsed);
    return true;
}

bool sameProfile(const Profile& a,const Profile& b) {
    return a.host==b.host && a.user==b.user && a.domain==b.domain && a.port==b.port;
}

std::string profileListLine(const Profile& p) {
    return "v2\t"+hexEncode(p.host)+"\t"+hexEncode(p.user)+"\t"+hexEncode(p.domain)+"\t"+
           std::to_string(p.port)+"\t"+hexEncode(p.password)+"\t"+
           std::to_string(normalizeScalePercent(p.scalePercent))+"\t"+
           std::to_string(normalizeColorDepth(p.colorDepth))+"\t"+
           (p.landscape ? "landscape" : "portrait")+"\n";
}

bool parseProfileListLine(const std::string& line,Profile& profile) {
    if(line.size()>8192) return false;
    std::vector<std::string> parts;
    size_t begin=0;
    while(begin<=line.size()) {
        const size_t end=line.find('\t',begin);
        parts.push_back(line.substr(begin,end==std::string::npos ? std::string::npos : end-begin));
        if(end==std::string::npos) break;
        begin=end+1;
    }
    const bool legacy=parts.size()==8 && parts[0]=="v1";
    if(!legacy && !(parts.size()==9 && parts[0]=="v2")) return false;
    if(!legacy && parts[8]!="portrait" && parts[8]!="landscape") return false;
    for(size_t i=1;i<=5;++i) if(parts[i].size()>4096) return false;
    Profile parsed;
    if(!hexDecode(parts[1],parsed.host) || !hexDecode(parts[2],parsed.user) ||
       !hexDecode(parts[3],parsed.domain) || !hexDecode(parts[5],parsed.password)) return false;
    if(!parsePort(parts[4],parsed.port)) return false;
    parsed.scalePercent=normalizeScalePercent(std::atoi(parts[6].c_str()));
    parsed.colorDepth=normalizeColorDepth(std::atoi(parts[7].c_str()));
    parsed.landscape=!legacy && parts[8]=="landscape";
    if(parsed.host.empty() || parsed.user.empty()) return false;
    profile=std::move(parsed);
    return true;
}

bool writePrivateFile(const char* path,const char* temp,const std::string& data) {
    const int fd=::open(temp,O_WRONLY|O_CREAT|O_TRUNC,0600);
    if(fd<0) return false;
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

const std::string& profileDirectory() {
    static const std::string directory=[] {
#ifdef PAPERDESK_E2E
        if(const char* test=std::getenv("PAPERDESK_TEST_RDP_CONFIG_DIR")) {
            struct stat st{};
            if(test[0]!='/' || ::lstat(test,&st)<0 || !S_ISDIR(st.st_mode) ||
               st.st_uid!=::getuid() || (st.st_mode&0777)!=0700) {
                std::fputs("Invalid private RDP test profile directory\n",stderr);
                std::abort();
            }
            return std::string(test);
        }
#endif
        return std::string("/home/root/.config/paperrdp");
    }();
    return directory;
}

bool saveProfile(const Profile& p) {
    const std::string& directory=profileDirectory();
    const std::string profilePath=directory+"/profile", profileTemp=directory+"/profile.tmp";
    const char *dir=directory.c_str(),*path=profilePath.c_str(),*temp=profileTemp.c_str();
    if(directory=="/home/root/.config/paperrdp" &&
       ::mkdir("/home/root/.config",0700)<0 && errno!=EEXIST) return false;
    if(::mkdir(dir,0700)<0 && errno!=EEXIST) return false;
    ::chmod(dir,0700);
    const std::string data="host="+p.host+"\nuser="+p.user+"\ndomain="+p.domain+
                           "\nport="+std::to_string(p.port)+"\npassword_hex="+hexEncode(p.password)+
                           "\nscale_percent="+std::to_string(normalizeScalePercent(p.scalePercent))+
                           "\ncolor_depth="+std::to_string(normalizeColorDepth(p.colorDepth))+
                           "\norientation="+(p.landscape ? "landscape" : "portrait")+"\n";
    // Explicit GUI Save/Delete is the only writer of the saved profile list.
    // Connecting updates only the legacy last-connection record.
    return writePrivateFile(path,temp,data);
}

void loadProfile(Profile& p) {
    std::ifstream f(profileDirectory()+"/profile");
    std::string line;
    while(std::getline(f,line)) {
        auto pos=line.find('='); if(pos==std::string::npos) continue;
        auto k=line.substr(0,pos), v=line.substr(pos+1);
        if(k=="host") p.host=v; else if(k=="user") p.user=v; else if(k=="domain") p.domain=v;
        else if(k=="port") { int port=0; if(parsePort(v,port)) p.port=port; }
        else if(k=="password_hex") hexDecode(v,p.password);
        else if(k=="scale_percent") p.scalePercent=normalizeScalePercent(std::atoi(v.c_str()));
        else if(k=="color_depth") p.colorDepth=normalizeColorDepth(std::atoi(v.c_str()));
        else if(k=="orientation") p.landscape=v=="landscape";
    }
}

// The same transform drives raster damage, sampling and pointer hit testing.
// Keyboard space reduces the viewport, never the server desktop dimensions.
struct ViewTransform {
    float scale, offsetX, offsetY, maxX, maxY;
    int remoteWidth, remoteHeight, viewportWidth, viewportHeight;
    bool contains(float x,float y) const {
        return x>=offsetX && y>=offsetY && x<viewportWidth && y<viewportHeight &&
               x<offsetX+remoteWidth*scale && y<offsetY+remoteHeight*scale;
    }
};

ViewTransform makeTransform(int rw,int rh,int width,int height,float zoom) {
    rw=std::max(1,rw); rh=std::max(1,rh);
    const float scale=std::min(float(width)/rw,float(height)/rh)*zoom;
    return {scale,std::max(0.0f,(width-rw*scale)/2),
            std::max(0.0f,(height-rh*scale)/2),
            std::max(0.0f,rw-width/scale),std::max(0.0f,rh-height/scale),
            rw,rh,width,height};
}

ViewTransform viewTransform(const App& a) {
    const auto* gdi=a.rdp && a.rdp->context ? a.rdp->context->gdi : nullptr;
    return makeTransform(gdi ? gdi->width : W,gdi ? gdi->height : RDP_H,
                         W,a.viewportHeight,a.zoom);
}
float outputScaleX(const App& a) { return viewTransform(a).scale; }
float outputScaleY(const App& a) { return viewTransform(a).scale; }
float maxViewX(const App& a) { return viewTransform(a).maxX; }
float maxViewY(const App& a) { return viewTransform(a).maxY; }
bool remotePoint(const App& a,float x,float y) {
    return viewTransform(a).contains(x,y-BAR_H);
}
int remoteX(const App& a,int x) {
    const auto t=viewTransform(a);
    return std::clamp<int>(a.viewX+(x-t.offsetX)/t.scale,0,t.remoteWidth-1);
}
int remoteY(const App& a,int y) {
    const auto t=viewTransform(a);
    return std::clamp<int>(a.viewY+(y-BAR_H-t.offsetY)/t.scale,0,t.remoteHeight-1);
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

    auto addDirty=[&a,gdi](int x,int y,int w,int h) {
        if(w<=0 || h<=0) return;
        x=std::clamp(x,0,gdi->width); y=std::clamp(y,0,gdi->height);
        int x2=std::clamp(x+w,0,gdi->width), y2=std::clamp(y+h,0,gdi->height);
        if(x2<=x || y2<=y) return;
        const auto transform=viewTransform(a);
        const float scaleX=transform.scale,scaleY=transform.scale;
        const int dx1=std::clamp<int>(std::floor(transform.offsetX+(x-a.viewX)*scaleX),0,W);
        const int dy1=std::clamp<int>(std::floor(transform.offsetY+(y-a.viewY)*scaleY),0,a.viewportHeight);
        const int dx2=std::clamp<int>(std::ceil(transform.offsetX+(x2-a.viewX)*scaleX),dx1,W);
        const int dy2=std::clamp<int>(std::ceil(transform.offsetY+(y2-a.viewY)*scaleY),dy1,a.viewportHeight);
        if(dx2<=dx1 || dy2<=dy1) return;
        const auto now=std::chrono::steady_clock::now();
        if(!a.dirty) a.dirtySince=now;
        a.lastDirty=now;
        a.dirtyX1=std::min(a.dirtyX1,x); a.dirtyY1=std::min(a.dirtyY1,y);
        a.dirtyX2=std::max(a.dirtyX2,x2); a.dirtyY2=std::max(a.dirtyY2,y2);
        const int firstCol=dx1/DAMAGE_TILE_W;
        const int lastCol=(dx2-1)/DAMAGE_TILE_W;
        const int firstRow=dy1/DAMAGE_TILE_H;
        const int lastRow=(dy2-1)/DAMAGE_TILE_H;
        for(int row=firstRow;row<=lastRow;++row) {
            for(int col=firstCol;col<=lastCol;++col) {
                const int tile=row*DAMAGE_COLS+col;
                if(!a.dirtyTiles[tile]) {
                    a.dirtyTiles[tile]=1;
                    ++a.dirtyTileCount;
                }
            }
        }
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
        // Dense desktop changes still need a little more breathing room than
        // cursor/text updates, but multi-second gaps make the session feel
        // frozen. One dense QTFB transaction plus a short debounce keeps the
        // frame coherent without building a stale queue.
        const bool largeFrame=a.dirtyTileCount>DAMAGE_TILE_COUNT/3;
        const auto minFrameGap=std::chrono::milliseconds(
            largeFrame ? DENSE_FRAME_MIN_GAP_MS : SPARSE_FRAME_MIN_GAP_MS);
        const auto quietPeriod=std::chrono::milliseconds(
            largeFrame ? DENSE_FRAME_QUIET_MS : SPARSE_FRAME_QUIET_MS);
        const auto maxLatency=std::chrono::milliseconds(
            largeFrame ? DENSE_FRAME_MAX_LATENCY_MS : SPARSE_FRAME_MAX_LATENCY_MS);
        if(now-a.lastFrame<minFrameGap) return;
        const bool burstSettled=now-a.lastDirty>=quietPeriod;
        const bool maxLatencyReached=now-a.dirtySince>=maxLatency;
        if(!burstSettled && !maxLatencyReached) return;
    }
    auto* gdi=a.rdp->context->gdi;
    if(!gdi->primary_buffer) return;
    const float vx=a.viewX, vy=a.viewY;
    const auto transform=viewTransform(a);
    const float scaleX=transform.scale,scaleY=transform.scale;
    // Mapping output coordinates to the FreeRDP surface used to perform two
    // floating-point divisions and clamps for every one of the 2.47 million
    // output pixels. The mapping is constant for a frame, so calculate it
    // once and keep the hot tile loop integer-only.
    std::vector<int> sourceX(W);
    std::vector<int> sourceY(a.viewportHeight);
    for(int dx=0;dx<W;++dx)
        sourceX[dx]=(dx<transform.offsetX || dx>=transform.offsetX+gdi->width*scaleX) ? -1 :
            std::clamp<int>(vx+(dx-transform.offsetX)/scaleX,0,gdi->width-1);
    for(int dy=0;dy<a.viewportHeight;++dy)
        sourceY[dy]=(dy<transform.offsetY || dy>=transform.offsetY+gdi->height*scaleY) ? -1 :
            std::clamp<int>(vy+(dy-transform.offsetY)/scaleY,0,gdi->height-1);
    auto* dst=a.pixels();
    struct ChangedRow { int x1=W,y1=RDP_H,x2=0,y2=0; bool changed=false; };
    std::vector<ChangedRow> changedRows(DAMAGE_ROWS);
    int changedTileCount=0;
    for(int tile=0;tile<DAMAGE_TILE_COUNT;++tile) {
        if(!a.dirtyTiles[tile]) continue;
        const int tileRow=tile/DAMAGE_COLS;
        const int tileCol=tile%DAMAGE_COLS;
        const int tx1=tileCol*DAMAGE_TILE_W;
        const int ty1=tileRow*DAMAGE_TILE_H;
        const int tx2=std::min(W,tx1+DAMAGE_TILE_W);
        const int ty2=std::min(a.viewportHeight,ty1+DAMAGE_TILE_H);
        int changedX1=W,changedY1=RDP_H,changedX2=0,changedY2=0;
        for(int dy=ty1;dy<ty2;++dy) {
            const int sy=sourceY[dy];
            uint16_t* out=dst+(dy+BAR_H)*W+tx1;
            for(int dx=tx1;dx<tx2;++dx,++out) {
                const int sx=sourceX[dx];
                uint16_t pixel=0xffff;
                if(sx>=0 && sy>=0) {
                    const uint8_t* src=gdi->primary_buffer+sy*gdi->stride+sx*4;
                    pixel=gray565(static_cast<uint8_t>((77*src[2]+150*src[1]+29*src[0])>>8));
                }
                if(*out!=pixel) {
                    *out=pixel;
                    changedX1=std::min(changedX1,dx); changedY1=std::min(changedY1,dy);
                    changedX2=std::max(changedX2,dx+1); changedY2=std::max(changedY2,dy+1);
                }
            }
        }
        if(changedX2>changedX1 && changedY2>changedY1) {
            auto& row=changedRows[tileRow];
            row.changed=true;
            row.x1=std::min(row.x1,changedX1); row.y1=std::min(row.y1,changedY1);
            row.x2=std::max(row.x2,changedX2); row.y2=std::max(row.y2,changedY2);
            ++changedTileCount;
        }
    }
    if(changedTileCount>DAMAGE_TILE_COUNT/3) {
        // Keep a dense desktop frame atomic, but do not refresh the unchanged
        // toolbar. This is a materially smaller e-ink transaction than the
        // former complete-screen update.
        a.update(0,BAR_H,W,a.viewportHeight);
    } else {
        // Sparse, distant changes stay sparse instead of becoming one giant
        // bounding rectangle. Pairing adjacent rows keeps the QTFB message
        // count bounded even with the finer damage grid.
        for(int row=0;row<DAMAGE_ROWS;) {
            if(!changedRows[row].changed) { ++row; continue; }
            ChangedRow merged=changedRows[row];
            int next=row+1;
            while(next<DAMAGE_ROWS && changedRows[next].changed && next-row<2) {
                merged.x1=std::min(merged.x1,changedRows[next].x1);
                merged.y1=std::min(merged.y1,changedRows[next].y1);
                merged.x2=std::max(merged.x2,changedRows[next].x2);
                merged.y2=std::max(merged.y2,changedRows[next].y2);
                ++next;
            }
            a.update(merged.x1,merged.y1+BAR_H,
                                   merged.x2-merged.x1,merged.y2-merged.y1);
            row=next;
        }
    }
    a.dirty=false; a.dirtyX1=W; a.dirtyY1=RDP_H; a.dirtyX2=0; a.dirtyY2=0;
    std::fill(a.dirtyTiles.begin(),a.dirtyTiles.end(),0); a.dirtyTileCount=0;
    a.lastFrame=now;
}

void maybeCleanRefresh(App& a) {
    const auto now=std::chrono::steady_clock::now();
    if(!a.cleanRefreshPending || a.mouseDown || !a.touches.empty() || a.dirty || now<a.cleanRefreshDue) return;
    // Full black/white cleanup is intentionally an idle-time maintenance
    // operation. Requiring real input silence and rate-limiting it prevents
    // the three-second flashing/freeze cycle seen during active sessions.
    if(now-a.lastDirty<std::chrono::milliseconds(CLEAN_REFRESH_IDLE_MS)) return;
    if(now-a.lastCleanRefresh<std::chrono::milliseconds(CLEAN_REFRESH_MIN_GAP_MS)) return;
    // UPDATE_ALL publishes the complete current framebuffer.  The explicit
    // refresh then clears e-ink ghosting left by the fast partial waveform.
    a.publish();
    a.fb.requestFullRefresh();
    a.cleanRefreshPending=false;
    a.lastCleanRefresh=now;
}

BOOL resizeDesktop(rdpContext* c) {
    if(!gdi_resize(c->gdi, freerdp_settings_get_uint32(c->settings,FreeRDP_DesktopWidth),
                   freerdp_settings_get_uint32(c->settings,FreeRDP_DesktopHeight))) return FALSE;
    auto* pc=reinterpret_cast<PaperContext*>(c);
    App& a=*pc->app;
    a.viewX=std::clamp(a.viewX,0.0f,maxViewX(a));
    a.viewY=std::clamp(a.viewY,0.0f,maxViewY(a));
    a.dirty=true;
    std::fill(a.dirtyTiles.begin(),a.dirtyTiles.end(),1);
    a.dirtyTileCount=DAMAGE_TILE_COUNT;
    a.dirtySince=a.lastDirty=std::chrono::steady_clock::now();
    return TRUE;
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
    a.publish();
    a.fb.requestFullRefresh();
    a.lastCleanRefresh=std::chrono::steady_clock::now();
    a.fb.setRefreshMode(REFRESH_MODE_UFAST);
    a.cleanRefreshPending=true;
    a.cleanRefreshDue=a.lastCleanRefresh+std::chrono::milliseconds(CLEAN_REFRESH_IDLE_MS);
    return TRUE;
}

void postDisconnect(freerdp* instance) { if(instance) gdi_free(instance); }
// Trust on first use: FreeRDP persists a new certificate (return 1), but a
// changed identity must never be accepted silently (return 0).
DWORD acceptCertificate(freerdp*,const char*,UINT16,const char*,const char*,const char*,const char*,DWORD) { return 1; }
DWORD acceptChangedCertificate(freerdp* instance,const char*,UINT16,const char*,const char*,const char*,const char*,const char*,const char*,const char*,DWORD) {
    if(instance && instance->context)
        reinterpret_cast<PaperContext*>(instance->context)->app->certificateChanged=true;
    return 0;
}

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
        case 0x01000000: case 0xff1b: case 0x1b: return 0x01;
        case 0x01000001: case 0x01000002: case 0xff09: case 0xfe20: case 0x09: return 0x0f;
        case 0x01000007: case 0xffff: return MAKE_RDP_SCANCODE(0x53,TRUE);
        case 0x01000010: case 0xff50: return MAKE_RDP_SCANCODE(0x47,TRUE);
        case 0x01000011: case 0xff57: return MAKE_RDP_SCANCODE(0x4f,TRUE);
        case 0x01000012: case 0xff51: return MAKE_RDP_SCANCODE(0x4b,TRUE);
        case 0x01000013: case 0xff52: return MAKE_RDP_SCANCODE(0x48,TRUE);
        case 0x01000014: case 0xff53: return MAKE_RDP_SCANCODE(0x4d,TRUE);
        case 0x01000015: case 0xff54: return MAKE_RDP_SCANCODE(0x50,TRUE);
        case 0x01000016: case 0xff55: return MAKE_RDP_SCANCODE(0x49,TRUE);
        case 0x01000017: case 0xff56: return MAKE_RDP_SCANCODE(0x51,TRUE);
        default:
            if(key>=0x01000030 && key<=0x0100003b) {
                const int n=key-0x01000030;
                return n<10 ? 0x3b+n : 0x57+n-10;
            }
            if(key>=0xffbe && key<=0xffc9) {
                const int n=key-0xffbe;
                return n<10 ? 0x3b+n : 0x57+n-10;
            }
            return 0;
    }
}

BOOL sendKeyPacket(rdpInput* input,BOOL down,UINT32 scan) {
    const UINT16 flags=(RDP_SCANCODE_EXTENDED(scan) ? KBD_FLAGS_EXTENDED : 0) |
                       (down ? 0 : KBD_FLAGS_RELEASE);
#ifdef PAPERDESK_RDP_TESTING
    return input->KeyboardEvent(input,flags,RDP_SCANCODE_CODE(scan));
#else
    return freerdp_input_send_keyboard_event(input,flags,RDP_SCANCODE_CODE(scan));
#endif
}
BOOL sendMousePacket(rdpInput* input,UINT16 flags,UINT16 x,UINT16 y) {
#ifdef PAPERDESK_RDP_TESTING
    return input->MouseEvent(input,flags,x,y);
#else
    return freerdp_input_send_mouse_event(input,flags,x,y);
#endif
}
BOOL sendUnicodePacket(rdpInput* input,UINT16 flags,UINT16 ch) {
#ifdef PAPERDESK_RDP_TESTING
    return input->UnicodeKeyboardEvent(input,flags,ch);
#else
    return freerdp_input_send_unicode_keyboard_event(input,flags,ch);
#endif
}

void remoteKey(App& a,int key,bool down) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    uint32_t scan=specialKeyToScan(key);
    if(!scan) scan=qtToScan(key);
    if(scan) sendKeyPacket(a.rdp->context->input,down,scan);
}

void sendUnicode(App& a,uint16_t ch);
void sendShortcut(App& a,int index);
bool handleClientCommand(App& a,int key,bool down);

void remoteInputKey(App& a,int rawKey,bool down) {
    if(handleClientCommand(a,rawKey,down)) return;
    if(a.mode!=Mode::Remote) return;
    const bool encodedUnicode=(rawKey&0xFF000000)==0x02000000;
    const int key=encodedUnicode ? rawKey&0xFFFF : rawKey;
    if(encodedUnicode) {
        // A tagged codepoint is not an X11 keysym: U+FF09 and U+FF50 are
        // printable fullwidth characters, even though their values coincide
        // with XK_Tab/Home. Only actual C0/DEL controls take the key path.
        if((key<0x20 || key==0x7f) && specialKeyToScan(key)) remoteKey(a,key,down);
        else if(down) sendUnicode(a,static_cast<uint16_t>(key));
    } else if(key==0x01000002 || key==0xfe20) {
        if(down) sendShortcut(a,30);
    } else {
        remoteKey(a,key,down);
    }
}

void sendChord(App& a,const std::vector<std::pair<uint32_t,bool>>& keys) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    for(const auto& key:keys)
        sendKeyPacket(a.rdp->context->input,TRUE,MAKE_RDP_SCANCODE(key.first,key.second));
    for(auto it=keys.rbegin();it!=keys.rend();++it)
        sendKeyPacket(a.rdp->context->input,FALSE,MAKE_RDP_SCANCODE(it->first,it->second));
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
        case 30: sendChord(a,{{0x2a,false},{0x0f,false}}); break;
        default: {
            static const int navigation[]={0x01000007,0x01000013,0x01000015,0x01000012,
                0x01000014,0x01000010,0x01000011,0x01000016,0x01000017};
            const int key=index>=9 && index<=17 ? navigation[index-9] :
                          index>=18 && index<=29 ? 0x01000030+index-18 : 0;
            if(key) { remoteKey(a,key,true); remoteKey(a,key,false); }
        }
    }
}

void sendUnicode(App& a,uint16_t ch) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    sendUnicodePacket(a.rdp->context->input,0,static_cast<UINT16>(ch));
    sendUnicodePacket(a.rdp->context->input,KBD_FLAGS_RELEASE,static_cast<UINT16>(ch));
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
    // The QML chrome owns this strip. Never let an event forwarded through
    // the overlay open the obsolete bitmap menu underneath Keyboard / Close.
    if(a.launchedFromNativeLogin && y<BAR_H) return;
    if(y<BAR_H) {
        a.pendingTap=false;
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
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input || !remotePoint(a,x,y)) return;
    const int rx=remoteX(a,x);
    const int ry=remoteY(a,y);
    sendMousePacket(a.rdp->context->input,PTR_FLAGS_MOVE|PTR_FLAGS_DOWN|PTR_FLAGS_BUTTON1,rx,ry);
    sendMousePacket(a.rdp->context->input,PTR_FLAGS_BUTTON1,rx,ry);
}

void sendRemoteClick(App& a,int x,int y) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input || !remotePoint(a,x,y)) return;
    const int rx=remoteX(a,x);
    const int ry=remoteY(a,y);
    sendMousePacket(a.rdp->context->input,
                                  PTR_FLAGS_MOVE|PTR_FLAGS_DOWN|PTR_FLAGS_BUTTON1,rx,ry);
    sendMousePacket(a.rdp->context->input,PTR_FLAGS_BUTTON1,rx,ry);
}

void sendRemoteRightClick(App& a,int x,int y) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input || !remotePoint(a,x,y)) return;
    const int rx=remoteX(a,x);
    const int ry=remoteY(a,y);
    sendMousePacket(a.rdp->context->input,
                                  PTR_FLAGS_MOVE|PTR_FLAGS_DOWN|PTR_FLAGS_BUTTON2,rx,ry);
    sendMousePacket(a.rdp->context->input,PTR_FLAGS_BUTTON2,rx,ry);
}

void flushPendingTap(App& a,bool force=false) {
    if(!a.pendingTap) return;
    const auto elapsed=std::chrono::steady_clock::now()-a.pendingTapSince;
    if(!force && elapsed<std::chrono::milliseconds(500)) return;
    // The click itself is sent immediately on release. This timer only
    // expires the short-lived candidate used to recognise a second tap.
    a.pendingTap=false;
}

void queueRemoteTap(App& a,int x,int y) {
    if(y<BAR_H || a.shortcutsOpen) {
        a.pendingTap=false;
        processRemoteTouch(a,x,y);
        return;
    }
    if(!remotePoint(a,x,y)) return;
    // Send an ordinary click without the old half-second penalty, then retain
    // only its position/time as a possible double-click candidate.
    sendRemoteClick(a,x,y);
    a.pendingTap=true;
    a.pendingTapX=x;
    a.pendingTapY=y;
    a.pendingTapSince=std::chrono::steady_clock::now();
}

void flushDoubleClickSecond(App& a) {
    if(!a.doubleClickSecondPending ||
       std::chrono::steady_clock::now()<a.doubleClickSecondDue) return;
    sendRemoteClick(a,a.doubleClickX,a.doubleClickY);
    a.doubleClickSecondPending=false;
    std::fprintf(stderr,"PaperDesk RDP double click %d %d\n",
                 a.doubleClickX,a.doubleClickY);
}

bool beginDoubleTap(App& a,const qtfb::UserInputContents& u) {
    if(!a.pendingTap || !remotePoint(a,u.x,u.y) || a.shortcutsOpen) return false;
    const auto elapsed=std::chrono::steady_clock::now()-a.pendingTapSince;
    const int dx=u.x-a.pendingTapX,dy=u.y-a.pendingTapY;
    if(elapsed>std::chrono::milliseconds(500) || dx*dx+dy*dy>40*40) {
        flushPendingTap(a,true);
        return false;
    }
    // The first click has already been sent. Snap the second click to the
    // first click's exact coordinates because Windows uses a very small
    // double-click rectangle. Also enforce a short minimum gap: synthetic
    // hardware taps may otherwise arrive in the same RDP event batch.
    a.doubleClickX=a.pendingTapX;
    a.doubleClickY=a.pendingTapY;
    a.doubleClickSecondPending=true;
    a.doubleClickSecondDue=std::max(std::chrono::steady_clock::now(),
        a.pendingTapSince+std::chrono::milliseconds(90));
    a.pendingTap=false;
    a.doubleTapTouchId=u.devId;
    return true;
}

void maybeSendLongPress(App& a) {
    if(a.mode!=Mode::Remote || (a.mouseTouchId<0 && !a.panCandidate) ||
       a.mouseDown || a.rightClickSent ||
       a.pinchActive || a.panActive || a.touches.size()!=1) return;
    if(std::chrono::steady_clock::now()-a.mousePressSince<std::chrono::milliseconds(700)) return;
    const auto point=a.touches.begin()->second;
    const float dx=point.first-a.mouseStartX,dy=point.second-a.mouseStartY;
    if(dx*dx+dy*dy>8.0f*8.0f) return;
    // A long press is an explicit right-click, not the first half of a later
    // double-click.  Discard any pending single tap before sending it.
    a.pendingTap=false;
    sendRemoteRightClick(a,static_cast<int>(point.first),static_cast<int>(point.second));
    a.rightClickSent=true;
    a.panCandidate=false;
    a.panId=-1;
    a.gestureConsumed=true;
    std::fprintf(stderr,"PaperDesk RDP right click %d %d\n",
                 static_cast<int>(point.first),static_cast<int>(point.second));
}

void redrawZoomedView(App& a) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->gdi) return;
    a.viewX=std::clamp(a.viewX,0.0f,maxViewX(a));
    a.viewY=std::clamp(a.viewY,0.0f,maxViewY(a));
    a.dirty=true;
    a.dirtyX1=std::max(0,int(std::floor(a.viewX)));
    a.dirtyY1=std::max(0,int(std::floor(a.viewY)));
    a.dirtyX2=std::min(a.rdp->context->gdi->width,
                       int(std::ceil(a.viewX+a.rdp->context->gdi->width/a.zoom)));
    a.dirtyY2=std::min(a.rdp->context->gdi->height,
                       int(std::ceil(a.viewY+a.rdp->context->gdi->height/a.zoom)));
    std::fill(a.dirtyTiles.begin(),a.dirtyTiles.end(),1);
    a.dirtyTileCount=DAMAGE_TILE_COUNT;
    flushRemoteFrame(a,true);
    a.status="CONNECTED  "+std::to_string(int(std::lround(a.zoom*100)))+"%";
    drawBar(a);
}

void remoteMouse(App& a,UINT16 flags,int x,int y) {
    if(!a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    const int rx=remoteX(a,x);
    const int ry=remoteY(a,y);
    sendMousePacket(a.rdp->context->input,flags,rx,ry);
}

void releaseRemoteMouse(App& a,int x,int y) {
    if(!a.mouseDown) return;
    remoteMouse(a,PTR_FLAGS_MOVE,x,y);
    remoteMouse(a,PTR_FLAGS_BUTTON1,x,y);
    a.mouseDown=false;
    a.mouseTouchId=-1;
    a.cleanRefreshPending=true;
    a.cleanRefreshDue=std::chrono::steady_clock::now()+
        std::chrono::milliseconds(CLEAN_REFRESH_IDLE_MS);
}

void resetRemoteInput(App& a,bool release=true) {
    if(release && a.mouseDown) releaseRemoteMouse(a,a.mouseLastX,a.mouseLastY);
    a.mouseDown=false; a.mouseTouchId=-1;
    a.pendingTap=false; a.doubleTapTouchId=-1; a.doubleClickSecondPending=false;
    a.rightClickSent=false; a.touches.clear(); a.pinchActive=false;
    a.gestureConsumed=false; a.panCandidate=false; a.panActive=false; a.panId=-1;
    a.twoFingerMode=TwoFingerMode::None; a.gestureSamplePending=false;
    a.gestureViewChanged=false; a.wheelRemainder=0; a.pendingWheel=0;
    a.lastWheel=std::chrono::steady_clock::now();
}

void setViewportHeight(App& a,int requested) {
    const int height=requested==0 ? RDP_H : std::clamp(requested,240,RDP_H);
    if(height==a.viewportHeight) return;
    const auto old=viewTransform(a);
    const float centerX=a.viewX+(W/2.0f-old.offsetX)/old.scale;
    const float centerY=a.viewY+(a.viewportHeight/2.0f-old.offsetY)/old.scale;
    resetRemoteInput(a);
    a.viewportHeight=height;
    const auto next=viewTransform(a);
    a.viewX=std::clamp(centerX-(W/2.0f-next.offsetX)/next.scale,0.0f,next.maxX);
    a.viewY=std::clamp(centerY-(height/2.0f-next.offsetY)/next.scale,0.0f,next.maxY);
    if(a.mode==Mode::Remote) {
        // Clear the old covered area once, never redraw it on remote damage.
        fill(a,0,BAR_H,W,RDP_H,255);
        a.update(0,BAR_H,W,RDP_H);
        redrawZoomedView(a);
    }
}

UINT16 wheelFlags(int rotation) {
    // RDP wheel rotation is a signed nine-bit value, not an absolute delta
    // plus a separately negated magnitude. One notch is normally 120 units.
    rotation=std::clamp(rotation,-240,240);
    return PTR_FLAGS_WHEEL | (static_cast<UINT16>(rotation)&WheelRotationMask);
}
void flushWheel(App& a,bool force=false) {
    if(a.mode!=Mode::Remote || !a.pendingWheel || !a.rdp || !a.rdp->context || !a.rdp->context->input) return;
    const auto now=std::chrono::steady_clock::now();
    if(!force && now-a.lastWheel<std::chrono::milliseconds(40)) return;
    const int rotation=std::clamp(a.pendingWheel,-240,240);
    sendMousePacket(a.rdp->context->input,wheelFlags(rotation),0,0);
    a.pendingWheel-=rotation;
    a.lastWheel=now;
}

void sampleTwoFinger(App& a,bool force=false) {
    if(a.touches.size()!=2 || a.twoFingerMode==TwoFingerMode::None || !a.gestureSamplePending) return;
    if(!force && std::chrono::steady_clock::now()<a.gestureSampleDue) return;
    a.gestureSamplePending=false;
    auto it=a.touches.begin(); const auto p1=it++->second,p2=it->second;
    const float dx=p2.first-p1.first,dy=p2.second-p1.second;
    const float distance=std::max(20.0f,std::hypot(dx,dy));
    const float cx=(p1.first+p2.first)/2,cy=(p1.second+p2.second)/2;
    const float translation=std::hypot(cx-a.gestureStartCx,cy-a.gestureStartCy);
    const float separation=std::abs(distance-a.pinchDistance);
    if(a.twoFingerMode==TwoFingerMode::Pending) {
        // Coalescing both fingers before classification avoids interpreting
        // staggered packets from a parallel scroll as a pinch.
        if(separation>std::max(14.0f,a.pinchDistance*0.07f) && separation>translation*1.5f)
            a.twoFingerMode=TwoFingerMode::Pinch;
        else if(translation>=14 && separation<std::max(20.0f,translation*0.9f))
            a.twoFingerMode=TwoFingerMode::Scroll;
    }
    if(a.twoFingerMode==TwoFingerMode::Scroll) {
        // Finger up scrolls the document down. Bound queued travel so a fast
        // swipe cannot leave seconds of wheel traffic after release.
        const float units=(cy-a.gestureLastCy)*(120.0f/36.0f)+a.wheelRemainder;
        const int whole=static_cast<int>(units);
        a.wheelRemainder=units-whole;
        a.pendingWheel=std::clamp(a.pendingWheel+whole,-960,960);
        a.gestureLastCy=cy;
        flushWheel(a);
    } else if(a.twoFingerMode==TwoFingerMode::Pinch) {
        const float previous=a.zoom,previousX=a.viewX,previousY=a.viewY;
        a.zoom=std::clamp(a.pinchStartZoom*distance/a.pinchDistance,1.0f,3.0f);
        const auto transform=viewTransform(a);
        a.viewX=std::clamp(a.pinchAnchorX-(cx-transform.offsetX)/transform.scale,0.0f,transform.maxX);
        a.viewY=std::clamp(a.pinchAnchorY-(cy-BAR_H-transform.offsetY)/transform.scale,0.0f,transform.maxY);
        a.gestureViewChanged=a.gestureViewChanged || previous!=a.zoom || previousX!=a.viewX || previousY!=a.viewY;
    }
}

void processTouchPacket(App& a,const qtfb::UserInputContents& u) {
    const bool press=u.inputType==INPUT_TOUCH_PRESS;
    const bool move=u.inputType==INPUT_TOUCH_UPDATE;
    const bool release=u.inputType==INPUT_TOUCH_RELEASE;
    if(!press&&!move&&!release) return;

    if(press && !remotePoint(a,u.x,u.y)) return;
    if(!press && a.touches.find(u.devId)==a.touches.end()) return;
    if((move || release) && !remotePoint(a,u.x,u.y)) {
        // Never turn a keyboard-covered release into a click. Existing drags
        // still receive a clamped button-up before their state is discarded.
        resetRemoteInput(a);
        return;
    }
    a.touches[u.devId]={float(u.x),float(u.y)};
    if(a.touches.size()>2) {
        if(a.mouseDown) releaseRemoteMouse(a,a.mouseLastX,a.mouseLastY);
        a.mouseTouchId=-1; a.panCandidate=false; a.panActive=false;
        a.twoFingerMode=TwoFingerMode::None; a.pinchActive=false;
        a.pendingTap=false; a.doubleClickSecondPending=false; a.gestureConsumed=true;
    }
    if(press && a.touches.size()==1 && beginDoubleTap(a,u)) return;
    if(release && a.doubleTapTouchId==u.devId) {
        a.touches.erase(u.devId);
        a.doubleTapTouchId=-1;
        if(a.touches.empty()) a.gestureConsumed=false;
        return;
    }
    if(press && a.touches.size()==1 && u.y>=BAR_H && !a.shortcutsOpen
       && a.zoom<=1.001f && a.mouseTouchId<0 && !a.gestureConsumed) {
        a.mouseTouchId=u.devId;
        a.mouseStartX=float(u.x);
        a.mouseStartY=float(u.y);
        a.mouseLastX=u.x;
        a.mouseLastY=u.y;
        a.lastMouseMove=std::chrono::steady_clock::now();
        a.mousePressSince=a.lastMouseMove;
        a.rightClickSent=false;
    }
    if(move && a.mouseTouchId==u.devId && a.touches.size()==1 && !a.rightClickSent) {
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
        // Long-press remains a right click while zoomed.  The long-press
        // movement threshold uses mouseStart*, so refresh that origin for
        // the zoomed/pan-candidate path as well as the unzoomed mouse path.
        a.mouseStartX=float(u.x);
        a.mouseStartY=float(u.y);
        a.panStartViewX=a.viewX;
        a.panStartViewY=a.viewY;
        a.mousePressSince=std::chrono::steady_clock::now();
        a.rightClickSent=false;
    }
    if(press && a.touches.size()==2) {
        if(a.mouseDown) releaseRemoteMouse(a,a.mouseLastX,a.mouseLastY);
        a.mouseTouchId=-1; a.panCandidate=false; a.panActive=false; a.panId=-1;
        a.pendingTap=false; a.doubleClickSecondPending=false; a.doubleTapTouchId=-1;
        auto it=a.touches.begin(); const auto p1=it++->second,p2=it->second;
        a.pinchDistance=std::max(20.0f,std::hypot(p2.first-p1.first,p2.second-p1.second));
        a.pinchStartZoom=a.zoom;
        a.gestureStartCx=(p1.first+p2.first)/2;
        a.gestureStartCy=a.gestureLastCy=(p1.second+p2.second)/2;
        const auto transform=viewTransform(a);
        a.pinchAnchorX=a.viewX+(a.gestureStartCx-transform.offsetX)/transform.scale;
        a.pinchAnchorY=a.viewY+(a.gestureStartCy-BAR_H-transform.offsetY)/transform.scale;
        a.pinchActive=true; a.gestureConsumed=true;
        a.twoFingerMode=TwoFingerMode::Pending; a.gestureViewChanged=false;
        a.wheelRemainder=0; a.gestureSamplePending=false;
    }
    if(move && !a.pinchActive && a.panCandidate && a.panId==u.devId && a.touches.size()==1) {
        const float dx=float(u.x)-a.panStartX,dy=float(u.y)-a.panStartY;
        if(!a.panActive && dx*dx+dy*dy>18.0f*18.0f) {
            a.panActive=true;
            a.gestureConsumed=true;
        }
        if(a.panActive) {
            a.viewX=a.panStartViewX-dx/outputScaleX(a);
            a.viewY=a.panStartViewY-dy/outputScaleY(a);
            a.viewX=std::clamp(a.viewX,0.0f,maxViewX(a));
            a.viewY=std::clamp(a.viewY,0.0f,maxViewY(a));
            // Do not publish intermediate pan frames.  A single coherent
            // frame is drawn on release below; live 320 ms redraws overflowed
            // the e-ink queue and produced duplicated/torn desktop halves.
        }
    }
    if((move||release) && a.pinchActive && a.touches.size()==2) {
        if(!a.gestureSamplePending)
            a.gestureSampleDue=std::chrono::steady_clock::now()+std::chrono::milliseconds(24);
        a.gestureSamplePending=true;
        sampleTwoFinger(a,release);
    }
    if(release) {
        const bool wasGesture=a.gestureConsumed;
        const bool finishPan=a.panActive && a.panId==u.devId;
        const bool finishMouse=a.mouseTouchId==u.devId;
        if(finishMouse) {
            if(a.rightClickSent) {
                a.rightClickSent=false;
                a.mouseTouchId=-1;
            } else if(a.mouseDown) releaseRemoteMouse(a,u.x,u.y);
            else { queueRemoteTap(a,u.x,u.y); a.mouseTouchId=-1; }
        }
        if(a.panId==u.devId) {
            a.panCandidate=false;
            a.panActive=false;
            a.panId=-1;
        }
        a.touches.erase(u.devId);
        if(a.pinchActive && a.touches.size()<2) {
            a.pinchActive=false; a.twoFingerMode=TwoFingerMode::None;
            a.gestureSamplePending=false;
            if(a.gestureViewChanged) redrawZoomedView(a);
            a.gestureViewChanged=false;
        }
        else if(finishPan) redrawZoomedView(a);
        else if(!finishMouse && !wasGesture && !a.gestureConsumed) queueRemoteTap(a,u.x,u.y);
        if(a.rightClickSent) a.rightClickSent=false;
        if(a.touches.empty()) a.gestureConsumed=false;
    }
}

void pollInput(App& a) {
    qtfb::ServerMessage msg{};
    // A repaint/input storm must not starve FreeRDP network processing.
    // Remaining packets are handled on the next 12 ms event-loop turn.
    for(int packetBudget=0;packetBudget<64 && a.fb.pollServerPacket(msg);++packetBudget) {
        if(msg.type!=MESSAGE_USERINPUT) continue;
        auto u=msg.userInput;
        if(u.inputType==INPUT_TOUCH_PRESS || u.inputType==INPUT_TOUCH_UPDATE ||
           u.inputType==INPUT_TOUCH_RELEASE || u.inputType==INPUT_PEN_RELEASE ||
           u.inputType==INPUT_PEN_PRESS || u.inputType==INPUT_PEN_UPDATE) {
            const auto point=logicalPoint(a.profile.landscape,u.x,u.y);
            u.x=point.first; u.y=point.second;
        }
        if(u.inputType==INPUT_BTN_PRESS || u.inputType==INPUT_VKB_PRESS ||
           u.inputType==INPUT_BTN_RELEASE || u.inputType==INPUT_VKB_RELEASE) {
            const bool down=u.inputType==INPUT_BTN_PRESS || u.inputType==INPUT_VKB_PRESS;
            if(handleClientCommand(a,u.x,down)) continue;
        }
        if(a.mode==Mode::Remote && (u.inputType==INPUT_TOUCH_PRESS || u.inputType==INPUT_TOUCH_UPDATE || u.inputType==INPUT_TOUCH_RELEASE)) {
            processTouchPacket(a,u);
            continue;
        }
        if(u.inputType==INPUT_TOUCH_RELEASE || u.inputType==INPUT_PEN_RELEASE) {
            if(a.mode==Mode::Login) processLoginTouch(a,u.x,u.y);
            else if(a.mode==Mode::Error) {
                if(u.x>=CLOSE_X&&u.y>=ACTION_Y&&u.y<ACTION_Y+ACTION_H) a.running=false;
                else if(u.y>=360 && u.y<480 && u.x>=70 && u.x<590) requestRetry(a);
                else if(u.y>=360 && u.y<480 && u.x>=650 && u.x<1170) a.running=false;
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
bool parseStateRequest(const std::string& line,int& request) {
    if(line.compare(0,6,"state ")!=0 || line.size()<7 || line.size()>15) return false;
    int value=0;
    for(size_t i=6;i<line.size();++i) {
        if(line[i]<'0' || line[i]>'9') return false;
        value=value*10+(line[i]-'0');
    }
    request=value; // At most nine decimal digits: no signed overflow.
    return true;
}

void pollAutomation(App& a,int fd,std::string& pending) {
    char chunk[256];
    for(int budget=0;budget<16;++budget) {
        const ssize_t count=::read(fd,chunk,sizeof(chunk));
        if(count>0) {
            pending.append(chunk,static_cast<size_t>(count));
            if(pending.size()>8192) { pending.clear(); break; }
        } else break;
    }
    for(int budget=0;budget<64;++budget) {
        const auto end=pending.find('\n');
        if(end==std::string::npos) break;
        const std::string line=pending.substr(0,end);
        pending.erase(0,end+1);
        int x=0,y=0,key=0,id=0;
        char command[8]={},extra=0;
        if(line=="quit") { a.running=false; return; }
        int request=0;
        if(parseStateRequest(line,request)) {
            std::fprintf(stderr,
                "PAPERDESK_RDP_NATIVE_STATE {\"request\":%d,\"pid\":%ld,\"mode\":%d,"
                "\"viewportHeight\":%d,\"zoom\":%.6f,\"certificateChanged\":%s,"
                "\"mouseDown\":%s,\"pendingWheel\":%d}\n",
                request,static_cast<long>(::getpid()),static_cast<int>(a.mode),
                a.viewportHeight,static_cast<double>(a.zoom),a.certificateChanged ? "true" : "false",
                a.mouseDown ? "true" : "false",a.pendingWheel);
            continue;
        }
        if(std::sscanf(line.c_str(),"%7s %d %d %d %c",command,&id,&x,&y,&extra)==4 &&
           id>=0 && id<32 && x>=0 && x<W && y>=0 && y<H && a.mode==Mode::Remote) {
            qtfb::UserInputContents u{};
            u.devId=id; u.x=x; u.y=y;
            if(std::strcmp(command,"down")==0) u.inputType=INPUT_TOUCH_PRESS;
            else if(std::strcmp(command,"move")==0) u.inputType=INPUT_TOUCH_UPDATE;
            else if(std::strcmp(command,"up")==0) u.inputType=INPUT_TOUCH_RELEASE;
            else continue;
            processTouchPacket(a,u);
        } else if(std::sscanf(line.c_str(),"tap %d %d %c",&x,&y,&extra)==2 && a.mode==Mode::Remote)
            processRemoteTouch(a,x,y);
        else if(std::sscanf(line.c_str(),"key %d %c",&key,&extra)==1) {
            remoteInputKey(a,key,true);
            remoteInputKey(a,key,false);
        }
    }
}
#endif

void disconnectRdp(App& a);

bool connectRdp(App& a) {
    disconnectRdp(a);
    freerdp* r=freerdp_new(); if(!r) return false;
    a.rdp=r; r->ContextSize=sizeof(PaperContext); r->ContextNew=contextNew;
    if(!freerdp_context_new(r)) {freerdp_free(r);a.rdp=nullptr;return false;}
    r->PostConnect=postConnect; r->PostDisconnect=postDisconnect;
    r->VerifyCertificateEx=acceptCertificate; r->VerifyChangedCertificateEx=acceptChangedCertificate;
    auto* s=r->context->settings;
    bool ok=true;
    ok &= freerdp_settings_set_string(s,FreeRDP_ServerHostname,a.profile.host.c_str());
    ok &= freerdp_settings_set_uint32(s,FreeRDP_ServerPort,a.profile.port);
    ok &= freerdp_settings_set_uint32(s,FreeRDP_TcpConnectTimeout,5000);
    ok &= freerdp_settings_set_string(s,FreeRDP_Username,a.profile.user.c_str());
    ok &= freerdp_settings_set_string(s,FreeRDP_Password,a.profile.password.c_str());
    if(!a.profile.domain.empty()) ok &= freerdp_settings_set_string(s,FreeRDP_Domain,a.profile.domain.c_str());
    const UINT32 sessionWidth=static_cast<UINT32>(W*a.profile.scalePercent/100);
    const UINT32 sessionHeight=static_cast<UINT32>(RDP_H*a.profile.scalePercent/100);
    ok &= freerdp_settings_set_uint32(s,FreeRDP_DesktopWidth,sessionWidth);
    ok &= freerdp_settings_set_uint32(s,FreeRDP_DesktopHeight,sessionHeight);
    ok &= freerdp_settings_set_uint32(s,FreeRDP_ColorDepth,a.profile.colorDepth);
    // Some older xrdp servers send a palette order without advertising it.
    // FreeRDP's command-line client exposes the same compatibility behaviour
    // as /relax-order-checks; without it an 8-bit session disconnects as soon
    // as the first colour table arrives.
    ok &= freerdp_settings_set_bool(s,FreeRDP_AllowUnanouncedOrdersFromServer,TRUE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_DisableWallpaper,TRUE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AllowFontSmoothing,FALSE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_DisableFullWindowDrag,TRUE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_DisableMenuAnims,TRUE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_DisableThemes,TRUE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AllowDesktopComposition,FALSE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AutoAcceptCertificate,TRUE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AudioPlayback,FALSE);
    ok &= freerdp_settings_set_bool(s,FreeRDP_AudioCapture,FALSE);
    std::fprintf(stderr,"PaperDesk RDP performance scale=%d colors=%d size=%ux%u\n",
                 a.profile.scalePercent,a.profile.colorDepth,sessionWidth,sessionHeight);
    if(!ok || !freerdp_connect(r)) {
        disconnectRdp(a); return false;
    }
    std::fprintf(stderr,"PaperDesk RDP connected\n");
    return true;
}

void disconnectRdp(App& a) {
    resetRemoteInput(a,false);
    a.shortcutsOpen=false; a.shift=false;
    a.dirty=false; a.dirtyTileCount=0;
    std::fill(a.dirtyTiles.begin(),a.dirtyTiles.end(),0);
    a.dirtyX1=W; a.dirtyY1=RDP_H; a.dirtyX2=a.dirtyY2=0;
    a.cleanRefreshPending=false;
    if(!a.rdp) return;
    freerdp_disconnect(a.rdp);
    freerdp_context_free(a.rdp); freerdp_free(a.rdp); a.rdp=nullptr;
}

bool requestRetry(App& a) {
    if(!canRetry(a)) return false;
    disconnectRdp(a);
    // No profile write here: this retry uses only the current in-memory copy.
    // A rejected changed certificate remains latched until the app closes.
    a.zoom=1; a.viewX=a.viewY=0;
    a.mode=Mode::Connecting; a.status="CONNECTING...";
    a.fb.setRefreshMode(REFRESH_MODE_UI);
    drawConnecting(a);
    return true;
}

bool handleClientCommand(App& a,int key,bool down) {
    if((key&0xff000000)==0x03000000) {
        if(down) setViewportHeight(a,key&0x00ffffff);
        return true;
    }
    if((key&0xffff0000)!=0x02ff0000) return false;
    if(!down) return true;
    const int command=key&0xffff;
    if(command==0x100) requestRetry(a);
    else if(command==0x101 && a.mode==Mode::Remote) {
        resetRemoteInput(a); a.zoom=1; a.viewX=a.viewY=0; redrawZoomedView(a);
    } else if(a.mode==Mode::Remote) sendShortcut(a,command);
    return true;
}

void signalHandler(int) { if(g_app) g_app->running=false; }
}

int main(int argc,char** argv) {
    std::signal(SIGTERM,signalHandler); std::signal(SIGINT,signalHandler); std::signal(SIGPIPE,SIG_IGN);
    Profile selected;
    loadProfile(selected);
    bool rememberPassword=true;
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
        if(arg=="--host") takeValue(selected.host);
        else if(arg=="--user") takeValue(selected.user);
        else if(arg=="--domain-hex") {
            std::string encoded;
            if(takeValue(encoded)) hexDecode(encoded,selected.domain);
        }
        else if(arg=="--password-hex") {
            std::string encoded;
            if(takeValue(encoded)) hexDecode(encoded,selected.password);
        } else if(arg=="--port" && i+1<argc) {
            int port=0;
            if(parsePort(argv[++i],port)) selected.port=port;
            autoConnect=true;
        } else if(arg=="--scale-percent" && i+1<argc) {
            selected.scalePercent=normalizeScalePercent(std::atoi(argv[++i]));
            autoConnect=true;
        } else if(arg=="--color-depth" && i+1<argc) {
            selected.colorDepth=normalizeColorDepth(std::atoi(argv[++i]));
            autoConnect=true;
        } else if(arg=="--orientation" && i+1<argc) {
            selected.landscape=std::string(argv[++i])=="landscape";
        } else if(arg=="--connect") autoConnect=true;
        else if(arg=="--no-save-password") rememberPassword=false;
    }
    configureOrientation(selected.landscape);
    std::fprintf(stderr,"PaperDesk RDP orientation %s logical=%dx%d\n",
                 selected.landscape ? "landscape" : "portrait",W,H);
    App app(selected); g_app=&app;
    app.rememberPassword=rememberPassword;
    std::fill(selected.password.begin(),selected.password.end(),'\0');
    // The editable login belongs to the native QML front-end.  AppLoad can
    // still expose this external engine as a direct entry, so make that path
    // reuse the saved profile instead of falling back to the framebuffer
    // login and its legacy drawn keyboard.
    if(!autoConnect && !app.profile.host.empty() && !app.profile.user.empty())
        autoConnect=true;
    if(autoConnect) {
        app.launchedFromNativeLogin=true;
        Profile persisted=profileForStorage(app.profile,app.rememberPassword);
        saveProfile(persisted);
        std::fill(persisted.password.begin(),persisted.password.end(),'\0');
        app.mode=Mode::Connecting;
        app.status="CONNECTING...";
        drawConnecting(app);
    } else {
        app.launchedFromNativeLogin=true;
        drawError(app,"OPEN PAPERDESK AND CHOOSE RDP");
    }
    while(app.running) {
        pollInput(app);
        sampleTwoFinger(app);
        flushWheel(app);
        maybeSendLongPress(app);
        flushPendingTap(app);
        flushDoubleClickSecond(app);
#ifdef PAPERDESK_E2E
        if(automationFd>=0) pollAutomation(app,automationFd,automationPending);
#endif
        if(!app.running) break;
        if(app.mode==Mode::Connecting) {
            if(!connectRdp(app)) drawError(app,app.certificateChanged ? "SERVER CERTIFICATE CHANGED" : "CONNECTION OR LOGIN ERROR");
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
