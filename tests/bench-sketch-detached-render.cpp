#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QElapsedTimer>
#include <QtCore/QEventLoop>
#include <QtQml/QQmlContext>
#include <QtQml/QQmlComponent>
#include <cassert>
#include <cstdio>
#include <execinfo.h>
#include <csignal>
#include <unistd.h>
#include <ucontext.h>
int main(int argc,char **argv){
#if defined(__arm__)
 struct sigaction action{};action.sa_flags=SA_SIGINFO;action.sa_sigaction=[](int,siginfo_t*,void *context){auto *uc=static_cast<ucontext_t*>(context);for(auto pc:{uc->uc_mcontext.arm_pc,uc->uc_mcontext.arm_lr}){Dl_info info{};dladdr(reinterpret_cast<void*>(pc),&info);fprintf(stderr,"fault address=%lx library=%s symbol=%s offset=%lx\n",pc,info.dli_fname?info.dli_fname:"?",info.dli_sname?info.dli_sname:"?",pc-reinterpret_cast<uintptr_t>(info.dli_fbase));}_exit(139);};sigaction(SIGSEGV,&action,nullptr);
#else
 std::signal(SIGSEGV,[](int){void *stack[48];int n=backtrace(stack,48);backtrace_symbols_fd(stack,n,2);_exit(139);});
#endif
 fprintf(stderr,"stage application\n");
 QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 fprintf(stderr,"stage backend\n");
 SketchRaster board(nullptr,dir.path());board.ensureMaterial();board.setFastDisplay(false);
 board.physics.tiltX=.85;board.physics.tiltY=.35;board.physics.contactAspect=2;board.physics.contactAngle=.3;
 board.researchPublicationStride=argc>1?atoi(argv[1]):1;
 board.researchSynchronous=argc>2&&QString(argv[2])=="sync";
 bool heavy=argc>3&&QString(argv[3])=="heavy";
 assert(board.setDeferredResearchEnabled(true));
 auto initial=board.opticalDigest();auto state=board.researchSurface;
 auto mass=state->mass,image=state->image;auto finger=state->finger;auto reference=state->physics;
 QQuickWindow window;window.resize(1200,1600);window.setColor(Qt::white);
 fprintf(stderr,"stage tiles\n");
 for(int y=0;y<1600;y+=128)for(int x=0;x<1200;x+=128){
  auto tile=new SketchTile(window.contentItem());tile->setPosition(QPointF(x,y));tile->setSize(QSizeF(std::min(128,1200-x),std::min(128,1600-y)));
  tile->setProperty("sourceX",x);tile->setProperty("sourceY",y);tile->setResearch(true);tile->setRaster(&board);
 }
 QQmlEngine engine;engine.rootContext()->setContextProperty("probe",&board);QQmlComponent timer(&engine);
 fprintf(stderr,"stage qml\n");
 timer.setData("import QtQml\nTimer { interval:16; repeat:true; running:true; onTriggered:probe.pollDeferredResearch() }",QUrl("qrc:/render-poll.qml"));
 std::unique_ptr<QObject> poll(timer.create());if(!poll){qWarning()<<timer.errors();return 2;}
 fprintf(stderr,"stage show\n");window.show();QElapsedTimer clock;clock.start();qint64 previous=0,maxGap=0,maxSubmit=0,finished=-1,feedFinished=-1;int sent=0,frames=0,maxPending=0;bool sealed=false;
 double px=120,py=900,pp=.55;
 QTimer feed,heartbeat,timeout;feed.setTimerType(Qt::PreciseTimer);heartbeat.setTimerType(Qt::PreciseTimer);timeout.setSingleShot(true);
 QObject::connect(&heartbeat,&QTimer::timeout,[&]{auto now=clock.nsecsElapsed();if(previous)maxGap=std::max(maxGap,now-previous);previous=now;maxPending=std::max(maxPending,sent-state->completed.load());});
 QObject::connect(&feed,&QTimer::timeout,[&]{
  int budget=24;
  while(sent<1260&&budget--&&clock.elapsed()>=sent*2){
   int i=sent;double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;
   if(heavy){int pass=i/60,step=i%60;x=120+960.*pass/20;y=900+300.*(pass%2?59-step:step)/59;p=.125+.75*step/59;}
   if(i==0){px=x;py=y;pp=p;}
   auto start=clock.nsecsElapsed();bool accepted=board.submitDeferredResearch(5,38,1,px,py,pp,x,y,p,i);maxSubmit=std::max(maxSubmit,clock.nsecsElapsed()-start);
   if(!accepted)break;sent++;px=x;py=y;pp=p;
  }
  if(sent==1260&&!sealed){sealed=board.publishDeferredResearch();if(sealed){feedFinished=clock.nsecsElapsed();feed.stop();}}
 });
 QEventLoop run;
 QObject::connect(&window,&QQuickWindow::frameSwapped,[&]{frames++;if(board.researchRevision==1260&&finished<0){finished=clock.nsecsElapsed();run.quit();}});
 QObject::connect(&timeout,&QTimer::timeout,&run,&QEventLoop::quit);timeout.start(15000);feed.start(1);heartbeat.start(1);run.exec();
 assert(finished>=0&&sealed&&board.flushDeferredResearch());QImage displayed=window.grabWindow().convertToFormat(QImage::Format_RGB32);assert(displayed.size()==QSize(1200,1600));
 px=120;py=900;pp=.55;
 for(int i=0;i<1260;i++){double t=i/1259.,x=120+960*t,y=900+300*t+14*std::sin(i*.17),p=.2+.7*(i%113)/112.;if(heavy){int pass=i/60,step=i%60;x=120+960.*pass/20;y=900+300.*(pass%2?59-step:step)/59;p=.125+.75*step/59;}if(i==0){px=x;py=y;pp=p;}reference.segment(mass.data(),image.data(),finger.data(),5,38,0,1,px,py,pp,x,y,p,i);px=x;py=y;pp=p;}
 assert(state->mass==mass&&state->image==image&&state->finger==finger&&board.researchDisplay==image&&board.opticalDigest()==initial);
 for(int y=0;y<1600;y++)assert(std::equal(image.begin()+y*1200,image.begin()+(y+1)*1200,reinterpret_cast<const uint32_t*>(displayed.constScanLine(y))));
 printf("{\"mode\":\"%s\",\"stride\":%d,\"frames\":%d,\"max_pending\":%d,\"gui_gap_ms\":%.3f,\"submit_max_ms\":%.3f,\"tail_after_submit_ms\":%.3f,\"tail_after_schedule_ms\":%.3f,\"exact\":true}\n",board.researchSynchronous?"sync":"async",board.researchPublicationStride,frames,maxPending,maxGap/1e6,maxSubmit/1e6,(finished-feedFinished)/1e6,finished/1e6-2518);
 // These lifecycle checks are outside measured interval.
 auto awaitFrame=[&]{QEventLoop loop;QTimer limit;limit.setSingleShot(true);auto c=QObject::connect(&window,&QQuickWindow::frameSwapped,&loop,&QEventLoop::quit);QObject::connect(&limit,&QTimer::timeout,&loop,&QEventLoop::quit);limit.start(2000);loop.exec();QObject::disconnect(c);assert(limit.isActive());};
 board.stopDeferredResearch();awaitFrame();auto cleared=window.grabWindow();assert(cleared.pixelColor(900,1100)==QColor(Qt::white));
 // Far-away existing pixel exercises full initial publication on a loaded page.
 board.image.setPixel(1100,100,qRgb(0,0,0));assert(board.setDeferredResearchEnabled(true));
 assert(board.submitDeferredResearch(5,38,1,100,200,.7,100,200,.7,0));
 assert(board.publishDeferredResearch()&&board.flushDeferredResearch());assert(board.pollDeferredResearch()==1);awaitFrame();
 assert(window.grabWindow().pixelColor(1100,100)==QColor(Qt::black));
 board.stopDeferredResearch();awaitFrame();assert(window.grabWindow().pixelColor(1100,100)==QColor(Qt::white));
 puts("PASS rendered lifecycle: detached stop clears tiles; non-white initial page and restart preserved");
}
