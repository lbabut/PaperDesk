#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <future>
#include <QtQml/QQmlEngine>
#include <QtQml/QQmlContext>
#include <QtQml/QQmlComponent>
int main(int argc,char **argv){
 QGuiApplication app(argc,argv);QTemporaryDir directory;assert(directory.isValid());
 SketchRaster board(nullptr,directory.path());board.ensureMaterial();
 assert(!board.researchDeferredEnabled&&!board.researchWorker);
 assert(!board.submitDeferredResearch(5,38,1,120,900,.55,120,900,.55,0));
 auto before=board.opticalDigest();auto material=board.material.copy();auto finger=board.finger.copy();auto physics=board.physics;
 board.rawPointerFiltering=true;assert(!board.setDeferredResearchEnabled(true));board.rawPointerFiltering=false;
 assert(board.setDeferredResearchEnabled(true));auto result=board.researchSurface;
 // A deliberately blocked worker must not prevent owner-thread publication polls.
 std::promise<void> entered, resume;auto gate=resume.get_future().share();
 assert(board.researchWorker->trySubmit([&entered,gate]{entered.set_value();gate.wait();}));
 entered.get_future().wait();
 assert(board.pollDeferredResearch()==0&&board.deferredDisplayDigest()==before);
 resume.set_value();
 std::vector<uint32_t> mass=result->mass,image=result->image;std::vector<uint16_t> f=result->finger;PaperMaterial reference=result->physics;
 assert(!board.submitDeferredResearch(1,38,1,120,900,.55,120,900,.55,0));
 assert(!board.submitDeferredResearch(5,38,1,120,900,.55,120,900,.55,1));
 double px=120,py=900,pp=.55;
 for(int i=0;i<1260;i++){
  double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  assert(board.submitDeferredResearch(5,38,1,px,py,pp,x,y,p,i));
  reference.segment(mass.data(),image.data(),f.data(),5,38,0,1,px,py,pp,x,y,p,i);px=x;py=y;pp=p;
  if(i%23==0)assert(board.pollDeferredResearch()>=0);
 }
 // Live save/export reads ONLY live buffers, never partially computed probe data.
 assert(board.save(directory.filePath("live.png")));assert(QImage(directory.filePath("live.png"))==board.image);
 assert(board.saveCache(0,"live-only")&&board.flushSaves());
 {SketchRaster reopened(nullptr,directory.path());assert(reopened.loadCache(0,"live-only"));assert(reopened.opticalDigest()==before&&reopened.material==material);}
 assert(board.flushDeferredResearch()&&result->completed==1260);
 assert(board.pollDeferredResearch()==1260&&board.researchDisplay==image);
 assert(board.pollDeferredResearch()==1260&&board.deferredDisplayDigest()==board.deferredResearchDigest());
 assert(result->mass==mass&&result->image==image&&result->finger==f);
 assert(result->physics.tooth==reference.tooth&&result->physics.burnish==reference.burnish&&result->physics.ink==reference.ink&&result->physics.wear==reference.wear&&result->physics.untilNext==reference.untilNext&&result->physics.kneadedLift==reference.kneadedLift&&result->physics.kneadedContact==reference.kneadedContact&&result->physics.hasInk==reference.hasInk);
 assert(!board.deferredResearchDigest().isEmpty()&&board.deferredResearchDigest()!=before);
 assert(board.opticalDigest()==before&&board.material==material&&board.finger==finger&&board.physics.wear==physics.wear&&board.physics.tooth==physics.tooth&&board.physics.burnish==physics.burnish&&board.physics.ink==physics.ink&&board.physics.untilNext==physics.untilNext);
 board.release();assert(!board.researchDeferredEnabled&&!board.researchSurface&&!board.researchWorker);
 assert(board.pollDeferredResearch()==-1&&board.deferredDisplayDigest().isEmpty());
 assert(!board.flushDeferredResearch()&&board.deferredResearchDigest().isEmpty());
 board.resetWhite();assert(board.setDeferredResearchEnabled(true));assert(board.submitDeferredResearch(5,38,1,200,200,.5,210,210,.7,0));
 auto pending=board.researchSurface;board.release();assert(pending->completed==1);
 board.resetWhite();assert(board.setDeferredResearchEnabled(true));board.begin();assert(!board.researchDeferredEnabled);assert(!board.setDeferredResearchEnabled(true));board.finish();
 assert(board.setDeferredResearchEnabled(true));board.clearPage();assert(!board.researchDeferredEnabled);
 assert(board.setDeferredResearchEnabled(true));board.resetWhite();assert(!board.researchDeferredEnabled);
 assert(board.setDeferredResearchEnabled(true));board.loadCache(123,"missing");assert(!board.researchDeferredEnabled);
 std::shared_ptr<SketchRaster::ResearchSurface> afterDestruction;
 {SketchRaster temporary(nullptr,directory.filePath("destruction"));assert(temporary.setDeferredResearchEnabled(true));
  afterDestruction=temporary.researchSurface;assert(temporary.submitDeferredResearch(5,38,1,200,200,.5,210,210,.7,0));}
 assert(afterDestruction->completed==1);
 // QML polls the actual backend while work remains queued; isolated offscreen
 // harness, no production page, pointer input, or physical-panel claim.
 board.resetWhite();assert(board.setDeferredResearchEnabled(true));
 px=120;py=900;pp=.55;
 for(int i=0;i<1260;i++){
  double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;
  assert(board.submitDeferredResearch(5,38,1,px,py,pp,x,y,p,i));px=x;py=y;pp=p;
 }
 QQmlEngine engine;engine.rootContext()->setContextProperty("probe",&board);
 QQmlComponent component(&engine);
 component.setData(R"QML(import QtQml
 Timer {
  interval: 1; repeat: true; running: true
  property int polls: 0
  property int previous: 0
  property bool complete: false
  onTriggered: {
   var revision = probe.pollDeferredResearch()
   if (revision < previous) throw new Error("revision regression")
   previous = revision; polls++
   if (revision === 1260) { complete = true; stop(); Qt.quit() }
  }
 }
 )QML",QUrl("qrc:/detached-probe.qml"));
 auto object=std::unique_ptr<QObject>(component.create());
 if(!object){qWarning()<<component.errors();return 2;}
 QObject::connect(&engine,&QQmlEngine::quit,&app,&QCoreApplication::quit);
 QTimer timeout;timeout.setSingleShot(true);QObject::connect(&timeout,&QTimer::timeout,&app,&QCoreApplication::quit);timeout.start(15000);
 app.exec();assert(object->property("complete").toBool());
 assert(board.researchDisplay==image&&board.opticalDigest()==before);
 printf("PASS QML timer publication polls=%d final_revision=1260 exact detached image, live page unchanged\n",object->property("polls").toInt());
 puts("PASS actual SketchRaster opt-in detached lane,validation,1260 exact samples/state,live image/material/save isolation,release barrier and refusal");
}
