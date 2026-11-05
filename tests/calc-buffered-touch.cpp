// Real Qt touch delivery: sequential and buffered sensor-frame handoffs.
#include <QtGui/QGuiApplication>
#include <QtQuick/QQuickWindow>
#include <QtQuick/QQuickItem>
#include <QtQml/QQmlEngine>
#include <QtQml/QQmlComponent>
#include <QtQml/QJSValue>
#include <QtCore/QTemporaryDir>
#include <QtCore/QDebug>
#include <functional>
#include <QtTest/qtesttouch.h>
#include <QtTest/qtestsystem.h>
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);if(argc!=2)return 2;QQmlEngine engine;QTemporaryDir dir;
 QQmlComponent c(&engine,QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
 if(c.isError()){qWarning()<<c.errors();return 2;}
 QQuickWindow window;window.resize(1404,1872);
 auto*root=qobject_cast<QQuickItem*>(c.createWithInitialProperties({{"settingsFile",dir.path()+"/calc.ini"}}));
 if(!root){qWarning()<<c.errors();return 3;}root->setParentItem(window.contentItem());window.show();QTest::qWait(150);
 auto*device=QTest::createTouchDevice(QInputDevice::DeviceType::TouchScreen);
 std::function<QQuickItem*(QQuickItem*,QString)> findItem=[&](QQuickItem*item,QString name)->QQuickItem*{if(item->objectName()==name)return item;for(auto*child:item->childItems())if(auto*found=findItem(child,name))return found;return nullptr;};
 auto key=[&](QString name){auto*k=findItem(root,name);if(!k)qFatal("Missing key");return k->mapToScene(QPointF(k->width()/2,k->height()/2)).toPoint();};
 auto one=key("deskKey20"),plus=key("deskKey23"),eq=key("deskKey24");
 int failures=0;
 for(int batch=0;batch<2;batch++)for(int handoff=0;handoff<2;handoff++){
  QMetaObject::invokeMethod(root,"officeKey",Q_ARG(QVariant,QString("AC")));
  auto t=QTest::touchEvent(&window,device,false);int slot=0;QPoint previous=one;
  if(handoff)t.press(slot,previous).commit(!batch);
  for(int i=handoff?1:0;i<120;i++){
   QPoint next=i==119?eq:(i%2?plus:one);
   if(handoff){int nextSlot=1-slot;t.release(slot,previous).press(nextSlot,next).commit(!batch);previous=next;slot=nextSlot;}
   else {t.press(i%2,next).commit(!batch);t.release(i%2,next).commit(!batch);}
  }
  if(handoff)t.release(slot,previous).commit(!batch);
  QTest::qWait(200);
  const auto state=root->property("desk").value<QJSValue>();
  QString value=state.property("input").toString(),expected;
  for(int i=0;i<59;i++)expected+="1 + ";expected+="1 = 60";
  const bool correct=value=="60"&&state.property("record").toString()==expected;
  qInfo()<<"batch"<<batch<<"handoff"<<handoff<<"result"<<value<<"full receipt correct"<<correct;
  failures+=!correct;
 }
 delete root;return failures?1:0;
}
