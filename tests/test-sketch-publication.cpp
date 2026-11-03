#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QThread>
#include <QtCore/QEventLoop>
#include <QtQuick/QQuickWindow>
#include <QtQuick/QSGRendererInterface>
#include <cassert>
#include <functional>

static void events(int milliseconds){QElapsedTimer timer;timer.start();while(timer.elapsed()<milliseconds){QCoreApplication::processEvents();QThread::msleep(1);}}
static void pendingStroke(SketchRaster &board){board.begin();assert(board.advance(4,38,1,200,300,.6,true));assert(board.advance(4,38,1,220,330,.8,false));}
// Await a real completed frame caused by show()/tile damage. The timer is
// only a failure deadline; this helper never requests a full-window repaint.
static void renderedFrame(QQuickWindow &window,const std::function<bool()> &ready){
 QEventLoop loop;QTimer deadline;deadline.setSingleShot(true);deadline.setInterval(5000);
 auto connection=QObject::connect(&window,&QQuickWindow::afterRendering,&loop,[&]{if(ready())loop.quit();},Qt::DirectConnection);
 QObject::connect(&deadline,&QTimer::timeout,&loop,&QEventLoop::quit);
 deadline.start();if(!ready())loop.exec();QObject::disconnect(connection);assert(ready());
}
class PaintCountTile:public SketchTile {
public:
 std::atomic<int> paintCount{0};
 using SketchTile::SketchTile;
 void paint(QPainter *painter)override{SketchTile::paint(painter);paintCount++;}
};
int main(int argc,char **argv){
 QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
 QGuiApplication application(argc,argv);QTemporaryDir directory;assert(directory.isValid());
 // Zero-pressure onset must neither publish white pixels nor throttle the
 // real contact that follows at exactly the same position.
 for(int tool : {0,1,2,3,4,5,8}){
  SketchRaster onset(nullptr,directory.path()+QString("/onset-%1").arg(tool));
  int emitted=0;QObject::connect(&onset,&SketchRaster::damaged,[&](const QRegion&){emitted++;});
  auto white=onset.image;onset.begin();
  assert(onset.advance(tool,16,1,220,300,0,true));
  assert(emitted==0&&!onset.displayPublicationTimer.isActive()&&onset.image==white);
  assert(onset.advance(tool,16,1,220,300,.7,false));
  assert(emitted==1&&onset.image!=white);
  auto dot=onset.image;assert(!onset.advance(tool,16,1,220,300,.7,false));assert(onset.image==dot);
  onset.finish();
 }
 SketchRaster batched(nullptr,directory.path()+"/batched"),immediate(nullptr,directory.path()+"/immediate");
 int batchEmissions=0,immediateEmissions=0;QRegion batchDamage,immediateDamage;
 QObject::connect(&batched,&SketchRaster::damaged,[&](const QRegion&r){batchEmissions++;batchDamage+=r;});
 QObject::connect(&immediate,&SketchRaster::damaged,[&](const QRegion&r){immediateEmissions++;immediateDamage+=r;});
 batched.begin();immediate.begin();immediate.livePublication=false;
 for(int i=0;i<1260;i++){
  int pass=i/60,step=i%60;double x=120+960.*pass/20,y=900+300.*(pass%2?59-step:step)/59,p=.125+.75*step/59;
  assert(batched.advance(4,38,1,x,y,p,i==0));assert(immediate.advance(4,38,1,x,y,p,i==0));
  if(i==0)assert(batchEmissions==1); // first dab is visible before the event loop
 }
 assert(batchEmissions==1&&immediateEmissions==1260);
 // Every raw sample already reached the authoritative pixels/material, even
 // though its notification is queued. No pressure or media state is skipped.
 assert(batched.image==immediate.image&&batched.material==immediate.material&&batched.finger==immediate.finger);
 assert(batched.physics.burnish==immediate.physics.burnish&&batched.physics.wear==immediate.physics.wear);
 batched.finish();immediate.finish();assert(batchEmissions==2&&batchDamage==immediateDamage);
 events(40);assert(batchEmissions==2&&!batched.displayPublicationTimer.isActive());

 SketchRaster timed(nullptr,directory.path()+"/timed");int timedEmissions=0;
 QObject::connect(&timed,&SketchRaster::damaged,[&](const QRegion&){timedEmissions++;});
 pendingStroke(timed);assert(timedEmissions==1&&timed.displayPublicationTimer.interval()==16);
 QElapsedTimer wait;wait.start();while(timedEmissions<2&&wait.elapsed()<500)events(1);
 assert(timedEmissions==2&&timed.displayPending.isEmpty());timed.finish();events(40);assert(timedEmissions==2);

 auto image=batched.image,mass=batched.material,finger=batched.finger;int beforeCancel=batchEmissions;
 batched.begin(true);assert(batched.advance(7,64,1,300,1000,.7,true));assert(batched.advance(7,64,1,320,1000,.7,false));
 batched.cancel();assert(batched.image==image&&batched.material==mass&&batched.finger==finger);
 int afterCancel=batchEmissions;assert(afterCancel==beforeCancel+2);events(40);assert(batchEmissions==afterCancel);

 pendingStroke(timed);int beforeReset=timedEmissions;timed.resetWhite();assert(timedEmissions==beforeReset+1);
 assert(timed.displayPending.isEmpty()&&!timed.livePublication);events(40);assert(timedEmissions==beforeReset+1);
 pendingStroke(timed);int beforeRelease=timedEmissions;timed.release();events(40);
 assert(timedEmissions==beforeRelease&&timed.image.isNull()&&timed.displayPending.isEmpty());

 SketchRaster source(nullptr,directory.path()+"/page");QString meta="page-publication-fixture";
 assert(source.saveCache(3,meta)&&source.flushSaves());pendingStroke(source);
 int loadEmissions=0;QObject::connect(&source,&SketchRaster::damaged,[&](const QRegion&r){assert(r==QRegion(source.image.rect()));loadEmissions++;});
 assert(source.loadCache(3,meta));assert(loadEmissions==1&&source.displayPending.isEmpty());events(40);assert(loadEmissions==1);
 {
  SketchRaster tiled(nullptr,directory.path()+"/two-tiles");QQuickWindow window;
  window.resize(256,128);window.setColor(Qt::white);
  PaintCountTile left(window.contentItem()),right(window.contentItem());
  left.setWidth(128);left.setHeight(128);left.setEnabled(false);left.setRaster(&tiled);
  right.setX(128);right.setWidth(128);right.setHeight(128);assert(right.setProperty("sourceX",128));right.setRaster(&tiled);
  window.show();renderedFrame(window,[&]{return left.paintCount.load()>0&&right.paintCount.load()>0;});
  const int previousLeft=left.paintCount.load(),previousRight=right.paintCount.load();
  int emissions=0;QObject::connect(&tiled,&SketchRaster::damaged,[&](const QRegion&){emissions++;});
  tiled.begin();assert(tiled.advance(4,38,1,20,20,.6,true));assert(tiled.advance(4,38,1,80,80,.8,false));
  assert(emissions==1&&!tiled.displayPending.isEmpty()&&tiled.displayPublicationTimer.interval()==16);
  renderedFrame(window,[&]{return emissions==2&&left.paintCount.load()>previousLeft&&left.opticalPixels(76,76,8,8)==tiled.pixels(76,76,8,8);});
  assert(right.paintCount.load()==previousRight);tiled.finish();assert(emissions==2);
 }
 {
  const auto path=directory.path()+"/preview-permit";
  SketchRaster permit(nullptr,directory.path()+"/permit",QString(),path);
  const QString command="fine 10 20 200 300 3 1 .15 .5 .95";
  assert(permit.writePreviewPermit(command));std::atomic<bool> stop{false};
  std::thread reader([&]{while(!stop){QFile file(path);assert(file.open(QIODevice::ReadOnly));auto bytes=file.readAll();assert(bytes=="off"||bytes==command.toUtf8());}});
  for(int i=0;i<100;i++)assert(permit.writePreviewPermit(i%2?command:QString("off")));
  stop=true;reader.join();assert(!permit.writePreviewPermit("fine bad\nsecond line"));
 }
 {
  SketchRaster repair(nullptr,directory.path()+"/preview-repair");
  repair.begin();repair.advance(1,3,1,20,20,.7,true);repair.finish(true);
  assert(!repair.previewRepair.isEmpty());
  repair.begin();repair.advance(1,3,1,200,200,.7,true);repair.finish(true);
  QRegion repaired;QObject::connect(&repair,&SketchRaster::damaged,[&](const QRegion&r){repaired+=r;});
  auto exact=repair.image,mass=repair.material;repair.repairPreview();
  assert(repaired.contains(QPoint(20,20))&&repaired.contains(QPoint(200,200)));
  assert(repair.previewRepair.isEmpty()&&repair.image==exact&&repair.material==mass);
  repair.begin();repair.advance(1,3,1,40,40,.7,true);repair.finish(true);repair.resetWhite();
  assert(repair.previewRepair.isEmpty());
 }
 puts("PASS first-dab immediacy, 16ms timer publication, untouched tile not repainted, full-shading physical equality, exact damage union, finish/cancel/reset/release/load lifecycle");
}
