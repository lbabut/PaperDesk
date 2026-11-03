#include <QtCore/QObject>
#include <QtCore/QVariantList>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDir>
#include <QtCore/QSaveFile>
#include <QtCore/QBuffer>
#include <QtCore/QStandardPaths>
#include <QtCore/QFileInfo>
#include <QtCore/QVariantMap>
#include <QtCore/QElapsedTimer>
#include <QtCore/QDateTime>
#include <QtGui/QImage>
#include <QtGui/QPdfWriter>
#include <QtGui/QPageSize>
#include <QtCore/QTemporaryDir>
#include <QtGui/QRegion>
#include <QtGui/QPainter>
#include <QtQml/qqml.h>
#include <QtQml/QQmlEngine>
#include <QtQml/QJSValue>
#include <QtQuick/QQuickPaintedItem>
#include <dlfcn.h>
#include <link.h>
#include <cstring>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <array>
#include <atomic>
#include <chrono>
#include <memory>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include "sketch-smudge.h"
#include "sketch-material.h"
#include "sketch-pen.h"
#include "sketch-touch.h"
#include "sketch-pressure.h"
#include "sketch-display.h"
#include <QtCore/QTimer>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonArray>
#include <QtCore/QSet>
#include <zlib.h>

// Software pipeline timings, not panel/optical latency. A scope retains the
// current stroke's counters so a concurrent reset cannot charge an old paint
// to the next stroke. Only begin() allocates; measured paths do no logging/I/O.
struct SketchLatency {
    struct Counter {
        std::atomic<qulonglong> calls{0},totalUs{0},maxUs{0};
        std::atomic<qlonglong> firstMs{0};
    } advance,publish,tilePaint;
    enum class Stage {Advance,Publish,TilePaint};
    struct Scope {
        std::shared_ptr<SketchLatency> owner;
        Counter *counter;
        std::chrono::steady_clock::time_point started;
        Scope(std::shared_ptr<SketchLatency> snapshot,Stage stage):owner(std::move(snapshot)),
            counter(stage==Stage::Advance?&owner->advance:stage==Stage::Publish?&owner->publish:&owner->tilePaint),
            started(std::chrono::steady_clock::now()){
            if(!counter->firstMs.load(std::memory_order_relaxed)){
                qlonglong empty=0;
                counter->firstMs.compare_exchange_strong(empty,QDateTime::currentMSecsSinceEpoch(),std::memory_order_relaxed);
            }
        }
        Scope(const Scope&)=delete;
        Scope& operator=(const Scope&)=delete;
        ~Scope(){
            const auto elapsed=qulonglong(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-started).count());
            counter->totalUs.fetch_add(elapsed,std::memory_order_relaxed);
            auto maximum=counter->maxUs.load(std::memory_order_relaxed);
            while(maximum<elapsed&&!counter->maxUs.compare_exchange_weak(maximum,elapsed,std::memory_order_relaxed)){}
            counter->calls.fetch_add(1,std::memory_order_relaxed);
        }
    };
};

class SketchRaster:public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool fastDisplay READ fastDisplay WRITE setFastDisplay NOTIFY displayModeChanged)
    Q_PROPERTY(bool materialAvailable READ available CONSTANT)
    Q_PROPERTY(bool penInRange READ penInRange NOTIFY proximityChanged)
    Q_PROPERTY(int maxSmudgeMs READ maxSmudgeMs NOTIFY timingChanged)
    Q_PROPERTY(bool calibrationActive READ calibrationActive NOTIFY calibrationChanged)
    Q_PROPERTY(int calibrationStage READ calibrationStage NOTIFY calibrationChanged)
