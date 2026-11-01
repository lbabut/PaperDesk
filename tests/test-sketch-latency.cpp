#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QTemporaryDir>
#include <QtCore/QThread>
#include <cassert>

static qulonglong value(const QVariantMap &stats,const char *key){assert(stats.contains(key));return stats.value(key).toULongLong();}
static void empty(const QVariantMap &stats){assert(stats.size()==12);for(auto it=stats.begin();it!=stats.end();++it)assert(it.value().toULongLong()==0);}
static void valid(const QVariantMap &stats,const char *stage){
    const auto name=QString::fromLatin1(stage);
    assert(stats.value(name+"_total_us").toULongLong()>=stats.value(name+"_max_us").toULongLong());
}
int main(int argc,char **argv){
    QGuiApplication application(argc,argv);QTemporaryDir directory;assert(directory.isValid());
    SketchRaster board(nullptr,directory.path());SketchTile tile;
    tile.setWidth(128);tile.setHeight(128);tile.setRaster(&board);
    QImage surface(128,128,QImage::Format_RGB32);surface.fill(Qt::white);
    {QPainter painter(&surface);tile.paint(&painter);}
    assert(value(board.latencyStats(),"tile_paint_calls")==1);
    board.begin();empty(board.latencyStats());
    const auto before=QDateTime::currentMSecsSinceEpoch();
    QObject::connect(&board,&SketchRaster::damaged,[](const QRegion&){QThread::usleep(3000);});
    assert(board.advance(1,12,1,30,30,.7,true));
    auto stats=board.latencyStats();
    assert(value(stats,"advance_calls")==1&&value(stats,"publish_calls")==1&&value(stats,"tile_paint_calls")==0);
    assert(value(stats,"first_advance_ms")>=qulonglong(before));
    assert(value(stats,"first_publish_ms")>=value(stats,"first_advance_ms"));
    assert(value(stats,"first_tile_paint_ms")==0&&value(stats,"publish_max_us")>=2000);
    assert(value(stats,"advance_total_us")>=value(stats,"publish_total_us"));
    {QPainter painter(&surface);tile.paint(&painter);}
    stats=board.latencyStats();
    assert(value(stats,"tile_paint_calls")==1&&value(stats,"first_tile_paint_ms")>=value(stats,"first_publish_ms"));
    assert(board.advance(1,12,1,45,45,.7,false));
    stats=board.latencyStats();
    // Instrument actual dispatch, not insertion into the 16 ms pending damage.
    assert(value(stats,"advance_calls")==2&&value(stats,"publish_calls")==1);
    assert(board.displayPublicationTimer.interval()==16&&board.displayPublicationTimer.isActive());
    board.finish();stats=board.latencyStats();assert(value(stats,"publish_calls")==2);
    assert(!board.advance(-1,12,1,60,60,.7,false));
    stats=board.latencyStats();assert(value(stats,"advance_calls")==3&&value(stats,"publish_calls")==2);
    for(const auto stage:{"advance","publish","tile_paint"})valid(stats,stage);

    // A previous render scope can finish after begin() without corrupting the
    // new stroke's counters or requiring a lock around Qt painting.
    auto previous=std::atomic_load(&board.latency);
    std::atomic<bool> entered{false},leave{false};
    std::thread oldPaint([&]{SketchLatency::Scope scope(previous,SketchLatency::Stage::TilePaint);entered=true;while(!leave.load())std::this_thread::yield();});
    while(!entered.load())std::this_thread::yield();
    board.begin();empty(board.latencyStats());leave=true;oldPaint.join();empty(board.latencyStats());
    assert(previous->tilePaint.calls.load()==2);

    const auto current=std::atomic_load(&board.latency);
    std::array<std::thread,4> workers;
    for(auto &worker:workers)worker=std::thread([current]{for(int i=0;i<250;i++){SketchLatency::Scope scope(current,SketchLatency::Stage::TilePaint);}});
    for(auto &worker:workers)worker.join();
    stats=board.latencyStats();assert(value(stats,"tile_paint_calls")==1000);
    assert(value(stats,"advance_calls")==0&&value(stats,"publish_calls")==0&&value(stats,"first_tile_paint_ms")>0);
    valid(stats,"tile_paint");
    board.begin();empty(board.latencyStats());
    puts("PASS latency counters, epoch first entries, measured dispatch cost, 16ms queue, early returns, concurrent paint and per-stroke reset");
}
