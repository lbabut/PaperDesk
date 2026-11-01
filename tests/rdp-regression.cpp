// Compile with the same ARM SDK and FreeRDP libraries as the actual client.
// Memory-only App and fake input callbacks: no network, device framebuffer
// or real profile I/O. The same regression binary also runs on the tablet.
#define PAPERDESK_RDP_TESTING
#define PAPERDESK_E2E
#define main paperdesk_application_main
#include "../product/payload/apps/paperrdp/paperrdp.cpp"
#undef main
#include <cassert>

struct InputPacket { UINT16 flags,code,x,y; };
static std::vector<InputPacket> keyPackets,unicodePackets,mousePackets;
static BOOL recordKey(rdpInput*,UINT16 flags,UINT8 code) {
    keyPackets.push_back({flags,code,0,0}); return TRUE;
}
static BOOL recordUnicode(rdpInput*,UINT16 flags,UINT16 code) {
    unicodePackets.push_back({flags,code,0,0}); return TRUE;
}
static BOOL recordMouse(rdpInput*,UINT16 flags,UINT16 x,UINT16 y) {
    mousePackets.push_back({flags,0,x,y}); return TRUE;
}
static void touch(App& app,int type,int id,int x,int y) {
    qtfb::UserInputContents u{}; u.inputType=type; u.devId=id; u.x=x; u.y=y;
    processTouchPacket(app,u);
}
static bool near(float a,float b) { return std::abs(a-b)<0.01f; }

