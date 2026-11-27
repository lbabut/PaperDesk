#define PAPERDESK_RDP_TESTING
#define main paperdesk_application_main
#include "../product/payload/apps/paperrdp/paperrdp.cpp"
#undef main
#include <cassert>
#include <cstdio>

static void allColors() {
    std::vector<uint8_t> src(4096*4);std::vector<uint16_t> dst(4098,0x19),ref=dst;
    for(unsigned base=0;base<0x1000000;base+=4096) {
        for(unsigned i=0;i<4096;i++) {unsigned c=base+i;src[i*4]=c;src[i*4+1]=c>>8;src[i*4+2]=c>>16;src[i*4+3]=i;
            ref[i+1]=gray565(uint8_t((77*src[i*4+2]+150*src[i*4+1]+29*src[i*4])>>8));}
        auto damage=rdp_render::contiguous(src.data(),dst.data()+1,4096);(void)damage;assert(dst==ref);
    }
    for(int n=0;n<257;n++)for(int mode=0;mode<3;mode++) {
        std::fill(dst.begin(),dst.end(),0x19);ref=dst;
        for(int i=0;i<n;i++){auto v=rdp_render::pixel(src.data()+i*4);if(mode==1||(mode==2&&i%3==0))dst[i+1]=v;ref[i+1]=v;}
        int left=n,right=0;for(int i=0;i<n;i++)if(dst[i+1]!=ref[i+1]){left=std::min(left,i);right=i+1;}
        auto d=rdp_render::contiguous(src.data(),dst.data()+1,n);assert(dst==ref&&d.left==left&&d.right==right);
    }
}

