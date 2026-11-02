#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QProcess>
#include <cassert>
#include <iostream>
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 QString meta=QStringLiteral("{\"bitmap\":true,\"revision\":1,\"strokes\":[],\"paper\":\"plain\"}");
 SketchRaster r(nullptr,dir.path()+"/cache");r.begin();assert(r.advance(8,2,1,100,200,.08,true));assert(r.advance(8,2,1,900,200,.95,false));r.finish();
 assert(r.physics.hasInk);auto image=r.image;auto ink=r.physics.ink;auto digest=r.opticalDigest();
 assert(r.saveCache(0,meta)&&r.flushSaves());
 QFile f(r.cachePath(0)+".material");assert(f.open(QIODevice::ReadOnly));assert(f.readLine()=="PaperSketch material 3\n");f.close();
 SketchRaster reopened(nullptr,dir.path()+"/cache");assert(reopened.loadCache(0,meta));assert(reopened.image==image&&reopened.physics.ink==ink&&reopened.physics.hasInk);
 for(int tool:{7,6}){
  reopened.begin(tool==7);assert(reopened.advance(tool,64,1,60,200,1,true));assert(reopened.advance(tool,64,1,950,200,1,false));reopened.finish();
  assert(reopened.image==image&&reopened.physics.ink==ink);
 }
 reopened.begin(true);reopened.advance(7,64,1,60,200,1,true);reopened.advance(7,64,1,950,200,1,false);reopened.cancel();assert(reopened.image==image&&reopened.physics.ink==ink);
 auto pdf=reopened.exportPdf("Rapidograph");assert(pdf["ok"].toBool());QProcess process;process.start("pdfimages",{"-png",pdf["path"].toString(),dir.path()+"/pdf"});assert(process.waitForFinished()&&process.exitCode()==0);assert(QImage(dir.path()+"/pdf-000.png").convertToFormat(QImage::Format_RGB32)==image);
 assert(reopened.discardPdfExport(pdf["path"].toString()));
 reopened.clearPage();assert(!reopened.physics.hasInk);assert(reopened.saveCache(1,meta)&&reopened.flushSaves());
 QFile old(reopened.cachePath(1)+".material");assert(old.open(QIODevice::ReadOnly));assert(old.readLine()=="PaperSketch material 2\n");old.close();
 assert(r.loadCache(1,meta));assert(!r.physics.hasInk&&std::all_of(r.physics.ink.begin(),r.physics.ink.end(),[](uint8_t v){return v==0;}));
 assert(reopened.loadCache(0,meta)&&reopened.image==image);
 reopened.resetWhite();assert(!reopened.physics.hasInk);
 QByteArray raw(1200*1600*10+82*81*2,0);auto compressed=qCompress(raw,1);assert(SketchRaster::materialPayload(compressed,true,true)==raw);assert(SketchRaster::materialPayload(compressed,true).isEmpty());assert(SketchRaster::materialPayload(compressed.left(compressed.size()/2),true,true).isEmpty());
 std::cout<<"PASS v3 ink cache exact reload, v2 pages/reset without ink leakage, finger cancellation, erasers, bounded decoding and lossless ink PDF"<<std::endl;
}
