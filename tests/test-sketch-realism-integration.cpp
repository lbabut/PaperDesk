#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>
#include <numeric>

static QString manifest(){
    QJsonArray pages{QJsonObject{{"strokes",QJsonArray()},{"paper","plain"},{"bitmap",true},{"revision",1},{"cacheSlot",0}}};
    auto book=QJsonDocument(QJsonObject{{"version",1},{"index",0},{"pages",pages}}).toJson(QJsonDocument::Compact);
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"document",QString::fromUtf8(book)}}).toJson(QJsonDocument::Compact));
}
int main(int argc,char **argv){
    QGuiApplication app(argc,argv);QTemporaryDir dir;assert(dir.isValid());
    const QString meta=R"({"bitmap":true,"revision":1,"strokes":[],"paper":"plain"})";
    // A missing page after closing must not be imported through a null pointer
    // or silently converted to a new white page by maintenance/calibration.
    SketchRaster unavailable(nullptr,dir.path()+"/missing");unavailable.resetWhite();unavailable.release();
    assert(!unavailable.loadCache(0,meta));unavailable.cleanFinger();unavailable.clearPage();unavailable.begin();
    assert(!unavailable.advance(1,20,1,100,100,.5,true));unavailable.finish();
    unavailable.startCalibration();unavailable.begin();assert(unavailable.advance(1,20,1,100,100,.5,true));
    unavailable.finish();unavailable.cancelCalibration();
    assert(unavailable.image.isNull()&&unavailable.material.isNull()&&unavailable.finger.isNull()&&!unavailable.materialReady);
    assert(!unavailable.saveCache(0,meta)&&!unavailable.saveNotebook(manifest(),0,meta));
    assert(!QFile::exists(unavailable.cachePath(0)+".material")&&!QFile::exists(unavailable.notebookPath()));
    unavailable.image=QImage(16,16,QImage::Format_RGB32);assert(!unavailable.ensureMaterial());
    unavailable.image=QImage(1200,1600,QImage::Format_Grayscale8);assert(!unavailable.ensureMaterial());
    assert(!unavailable.saveCache(0,meta));
    SketchRaster kneaded(nullptr,dir.path()+"/kneaded");kneaded.begin();
    assert(kneaded.advance(4,24,1,300,300,1,true));
    assert(kneaded.advance(4,24,1,400,300,1,false));kneaded.finish();kneaded.setMaterialOptions(0,true);
    kneaded.begin();assert(kneaded.advance(6,24,1,350,300,0,true));auto beforeLift=kneaded.material;
    assert(kneaded.advance(6,24,1,350,300,1,false));assert(kneaded.material!=beforeLift);
    auto once=kneaded.material;assert(!kneaded.advance(6,24,1,350,300,1,false));
    assert(kneaded.material==once);kneaded.finish();
    SketchRaster board(nullptr,dir.path());board.setNamespace("realism");board.begin();
    assert(board.advance(1,16,1,300,300,.7,true));board.finish();
    auto pixels=board.image;auto mass=board.material;auto finger=board.finger;
    auto surface=board.physics.burnish;auto wear=board.physics.wear;
    board.startCalibration();assert(board.calibrationActive());
    for(int stage=0;stage<3;stage++){
        board.begin();for(int i=0;i<40;i++)assert(board.advance(1,20,1,100+i,100,.1+.35*stage,i==0));board.finish();
        if(stage<2)assert(board.nextCalibration());
    }
    assert(board.finishCalibration()["ok"].toBool());assert(!board.calibrationActive());
    assert(board.image==pixels&&board.material==mass&&board.finger==finger&&board.physics.burnish==surface&&board.physics.wear==wear);
    QFile calibration(board.calibrationPath());assert(calibration.open(QIODevice::ReadOnly));auto profile=calibration.readAll();calibration.close();
    board.startCalibration();board.begin();board.advance(1,20,1,500,500,1,true);board.cancelCalibration();
    assert(board.image==pixels&&board.physics.wear==wear);assert(calibration.open(QIODevice::ReadOnly)&&calibration.readAll()==profile);calibration.close();
    SketchRaster reopened(nullptr,dir.path());reopened.setNamespace("realism");assert(reopened.pressureCurve.calibrated&&std::abs(reopened.pressureCurve.map(.45)-.5)<1e-8);
    assert(reopened.resetCalibration()&&!QFile::exists(reopened.calibrationPath()));

    // v1 remains optically identical and is not rewritten just by opening.
    SketchRaster legacy(nullptr,dir.path()+"/legacy");legacy.image.fill(qRgb(127,127,127));legacy.ensureMaterial();
    QByteArray oldRaw;oldRaw.append(reinterpret_cast<const char*>(legacy.material.constBits()),1200*1600*4);
    oldRaw.append(reinterpret_cast<const char*>(legacy.image.constBits()),1200*1600*4);
    for(int y=0;y<81;y++)oldRaw.append(reinterpret_cast<const char*>(legacy.finger.constScanLine(y)),164);
    QDir().mkpath(legacy.cacheDirectory);QFile oldFile(legacy.cachePath(0)+".material");assert(oldFile.open(QIODevice::WriteOnly));
    auto oldBytes="PaperSketch material 1\n"+meta.toUtf8()+"\n"+qCompress(oldRaw);oldFile.write(oldBytes);oldFile.close();
    legacy.image.fill(Qt::white);assert(legacy.loadCache(0,meta));assert(qRed(legacy.image.pixel(20,20))==127);
    assert(std::accumulate(legacy.physics.burnish.begin(),legacy.physics.burnish.end(),0LL)==0);
    assert(oldFile.open(QIODevice::ReadOnly)&&oldFile.readAll()==oldBytes);oldFile.close();
    legacy.setMaterialOptions(2,false);legacy.begin();legacy.advance(3,20,1,400,400,1,true);legacy.advance(3,20,1,450,400,1,false);legacy.finish();
    assert(legacy.physics.wear[3]>0&&std::accumulate(legacy.physics.burnish.begin(),legacy.physics.burnish.end(),0LL)>0);
    legacy.saveCache(0,meta);assert(legacy.flushSaves());
    SketchRaster loaded(nullptr,legacy.cacheDirectory);assert(loaded.loadCache(0,meta));
    assert(loaded.image==legacy.image&&loaded.material==legacy.material&&loaded.finger==legacy.finger);
    assert(loaded.physics.burnish==legacy.physics.burnish&&loaded.physics.wear==legacy.physics.wear&&loaded.materialPaperKind()==2);
    legacy.saveNotebook(manifest(),0,meta);assert(legacy.flushSaves());auto savedWear=legacy.physics.wear[3];
    legacy.sharpen(3);assert(legacy.toolWear(3)==0);legacy.restoreSavedTools();assert(legacy.toolWear(3)==savedWear);
    SketchRaster toolkit(nullptr,legacy.cacheDirectory);assert(!toolkit.loadNotebook().isEmpty());toolkit.sharpen(3);assert(toolkit.loadCache(0,meta));assert(toolkit.toolWear(3)==0);

    // Matched raw tilt reaches the material footprint; coalesced curves keep
    // disjoint damage rather than painting their entire enclosing rectangle.
    SketchRaster raw(nullptr,dir.path()+"/raw");raw.setInputTransform(0,0,1,1);raw.begin();
    raw.penSamples.push(100,100,.6,1,.8,0);auto p=raw.pressureAt(100,100,.6);raw.advance(1,12,1,100,100,p,true);
    assert(raw.physics.tiltX==.8&&raw.contactStats()["tilt_samples"].toInt()>0);
    QRegion damage;QObject::connect(&raw,&SketchRaster::damaged,[&](QRegion value){damage+=value;});
    raw.penSamples.push(100,150,.6,1,.8,0);raw.penSamples.push(150,150,.6,1,.8,0);raw.penSamples.push(150,100,.6,1,.8,0);
    p=raw.pressureAt(150,100,.6);raw.advance(1,12,1,150,100,p,false);raw.finish();
    assert(!damage.contains(QPoint(125,125)));
    raw.touchSamples.push({150,100,60,30,.5,.4});raw.begin(true);raw.advance(7,64,1,150,100,.7,true);
    assert(raw.contactStats()["finger_geometry_matches"].toInt()==1&&raw.physics.contactAspect==2);
    raw.cancel();
    puts("PASS calibration isolation/persistence, v1 migration/v2 physical state, global toolkit, raw tilt/contact and disjoint damage");
}