static void frameCase(const char* label,bool landscape,int rw,int rh,float zoom,float vx,int keyboard,int frames,bool sparse) {
    configureOrientation(landscape);Profile p;p.landscape=landscape;
    App scalar(p),fast(p);scalar.fastRows=false;
    freerdp instance{};rdpContext context{};rdpGdi gdi{};
    instance.context=&context;context.gdi=&gdi;gdi.width=rw;gdi.height=rh;gdi.stride=rw*4+16;
    std::vector<BYTE> source(gdi.stride*rh);gdi.primary_buffer=source.data();
    for(App* a:{&scalar,&fast}){a->rdp=&instance;a->mode=Mode::Remote;a->zoom=zoom;a->viewX=vx;a->viewportHeight=RDP_H-keyboard;}
    long long times[2]={};
    for(int f=0;f<frames;f++) {
        for(int y=0;y<rh;y++)for(int x=0;x<rw;x++) {
            auto* q=source.data()+y*gdi.stride+x*4;
            if(!sparse||f==0||(x>=100&&x<120&&y>=120&&y<140)){q[0]=(x*7+y+f*11)&255;q[1]=(x+y*3+f*5)&255;q[2]=(x*3+y*7+f*19)&255;q[3]=f;}
        }
        for(int order=0;order<2;order++) {
            int variant=(f+order)%2;App& a=variant?fast:scalar;
            a.fb.regions.clear();a.dirty=true;a.dirtyTileCount=0;
            for(int t=0;t<DAMAGE_TILE_COUNT;t++){int row=t/DAMAGE_COLS,col=t%DAMAGE_COLS;
                bool marked=!sparse||f==0||(col==100/DAMAGE_TILE_W&&row==120/DAMAGE_TILE_H);
                a.dirtyTiles[t]=marked;a.dirtyTileCount+=marked;}
            auto begin=std::chrono::steady_clock::now();flushRemoteFrame(a,true);
            times[variant]+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-begin).count();
        }
        assert(scalar.fb.storage==fast.fb.storage&&scalar.landscapePixels==fast.landscapePixels);
        assert(scalar.fb.regions==fast.fb.regions&&scalar.fb.updates==fast.fb.updates);
        assert(!scalar.dirty&&!fast.dirty&&scalar.dirtyTileCount==0&&fast.dirtyTileCount==0);
    }
    printf("{\"case\":\"%s\",\"frames\":%d,\"scalar_us\":%lld,\"candidate_us\":%lld,\"exact_pixels_and_regions\":true,\"network\":false,\"optical\":false}\n",label,frames,times[0],times[1]);
    fflush(stdout);
}
// Unlike scalar-vs-NEON equality, this compares sparse EndPaint damage with
// an independent full redraw. Both optimized paths could share a damage bug.
static void movingOutline(bool landscape,int keyboard,float zoom) {
    configureOrientation(landscape);Profile p;p.landscape=landscape;
    App partial(p),full(p);freerdp instance{};PaperContext context{};
    rdpGdi gdi{};gdiBitmap primary{};GDI_DC dc{};GDI_WND wnd{};GDI_RGN invalid{};
    instance.context=&context.context;context.context.gdi=&gdi;context.app=&partial;
    gdi.primary=&primary;primary.hdc=&dc;dc.hwnd=&wnd;wnd.invalid=&invalid;
    gdi.width=W/2;gdi.height=RDP_H/2;gdi.stride=gdi.width*4+16;
    std::vector<BYTE> source(gdi.stride*gdi.height),previous=source;
    gdi.primary_buffer=source.data();
    for(App* a:{&partial,&full}) {
        a->rdp=&instance;a->mode=Mode::Remote;a->viewportHeight=RDP_H-keyboard;
        a->zoom=zoom;a->viewX=zoom>1?17.5f:0;a->viewY=keyboard?31.25f:0;
    }
    for(int frame=0;frame<25;frame++) {
        const int left=30+frame*7,top=40+frame*5;
        for(int y=0;y<gdi.height;y++)for(int x=0;x<gdi.width;x++) {
            bool line=frame<24 && ((x>=left&&x<=left+140&&(y==top||y==top+100)) ||
                      (y>=top&&y<=top+100&&(x==left||x==left+140)));
            BYTE v=line?0:BYTE(170+(x/11+y/13)%70);auto*q=source.data()+y*gdi.stride+x*4;
            q[0]=q[1]=q[2]=v;q[3]=255;
        }
        std::vector<GDI_RGN> rows;
        for(int y=0;y<gdi.height;y++) {
            int leftChanged=gdi.width,rightChanged=0;
            for(int x=0;x<gdi.width;x++)if(std::memcmp(source.data()+y*gdi.stride+x*4,previous.data()+y*gdi.stride+x*4,4)) {
                leftChanged=std::min(leftChanged,x);rightChanged=x+1;
            }
            if(rightChanged>leftChanged){GDI_RGN r{};r.x=leftChanged;r.y=y;r.w=rightChanged-leftChanged;r.h=1;rows.push_back(r);}
        }
        invalid.null=rows.empty();wnd.ninvalid=rows.size();wnd.cinvalid=rows.data();
        assert(endPaint(&context.context));flushRemoteFrame(partial,true);
        full.dirty=true;std::fill(full.dirtyTiles.begin(),full.dirtyTiles.end(),1);
        full.dirtyTileCount=DAMAGE_TILE_COUNT;flushRemoteFrame(full,true);
        assert(partial.fb.storage==full.fb.storage);
        assert(partial.landscapePixels==full.landscapePixels);
        previous=source;
    }
    printf("PASS outline sparse-vs-full: landscape=%d keyboard=%d zoom=%.2f frames=25; not optical/network\n",landscape,keyboard,zoom);
}
int main() {
    allColors();puts("PASS all16777216 RGB values, alpha ignored, edge lengths and exact damage spans");
    frameCase("portrait_1to1_dense",false,1404,1760,1,0,0,12,false);
    frameCase("portrait_1to1_sparse",false,1404,1760,1,0,0,40,true);
    frameCase("landscape_1to1_dense",true,1872,1292,1,0,0,12,false);
    frameCase("scaled_letterbox",false,1920,1080,1,0,0,6,false);
    frameCase("zoom_pan",false,1404,1760,1.5,30.5,0,6,false);
    frameCase("keyboard",false,1404,1760,1,0,6*88,6,false);
    for(bool landscape:{false,true})for(int keyboard:{0,400})for(float zoom:{1.0f,1.5f})
        movingOutline(landscape,keyboard,zoom);
    puts("PASS actual renderer differential matrix; private framebuffer, no profiles/network/QTFB");
}
