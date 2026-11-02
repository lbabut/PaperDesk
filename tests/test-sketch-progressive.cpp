#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QEventLoop>
#include <QtCore/QThread>
#include <QtQuick/QQuickWindow>
#include <QtQuick/QSGRendererInterface>
#include <functional>
#include <cassert>
#include <cstdio>

static void equal(const SketchRaster&a,const SketchRaster&b){
 assert(a.image==b.image);assert(a.material==b.material);assert(a.finger==b.finger);
 assert(a.physics.burnish==b.physics.burnish);assert(a.physics.wear==b.physics.wear);
 assert(a.physics.ink==b.physics.ink);
}
static bool dark(const QVariantList &pixels){for(int i=0;i<pixels.size();i+=4)if(pixels[i].toInt()<250)return true;return false;}
int main(int argc,char **argv){
 QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
 QGuiApplication app(argc,argv);QTemporaryDir dir;
 SketchRaster exact(nullptr,dir.path()+"/exact"),quick(nullptr,dir.path()+"/quick");
 // Incl. repeated/zero pressure, pressure calibration, tilt, loaded paper,
 // multiple strokes and 700-point bursts with periodic delivery (no input loss).
 for(int stock=0;stock<3;stock++)for(int tool=0;tool<6;tool++){
  exact.setMaterialOptions(stock,false);quick.setMaterialOptions(stock,false);
  exact.pressureCurve.calibrated=quick.pressureCurve.calibrated=true;
  exact.pressureCurve.anchors=quick.pressureCurve.anchors={{.1,.4,.9}};
  exact.begin();quick.beginProgressive();
  int damageEvents=0;auto connection=QObject::connect(&quick,&SketchRaster::damaged,[&](const QRegion&){damageEvents++;});
  for(int i=0;i<700;i++){
   double x=i<3?240:240+(i%180)*2.1,y=200+stock*130+(i%27)*.7;
   double p=i==0?0:i==1?.15:(i%57)/56.;
   if(tool>=4&&i>360){exact.advancePoint(tool,30,.8,x,y,p,i==0,.7,.3);quick.dispatchPoint(tool,30,.8,x,y,p,i==0,.7,.3);}
   else{exact.advance(tool,tool<4?12:30,.8,x,y,p,i==0);quick.advance(tool,tool<4?12:30,.8,x,y,p,i==0);}
   if(i==1){assert(damageEvents>0);assert(!quick.previewLayer.isNull());}
   assert(quick.previewPoints.size()<=512);
   if(i%17==0)quick.pollProgressive();
  }
  exact.finish();quick.finish();equal(exact,quick);
  assert(quick.previewLayer.isNull()&&!quick.progressive);
  QObject::disconnect(connection);
 }
 // Cancel after some exact tiles have already been delivered restores the
 // original page, with no mutation of pigment, wear, ink or fingertip.
 auto before=quick.image,mass=quick.material;auto wear=quick.physics.wear;
 quick.beginProgressive();quick.advance(4,38,1,600,600,.7,true);
 quick.progressive->close();quick.pollProgressive();assert(quick.image!=before);
 quick.cancel();assert(quick.image==before&&quick.material==mass&&quick.physics.wear==wear);
 // Save while a stroke is outstanding drains exact work before serialization;
 // a subsequent point continues the stroke without a spurious origin segment.
 exact.begin();quick.beginProgressive();
 exact.advance(1,12,1,500,600,.7,true);quick.advance(1,12,1,500,600,.7,true);
 assert(quick.saveCache(3,"progressive-save")&&quick.flushSaves());assert(!quick.progressive);equal(exact,quick);
 exact.advance(1,12,1,520,610,.8,false);quick.advance(1,12,1,520,610,.8,false);
 exact.finish();quick.finish();equal(exact,quick);
 // Paint the actual native tile: provisional ink exists while exact pixels
 // are still white; delivery swaps in exact pixels without a blank tile.
 {
  SketchRaster board(nullptr,dir.path()+"/tile");SketchTile tile;
  tile.setWidth(128);tile.setHeight(128);tile.setRaster(&board);
  board.beginProgressive();board.progressiveTimer.stop();board.advance(4,30,1,64,64,.7,true);
  auto white=board.image;QImage surface(128,128,QImage::Format_RGB32);
  {QPainter p(&surface);tile.paint(&p);}assert(dark(tile.pixels(58,58,12,12)));assert(board.image==white);
  board.progressive->close();board.pollProgressive();board.flushDisplayDamage();
  {QPainter p(&surface);tile.paint(&p);}
  assert(board.previewPoints.empty()&&tile.opticalPixels(58,58,12,12)==board.pixels(58,58,12,12));
  auto shown=tile.pixels(58,58,12,12);assert(dark(shown));for(int i=0;i<shown.size();i+=4)assert(shown[i].toInt()==0||shown[i].toInt()==255);
  board.finish();
 }
 // A reader can snapshot the GUI wrapper, trigger a detach, and release
 // that snapshot before the worker reads another distant tile. The separately
 // owned backing must keep the raw source pixel storage alive until join.
 {
  SketchRaster reference(nullptr,dir.path()+"/reader-ref"),readerBoard(nullptr,dir.path()+"/reader");
  reference.begin();readerBoard.beginProgressive();
  reference.advance(1,16,1,100,200,.7,true);readerBoard.advance(1,16,1,100,200,.7,true);
  QImage reader=readerBoard.image;QElapsedTimer wait;wait.start();
  while(readerBoard.progressiveUndo.empty()&&wait.elapsed()<5000){readerBoard.pollProgressive();QThread::msleep(1);}
  assert(!readerBoard.progressiveUndo.empty());reader=QImage();
  reference.advance(1,16,1,700,900,.8,false);readerBoard.advance(1,16,1,700,900,.8,false);
  reference.finish();readerBoard.finish();equal(reference,readerBoard);
 }
 // Every lifecycle boundary joins pending work before replacing/releasing it.
 quick.beginProgressive();quick.advance(4,30,1,100,200,.8,true);quick.resetWhite();assert(!quick.progressive&&quick.image.pixelColor(100,200)==Qt::white);
 quick.beginProgressive();quick.advance(4,30,1,100,200,.8,true);quick.release();assert(!quick.progressive&&quick.image.isNull());
 puts("PASS progressive: synchronous preview, exact pigment/image/wear/calibration/tilt across 18 loaded trajectories, bounded queues, cancel after delivery, save drain/continue and lifecycle joins");
}
