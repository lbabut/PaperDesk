
#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
static void blank(const SketchRaster &board){
 const auto *mass=reinterpret_cast<const uint32_t*>(board.material.constBits());
 const auto *pixels=reinterpret_cast<const uint32_t*>(board.image.constBits());
 for(int i=0;i<1200*1600;i++){assert(mass[i]==0);assert(pixels[i]==0xffffffffu);}
}
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;SketchRaster board(nullptr,dir.path());
 board.resetWhite();blank(board);puts("PASS fresh new page has zero pigment");fflush(stdout);
 board.begin();board.advance(5,80,1,300,300,.4,true);board.advance(5,80,1,500,300,.4,false);board.finish();
 board.clearPage();blank(board);puts("PASS cleared page has zero pigment");fflush(stdout);
 for(int tool=0;tool<6;tool++){
  board.resetWhite();board.physics.wear.fill(0);board.setMaterialOptions(2,false);board.begin();
  board.advance(tool,80,1,200,400,.4,true);board.advance(tool,80,1,800,400,.4,false);board.finish();
  auto fresh=board.image,physical=board.material;
  board.clearPage();blank(board);board.physics.wear.fill(0);board.begin();
  board.advance(tool,80,1,200,400,.4,true);board.advance(tool,80,1,800,400,.4,false);board.finish();
  assert(board.image==fresh&&board.material==physical);
 }
 puts("PASS new and cleared pages produce identical pencil and charcoal strokes");
 board.resetWhite();board.material.fill(0xff000000u);
 auto mass=reinterpret_cast<uint32_t*>(board.material.bits());mass[0]=(1234u<<16)|3456u;
 board.image.setPixel(0,0,0xff000000u|uint32_t(board.physics.optical[4690])*0x010101u);
 auto original=board.image;const QString meta="legacy-blank-fixture";
 assert(board.saveCache(2,meta)&&board.flushSaves());
 QFile file(board.cachePath(2)+".material");assert(file.open(QIODevice::ReadOnly));auto disk=file.readAll();file.close();
 SketchRaster restored(nullptr,dir.path());assert(restored.loadCache(2,meta));
 assert(restored.image==original);
 auto repaired=reinterpret_cast<const uint32_t*>(restored.material.constBits());assert(repaired[0]==((1234u<<16)|3456u));
 for(int i=1;i<1200*1600;i++)assert(repaired[i]==0);
 assert(restored.pigmentDiagnostics()["repaired_blank_pixels"].toInt()==1200*1600-1);
 assert(restored.pigmentDiagnostics()["optical_mismatches"].toInt()==0);
 assert(file.open(QIODevice::ReadOnly)&&file.readAll()==disk);file.close();
 assert(restored.saveCache(2,meta)&&restored.flushSaves());
 SketchRaster reopened(nullptr,dir.path());assert(reopened.loadCache(2,meta));assert(reopened.image==original);
 assert(reopened.pigmentDiagnostics()["repaired_blank_pixels"].toInt()==0);
 puts("PASS historical RGB32 blank pigment repaired in memory, marks and saved bytes preserved until explicit Save");

}