public:
    std::shared_ptr<SketchLatency> latency=std::make_shared<SketchLatency>();
    Q_INVOKABLE QVariantMap latencyStats()const{
        const auto snapshot=std::atomic_load_explicit(&latency,std::memory_order_acquire);
        auto load=[](const auto &value){return value.load(std::memory_order_relaxed);};
        return {{"advance_calls",load(snapshot->advance.calls)},{"advance_total_us",load(snapshot->advance.totalUs)},{"advance_max_us",load(snapshot->advance.maxUs)},
            {"publish_calls",load(snapshot->publish.calls)},{"publish_total_us",load(snapshot->publish.totalUs)},{"publish_max_us",load(snapshot->publish.maxUs)},
            {"tile_paint_calls",load(snapshot->tilePaint.calls)},{"tile_paint_total_us",load(snapshot->tilePaint.totalUs)},{"tile_paint_max_us",load(snapshot->tilePaint.maxUs)},
            {"first_advance_ms",load(snapshot->advance.firstMs)},{"first_publish_ms",load(snapshot->publish.firstMs)},{"first_tile_paint_ms",load(snapshot->tilePaint.firstMs)}};
    }
    bool displayFast=true;
    bool fastDisplay()const{return displayFast;}
    void setFastDisplay(bool value){if(displayFast==value)return;displayFast=value;emit displayModeChanged();publishDirty(image.rect());}
    Q_PROPERTY(bool rawPenInputAvailable READ rawPenInputAvailable NOTIFY proximityChanged)
    bool penReaderReady=false;
    bool rawPenInputAvailable()const{return penReaderReady;}
    Q_INVOKABLE void setRawPenInputEnabled(bool value){penSamples.enableInput(value);}
    void notifyPenInput(){QMetaObject::invokeMethod(this,[this]{emit penInputReady();},Qt::QueuedConnection);}
    Q_INVOKABLE QVariantList takePenInput(){
        auto events=penSamples.takeInput(32);QVariantList result;
        for(const auto &event:events){const auto &p=event.sample;
            result.append(QVariant(QVariantList{event.phase,p.x,p.y,p.p,p.tiltX,p.tiltY,p.eraser,p.contact}));
        }
        // A batch limit bounds one GUI turn; remaining events stay queued.
        if(penSamples.inputPending())notifyPenInput();
        return result;
    }
    Q_INVOKABLE QVariantList penInputStats()const{auto s=penSamples.inputStats();return {qulonglong(s[0]),qulonglong(s[1]),qulonglong(s[2])};}
    Q_SIGNAL void penInputReady();
    PaperPen penSamples;PaperTouch touchSamples;PaperPressure pressureCurve;
    double inputX=0,inputY=0,inputScaleX=1,inputScaleY=1;int pressureMatches=0,pressureFallbacks=0;
    int tiltSamples=0,touchGeometryMatches=0,touchMatches=0,touchFallbacks=0;bool kitLoaded=false;
    Q_INVOKABLE void setInputTransform(double x,double y,double sx,double sy){inputX=x;inputY=y;inputScaleX=sx;inputScaleY=sy;penSamples.setViewport(x,y,sx,sy);}
    PaperPen::Sample pendingSample;uint64_t lastRawId=0;unsigned lastContact=0;int rawReplayed=0,rawBatchMax=0;bool collectingDamage=false;QRegion collectedDamage;
    Q_INVOKABLE double pressureAt(double x,double y,double fallback){
        pendingSample=penSamples.match(inputX+x*inputScaleX,inputY+y*inputScaleY);
        if(pendingSample.p>=0){pressureMatches++;return std::clamp(pendingSample.p,0.0,1.0);}
        pressureFallbacks++;return penPressure(fallback);
    }
    Q_INVOKABLE double touchPressureAt(double x,double y,double fallback){
        auto sample=touchSamples.match(inputX+x*inputScaleX,inputY+y*inputScaleY);
        if(sample.time && sample.pressure>=0){touchMatches++;return std::clamp(sample.pressure,.04,1.0);}
        touchFallbacks++;return std::clamp(fallback,.04,1.0);
    }
    Q_INVOKABLE QVariantList touchPressureMatchCounts()const{return {touchMatches,touchFallbacks};}
    Q_INVOKABLE QVariantList rawReplayStats()const{return {rawReplayed,rawBatchMax};}
    Q_INVOKABLE QVariantList pressureMatchCounts()const{return {pressureMatches,pressureFallbacks};}
    Q_INVOKABLE QVariantMap contactStats()const{
        auto stats=penSamples.matchDiagnostics();
        return {{"tilt_samples",tiltSamples},{"finger_geometry_matches",touchGeometryMatches},{"tilt_x",physics.tiltX},{"tilt_y",physics.tiltY},{"paper_kind",physics.paperKind},{"calibrated",pressureCurve.calibrated},
            {"pen_match_calls",qulonglong(stats.calls)},{"pen_match_misses",qulonglong(stats.misses)},
            {"pen_stale_position_misses",qulonglong(stats.stalePositionMisses)},{"pen_samples_at_miss",stats.samplesAtMiss},
            {"pen_nearest_miss_age_ms",qlonglong(stats.nearestMissAge)},{"pen_youngest_miss_age_ms",qlonglong(stats.youngestMissAge)},
            {"pen_max_stale_age_ms",qlonglong(stats.maxStaleAge)},{"pen_nearest_miss_distance_px",stats.nearestMissDistance}};
    }
    Q_INVOKABLE QVariantMap materialState()const{
        QJsonArray wear;for(double value:physics.wear)wear.append(value);
        return {{"surface_digest",QString::fromLatin1(QCryptographicHash::hash(QByteArray::fromRawData(reinterpret_cast<const char*>(physics.burnish.data()),physics.burnish.size()),QCryptographicHash::Sha256).toHex())},
                {"finger_digest",QString::fromLatin1(QCryptographicHash::hash(QByteArray::fromRawData(reinterpret_cast<const char*>(finger.constBits()),finger.sizeInBytes()),QCryptographicHash::Sha256).toHex())},
                {"paper_kind",physics.paperKind},{"wear",wear.toVariantList()}};
    }
    QImage image{1200,1600,QImage::Format_RGB32};
    QImage material, finger, currentFinger;bool tentativeTouch=false;
    struct Patch{QRect rect;QImage optical,mass;};
    QList<Patch> currentPatches;std::array<bool,130> captured{};
    void capture(QRect dirty){
        for(int ty=dirty.top()/128;ty<=dirty.bottom()/128;ty++)for(int tx=dirty.left()/128;tx<=dirty.right()/128;tx++){
            int key=ty*10+tx;if(key<0||key>=130||captured[key])continue;captured[key]=true;
            QRect rect=QRect(tx*128,ty*128,128,128).intersected(image.rect());
            currentPatches.append({rect,image.copy(rect),material.copy(rect)});
        }
    }
    void swapPatches(QList<Patch>& patches){
        for(auto &p:patches){
            for(int y=0;y<p.rect.height();y++){
                memcpy(image.scanLine(p.rect.y()+y)+p.rect.x()*4,p.optical.constScanLine(y),p.rect.width()*4);
                memcpy(material.scanLine(p.rect.y()+y)+p.rect.x()*4,p.mass.constScanLine(y),p.rect.width()*4);
            }
        }
    }
    PaperMaterial physics;bool materialReady=false;QString loadedMeta;QTimer proximityTimer;bool penNearby=false;
    bool penInRange()const{return penNearby;}
    bool ensureMaterial(){
        // Failed page loads after release must stay unavailable. Allocating a
        // white image here would let maintenance or Save replace missing art.
        if(image.size()!=QSize(1200,1600)||image.format()!=QImage::Format_RGB32)return false;
        physics.init(1200,1600);
        if(!materialReady){material=QImage(1200,1600,QImage::Format_RGB32);physics.import(reinterpret_cast<const uint32_t*>(image.constBits()),reinterpret_cast<uint32_t*>(material.bits()));physics.resetSurface();materialReady=true;}
        if(finger.isNull()){finger=QImage(82,81,QImage::Format_Grayscale16);finger.fill(0);}
        return true;
    }
    // Atomic replacement prevents the pen thread from seeing a half-written
    // heartbeat and disarming in the middle of a fine stroke.
    Q_INVOKABLE bool writePreviewPermit(const QString &value){
        const auto bytes=value.toUtf8();
        if(bytes.size()>240||bytes.contains('\n')||bytes.contains('\r')||!(bytes=="off"||bytes.startsWith("fine ")||bytes.startsWith("on ")))return false;
        QSaveFile file(previewPermitPath);if(!file.open(QIODevice::WriteOnly))return false;
        file.setPermissions(QFileDevice::ReadOwner|QFileDevice::WriteOwner);
        return file.write(bytes)==bytes.size()&&file.commit();
    }
    QRegion previewRepair;
    Q_INVOKABLE QVariantList previewPressureAnchors()const{return {pressureCurve.calibrated?pressureCurve.anchors[0]:.15,pressureCurve.calibrated?pressureCurve.anchors[1]:.5,pressureCurve.calibrated?pressureCurve.anchors[2]:.95};}
    Q_INVOKABLE void repairPreview(){auto region=std::move(previewRepair);previewRepair=QRegion();emitDisplayDamage(region);}
    QTimer displayPublicationTimer;
    QRegion displayPending;
    bool livePublication=false;
    bool awaitingPenContact=false;
    bool rearEraserStroke=false;
    void emitDisplayDamage(const QRegion &damage){if(damage.isEmpty())return;SketchLatency::Scope timing(std::atomic_load_explicit(&latency,std::memory_order_acquire),SketchLatency::Stage::Publish);emit damaged(damage);emit changed(damage.boundingRect());}
    void flushDisplayDamage(){
        displayPublicationTimer.stop();
        auto damage=std::move(displayPending);displayPending=QRegion();
        emitDisplayDamage(damage);
    }
    void dropDisplayDamage(){displayPublicationTimer.stop();displayPending=QRegion();previewRepair=QRegion();livePublication=false;}
    void publishRegion(const QRegion &damage){
        if(damage.isEmpty())return;
        if(!livePublication){emitDisplayDamage(damage);return;}
        // Material pixels update on every sample. Publish the first mark
        // immediately, then notify the 130 tiles once per 16 ms window.
        if(!displayPublicationTimer.isActive()){
            emitDisplayDamage(damage);
            if(livePublication)displayPublicationTimer.start();
        }else displayPending+=damage;
    }
    void publishDirty(QRect dirty){if(collectingDamage)collectedDamage+=dirty;else publishRegion(QRegion(dirty));}
    Q_INVOKABLE QString pageMetadata()const{return loadedMeta;}
    QString cacheNamespace="PaperDeskSketch";QString cacheDirectory,exportDirectoryOverride,previewPermitPath;
    bool calibrationActive()const{return pressureCurve.active;}
    int calibrationStage()const{return pressureCurve.stage;}
    QString calibrationPath()const{return cachePath(0)+".pressure.json";}
    void loadCalibration(){
        pressureCurve=PaperPressure{};QFile file(calibrationPath());
        if(!file.open(QIODevice::ReadOnly)||file.size()>4096)return;
        auto object=QJsonDocument::fromJson(file.readAll()).object();auto a=object.value("anchors").toArray();
        if(object.value("version").toInt()!=1||a.size()!=3)return;
        std::array<double,3> values{{a[0].toDouble(-1),a[1].toDouble(-1),a[2].toDouble(-1)}};
        if(PaperPressure::valid(values)){pressureCurve.anchors=values;pressureCurve.calibrated=true;}
    }
    QString toolPreferencesPath()const{return cachePath(0)+".tools.json";}
    static bool validToolPreferences(const QJsonObject &o){
        auto sizes=o.value("sizes").toArray();double selected=o.value("selectedTool").toDouble(-1);
        if(o.value("version").toDouble(-1)!=1||selected<0||selected>8||std::floor(selected)!=selected||sizes.size()!=9||!o.value("kneadedEraser").isBool())return false;
        for(const auto &value:sizes){double size=value.toDouble(-1);if(!std::isfinite(size)||size<1||size>80)return false;}
        return true;
    }
    Q_INVOKABLE QString loadToolPreferences()const{
        QFile file(toolPreferencesPath());if(!file.open(QIODevice::ReadOnly)||file.size()>4096)return {};
        auto raw=file.readAll();auto doc=QJsonDocument::fromJson(raw);
        return doc.isObject()&&validToolPreferences(doc.object())?QString::fromUtf8(raw):QString();
    }
    Q_INVOKABLE bool saveToolPreferences(const QString &value){
        auto raw=value.toUtf8();if(raw.size()>4096)return false;
        auto doc=QJsonDocument::fromJson(raw);if(!doc.isObject()||!validToolPreferences(doc.object()))return false;
        return QDir().mkpath(cacheDirectory)&&atomicWrite(toolPreferencesPath(),doc.toJson(QJsonDocument::Compact));
    }
    Q_INVOKABLE void startCalibration(){pressureCurve.start();emit calibrationChanged();}
    Q_INVOKABLE bool nextCalibration(){bool ok=pressureCurve.next();emit calibrationChanged();return ok;}
    Q_INVOKABLE QVariantMap finishCalibration(){
        std::array<double,3> values;
        if(!pressureCurve.candidate(values))return {{"ok",false},{"error","Draw at least 16 samples in each stage, increasing from light to firm pressure."}};
        QJsonArray array;for(double p:values)array.append(p);
        auto raw=QJsonDocument(QJsonObject{{"version",1},{"anchors",array}}).toJson(QJsonDocument::Compact);
        if(!QDir().mkpath(cacheDirectory)||!atomicWrite(calibrationPath(),raw))return {{"ok",false},{"error","Calibration could not be saved. The previous profile is unchanged."}};
        pressureCurve.anchors=values;pressureCurve.calibrated=true;pressureCurve.cancel();emit calibrationChanged();return {{"ok",true}};
    }
    Q_INVOKABLE void cancelCalibration(){pressureCurve.cancel();emit calibrationChanged();}
    Q_INVOKABLE bool resetCalibration(){
        if(QFile::exists(calibrationPath())&&!QFile::remove(calibrationPath()))return false;
        pressureCurve=PaperPressure{};emit calibrationChanged();return true;
    }
    Q_INVOKABLE QString calibrationSummary()const{return pressureCurve.calibrated?QStringLiteral("Calibrated for your hand"):QStringLiteral("Standard pressure response");}
    Q_INVOKABLE void setMaterialOptions(int paperKind,bool kneaded){physics.setPaperKind(std::clamp(paperKind,0,2));physics.kneaded=kneaded;}
    Q_INVOKABLE int materialPaperKind()const{return physics.paperKind;}
    Q_INVOKABLE void sharpen(int tool){physics.sharpen(tool);kitLoaded=true;}
    Q_INVOKABLE double toolWear(int tool)const{return tool>=0&&tool<6?physics.wear[tool]:0;}
    Q_INVOKABLE void cleanFinger(){if(ensureMaterial())finger.fill(0);}
    bool restoreKit(const QByteArray &raw){
        auto values=QJsonDocument::fromJson(raw).object().value("physicalTools").toArray();if(values.size()!=6)return false;
        std::array<double,6> next;for(int i=0;i<6;i++){next[i]=values[i].toDouble(-1);if(!std::isfinite(next[i])||next[i]<0||next[i]>1)return false;}
        physics.wear=next;kitLoaded=true;return true;
    }
    Q_INVOKABLE void restoreSavedTools(){physics.wear.fill(0);kitLoaded=false;QFile file(notebookPath());if(file.open(QIODevice::ReadOnly)&&file.size()<16*1024*1024)restoreKit(file.readAll());}
    int slowest=0;QRect pendingDirty;bool unpublished=false;
    struct SaveJob {QString cache,file,json;QByteArray document;QImage snapshot,mass,fingertip;QByteArray surface,ink;std::array<double,6> wear;int paperKind=0;};
    std::mutex saveMutex;std::condition_variable saveWake;std::deque<SaveJob> saves;
    bool stopping=false,writing=false,writeError=false;std::thread writer;
    static bool atomicWrite(const QString &path,const QByteArray &bytes){
        QSaveFile f(path);return f.open(QIODevice::WriteOnly) && f.write(bytes)==bytes.size() && f.commit();
    }
    static bool documentSlots(const QByteArray &manifest,QSet<int>&pageIds){
        auto envelope=QJsonDocument::fromJson(manifest).object();
        auto book=QJsonDocument::fromJson(envelope.value("document").toString().toUtf8()).object();
        auto pages=book.value("pages").toArray();if(book.value("version").toInt()!=1||pages.isEmpty()||pages.size()>12)return false;
        for(int i=0;i<pages.size();i++){
            auto page=pages[i].toObject();auto value=page.value("cacheSlot");int slot=value.isUndefined()?i:value.toInt(-1);
            if(slot<0||slot>1000000000||(!value.isUndefined()&&value.toDouble()!=slot)||pageIds.contains(slot))return false;
            pageIds.insert(slot);
        }return true;
    }
    static void pruneRemovedPages(const QByteArray&before,const QByteArray&after,const QString&file){
        QSet<int> oldSlots,newSlots;const QString suffix="0.bin.material-notebook.json";
        if(!file.endsWith(suffix)||!documentSlots(before,oldSlots)||!documentSlots(after,newSlots))return;
        auto prefix=file.left(file.size()-suffix.size());
        for(int slot:oldSlots)if(!newSlots.contains(slot)){
            QFile::remove(prefix+QString::number(slot)+".bin.material");
            QFile::remove(prefix+QString::number(slot)+".bin");
        }
    }
    void writeLoop(){
        for(;;){
            SaveJob job;
            {std::unique_lock<std::mutex> lock(saveMutex);saveWake.wait(lock,[this]{return stopping||!saves.empty();});
             if(saves.empty()&&stopping)return;job=std::move(saves.front());saves.pop_front();writing=true;}
            QDir().mkpath(cacheDirectory);bool ok=true;
            // An atomic page contains both optical pixels and physical pigment.
            bool inkPage=!job.ink.isEmpty();
            QByteArray raw;raw.reserve(1200*1600*(inkPage?10:9)+82*81*2);
            raw.append(reinterpret_cast<const char*>(job.mass.constBits()),1200*1600*4);
            raw.append(reinterpret_cast<const char*>(job.snapshot.constBits()),1200*1600*4);
            for(int y=0;y<81;y++)raw.append(reinterpret_cast<const char*>(job.fingertip.constScanLine(y)),82*2);
            raw.append(job.surface);job.surface.clear();raw.append(job.ink);job.ink.clear();
            job.snapshot=QImage();job.mass=QImage();job.fingertip=QImage();
            QJsonArray wear;for(double value:job.wear)wear.append(value);
            auto physical=QJsonDocument(QJsonObject{{"paperKind",job.paperKind},{"wear",wear}}).toJson(QJsonDocument::Compact);
            QByteArray bytes=QByteArray(inkPage?"PaperSketch material 3\n":"PaperSketch material 2\n")+job.json.toUtf8()+"\n"+physical+"\n"+qCompress(raw,1);
            QByteArray before;if(!job.file.isEmpty()){QFile old(job.file);if(old.open(QIODevice::ReadOnly)&&old.size()<16*1024*1024)before=old.readAll();}
            ok=atomicWrite(job.cache+".material",bytes);
            if(ok && !job.file.isEmpty()){ok=atomicWrite(job.file,job.document);if(ok)pruneRemovedPages(before,job.document,job.file);}
            {std::lock_guard<std::mutex> lock(saveMutex);writing=false;if(!ok)writeError=true;}saveWake.notify_all();
            if(!ok)emit saveFailed();else emit saveCompleted();
        }
    }
    void enqueue(SaveJob job){
        {std::lock_guard<std::mutex> lock(saveMutex);
         // Only replace pending work for the same page; other pages remain durable.
         for(auto it=saves.begin();it!=saves.end();){if(it->cache==job.cache && (it->file.isEmpty()||!job.file.isEmpty()))it=saves.erase(it);else ++it;}
         writeError=false;saves.push_back(std::move(job));}
        saveWake.notify_one();
    }
    SketchRaster(QObject *parent=nullptr,QString directory="/home/root/.local/share/paperdesk/sketch",QString exports=QString(),QString permit=QString("/tmp/papersketch-ink")):QObject(parent),cacheDirectory(directory),exportDirectoryOverride(exports),previewPermitPath(permit){image.fill(Qt::white);displayPublicationTimer.setInterval(16);displayPublicationTimer.setSingleShot(true);displayPublicationTimer.setTimerType(Qt::PreciseTimer);connect(&displayPublicationTimer,&QTimer::timeout,this,[this]{bool hadDamage=!displayPending.isEmpty();flushDisplayDamage();if(hadDamage&&livePublication)displayPublicationTimer.start();});proximityTimer.setInterval(40);connect(&proximityTimer,&QTimer::timeout,this,[this]{bool nearby=penSamples.nearby.load(),reader=penSamples.ready.load();if(nearby!=penNearby||reader!=penReaderReady){if(nearby&&tentativeTouch)cancel();penNearby=nearby;penReaderReady=reader;emit proximityChanged();}});proximityTimer.start();penSamples.setInputWake([this]{notifyPenInput();});writer=std::thread([this]{writeLoop();});}
    ~SketchRaster() override {penSamples.shutdown();{std::lock_guard<std::mutex> lock(saveMutex);stopping=true;}saveWake.notify_one();writer.join();if(pressureFd>=0)close(pressureFd);}
    mutable int pressureFd=-1;mutable double pressureLast=.5;mutable QElapsedTimer pressureAge;
    Q_INVOKABLE double penPressure(double fallback)const{
        if(pressureFd<0){
            int fd=open("/dev/input/event1",O_RDONLY|O_NONBLOCK|O_CLOEXEC);char name[128]={0};
            if(fd>=0 && ioctl(fd,EVIOCGNAME(sizeof name),name)>=0 && strstr(name,"Wacom"))pressureFd=fd;
            else if(fd>=0)close(fd);
        }
        input_absinfo pressure{};
        if(pressureFd>=0 && ioctl(pressureFd,EVIOCGABS(ABS_PRESSURE),&pressure)==0 && pressure.maximum>pressure.minimum && pressure.value>pressure.minimum)
            {pressureLast=sk_clamp(double(pressure.value-pressure.minimum)/(pressure.maximum-pressure.minimum),0,1);pressureAge.start();return pressureLast;}
        if(pressureAge.isValid()&&pressureAge.elapsed()<100)return pressureLast;
        return fallback;
    }
    Q_INVOKABLE bool eraserActive(double x,double y){
        // Query current kernel tool state on contact, including synthesized
        // mouse events. Do not wait for the background pressure reader.
        penPressure(0);unsigned char keys[KEY_MAX/8+1]={0};
        if(pressureFd>=0&&ioctl(pressureFd,EVIOCGKEY(sizeof keys),keys)>=0){
            if(keys[BTN_TOOL_RUBBER/8]&(1<<(BTN_TOOL_RUBBER%8)))return true;
            if(keys[BTN_TOOL_PEN/8]&(1<<(BTN_TOOL_PEN%8)))return false;
        }
        // A very short contact can end before Qt delivers its press event.
        // Retain the tool carried by that position-matched raw sample.
        auto sample=penSamples.match(inputX+x*inputScaleX,inputY+y*inputScaleY);
        return sample.p>=0?sample.eraser:penSamples.eraserNearby.load();
    }
    bool available()const{return true;}
    int maxSmudgeMs()const{return slowest;}
    Q_INVOKABLE bool importPixels(QJSValue pixels) {
        if(pixels.property("length").toInt()!=1200*1600*4)return false;
        QImage next(1200,1600,QImage::Format_RGB32);
        for(int y=0;y<1600;y++){auto row=reinterpret_cast<QRgb*>(next.scanLine(y));for(int x=0;x<1200;x++){int v=pixels.property((y*1200+x)*4).toInt();row[x]=qRgb(v,v,v);}}
        dropDisplayDamage();currentPatches.clear();image=next;materialReady=false;ensureMaterial();publishDirty(QRect(0,0,1200,1600));return true;
    }
    Q_INVOKABLE void setNamespace(QString name){cacheNamespace=name;kitLoaded=false;physics.wear.fill(0);loadCalibration();penSamples.activate();touchSamples.activate();proximityTimer.start();}
    Q_INVOKABLE void release(){rearEraserStroke=false;dropDisplayDamage();pressureCurve.cancel();penSamples.pause();touchSamples.pause();proximityTimer.stop();image=QImage();material=QImage();finger=QImage();currentFinger=QImage();currentPatches.clear();materialReady=false;}
    Q_INVOKABLE void resetWhite(){rearEraserStroke=false;dropDisplayDamage();currentPatches.clear();currentFinger=QImage();tentativeTouch=false;if(image.size()!=QSize(1200,1600)||image.format()!=QImage::Format_RGB32)image=QImage(1200,1600,QImage::Format_RGB32);image.fill(Qt::white);materialReady=false;ensureMaterial();physics.resetSurface();finger.fill(0);slowest=0;emit timingChanged();publishDirty(image.rect());}
    Q_INVOKABLE void clearPage(){if(!ensureMaterial())return;dropDisplayDamage();image.fill(Qt::white);material.fill(0);finger.fill(0);physics.resetSurface();physics.resetInk();publishDirty(image.rect());}
    Q_INVOKABLE void begin(bool tentative=false,bool rearEraser=false){rearEraserStroke=rearEraser&&!tentative;flushDisplayDamage();std::atomic_store_explicit(&latency,std::make_shared<SketchLatency>(),std::memory_order_release);livePublication=false;lastRawId=0;lastContact=0;pendingSample=PaperPen::Sample();rawReplayed=0;rawBatchMax=0;collectingDamage=false;collectedDamage=QRegion();pressureMatches=0;pressureFallbacks=0;penSamples.resetMatchDiagnostics();tiltSamples=0;touchGeometryMatches=0;touchMatches=0;touchFallbacks=0;if(!ensureMaterial())return;livePublication=true;awaitingPenContact=!tentative;tentativeTouch=tentative;currentFinger=tentative?finger:QImage();captured.fill(false);currentPatches.clear();physics.untilNext=0;pendingDirty=QRect();unpublished=false;}
    Q_INVOKABLE void finish(bool preview=false){if(preview&&!pendingDirty.isEmpty()){int margin=int(std::ceil(16/std::max(.1,std::min(inputScaleX,inputScaleY))))+4;auto repair=pendingDirty.adjusted(-margin,-margin,margin,margin).intersected(image.rect());previewRepair+=repair;publishDirty(repair);}rearEraserStroke=false;currentPatches.clear();currentFinger=QImage();tentativeTouch=false;if(unpublished&&!pendingDirty.isEmpty())publishDirty(pendingDirty);livePublication=false;flushDisplayDamage();pendingDirty=QRect();unpublished=false;}
    Q_INVOKABLE void cancel(){
        if(!tentativeTouch)return;dropDisplayDamage();QRect dirty;for(const auto &p:currentPatches)dirty=dirty.united(p.rect);
        swapPatches(currentPatches);currentPatches.clear();finger=currentFinger;currentFinger=QImage();tentativeTouch=false;pendingDirty=QRect();if(!dirty.isEmpty())publishDirty(dirty);
    }
    Q_INVOKABLE QVariantList pixels(int x,int y,int w,int h)const {
        QVariantList out;if(w<0||h<0||w*h>4096)return out;out.reserve(w*h*4);
        for(int py=y;py<y+h;py++)for(int px=x;px<x+w;px++){auto c=image.valid(px,py)?image.pixel(px,py):qRgb(255,255,255);out<<qRed(c)<<qGreen(c)<<qBlue(c)<<255;}return out;
    }
    Q_INVOKABLE QString opticalDigest()const{return QString::fromLatin1(QCryptographicHash::hash(QByteArray::fromRawData(reinterpret_cast<const char*>(image.constBits()),image.sizeInBytes()),QCryptographicHash::Sha256).toHex());}
    Q_INVOKABLE bool save(const QString&path)const{return image.save(path,"PNG");}
    Q_INVOKABLE QString documentsDirectory()const{
        if(!exportDirectoryOverride.isEmpty())return exportDirectoryOverride;
        auto directory=QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        return directory.isEmpty()?QDir::homePath()+"/Documents":directory;
    }
    Q_INVOKABLE QVariantMap exportPng(QString name,bool overwrite=false)const{
        name=name.trimmed();if(name.endsWith(".png",Qt::CaseInsensitive))name.chop(4);
        bool invalid=name.isEmpty()||name.startsWith('.')||name.contains('/')||name.contains('\\')||name.toUtf8().size()>240;
        for(auto ch:name)if(ch.unicode()<32)invalid=true;
        if(invalid)return {{"ok",false},{"error","Choose a file name without folders or control characters."}};
        auto directory=documentsDirectory();
        if(!QDir().mkpath(directory))return {{"ok",false},{"error","Cannot create the Documents folder."}};
        auto path=QDir(directory).filePath(name+".png");
        if(QFileInfo::exists(path)&&!overwrite)return {{"ok",false},{"exists",true},{"path",path},{"error","This file already exists. Replace it?"}};
        QSaveFile file(path);
        if(image.isNull()||!file.open(QIODevice::WriteOnly)||!image.save(&file,"PNG")||!file.commit())
            return {{"ok",false},{"error","PNG could not be saved. Your drawing is still in memory."}};
        return {{"ok",true},{"path",path}};
    }

    QSet<QString> pendingPdfPaths;
    Q_INVOKABLE QVariantMap exportPdf(QString name){
        bool controls=false;for(auto ch:name)if(ch.unicode()<32||ch.unicode()==127)controls=true;
        name=name.trimmed();if(name.endsWith(".pdf",Qt::CaseInsensitive))name.chop(4);
        bool invalid=controls||name.isEmpty()||name.startsWith('.')||name.contains('/')||name.contains(QChar(92))||name.toUtf8().size()>240;
        for(auto ch:name)if(ch.unicode()<32)invalid=true;
        if(invalid)return {{"ok",false},{"error","Choose a document name without folders or control characters."}};
        if(image.isNull())return {{"ok",false},{"error","The drawing is not ready for export."}};
        if(!QDir().mkpath(cacheDirectory))return {{"ok",false},{"error","Cannot create the PDF export folder."}};
        QTemporaryDir job(QDir(cacheDirectory).filePath("pdf-export-XXXXXX"));
        if(!job.isValid())return {{"ok",false},{"error","Cannot create the PDF export folder."}};
        auto path=QDir(job.path()).filePath(name+".pdf");
        QSaveFile file(path);bool written=false;
        if(file.open(QIODevice::WriteOnly)){
            {
                QPdfWriter writer(&file);writer.setResolution(144);
                writer.setPageSize(QPageSize(QSizeF(600,800),QPageSize::Point));
                writer.setPageMargins(QMarginsF(0,0,0,0),QPageLayout::Point);
                writer.setTitle(name);writer.setCreator("Paper Sketch");
                QPainter painter;
                if(painter.begin(&writer)){
                    painter.setRenderHint(QPainter::LosslessImageRendering,true);
                    painter.drawImage(QRect(0,0,writer.width(),writer.height()),image.convertToFormat(QImage::Format_Grayscale8));
                    written=painter.end();
                }
            }
            if(written)written=file.commit();
        }
        if(!written)return {{"ok",false},{"error","PDF could not be created. Your drawing is still in memory."}};
        pendingPdfPaths.insert(path);job.setAutoRemove(false);
        return {{"ok",true},{"path",path},{"title",name}};
    }
    Q_INVOKABLE bool discardPdfExport(const QString &path){
        if(!pendingPdfPaths.contains(path))return false;
        if(!QFile::remove(path))return false;
        pendingPdfPaths.remove(path);QDir().rmdir(QFileInfo(path).absolutePath());return true;
    }

    QString cachePath(int page)const{return (cacheDirectory+QStringLiteral("/cache-%1-%2.bin")).arg(QString::fromLatin1(QCryptographicHash::hash(cacheNamespace.toUtf8(),QCryptographicHash::Sha256).toHex().left(12))).arg(page);}
    static QByteArray materialPayload(const QByteArray &compressed,bool surface=false,bool ink=false){
        const uint32_t expected=1200*1600*(8+int(surface)+int(ink))+82*81*2;
        if(compressed.size()<4||compressed.size()>32*1024*1024)return {};
        const auto *header=reinterpret_cast<const unsigned char*>(compressed.constData());
        uint32_t declared=(uint32_t(header[0])<<24)|(uint32_t(header[1])<<16)|(uint32_t(header[2])<<8)|header[3];
        if(declared!=expected)return {};
        // qUncompress treats its four-byte size as an allocation hint and can
        // grow beyond it. Inflate into one fixed buffer so a malformed cache
        // cannot allocate an arbitrarily large page inside the UI process.
        QByteArray raw(expected,Qt::Uninitialized);uLongf actual=expected;
        int result=uncompress(reinterpret_cast<Bytef*>(raw.data()),&actual,
            reinterpret_cast<const Bytef*>(compressed.constData()+4),uLong(compressed.size()-4));
        if(result!=Z_OK||actual!=expected)return {};
        for(int i=0;i<1200*1600;i++){
            uint32_t mass;memcpy(&mass,raw.constData()+i*4,4);
            if((mass>>16)+(mass&65535)>65535)return {};
        }
        return raw;
    }
    Q_INVOKABLE bool loadCache(int page,const QString&json){
        dropDisplayDamage();loadedMeta.clear();currentPatches.clear();
        QFile mf(cachePath(page)+".material");
        if(mf.open(QIODevice::ReadOnly)&&mf.size()<32*1024*1024){
            auto header=mf.readLine(128);bool v3=header=="PaperSketch material 3\n",v2=v3||header=="PaperSketch material 2\n";
            if(v2||header=="PaperSketch material 1\n"){
                auto meta=QString::fromUtf8(mf.readLine(1024*1024)).trimmed();
                auto desired=QJsonDocument::fromJson(json.toUtf8()).object(),stored=QJsonDocument::fromJson(meta.toUtf8()).object();
                if(meta==json || (desired.value("bitmap").toBool() && stored.value("bitmap").toBool() && stored.value("revision").toInt()>=desired.value("revision").toInt())){
                    int kind=0;std::array<double,6> wear{};bool valid=true;
                    if(v2){auto physical=QJsonDocument::fromJson(mf.readLine(4096)).object();kind=physical.value("paperKind").toInt(-1);auto array=physical.value("wear").toArray();
                        valid=kind>=0&&kind<=2&&array.size()==6;
                        if(valid)for(int i=0;i<6;i++){wear[i]=array[i].toDouble(-1);valid=valid&&std::isfinite(wear[i])&&wear[i]>=0&&wear[i]<=1;}}
                    auto raw=valid?materialPayload(mf.readAll(),v2,v3):QByteArray();
                    if(!raw.isEmpty()){
                        image=QImage(1200,1600,QImage::Format_RGB32);material=QImage(1200,1600,QImage::Format_RGB32);finger=QImage(82,81,QImage::Format_Grayscale16);
                        memcpy(material.bits(),raw.constData(),1200*1600*4);memcpy(image.bits(),raw.constData()+1200*1600*4,1200*1600*4);
                        for(int y=0;y<81;y++)memcpy(finger.scanLine(y),raw.constData()+1200*1600*8+y*82*2,82*2);
                        materialReady=true;physics.init(1200,1600);physics.setPaperKind(kind);physics.resetSurface();
                        if(v2)memcpy(physics.burnish.data(),raw.constData()+1200*1600*8+82*81*2,1200*1600);
                        physics.resetInk();
                        if(v3){memcpy(physics.ink.data(),raw.constData()+1200*1600*9+82*81*2,1200*1600);physics.hasInk=true;}
                        bool recoverNewer=stored.value("revision").toInt()>desired.value("revision").toInt();
                        if(!kitLoaded||recoverNewer)physics.wear=wear;
                        kitLoaded=true;
                        loadedMeta=meta;publishDirty(image.rect());return true;
                    }
                }
            }
        }
        QFile f(cachePath(page));if(!f.open(QIODevice::ReadOnly)||f.size()>12*1024*1024)return false;
        auto key=QCryptographicHash::hash(json.toUtf8(),QCryptographicHash::Sha256).toHex();
        if(f.readLine().trimmed()!=key)return false;QImage next=QImage::fromData(f.readAll(),"PNG");
        if(next.size()!=QSize(1200,1600))return false;image=next.convertToFormat(QImage::Format_RGB32);materialReady=false;ensureMaterial();publishDirty(image.rect());return true;
    }
    QString notebookPath()const{return cachePath(0)+".material-notebook.json";}
    Q_INVOKABLE QString loadNotebook(){QFile f(notebookPath());if(!f.exists())f.setFileName(cachePath(0)+".notebook.json");if(!f.open(QIODevice::ReadOnly)||f.size()>16*1024*1024)return QString();auto raw=f.readAll();restoreKit(raw);return QString::fromUtf8(raw);}
    SaveJob saveJob(int page,const QString &json,const QByteArray &document=QByteArray()){
        if(!ensureMaterial())return {};return {cachePath(page),document.isEmpty()?QString():notebookPath(),json,document,image,material,finger,
            QByteArray(reinterpret_cast<const char*>(physics.burnish.data()),physics.burnish.size()),
            physics.hasInk?QByteArray(reinterpret_cast<const char*>(physics.ink.data()),physics.ink.size()):QByteArray(),physics.wear,physics.paperKind};
    }
    Q_INVOKABLE bool saveCache(int page,const QString&json){auto job=saveJob(page,json);if(job.snapshot.isNull())return false;enqueue(std::move(job));return true;}
    Q_INVOKABLE bool flushSaves(){std::unique_lock<std::mutex> lock(saveMutex);saveWake.wait(lock,[this]{return saves.empty()&&!writing;});return !writeError;}
    Q_INVOKABLE bool saveNotebook(const QString&document,int page,const QString&json){
        if(!ensureMaterial())return false;
        auto object=QJsonDocument::fromJson(document.toUtf8()).object();QJsonArray wear;for(double p:physics.wear)wear.append(p);object.insert("physicalTools",wear);
        // Preserve the exact caller envelope when no physical state has changed;
        // older integrations compare their untouched manifest byte-for-byte.
        QByteArray raw=document.toUtf8();bool used=kitLoaded;for(double p:physics.wear)used=used||p>0;
        QSet<int> pageSlots;if(used&&documentSlots(raw,pageSlots))raw=QJsonDocument(object).toJson(QJsonDocument::Compact);
        kitLoaded=true;
        enqueue(saveJob(page,json,raw));return true;
    }
    double lastX=0,lastY=0,lastP=.5;long long lastTouchTime=0;
    bool advancePoint(int tool,double size,double strength,double x,double y,double p,bool first,double tiltX=0,double tiltY=0){
        if(tool<0||tool>8||!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(p)||!std::isfinite(size)||!std::isfinite(strength)||size<1||size>80||strength<.05||strength>1)return false;
        if(pressureCurve.active){pressureCurve.collect(p);return true;}
        x=std::clamp(x,0.0,1200.0);y=std::clamp(y,0.0,1600.0);p=std::clamp(p,0.0,1.0);
        // The rear sensor is not the calibrated drawing nib. Once it reports
        // positive contact, use the ordinary hard eraser at full contact.
        // Keep zero pressure as hover so a stationary pressure rise starts it.
        if(rearEraserStroke&&tool==6&&p>0)p=1;

        double dx=x-lastX,dy=y-lastY;
        double threshold=tentativeTouch?std::clamp(size*.08,1.0,3.0):0;
        bool pendingKneaded=tool==6&&physics.kneaded&&p>0&&(!physics.kneadedContact||pressureCurve.map(p)>lastP+.0001);
        if(!first && (tentativeTouch?dx*dx+dy*dy<threshold*threshold:dx==0&&dy==0)&&!pendingKneaded&&!awaitingPenContact)return false;
        physics.tiltX=tiltX;physics.tiltY=tiltY;
        if(tiltX!=0||tiltY!=0)tiltSamples++;
        if(tentativeTouch){
            auto sample=touchSamples.match(inputX+x*inputScaleX,inputY+y*inputScaleY);
            physics.contactAspect=1.35;physics.contactAngle=first?0:std::atan2(dy,dx);
            if(sample.time){
                if(sample.major>=6 && sample.minor>=4){
                    size=std::clamp(std::max(size,sample.major/std::max(.01,(inputScaleX+inputScaleY)/2)),48.0,80.0);
                    physics.contactAspect=std::clamp(sample.major/sample.minor,1.0,2.0);
                    physics.contactAngle=sample.angle;touchGeometryMatches++;
                }

            }
            auto now=PaperTouch::now();
            lastTouchTime=now;
        }else{if(tool!=8)p=pressureCurve.map(p);physics.contactAspect=1;physics.contactAngle=0;}
        // Hover/zero-pressure press must not consume the first visible dab or
        // arm the publication timer. A stationary pressure rise is a contact,
        // even when Qt delivers no drag activation or coordinate change.
        if(awaitingPenContact){
            if(p<=0){lastX=x;lastY=y;lastP=p;return true;}
            first=true;awaitingPenContact=false;
        }
        double ax=first?x:lastX,ay=first?y:lastY,ap=first?p:lastP;
        if(!ensureMaterial())return false;
        double radius=std::max(physics.footprintRadius(tool,size,ap),physics.footprintRadius(tool,size,p))+3;
        auto dirty=QRectF(QPointF(std::min(ax,x)-radius,std::min(ay,y)-radius),QPointF(std::max(ax,x)+radius,std::max(ay,y)+radius)).toAlignedRect().intersected(image.rect());
        QElapsedTimer timer;timer.start();if(tentativeTouch)capture(dirty);
        physics.segment(reinterpret_cast<uint32_t*>(material.bits()),reinterpret_cast<uint32_t*>(image.bits()),reinterpret_cast<uint16_t*>(finger.bits()),tool,size,0,strength,ax,ay,ap,x,y,p,first?0:1);
        int elapsed=timer.elapsed();if(elapsed>slowest){slowest=elapsed;emit timingChanged();}
        pendingDirty=pendingDirty.united(dirty);publishDirty(dirty);lastX=x;lastY=y;lastP=p;return true;
    }
    Q_INVOKABLE bool advancePenInput(int tool,double size,double strength,double x,double y,double p,bool first,double tiltX,double tiltY){
        SketchLatency::Scope timing(std::atomic_load_explicit(&latency,std::memory_order_acquire),SketchLatency::Stage::Advance);
        return advancePoint(tool,size,strength,x,y,p,first,tiltX,tiltY);
    }
    Q_INVOKABLE bool advance(int tool,double size,double strength,double x,double y,double p,bool first){
        SketchLatency::Scope timing(std::atomic_load_explicit(&latency,std::memory_order_acquire),SketchLatency::Stage::Advance);
        if(tool<0||tool>8||!std::isfinite(size)||size<1||size>80||!std::isfinite(strength)||strength<.05||strength>1||!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(p))return false;
        auto sample=pendingSample;pendingSample=PaperPen::Sample();
        if(sample.id&&inputScaleX>0&&inputScaleY>0&&!tentativeTouch){
            if(first||!lastContact||lastContact!=sample.contact){
                bool restart=first||(lastContact&&lastContact!=sample.contact);
                lastRawId=sample.id;lastContact=sample.contact;
                return advancePoint(tool,size,strength,x,y,sample.p,restart,sample.tiltX,sample.tiltY);
            }
            if(sample.id<=lastRawId)return false;
            std::array<PaperPen::Sample,64> path;auto n=penSamples.between(lastRawId,sample,path);
            bool updated=false;collectingDamage=true;collectedDamage=QRegion();
            for(unsigned i=0;i<n;i++)updated=advancePoint(tool,size,strength,(path[i].x-inputX)/inputScaleX,(path[i].y-inputY)/inputScaleY,path[i].p,false,path[i].tiltX,path[i].tiltY)||updated;
            collectingDamage=false;publishRegion(collectedDamage);collectedDamage=QRegion();
            lastRawId=sample.id;lastContact=sample.contact;rawReplayed+=std::max(0,int(n)-1);rawBatchMax=std::max(rawBatchMax,int(n));
            if(n)return updated;
        }
        lastRawId=0;lastContact=0;
        return advancePoint(tool,size,strength,x,y,p,first);
    }
    static double noise(double x,double y,quint32 seed){double v=sin(x*12.9898+y*78.233+(seed%65536)*0.017)*43758.5453;return v-floor(v);}
    Q_INVOKABLE bool segment(QVariantList spec,QVariantList av,QVariantList bv,bool publish) {
        if(spec.size()!=7||av.size()!=3||bv.size()!=3)return false;
        int tool=spec[0].toInt(),index=spec[6].toInt();double size=spec[1].toDouble(),tone=spec[2].toDouble(),strength=spec[3].toDouble();
        quint32 seed=spec[5].toUInt();QPointF a(av[0].toDouble(),av[1].toDouble()),b(bv[0].toDouble(),bv[1].toDouble());
        double ap=av[2].toDouble(),bp=bv[2].toDouble();
        if(tool<0||tool>8||index<0||!std::isfinite(size)||size<1||size>80||!std::isfinite(strength)||strength<0.05||strength>1||!std::isfinite(tone)||tone<0||tone>255||!std::isfinite(a.x())||!std::isfinite(a.y())||!std::isfinite(b.x())||!std::isfinite(b.y())||!std::isfinite(ap)||!std::isfinite(bp)||ap<0||ap>1||bp<0||bp>1||a.x()<0||a.x()>1200||a.y()<0||a.y()>1600||b.x()<0||b.x()>1200||b.y()<0||b.y()>1600)return false;
        if(pressureCurve.active){pressureCurve.collect(bp);return true;}
        double radius=std::max(physics.footprintRadius(tool,size,ap),physics.footprintRadius(tool,size,bp))+3;
        QRect dirty=QRectF(QPointF(std::min(a.x(),b.x())-radius,std::min(a.y(),b.y())-radius),QPointF(std::max(a.x(),b.x())+radius,std::max(a.y(),b.y())+radius)).toAlignedRect().intersected(image.rect());
        if(spec[4].toInt()>=8||tool==8){
            if(!ensureMaterial())return false;QElapsedTimer timer;timer.start();if(tentativeTouch)capture(dirty);
            physics.segment(reinterpret_cast<uint32_t*>(material.bits()),reinterpret_cast<uint32_t*>(image.bits()),reinterpret_cast<uint16_t*>(finger.bits()),tool,size,tone,strength,a.x(),a.y(),av[2].toDouble(),b.x(),b.y(),bv[2].toDouble(),index);
            slowest=std::max(slowest,(int)timer.elapsed());pendingDirty=pendingDirty.united(dirty);publishDirty(dirty);emit timingChanged();return true;
        }
        materialReady=false;
        if(tool==7){
            if(spec[4].toInt()>=7)strength*=sk_clamp((av[2].toDouble()+bv[2].toDouble())/2,0.04,1);
            double dx=b.x()-a.x(),dy=b.y()-a.y();if(dx*dx+dy*dy<0.01)return true;
            int pad=(int)ceil(sk_clamp(size/2,6,40)*2),sx=std::max(0,(int)floor(std::min(a.x(),b.x())-pad)),sy=std::max(0,(int)floor(std::min(a.y(),b.y())-pad));
            int w=std::min(1200-sx,(int)ceil(fabs(dx)+pad*2)),h=std::min(1600-sy,(int)ceil(fabs(dy)+pad*2));
            QElapsedTimer timer;timer.start();QImage patch=image.copy(sx,sy,w,h).convertToFormat(QImage::Format_RGBA8888);
            if(!sk_smudge(patch.bits(),w,h,a.x()-sx,a.y()-sy,b.x()-sx,b.y()-sy,size,strength))return false;
            QPainter painter(&image);painter.drawImage(sx,sy,patch);painter.end();slowest=std::max(slowest,(int)timer.elapsed());emit timingChanged();
        }else{
            double p=(av[2].toDouble()+bv[2].toDouble())/2,w=std::max(0.8,size*(0.18+0.82*p));
            const double opacities[]={0.22,0.38,0.53,0.7,0.5,0.35,1};
            double alpha=tool==6?strength:opacities[tool]*strength*(0.3+0.7*p),value=tool==6?255:tone;
            QPainter painter(&image);painter.setRenderHint(QPainter::Antialiasing,true);
            auto color=[value](double opacity){QColor c((int)value,(int)value,(int)value);c.setAlphaF(sk_clamp(opacity,0,1));return c;};
            if(!index||a==b){painter.setPen(Qt::NoPen);painter.setBrush(color(alpha));painter.drawEllipse(b,w/2,w/2);}
            else{
                int layers=tool==4||tool==5?3:1;double weights[]={0.3,0.6,0.5};
                for(int i=0;i<layers;i++){QPen pen(color(alpha*(layers==1?1:weights[i])),w*(1-i*0.22),Qt::SolidLine,Qt::RoundCap,Qt::RoundJoin);painter.setPen(pen);painter.drawLine(a,b);}
                if(tool<4&&w>3){double grains[]={0.35,0.3,0.24,0.18};double offset=(noise(0,0,seed)-0.5)*w*0.15;QPen pen(color(alpha*grains[tool]),std::max(0.5,w*0.06),Qt::SolidLine,Qt::RoundCap);painter.setPen(pen);painter.drawLine(a+QPointF(offset,0),b+QPointF(offset,0));}
            }
        }
        pendingDirty=pendingDirty.united(dirty);if(publish)publishDirty(dirty);else unpublished=true;return true;
    }