static void inputAndViewportTests() {
    Profile p; p.host="fixture.invalid"; p.user="fixture-user";
    App app(p);
    freerdp instance{}; rdpContext context{}; rdpInput input{}; rdpGdi gdi{};
    instance.context=&context; context.input=&input; context.gdi=&gdi;
    input.KeyboardEvent=recordKey; input.UnicodeKeyboardEvent=recordUnicode; input.MouseEvent=recordMouse;
    app.rdp=&instance; app.mode=Mode::Remote;
    gdi.width=W; gdi.height=RDP_H; gdi.stride=W*4;
    std::vector<BYTE> desktop(W*RDP_H*4,0); gdi.primary_buffer=desktop.data();
    const std::vector<std::pair<int,UINT32>> nav={
        {0x01000001,0x0f},{0xff09,0x0f},{9,0x0f},
        {0x01000007,0x153},{0xffff,0x153},
        {0x01000010,0x147},{0xff50,0x147},{0x01000011,0x14f},{0xff57,0x14f},
        {0x01000012,0x14b},{0xff51,0x14b},{0x01000013,0x148},{0xff52,0x148},
        {0x01000014,0x14d},{0xff53,0x14d},{0x01000015,0x150},{0xff54,0x150},
        {0x01000016,0x149},{0xff55,0x149},{0x01000017,0x151},{0xff56,0x151}};
    for(const auto& [key,scan]:nav) {
        keyPackets.clear(); remoteInputKey(app,key,true); remoteInputKey(app,key,false);
        assert(keyPackets.size()==2);
        assert(keyPackets[0].code==(scan&0xff) && keyPackets[1].code==(scan&0xff));
        const UINT16 extended=(scan&0x100) ? KBD_FLAGS_EXTENDED : 0;
        assert(keyPackets[0].flags==extended);
        assert(keyPackets[1].flags==(extended|KBD_FLAGS_RELEASE));
    }
    for(int n=0;n<12;++n) for(int base:{0x01000030,0xffbe}) {
        keyPackets.clear(); remoteInputKey(app,base+n,true); remoteInputKey(app,base+n,false);
        const int scan=n<10 ? 0x3b+n : 0x57+n-10;
        assert(keyPackets.size()==2 && keyPackets[0].code==scan);
        assert(keyPackets[0].flags==0 && keyPackets[1].flags==KBD_FLAGS_RELEASE);
    }
    keyPackets.clear(); sendShortcut(app,5);
    assert(keyPackets.size()==6);
    assert(keyPackets[2].code==0x4f && keyPackets[2].flags==KBD_FLAGS_EXTENDED);
    assert(keyPackets[3].code==0x4f && keyPackets[3].flags==(KBD_FLAGS_EXTENDED|KBD_FLAGS_RELEASE));
    assert(keyPackets[0].code==0x1d && keyPackets[5].code==0x1d);
    keyPackets.clear(); sendShortcut(app,6);
    assert(keyPackets.size()==2 && keyPackets[0].code==0x5b && keyPackets[0].flags==KBD_FLAGS_EXTENDED);
    keyPackets.clear(); remoteInputKey(app,0x01000002,true); remoteInputKey(app,0x01000002,false);
    assert(keyPackets.size()==4 && keyPackets[0].code==0x2a && keyPackets[1].code==0x0f);
    for(int n=9;n<=30;++n) {
        keyPackets.clear(); remoteInputKey(app,0x02ff0000|n,true); remoteInputKey(app,0x02ff0000|n,false);
        assert(keyPackets.size()==size_t(n==30 ? 4 : 2));
    }
    keyPackets.clear(); unicodePackets.clear();
    remoteInputKey(app,0x02000000|0x105,true); remoteInputKey(app,0x02000000|0x105,false);
    assert(keyPackets.empty() && unicodePackets.size()==2 && unicodePackets[0].code==0x105);
    for(int code:{0xff08,0xff09,0xff50}) {
        keyPackets.clear(); unicodePackets.clear();
        remoteInputKey(app,0x02000000|code,true); remoteInputKey(app,0x02000000|code,false);
        assert(keyPackets.empty() && unicodePackets.size()==2 && unicodePackets[0].code==code);
    }
    unicodePackets.clear(); remoteInputKey(app,0x02000009,true); remoteInputKey(app,0x02000009,false);
    assert(unicodePackets.empty() && keyPackets.size()==2 && keyPackets[0].code==0x0f);

    // Single-finger drag, ordinary click and right click retain distinct paths.
    mousePackets.clear(); touch(app,INPUT_TOUCH_PRESS,1,300,500);
    touch(app,INPUT_TOUCH_UPDATE,1,340,540); touch(app,INPUT_TOUCH_RELEASE,1,340,540);
    assert(mousePackets.size()>=3 && (mousePackets.front().flags&PTR_FLAGS_DOWN));
    assert(mousePackets.back().flags==PTR_FLAGS_BUTTON1 && !app.mouseDown);
    resetRemoteInput(app); mousePackets.clear();
    touch(app,INPUT_TOUCH_PRESS,1,500,700); touch(app,INPUT_TOUCH_RELEASE,1,500,700);
    assert(mousePackets.size()==2 && app.pendingTap);
    touch(app,INPUT_TOUCH_PRESS,1,501,701); touch(app,INPUT_TOUCH_RELEASE,1,501,701);
    app.doubleClickSecondDue-=std::chrono::seconds(1); flushDoubleClickSecond(app);
    assert(mousePackets.size()==4 && !app.doubleClickSecondPending);
    resetRemoteInput(app); mousePackets.clear();
    touch(app,INPUT_TOUCH_PRESS,1,500,700);
    app.mousePressSince-=std::chrono::seconds(1); maybeSendLongPress(app);
    touch(app,INPUT_TOUCH_RELEASE,1,500,700);
    assert(mousePackets.size()==2 && (mousePackets.front().flags&PTR_FLAGS_BUTTON2));

    // Staggered parallel finger packets coalesce into document scroll, not zoom.
    resetRemoteInput(app); mousePackets.clear();
    touch(app,INPUT_TOUCH_PRESS,1,400,800); touch(app,INPUT_TOUCH_PRESS,2,700,800);
    touch(app,INPUT_TOUCH_UPDATE,1,400,728); touch(app,INPUT_TOUCH_UPDATE,2,700,728);
    app.gestureSampleDue-=std::chrono::seconds(1); app.lastWheel-=std::chrono::seconds(1);
    sampleTwoFinger(app); flushWheel(app);
    assert(app.twoFingerMode==TwoFingerMode::Scroll && near(app.zoom,1));
    assert(mousePackets.size()==1 && mousePackets[0].flags==wheelFlags(-240));
    assert((mousePackets[0].flags&PTR_FLAGS_WHEEL) && (mousePackets[0].flags&PTR_FLAGS_WHEEL_NEGATIVE));
    touch(app,INPUT_TOUCH_RELEASE,1,400,728); touch(app,INPUT_TOUCH_RELEASE,2,700,728);
    assert(mousePackets.size()==1 && app.touches.empty());
    assert(wheelFlags(120)==0x278 && wheelFlags(-120)==0x388);
    app.pendingWheel=-10000; // the production accumulator itself clamps at 960
    app.pendingWheel=std::clamp(app.pendingWheel,-960,960);
    for(int n=0;n<4;++n) { app.lastWheel-=std::chrono::seconds(1); flushWheel(app); }
    assert(app.pendingWheel==0);
    for(const auto packet:mousePackets) assert((packet.flags&WheelRotationMask)==0x110);
    const auto count=mousePackets.size(); flushWheel(app); assert(mousePackets.size()==count);

    // Pinch is sticky and never emits a wheel; it redraws only after release.
    resetRemoteInput(app); mousePackets.clear();
    touch(app,INPUT_TOUCH_PRESS,1,500,800); touch(app,INPUT_TOUCH_PRESS,2,700,800);
    touch(app,INPUT_TOUCH_UPDATE,1,450,800); touch(app,INPUT_TOUCH_UPDATE,2,750,800);
    sampleTwoFinger(app,true);
    assert(app.twoFingerMode==TwoFingerMode::Pinch && near(app.zoom,1.5f) && mousePackets.empty());
    touch(app,INPUT_TOUCH_RELEASE,1,450,800); touch(app,INPUT_TOUCH_RELEASE,2,750,800);
    assert(!app.pinchActive && app.pendingWheel==0 && mousePackets.empty());
    touch(app,INPUT_TOUCH_PRESS,1,600,900); touch(app,INPUT_TOUCH_UPDATE,1,500,800);
    assert(app.panActive); touch(app,INPUT_TOUCH_RELEASE,1,500,800);
    assert(!app.panActive && app.viewX>0 && app.viewY>0);

    // Geometry transitions release a held pointer, cancel scheduled taps and
    // leave keyboard/padding unable to generate remote clicks.
    app.zoom=1; app.viewX=app.viewY=0; resetRemoteInput(app); mousePackets.clear();
    touch(app,INPUT_TOUCH_PRESS,1,400,700); touch(app,INPUT_TOUCH_UPDATE,1,450,750);
    assert(app.mouseDown);
    setViewportHeight(app,700);
    assert(!app.mouseDown && app.touches.empty() && !app.pendingTap && app.pendingWheel==0);
    assert(mousePackets.back().flags==PTR_FLAGS_BUTTON1);
    assert(near(outputScaleX(app),outputScaleY(app)));
    const auto t=viewTransform(app);
    assert(t.offsetX>0 && near(t.offsetY,0));
    assert(app.pixels()[(BAR_H+300)*W]==0xffff);
    assert(app.pixels()[(BAR_H+300)*W+W/2]==0);
    assert(app.pixels()[(BAR_H+701)*W+W/2]==0xffff);
    mousePackets.clear();
    touch(app,INPUT_TOUCH_PRESS,1,1,300); touch(app,INPUT_TOUCH_RELEASE,1,1,300);
    touch(app,INPUT_TOUCH_PRESS,1,W/2,BAR_H+701); touch(app,INPUT_TOUCH_RELEASE,1,W/2,BAR_H+701);
    sendRemoteClick(app,1,300); processRemoteTouch(app,W/2,BAR_H+701);
    assert(mousePackets.empty());
    // Both edges of the actual content map into the corresponding remote edges.
    assert(remoteX(app,int(std::ceil(t.offsetX)))<=1);
    assert(remoteX(app,int(t.offsetX+gdi.width*t.scale)-1)>=gdi.width-4);
    assert(remoteY(app,BAR_H)==0);
    const int updates=app.fb.updates;
    app.cleanRefreshPending=false; app.dirty=false;
    for(int n=0;n<100;++n) { flushRemoteFrame(app); maybeCleanRefresh(app); flushWheel(app); sampleTwoFinger(app); }
    assert(app.fb.updates==updates);
    remoteInputKey(app,0x03000000,false); assert(app.viewportHeight==700);
    remoteInputKey(app,0x03000000,true); assert(app.viewportHeight==RDP_H);
    remoteInputKey(app,0x02ff0101,true); assert(near(app.zoom,1));
    app.rdp=nullptr; // fixture owns stack-backed FreeRDP objects

    // Retry uses only memory, clears pending input and never unlocks a changed
    // certificate. Viewport survives Connecting/Error and a retry transition.
    app.mode=Mode::Error; app.viewportHeight=700;
    app.pendingWheel=240; app.pendingTap=true; app.doubleClickSecondPending=true;
    app.mouseDown=true; app.cleanRefreshPending=true; app.shortcutsOpen=true;
    app.profile.password="synthetic-session-only";
    assert(canRetry(app) && requestRetry(app));
    assert(app.mode==Mode::Connecting && app.viewportHeight==700);
    assert(app.profile.password=="synthetic-session-only" && app.profile.host==p.host);
    assert(!app.pendingTap && !app.doubleClickSecondPending && !app.pendingWheel && !app.mouseDown);
    assert(!app.cleanRefreshPending && !app.shortcutsOpen && !app.rdp);
    assert(!requestRetry(app));
    app.mode=Mode::Remote; assert(!requestRetry(app));
    app.mode=Mode::Error;
    PaperContext certificateContext{}; certificateContext.app=&app;
    instance.context=&certificateContext.context;
    assert(acceptChangedCertificate(&instance,nullptr,0,nullptr,nullptr,nullptr,nullptr,
                                    nullptr,nullptr,nullptr,0)==0);
    instance.context=&context;
    assert(app.certificateChanged);
    assert(!canRetry(app) && !requestRetry(app));
    assert(handleClientCommand(app,0x02ff0100,true) && app.mode==Mode::Error);
    app.certificateChanged=false; app.profile.user.clear(); assert(!canRetry(app));
}

