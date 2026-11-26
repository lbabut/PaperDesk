#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtCore/QCoreApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <cstdio>
static void equal(SketchRaster &a,SketchRaster &b){
 assert(a.image==b.image&&a.material==b.material&&a.finger==b.finger);
 assert(a.physics.burnish==b.physics.burnish&&a.physics.tooth==b.physics.tooth&&a.physics.ink==b.physics.ink&&a.physics.wear==b.physics.wear&&a.physics.untilNext==b.physics.untilNext);
}
int main(int argc,char **argv){
 QCoreApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 SketchRaster a(nullptr,dir.filePath("async"),dir.filePath("exports-a"),dir.filePath("permit-a"),false);
 SketchRaster b(nullptr,dir.filePath("sync"),dir.filePath("exports-b"),dir.filePath("permit-b"),false);
 // Non-white loaded page, including distant pixels outside the new stroke.
 QImage loaded(1200,1600,QImage::Format_RGB32);
 for(int y=0;y<1600;y++)for(int x=0;x<1200;x++)loaded.setPixel(x,y,qRgb((x*7+y)%256,(y*3+x)%256,(x+y*11)%256));
 auto file=dir.filePath("loaded.png");assert(loaded.save(file));
 a.image=QImage(file).convertToFormat(QImage::Format_RGB32);b.image=a.image.copy();
 assert(!a.image.isNull()&&a.ensureMaterial()&&b.ensureMaterial());
 a.setDeferredSeededTilesEnabled(true);a.setDeferredLiveEnabled(true);
 for(int stroke=0;stroke<6;stroke++){
  a.begin();b.begin();
  for(int i=0;i<180;i++){
   double x=std::min(1199.,std::max(0.,30.+6.4*i)),y=30+290*stroke+18*std::sin(i*.19);
   y=std::min(1599.,y);double p=.1+.9*(i%37)/36.,size=stroke%2?80:38;
   int tool=4+stroke%2;
   assert(a.advancePenInput(tool,size,1,x,y,p,i==0,.8,-.5));assert(b.advancePenInput(tool,size,1,x,y,p,i==0,.8,-.5));
   if(i%23==0||i==179){
    // Barrier only for fidelity, not part of a timing claim. Do not settle or
    // copy back authoritative state until after display equality is checked.
    assert(a.publishDeferredResearch());assert(a.flushDeferredResearch());a.pollDeferredResearch();
    assert(a.researchDisplay.size()==1200*1600);
    assert(!memcmp(a.researchDisplay.data(),b.image.constBits(),1200*1600*4));
   }
  }
  a.finish();b.finish();equal(a,b);
 }
 // Seeded transport page reset must not retain stale versions/pending damage.
 DirtyTilesPrototype tiles(5,7,4,true);std::vector<uint32_t> pixels(35,0xff123456),display=pixels;
 pixels[34]=0xff000000;tiles.markRect(1,4,6,4,6);assert(tiles.publishForPage(1,1,pixels));
 auto old=tiles.take();assert(tiles.apply(old,display));assert(display==pixels);
 assert(tiles.beginPage(2));display.assign(35,0xffabcdef);pixels=display;
 assert(!tiles.apply(old,display,2));pixels[0]=0xff777777;tiles.markRect(2,0,0,0,0);
 assert(tiles.publishForPage(2,1,pixels));auto current=tiles.take();assert(tiles.apply(current,display,2));assert(display==pixels);
 puts("PASS seeded loaded-page display at every barrier, exact material/physics, six strokes and page reset; no hardware readers");
}
