#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
int main(int argc,char **argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;
 SketchRaster board(nullptr,dir.path());board.setNamespace("preferences-test");board.resetWhite();
 board.begin();board.advance(4,18,1,200,300,.7,true);board.finish();
 auto image=board.image.copy(),mass=board.material.copy();auto state=board.materialState();
 QString raw=R"({"version":1,"selectedTool":4,"sizes":[3,7,9,12,43,28,24,64,2],"kneadedEraser":true})";
 assert(board.loadToolPreferences().isEmpty());assert(board.loadNotebook().isEmpty());
 assert(board.saveToolPreferences(raw));
 assert(board.image==image&&board.material==mass&&board.materialState()==state&&board.loadNotebook().isEmpty());
 QString stored=board.loadToolPreferences();assert(!stored.isEmpty());
 {SketchRaster reopened(nullptr,dir.path());reopened.setNamespace("preferences-test");assert(reopened.loadToolPreferences()==stored);}
 for(QString bad:{QString("{}"),QString("{"),QString(raw).replace("43","81"),QString(raw).replace("\"selectedTool\":4","\"selectedTool\":9"),QString(raw).replace("true","0"),QString(5000,'x')}){
  assert(!board.saveToolPreferences(bad));assert(board.loadToolPreferences()==stored);
 }
 board.setNamespace("other-session");assert(board.loadToolPreferences().isEmpty());
 board.setNamespace("preferences-test");assert(board.loadToolPreferences()==stored);
 puts("PASS independent atomic tool preferences, cold reopen, validation, namespace isolation and drawing preservation");
}
