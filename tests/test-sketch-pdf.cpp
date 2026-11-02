#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QProcess>
#include <cassert>
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
 SketchRaster raster(nullptr,dir.path()+"/cache");
 for(int y=0;y<1600;y++)for(int x=0;x<1200;x++){int g=(x/5+y/7)%256;raster.image.setPixel(x,y,qRgb(g,g,g));}
 auto digest=raster.opticalDigest();auto document=raster.loadNotebook();
 auto a=raster.exportPdf(QString::fromUtf8("  Łąka 100% #.PDF  "));assert(a["ok"].toBool());
 auto path=a["path"].toString();assert(a["title"].toString()==QString::fromUtf8("Łąka 100% #"));
 QFile f(path);assert(f.open(QIODevice::ReadOnly));auto bytes=f.readAll();f.close();assert(bytes.startsWith("%PDF-")&&bytes.contains("%%EOF"));
 QProcess extract;extract.start("pdfimages",{"-png",path,dir.path()+"/image"});assert(extract.waitForFinished()&&extract.exitCode()==0);
 QImage image(dir.path()+"/image-000.png");assert(image.size()==QSize(1200,1600));assert(image.convertToFormat(QImage::Format_RGB32)==raster.image);
 QProcess info;info.start("pdfinfo",{path});assert(info.waitForFinished()&&info.exitCode()==0);auto text=info.readAllStandardOutput();bool onePage=false;for(const auto &line:QString::fromUtf8(text).split(QChar(10)))if(line.startsWith("Pages:"))onePage=line.mid(6).trimmed().toInt()==1;assert(onePage&&text.contains("600 x 800 pts"));
 auto b=raster.exportPdf(QString::fromUtf8("Łąka 100% #"));assert(b["ok"].toBool()&&b["path"]!=a["path"]);assert(QFile::exists(path));
 for(auto bad:QStringList{"../escape","/absolute","x/y",QString("a")+QChar(92)+"b","..","",QString("bad")+QChar(10),QString(241,'a')})assert(!raster.exportPdf(bad)["ok"].toBool());
 assert(raster.opticalDigest()==digest&&raster.loadNotebook()==document);
 assert(!raster.discardPdfExport(dir.path()+"/unrelated.pdf"));
 assert(raster.discardPdfExport(path));assert(!QFile::exists(path));
 assert(raster.discardPdfExport(b["path"].toString()));
 puts("PASS atomic named one-page PDF, exact lossless 1200x1600 grayscale image, independent copies, path validation and drawing preservation");
}
