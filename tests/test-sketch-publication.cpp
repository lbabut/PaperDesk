#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QThread>
#include <cassert>

static void events(int milliseconds){QElapsedTimer timer;timer.start();while(timer.elapsed()<milliseconds){QCoreApplication::processEvents();QThread::msleep(1);}}
static void pendingStroke(SketchRaster &board){board.begin();assert(board.advance(4,38,1,200,300,.6,true));assert(board.advance(4,38,1,220,330,.8,false));}
int main(int argc,char **argv){
 QGuiApplication application(argc,argv);QTemporaryDir directory;assert(directory.isValid());
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
 puts("PASS first-dab immediacy, 16ms timer publication, full-shading physical equality, exact damage union, finish/cancel/reset/release/load lifecycle");
}
