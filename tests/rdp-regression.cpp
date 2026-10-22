// Compile with the same ARM SDK and FreeRDP libraries as the actual client.
// No App is constructed, so these tests never connect, open a framebuffer,
// or modify real profiles. Run the resulting binary on the physical tablet.
#define main paperdesk_application_main
#include "../product/payload/apps/paperrdp/paperrdp.cpp"
#undef main
#include <cassert>

int main() {
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
    std::puts("NATIVE_RDP_ORIENTATION_RASTER_TOUCH_PROFILES_PASS");
    std::puts("NATIVE_RDP_PASSWORD_CERTIFICATE_PROFILE_KEY_TESTS_PASS");
}
