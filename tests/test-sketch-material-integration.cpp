#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QThread>
#include <cassert>
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());SketchRaster b(nullptr,dir.path());
 QVariantList spec{4,24,0,1,8,123,0};b.begin();assert(b.segment(spec,{300,240,1},{300,240,1},true));spec[6]=1;assert(b.segment(spec,{300,240,1},{300,360,1},true));b.finish();
 auto original=b.image;auto originalMass=b.material;
 SketchRaster scalar(nullptr,dir.path()+"/scalar");scalar.begin();assert(scalar.advance(4,24,1,300,240,1,true));
 for(int y=242;y<=360;y+=2)assert(scalar.advance(4,24,1,300,y,1,false));
 scalar.finish();assert(scalar.image==original && scalar.material==originalMass);
 b.begin();assert(b.segment({7,64,0,1,8,124,0},{240,300,1},{240,300,1},true));assert(b.segment({7,64,0,1,8,124,1},{240,300,1},{380,300,1},true));b.finish();auto blended=b.image;auto mass=b.material;auto finger=b.finger;
 assert(b.currentPatches.isEmpty() && b.currentFinger.isNull());
 b.begin(true);b.segment({7,64,0,1,8,125,0},{270,300,1},{270,300,1},true);b.segment({7,64,0,1,8,125,1},{270,300,1},{350,300,1},true);b.cancel();
 assert(b.image==blended && b.material==mass && b.finger==finger);
 bool saved=false;QObject::connect(&b,&SketchRaster::saveCompleted,&b,[&]{saved=true;});
 QString page=R"({"bitmap":true,"revision":2,"strokes":[],"paper":"plain"})",doc=R"({"document":"bitmap-fixture"})";
 b.saveNotebook(doc,0,page);QElapsedTimer wait;wait.start();while(!saved && wait.elapsed()<5000){QCoreApplication::processEvents();QThread::msleep(1);}assert(saved);
 SketchRaster loaded(nullptr,dir.path());assert(loaded.loadNotebook()==doc);assert(loaded.loadCache(0,page));assert(loaded.image==blended && loaded.material==mass && loaded.finger==finger);
 assert(!loaded.loadCache(0,"wrong-cache-key"));
 b.image.save("work/papersketch-native-ink/material-smudge.png");
 printf("PASS material integration: no post-stroke history; tentative palm cancellation restores pigment and fingertip; atomic bitmap reload is identical\\n");
}
