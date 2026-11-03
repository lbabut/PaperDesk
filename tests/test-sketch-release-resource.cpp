// Verify prepared release bytecode contains the exact drawing sources tested.
#include <QtCore/QCoreApplication>
#include <QtCore/QFile>
#include <QtCore/QResource>
#include <cassert>
#include <cstdio>
int main(int argc,char**argv){
 QCoreApplication app(argc,argv);
 const QString root="product/payload/apps/papersketch/";
 assert(QResource::registerResource(root+"resources.rcc","/release-check"));
 for(const char* name:{"ui/main.qml","ui/native-tile.qml","ui/ToolIcon.qml","engine.js"}){
  QFile source(root+name),compiled(QString(":/release-check/")+name);
  assert(source.open(QIODevice::ReadOnly)&&compiled.open(QIODevice::ReadOnly));
  assert(source.readAll()==compiled.readAll());
 }
 puts("PASS: prepared Sketch RCC contains the exact tested QML, tile, icon and engine sources");
}
