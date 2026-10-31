#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QEventLoop>
#include <cassert>
int main(int argc,char **argv){
    QGuiApplication app(argc,argv);
    _xovi_construct();QQmlEngine engine;QQmlComponent component(&engine);
    component.setData("import PaperSketch.Native 1.0; RasterTile { width:128; height:128 }",QUrl("inmemory:/tile.qml"));
    QElapsedTimer readyTimer;readyTimer.start();while(component.isLoading() && readyTimer.elapsed()<5000)QCoreApplication::processEvents(QEventLoop::AllEvents,50);
    if(component.isError())qWarning()<<component.errors();assert(component.isReady());QObject *object=component.create();assert(object);delete object;
    QTemporaryDir dir;assert(dir.isValid());SketchRaster board(nullptr,dir.path());
    QVariantList a{300,240,1},b{300,360,1},spec{3,24,0,1,6,123,0};
    board.begin();assert(board.segment(spec,a,a,false));spec[6]=1;assert(board.segment(spec,a,b,false));board.finish();
    QImage pencil=board.image;int original=qRed(pencil.pixel(300,300));assert(original<150);
    board.begin();assert(board.segment(QVariantList{7,64,0,1,6,124,1},QVariantList{240,300,0.7},QVariantList{360,300,0.7},true));board.finish();
    int core=qRed(board.image.pixel(300,300)),beside=qRed(board.image.pixel(327,300));
    assert(core>original+10 && core<245 && beside<230);QImage blended=board.image;
    assert(board.undo() && board.image==pencil);assert(board.redo() && board.image==blended);
    SketchTile tile;tile.setWidth(128);tile.setHeight(128);tile.setProperty("sourceX",256);tile.setProperty("sourceY",256);tile.setRaster(&board);
    QImage display(128,128,QImage::Format_RGB32);{QPainter painter(&display);tile.paint(&painter);}
    assert(qRed(display.pixel(44,44))==core && tile.pixels(44,44,1,1)[0].toInt()==core);
    assert(board.save(dir.filePath("drawing.png")));QImage exported(dir.filePath("drawing.png"));assert(exported.size()==board.image.size() && exported.pixel(300,300)==board.image.pixel(300,300));
    assert(board.saveCache(0,"fixture"));SketchRaster loaded(nullptr,dir.path());assert(loaded.loadCache(0,"fixture") && loaded.image==board.image);assert(!loaded.loadCache(0,"stale-fixture"));
    QJSEngine js;QJSValue bytes=js.evaluate("var a=new Uint8Array(1200*1600*4);a.fill(255);a[0]=0;a");
    SketchRaster imported(nullptr,dir.path());assert(imported.importPixels(bytes));assert(qRed(imported.image.pixel(0,0))==0 && qRed(imported.image.pixel(1,0))==255);
    imported.release();assert(imported.image.isNull());imported.resetWhite();assert(imported.image.size()==QSize(1200,1600) && qRed(imported.image.pixel(0,0))==255);
    printf("PASS native raster: graphite %d -> %d, transferred %d; tile, undo/redo, PNG and cache verified\n",original,core,beside);
}
