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

 board.resetWhite();board.setMaterialOptions(0,false);
 board.begin();board.advance(5,32,1,400,900,.8,true);board.finish();
 const QImage seedMass=board.material.copy(),seedImage=board.image.copy();
 const int before=qGray(seedImage.pixel(400,900));assert(before<200);
 board.pressureCurve.calibrated=true;board.pressureCurve.anchors={{.5,.75,.95}};
 auto restore=[&]{board.material=seedMass.copy();board.image=seedImage.copy();};
 restore();board.begin(false,true);board.advance(6,32,1,400,900,.005,true);board.finish();
 const QImage lightRear=board.image.copy();
 assert(qGray(lightRear.pixel(400,900))>before+20);
 restore();board.begin(false,true);board.advance(6,32,1,400,900,.9,true);board.finish();
 assert(board.image==lightRear);
 // A hover must not erase; the first positive sample can arrive without movement.
 restore();board.begin(false,true);board.advance(6,32,1,400,900,0,true);
 assert(board.image==seedImage);
 board.advance(6,32,1,400,900,.005,false);board.finish();assert(board.image==lightRear);
 // Flipping back clears the override. A manually selected eraser stays pressure-sensitive.
 restore();board.begin();board.advance(6,32,1,400,900,.005,true);board.finish();
 assert(qGray(lightRear.pixel(400,900))>qGray(board.image.pixel(400,900))+15);
 restore();board.begin();board.advance(6,32,1,400,900,1,true);board.finish();
 assert(board.image==lightRear);
 puts("PASS rear contact strength independent of nib calibration, hover gating and nib-pressure restoration");
 puts("PASS rear stylus raw tool matching, normal-tip restoration, pause clearing and experimental renderer absence");
}
