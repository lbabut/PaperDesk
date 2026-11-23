#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
static void equal(SketchRaster &a,SketchRaster &b){
 assert(a.opticalDigest()==b.opticalDigest());assert(a.material==b.material&&a.finger==b.finger);
 assert(a.physics.burnish==b.physics.burnish&&a.physics.tooth==b.physics.tooth&&a.physics.ink==b.physics.ink&&a.physics.wear==b.physics.wear&&a.physics.untilNext==b.physics.untilNext);
}
int main(int argc,char **argv){QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 SketchRaster a(nullptr,dir.filePath("async")),b(nullptr,dir.filePath("sync"));a.setDeferredLiveEnabled(true);
 for(int stroke=0;stroke<4;stroke++){
  a.begin();b.begin();
  for(int i=0;i<320;i++){
   double x=120+2*i,y=700+90*std::sin(i*.2),p=.15+.8*(i%41)/40.,tx=.85*std::sin(i*.01),ty=.35;
   assert(a.advancePenInput(4+stroke%2,38,1,x,y,p,i==0,tx,ty)==b.advancePenInput(4+stroke%2,38,1,x,y,p,i==0,tx,ty));
   if(i==113){assert(a.saveCache(stroke,"midstroke")&&a.flushSaves());equal(a,b);}
  }
  a.finish();b.finish();equal(a,b);assert(!a.researchLive&&!a.researchWorker);
 }
 a.begin();b.begin();assert(a.advancePenInput(5,38,1,230,300,.8,true,.8,.3));assert(b.advancePenInput(5,38,1,230,300,.8,true,.8,.3));
 assert(a.save(dir.filePath("active.png")));equal(a,b);assert(QImage(dir.filePath("active.png"))==b.image);
 a.sharpen(5);b.sharpen(5);equal(a,b);a.finish();b.finish();
 a.begin(true);b.begin(true);a.advance(7,64,1,200,300,.7,true);b.advance(7,64,1,200,300,.7,true);assert(!a.researchLive);a.cancel();b.cancel();equal(a,b);
 a.begin();a.advancePenInput(5,38,1,300,400,.8,true,.8,.3);a.resetWhite();b.resetWhite();equal(a,b);
 a.begin();a.advancePenInput(5,38,1,300,400,.8,true,.8,.3);a.release();assert(a.image.isNull()&&!a.researchLive&&!a.researchWorker);
 puts("PASS actual advancePenInput async: variable pressure/tilt, four strokes, midstroke save/resume, PNG, sharpen, tentative touch cancellation, reset and release");
}
