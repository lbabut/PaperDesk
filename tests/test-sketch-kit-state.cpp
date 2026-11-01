#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <cassert>

static QString pageMeta(int revision) {
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"bitmap",true},{"revision",revision},
        {"strokes",QJsonArray()},{"paper","plain"}}).toJson(QJsonDocument::Compact));
}
static QString notebook() {
    QJsonArray pages;
    for (int slot=0;slot<2;slot++) pages.append(QJsonObject{{"bitmap",true},{"revision",1},
        {"strokes",QJsonArray()},{"paper","plain"},{"cacheSlot",slot}});
    auto document=QJsonDocument(QJsonObject{{"version",1},{"index",0},{"pages",pages}}).toJson(QJsonDocument::Compact);
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"document",QString::fromUtf8(document)}}).toJson(QJsonDocument::Compact));
}
static QByteArray legacyPage(SketchRaster &board,int slot,const QString &meta) {
    board.ensureMaterial();QByteArray raw;
    raw.append(reinterpret_cast<const char*>(board.material.constBits()),1200*1600*4);
    raw.append(reinterpret_cast<const char*>(board.image.constBits()),1200*1600*4);
    for(int y=0;y<81;y++)raw.append(reinterpret_cast<const char*>(board.finger.constScanLine(y)),164);
    QByteArray data="PaperSketch material 1\n"+meta.toUtf8()+"\n"+qCompress(raw);
    QDir().mkpath(board.cacheDirectory);QFile file(board.cachePath(slot)+".material");
    assert(file.open(QIODevice::WriteOnly)&&file.write(data)==data.size());file.close();return data;
}
static void draw(SketchRaster &board) {
    board.begin();assert(board.advance(3,20,1,300,300,.9,true));
    assert(board.advance(3,20,1,500,300,.9,false));board.finish();
}
int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);QTemporaryDir directory;assert(directory.isValid());
    const auto meta=pageMeta(1);SketchRaster first(nullptr,directory.path());
    auto original=legacyPage(first,0,meta);legacyPage(first,1,meta);
    assert(first.loadNotebook().isEmpty());assert(first.loadCache(0,meta));assert(first.kitLoaded);
    QFile untouched(first.cachePath(0)+".material");assert(untouched.open(QIODevice::ReadOnly));
    assert(untouched.readAll()==original);untouched.close();
    draw(first);auto upgradedWear=first.toolWear(3);assert(upgradedWear>0);
    assert(first.saveNotebook(notebook(),0,meta)&&first.flushSaves());
    assert(first.loadCache(1,meta)&&first.toolWear(3)==upgradedWear);
    // An explicit sharpening also survives opening another page containing
    // older local wear, until the toolkit is saved or discarded deliberately.
    first.sharpen(3);assert(first.loadCache(0,meta)&&first.toolWear(3)==0);
    first.restoreSavedTools();assert(first.toolWear(3)==upgradedWear);

    // Simulate page commit succeeding while the manifest commit is interrupted.
    // The newer page is authoritative for pigment AND physical-tool state.
    SketchRaster interrupted(nullptr,directory.path());assert(!interrupted.loadNotebook().isEmpty());
    assert(interrupted.loadCache(0,meta));interrupted.setMaterialOptions(2,false);draw(interrupted);
    auto recoveredWear=interrupted.toolWear(3);auto recoveredBurnish=interrupted.physics.burnish;
    auto recoveredPixels=interrupted.opticalDigest();assert(recoveredWear>upgradedWear);
    assert(interrupted.saveCache(0,pageMeta(2))&&interrupted.flushSaves());
    SketchRaster recovered(nullptr,directory.path());assert(!recovered.loadNotebook().isEmpty());
    assert(recovered.toolWear(3)==upgradedWear);assert(recovered.loadCache(0,meta));
    assert(recovered.toolWear(3)==recoveredWear&&recovered.physics.burnish==recoveredBurnish);
    assert(recovered.opticalDigest()==recoveredPixels&&recovered.materialPaperKind()==2);
    assert(recovered.loadCache(1,meta)&&recovered.toolWear(3)==recoveredWear);
    puts("PASS legacy upgrade toolkit continuity, explicit sharpening, saved-tool discard and newer-page physical-state recovery");
}
