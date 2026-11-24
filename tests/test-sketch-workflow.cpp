#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <limits>
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 const auto nan=std::numeric_limits<double>::quiet_NaN();
 SketchRaster validation(nullptr,dir.path()+"/validation");validation.begin();
 const auto clean=validation.opticalDigest();
 assert(validation.advance(1,12,1,100,100,0,true));
 assert(validation.opticalDigest()==clean);
 assert(!validation.advance(1,nan,1,100,100,.5,true));
 assert(!validation.segment({1,12,0,1,8,1,0},{nan,100,.5},{100,100,.5},true));
 assert(!validation.segment({1,12,nan,1,8,1,0},{100,100,.5},{100,100,.5},true));
 assert(!validation.segment({1,12,0,1,8,1,0},{100,100,nan},{100,100,.5},true));
 assert(validation.opticalDigest()==clean);
 assert(SketchRaster::materialPayload(QByteArray::fromHex("ffffffff789c")).isEmpty());
 QByteArray badMass(1200*1600*8+82*81*2,0);uint32_t overflow=0xffffffffu;
 memcpy(badMass.data(),&overflow,4);
 assert(SketchRaster::materialPayload(qCompress(badMass)).isEmpty());
 badMass.fill(0);assert(SketchRaster::materialPayload(qCompress(badMass))==badMass);
 // A plausible Qt length prefix must not permit larger deflate output.
 // qUncompress itself expands this stream despite the forged size prefix.
 QByteArray oversized(badMass.size()*2,0);auto compressedOversized=qCompress(oversized,1);
 auto validCompressed=qCompress(badMass,1);
 memcpy(compressedOversized.data(),validCompressed.constData(),4);
 oversized.clear();oversized.squeeze();
 assert(SketchRaster::materialPayload(compressedOversized).isEmpty());
 assert(SketchRaster::materialPayload(validCompressed.left(validCompressed.size()/2)).isEmpty());
 validation.finish();
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

 // The old 12-page ceiling must not disable tool-state persistence or pruning.
 QJsonArray many;for(int slot=0;slot<13;slot++)many.append(QJsonObject{{"strokes",QJsonArray()},{"paper","plain"},{"bitmap",true},{"revision",1},{"cacheSlot",slot}});
 auto envelope=[&](){return QString::fromUtf8(QJsonDocument(QJsonObject{{"document",QString::fromUtf8(QJsonDocument(QJsonObject{{"version",1},{"index",12},{"pages",many},{"nextCacheSlot",13}}).toJson(QJsonDocument::Compact))}}).toJson(QJsonDocument::Compact));};
 SketchRaster large(nullptr,dir.path()+"/large");large.physics.wear[0]=.3;
 large.image.fill(qRgb(42,42,42));assert(large.saveNotebook(envelope(),12,"p12"));assert(large.flushSaves());
 auto persisted=large.loadNotebook();auto stored=QJsonDocument::fromJson(persisted.toUtf8()).object();
 assert(stored.value("physicalTools").toArray()[0].toDouble()==.3);
 assert(QJsonDocument::fromJson(stored.value("document").toString().toUtf8()).object().value("pages").toArray().size()==13);
 SketchRaster largeReload(nullptr,dir.path()+"/large");assert(largeReload.loadNotebook()==persisted);
 assert(largeReload.loadCache(12,"p12"));assert(largeReload.image==large.image);
 assert(!large.saveNotebook(QString(16*1024*1024+1,'x'),12,"p12"));
 assert(!large.saveNotebook(QString(9*1024*1024,QChar(0x0105)),12,"p12"));
 assert(large.loadNotebook()==persisted);
 many.removeAt(12);assert(large.saveNotebook(envelope(),0,"p0"));assert(large.flushSaves());
 assert(!QFile::exists(large.cachePath(12)+".material"));

 printf("PASS named atomic Documents PNG, collision/path validation, grayscale export, coalesced curved input and contact separation\n");
}