signals:
    void calibrationChanged();
    void damaged(QRegion region);
    void displayModeChanged();
    void proximityChanged();
    void saveFailed();
    void saveCompleted();
    void changed(QRect rect);
    void timingChanged();
};

class SketchTile:public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QObject* raster READ raster WRITE setRaster)
    Q_PROPERTY(int sourceX MEMBER sx)
    Q_PROPERTY(int sourceY MEMBER sy)
    SketchRaster *board=nullptr;int sx=0,sy=0;QImage painted,optical;QRegion pendingDamage;bool resetDisplay=true,lastFast=true;int lastSourceX=-1,lastSourceY=-1;
public:
    SketchTile(QQuickItem *parent=nullptr):QQuickPaintedItem(parent){setRenderTarget(QQuickPaintedItem::Image);setOpaquePainting(true);setSmooth(false);}
    QObject* raster()const{return board;}
    void setRaster(QObject*obj){
        if(board)disconnect(board,nullptr,this,nullptr);
        board=qobject_cast<SketchRaster*>(obj);resetDisplay=true;
        if(board)connect(board,&SketchRaster::damaged,this,[this](const QRegion &region){
            const QRect bounds(sx,sy,(int)width(),(int)height()),box=region.boundingRect();
            if(!box.intersects(bounds))return;
            if(region.rectCount()==1){
                auto local=box.intersected(bounds).translated(-sx,-sy);
                pendingDamage+=local;update(local);return;
            }
            auto local=region.intersected(bounds).translated(-sx,-sy);
            if(!local.isEmpty()){pendingDamage+=local;update(local.boundingRect());}
        });
        update();
    }
    void paint(QPainter *painter)override{
        if(!board)return;
        SketchLatency::Scope timing(std::atomic_load_explicit(&board->latency,std::memory_order_acquire),SketchLatency::Stage::TilePaint);
        QSize size((int)width(),(int)height());bool fast=board->fastDisplay();
        if(size.isEmpty())return;
        if(optical.size()!=size||resetDisplay||lastFast!=fast||lastSourceX!=sx||lastSourceY!=sy){
            optical=QImage(size,QImage::Format_RGB32);painted=QImage(size,QImage::Format_RGB32);
            optical.fill(Qt::white);painted.fill(Qt::white);
            pendingDamage=QRegion(QRect(QPoint(0,0),size));resetDisplay=false;lastFast=fast;lastSourceX=sx;lastSourceY=sy;
        }
        auto bounds=QRect(sx,sy,size.width(),size.height()).intersected(board->image.rect()).translated(-sx,-sy);
        auto dirty=pendingDamage.intersected(bounds);pendingDamage=QRegion();
        if(!dirty.isEmpty()&&sx>=0&&sy>=0){
            const auto source=reinterpret_cast<const uint32_t*>(board->image.constScanLine(sy))+sx;
            auto raw=reinterpret_cast<uint32_t*>(optical.bits()),display=reinterpret_cast<uint32_t*>(painted.bits());
            for(const auto rect:dirty)paperDisplayPatch(source,board->image.bytesPerLine()/4,raw,display,optical.bytesPerLine()/4,rect.x(),rect.y(),rect.width(),rect.height(),sx,sy,fast);
        }
        painter->setRenderHint(QPainter::SmoothPixmapTransform,false);painter->drawImage(0,0,painted);
    }
    Q_INVOKABLE QVariantList opticalPixels(int x,int y,int w,int h)const{QVariantList out;if(w<0||h<0||w*h>4096)return out;for(int py=y;py<y+h;py++)for(int px=x;px<x+w;px++){auto c=optical.valid(px,py)?optical.pixel(px,py):qRgb(255,255,255);out<<qRed(c)<<qGreen(c)<<qBlue(c)<<255;}return out;}
    Q_INVOKABLE QVariantList pixels(int x,int y,int w,int h)const{QVariantList out;if(w<0||h<0||w*h>4096)return out;for(int py=y;py<y+h;py++)for(int px=x;px<x+w;px++){auto c=painted.valid(px,py)?painted.pixel(px,py):qRgb(255,255,255);out<<qRed(c)<<qGreen(c)<<qBlue(c)<<255;}return out;}
};
extern "C" void _xovi_construct(){
    qmlRegisterSingletonType<SketchRaster>("PaperSketch.Native",1,0,"Raster",[](QQmlEngine*,QJSEngine*)->QObject*{return new SketchRaster;});
    qmlRegisterType<SketchTile>("PaperSketch.Native",1,0,"RasterTile");
    fprintf(stderr,"[papersketch-raster] native image engine registered\n");
}
#include "papersketch-raster.moc"