static void automationStateTest() {
    int request=-1;
    assert(parseStateRequest("state 0",request) && request==0);
    assert(parseStateRequest("state 999999999",request) && request==999999999);
    for(const std::string invalid:{"state -1","state 1000000000","state 2147483648",
                                  "state ","state 1 extra","state 1 ","state +1"})
        assert(!parseStateRequest(invalid,request));
    Profile profile; profile.host="private-not-logged.invalid"; profile.password="private-not-logged";
    App app(profile); app.mode=Mode::Error; app.viewportHeight=700; app.zoom=1.5f;
    app.certificateChanged=true; app.mouseDown=true; app.pendingWheel=-240;
    int channel[2]; assert(::pipe(channel)==0);
    const std::string commands="state 42\nstate -1\n";
    assert(::write(channel[1],commands.data(),commands.size())==ssize_t(commands.size()));
    assert(::close(channel[1])==0);
    FILE* capture=::tmpfile(); assert(capture);
    std::fflush(stderr); const int savedStderr=::dup(STDERR_FILENO); assert(savedStderr>=0);
    assert(::dup2(::fileno(capture),STDERR_FILENO)>=0);
    std::string pending; pollAutomation(app,channel[0],pending);
    std::fflush(stderr); assert(::dup2(savedStderr,STDERR_FILENO)>=0); ::close(savedStderr);
    ::close(channel[0]); std::rewind(capture);
    char buffer[1024]={}; const size_t count=std::fread(buffer,1,sizeof(buffer)-1,capture); std::fclose(capture);
    const std::string output(buffer,count);
    assert(output.find("PAPERDESK_RDP_NATIVE_STATE {\"request\":42,\"pid\":"+std::to_string(::getpid()))==0);
    assert(output.find("\"mode\":3,\"viewportHeight\":700,\"zoom\":1.500000,")!=std::string::npos);
    assert(output.find("\"certificateChanged\":true,\"mouseDown\":true,\"pendingWheel\":-240}")!=std::string::npos);
    assert(output.find("private-not-logged")==std::string::npos);
    assert(std::count(output.begin(),output.end(),'\n')==1);
    assert(app.mode==Mode::Error && app.viewportHeight==700 && app.pendingWheel==-240);
}

