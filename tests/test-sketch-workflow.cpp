#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 SketchRaster board(nullptr,dir.path()+"/cache",dir.path()+"/Documents");
 board.image.fill(qRgb(127,127,127));
 auto result=board.exportPng(QString::fromUtf8("  Łąka 01.PNG  "));
 assert(result["ok"].toBool());auto path=result["path"].toString();
 assert(path==dir.path()+QString::fromUtf8("/Documents/Łąka 01.png"));
 QImage saved(path);assert(saved==board.image);
 board.image.fill(Qt::white);
 auto collision=board.exportPng(QString::fromUtf8("Łąka 01"));
 assert(!collision["ok"].toBool()&&collision["exists"].toBool());assert(QImage(path)==saved);
 assert(board.exportPng(QString::fromUtf8("Łąka 01"),true)["ok"].toBool());assert(QImage(path)==board.image);
 for(const auto &bad:QStringList{"../escape","/absolute","x/y","a\\b","..","","name\nline",QString(241,'a')})assert(!board.exportPng(bad)["ok"].toBool());
 assert(board.loadNotebook().isEmpty());
 SketchRaster ink(nullptr,dir.path()+"/ink");ink.setInputTransform(0,0,1,1);
 ink.begin();ink.penSamples.push(100,100,.6);double p=ink.pressureAt(100,100,.5);
 assert(ink.advance(1,12,1,100,100,p,true));
 ink.penSamples.push(120,140,.7);ink.penSamples.push(150,180,.9);
 ink.penSamples.push(180,140,.8);ink.penSamples.push(200,100,.7);
 p=ink.pressureAt(200,100,.5);assert(ink.advance(1,12,1,200,100,p,false));
 assert(qRed(ink.image.pixel(150,180))<250);assert(qRed(ink.image.pixel(150,100))==255);
 assert(ink.rawReplayStats()[0].toInt()>=3&&ink.rawReplayStats()[1].toInt()<=64);
 ink.penSamples.push(240,100,.8,2);p=ink.pressureAt(240,100,.5);ink.advance(1,12,1,240,100,p,false);
 assert(qRed(ink.image.pixel(220,100))==255);
 auto replayed=ink.rawReplayStats()[0].toInt();
 p=ink.pressureAt(300,250,.6);ink.advance(1,12,1,300,250,p,false);
 ink.penSamples.push(290,230,.7,2);ink.penSamples.push(310,270,.8,2);p=ink.pressureAt(310,270,.5);ink.advance(1,12,1,310,270,p,false);
 assert(ink.rawReplayStats()[0].toInt()==replayed);
 ink.finish();
 SketchRaster pages(nullptr,dir.path()+"/pages");
 auto document=[](std::initializer_list<int> pageIds){
  QJsonArray list;for(int slot:pageIds)list.append(QJsonObject{{"strokes",QJsonArray()},{"paper","plain"},{"bitmap",true},{"revision",1},{"cacheSlot",slot}});
  auto book=QJsonDocument(QJsonObject{{"version",1},{"index",0},{"pages",list},{"nextCacheSlot",3}}).toJson(QJsonDocument::Compact);
  return QString::fromUtf8(QJsonDocument(QJsonObject{{"document",QString::fromUtf8(book)}}).toJson(QJsonDocument::Compact));
 };
 pages.image.fill(qRgb(20,20,20));pages.saveNotebook(document({0}),0,"p0");assert(pages.flushSaves());
 pages.image.fill(qRgb(80,80,80));pages.materialReady=false;pages.saveNotebook(document({0,1}),1,"p1");assert(pages.flushSaves());
 pages.image.fill(qRgb(140,140,140));pages.materialReady=false;pages.saveNotebook(document({0,1,2}),2,"p2");assert(pages.flushSaves());
 QFile orphan(pages.cachePath(7)+".material");assert(orphan.open(QIODevice::WriteOnly));orphan.write("old orphan");orphan.close();
 assert(QFile::exists(pages.cachePath(1)+".material"));
 pages.saveNotebook(document({0,2}),2,"p2");assert(pages.flushSaves());
 assert(!QFile::exists(pages.cachePath(1)+".material"));assert(QFile::exists(pages.cachePath(0)+".material")&&QFile::exists(pages.cachePath(2)+".material")&&QFile::exists(pages.cachePath(7)+".material"));
 SketchRaster reopened(nullptr,dir.path()+"/pages");assert(reopened.loadCache(2,"p2"));assert(reopened.image==pages.image);

 printf("PASS named atomic Documents PNG, collision/path validation, grayscale export, coalesced curved input and contact separation\n");
}
