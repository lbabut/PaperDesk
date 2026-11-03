#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
class InputWindow:public QQuickWindow {
public:
 int delivered=0;
 bool event(QEvent *e)override{
  if(e->type()==QEvent::MouseMove||e->type()==QEvent::MouseButtonPress||e->type()==QEvent::MouseButtonRelease||e->type()==QEvent::TouchBegin){delivered++;return true;}
  return QQuickWindow::event(e);
 }
};
int main(int argc,char **argv){
 QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);QGuiApplication app(argc,argv);
 QTemporaryDir dir;SketchRaster board(nullptr,dir.path());InputWindow window,other;
 window.resize(1000,1000);window.show();app.processEvents();window.delivered=0;
 board.setInputTransform(100,100,.5,.5);board.setInputWindow(&window);board.setRawPenInputEnabled(true);
 auto send=[&](QEvent::Type type,QPointF p,Qt::MouseButton button=Qt::NoButton,Qt::MouseButtons buttons=Qt::NoButton){
  QMouseEvent event(type,p,p,button,buttons,Qt::NoModifier);QCoreApplication::sendEvent(&window,&event);
 };
 send(QEvent::MouseMove,{200,200});assert(window.delivered==1); // entry clears old hover
 send(QEvent::MouseMove,{201,200});assert(window.delivered==1);
 send(QEvent::MouseButtonPress,{201,200},Qt::LeftButton,Qt::LeftButton);assert(window.delivered==1);
 send(QEvent::MouseMove,{20,20},Qt::NoButton,Qt::LeftButton);assert(window.delivered==1);
 send(QEvent::MouseButtonRelease,{20,20},Qt::LeftButton);assert(window.delivered==1);
 send(QEvent::MouseMove,{20,20});assert(window.delivered==2);
 send(QEvent::MouseButtonPress,{20,20},Qt::LeftButton,Qt::LeftButton);assert(window.delivered==3);
 send(QEvent::MouseMove,{201,200},Qt::NoButton,Qt::LeftButton);assert(window.delivered==4); // toolbar drag
 send(QEvent::MouseButtonRelease,{201,200},Qt::LeftButton);assert(window.delivered==5);
 QEvent touch(QEvent::TouchBegin);QCoreApplication::sendEvent(&window,&touch);assert(window.delivered==6);
 QMouseEvent foreign(QEvent::MouseMove,{200,200},{200,200},Qt::NoButton,Qt::NoButton,Qt::NoModifier);assert(!board.eventFilter(&other,&foreign));
 board.setRawPenInputEnabled(false);send(QEvent::MouseMove,{201,200});assert(window.delivered==7);
 board.setRawPenInputEnabled(true); // direct press without hover: forward complete gesture
 send(QEvent::MouseButtonPress,{200,200},Qt::LeftButton,Qt::LeftButton);
 send(QEvent::MouseMove,{202,200},Qt::NoButton,Qt::LeftButton);
 send(QEvent::MouseButtonRelease,{202,200},Qt::LeftButton);assert(window.delivered==10);
 send(QEvent::MouseButtonPress,{200,200},Qt::LeftButton,Qt::LeftButton);
 send(QEvent::MouseMove,{20,20});assert(window.delivered==11); // lost release recovers
 board.release();send(QEvent::MouseMove,{200,200});assert(window.delivered==12);
 board.setRawPenInputEnabled(true);
 send(QEvent::MouseMove,{200,200});send(QEvent::MouseMove,{201,200});
 send(QEvent::MouseButtonPress,{201,200},Qt::LeftButton,Qt::LeftButton);
 int count=window.delivered;
 send(QEvent::MouseButtonRelease,{201,200},Qt::RightButton,Qt::LeftButton);assert(window.delivered==count+1);
 send(QEvent::MouseMove,{20,20},Qt::NoButton,Qt::LeftButton);assert(window.delivered==count+1);
 send(QEvent::MouseButtonRelease,{20,20},Qt::LeftButton);assert(window.delivered==count+1);
 QPointingDevice pen("unit-pen",99,QInputDevice::DeviceType::Stylus,QPointingDevice::PointerType::Pen,
   QInputDevice::Capability::Position|QInputDevice::Capability::Pressure|QInputDevice::Capability::Hover,1,1);
 auto tablet=[&](QEvent::Type type,Qt::MouseButton button,Qt::MouseButtons buttons){
  QTabletEvent event(type,&pen,{200,200},{200,200},.5,0,0,0,0,0,Qt::NoModifier,button,buttons);
  return board.eventFilter(&window,&event);
 };
 assert(!tablet(QEvent::TabletMove,Qt::NoButton,Qt::NoButton));
 assert(tablet(QEvent::TabletMove,Qt::NoButton,Qt::NoButton));
 assert(tablet(QEvent::TabletPress,Qt::LeftButton,Qt::LeftButton));
 assert(tablet(QEvent::TabletRelease,Qt::LeftButton,Qt::NoButton));
 board.setRawPenInputEnabled(false);board.setRawPenInputEnabled(true);
 send(QEvent::MouseButtonPress,{200,200},Qt::LeftButton,Qt::LeftButton);assert(board.mouseCapture.forwarded);
 send(QEvent::MouseMove,{201,200});assert(!board.mouseCapture.forwarded&&!board.mouseCapture.captured);
 assert(board.pointerFilterStats()["consumed"].toUInt()>0);
 assert(board.penInputStats()[0].toInt()==0); // filtering never creates material input
 puts("PASS scoped raw-mode pointer filter: entry/exit, complete contacts, toolbar drags, touch/foreign windows, direct tap, lost release, disable/release");
}