static void lastConnectionPersistenceTest() {
    char directory[]="/tmp/paperdesk-rdp-regression-XXXXXX";
    assert(::mkdtemp(directory));
    assert(::setenv("PAPERDESK_TEST_RDP_CONFIG_DIR",directory,1)==0);
    const std::string list=std::string(directory)+"/profiles";
    const std::string listData="opaque-explicitly-saved-list\n";
    { std::ofstream out(list); out<<listData; }
    struct stat before{},after{}; assert(::stat(list.c_str(),&before)==0);
    Profile p; p.host="fixture.invalid"; p.user="fixture"; p.password="synthetic-only";
    assert(saveProfile(profileForStorage(p,false)));
    Profile loaded; loadProfile(loaded); assert(loaded.password.empty() && loaded.host==p.host);
    assert(saveProfile(profileForStorage(p,true)));
    loadProfile(loaded); assert(loaded.password==p.password);
    assert(::stat(list.c_str(),&after)==0);
    assert(before.st_ino==after.st_ino && before.st_mtim.tv_sec==after.st_mtim.tv_sec &&
           before.st_mtim.tv_nsec==after.st_mtim.tv_nsec && before.st_size==after.st_size);
    std::ifstream saved(list); std::string actual((std::istreambuf_iterator<char>(saved)),{});
    assert(actual==listData);
    assert(::unlink(list.c_str())==0);
    assert(::unlink((std::string(directory)+"/profile").c_str())==0);
    assert(::rmdir(directory)==0);
}

