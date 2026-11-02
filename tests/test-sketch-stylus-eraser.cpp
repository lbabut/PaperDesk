#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
int main(int argc,char **argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;SketchRaster board(nullptr,dir.path());
 assert(board.metaObject()->indexOfMethod("beginProgressive()")<0);
 board.penSamples.pause();board.pressureFd=open("/dev/null",O_RDONLY);assert(board.pressureFd>=0);
 board.setInputTransform(10,20,2,2);
 board.penSamples.push(610,820,.6,10,0,0,true);assert(board.eraserActive(300,400));
 board.penSamples.push(610,820,.5,11,0,0,false);assert(!board.eraserActive(300,400));
 board.penSamples.pause();assert(!board.eraserActive(300,400));
 puts("PASS rear stylus raw tool matching, normal-tip restoration, pause clearing and experimental renderer absence");
}