int main() {
    automationStateTest();
    lastConnectionPersistenceTest();
    Profile session;
    session.host="fixture.invalid";
    session.user="fixture-user";
    session.password="session-only-fixture";
    const Profile privateSession=profileForStorage(session,false);
    assert(privateSession.password.empty());
    assert(session.password=="session-only-fixture");
    assert(privateSession.host==session.host && privateSession.user==session.user);
    assert(profileForStorage(session,true).password==session.password);
    assert(acceptCertificate(nullptr,nullptr,0,nullptr,nullptr,nullptr,nullptr,0)==1);
    assert(acceptChangedCertificate(nullptr,nullptr,0,nullptr,nullptr,nullptr,nullptr,
                                    nullptr,nullptr,nullptr,0)==0);
    int port=0;
    assert(parsePort("3389",port) && port==3389);
    assert(!parsePort("0",port) && !parsePort("65536",port) && !parsePort("oops",port));
    Profile decoded;
    assert(parseProfileListLine(profileListLine(session).substr(0,profileListLine(session).size()-1),decoded));
    assert(decoded.password==session.password && sameProfile(session,decoded));
    assert(specialKeyToScan(0x01000004)==0x1c);
    assert(specialKeyToScan(0x01000005)==0x1c);
    assert(specialKeyToScan(0x01000003)==0x0e);
    assert(specialKeyToScan(8)==0x0e);
    // Old profiles must remain upright. New profiles carry orientation and
    // malformed orientation must not silently replace a saved connection.
    const std::string legacy="v1\t66697874757265\t75736572\t\t3389\t\t75\t8";
    assert(parseProfileListLine(legacy,decoded) && !decoded.landscape);
    session.landscape=true;
    const auto landscapeLine=profileListLine(session);
    assert(parseProfileListLine(landscapeLine.substr(0,landscapeLine.size()-1),decoded));
    assert(decoded.landscape && decoded.password==session.password);
    assert(!parseProfileListLine(legacy+"\tlandscape",decoded));
    assert(!parseProfileListLine("v2"+legacy.substr(2)+"\tunknown",decoded));
    configureOrientation(true);
    assert(W==1872 && H==1404 && RDP_H==1292);
    assert(DAMAGE_COLS*DAMAGE_ROWS==DAMAGE_TILE_COUNT);
    std::vector<uint16_t> logical(W*H), physical(W*H,0xeeee);
    for(int y=0;y<H;++y) for(int x=0;x<W;++x)
        logical[y*W+x]=static_cast<uint16_t>((x*7+y*13)%65521);
    rotateRect(logical.data(),physical.data(),{0,0,W,H});
    for(int y=0;y<PHYSICAL_H;++y) for(int x=0;x<PHYSICAL_W;++x) {
        const auto p=logicalPoint(true,x,y);
        assert(p.first>=0 && p.first<W && p.second>=0 && p.second<H);
        assert(physical[y*PHYSICAL_W+x]==logical[static_cast<int>(p.second)*W+static_cast<int>(p.first)]);
    }
    std::fill(physical.begin(),physical.end(),0xeeee);
    const ScreenRect r{111,207,88,133};
    const ScreenRect rotated=physicalRect(true,r);
    rotateRect(logical.data(),physical.data(),r);
    for(int y=0;y<PHYSICAL_H;++y) for(int x=0;x<PHYSICAL_W;++x) {
        const bool inside=x>=rotated.x && x<rotated.x+rotated.w && y>=rotated.y && y<rotated.y+rotated.h;
        if(!inside) assert(physical[y*PHYSICAL_W+x]==0xeeee);
        else {
            const auto p=logicalPoint(true,x,y);
            assert(physical[y*PHYSICAL_W+x]==logical[static_cast<int>(p.second)*W+static_cast<int>(p.first)]);
        }
    }
    const auto origin=logicalPoint(false,51,207);
    assert(origin.first==51 && origin.second==207);
    configureOrientation(false);
    assert(W==1404 && H==1872 && RDP_H==1760);
    for(bool landscape:{false,true}) {
        configureOrientation(landscape);
        for(int scale:{50,75,100,125}) for(int height:{RDP_H,700,240}) for(float zoom:{1.0f,1.5f,3.0f}) {
            const int rw=W*scale/100,rh=RDP_H*scale/100;
            const auto t=makeTransform(rw,rh,W,height,zoom);
            assert(t.scale>0 && t.maxX>=0 && t.maxY>=0);
            assert(near(t.scale,std::min(float(W)/rw,float(height)/rh)*zoom));
            assert(t.contains(W/2.0f,height/2.0f));
            assert(!t.contains(W/2.0f,height+1));
            if(t.offsetX>1) assert(!t.contains(t.offsetX-1,height/2.0f));
            if(t.offsetY>1) assert(!t.contains(W/2.0f,t.offsetY-1));
            if(zoom==1) assert(near(t.maxX,0) && near(t.maxY,0));
        }
        inputAndViewportTests();
    }
    configureOrientation(false);
    std::puts("NATIVE_RDP_KEYS_WHEEL_VIEWPORT_RETRY_IDLE_TESTS_PASS");
    std::puts("NATIVE_RDP_ORIENTATION_RASTER_TOUCH_PROFILES_PASS");
    std::puts("NATIVE_RDP_PASSWORD_CERTIFICATE_PROFILE_KEY_TESTS_PASS");
}
