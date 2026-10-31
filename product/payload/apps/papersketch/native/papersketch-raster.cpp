#include <QtCore/QObject>
#include <QtCore/QVariantList>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDir>
#include <QtCore/QSaveFile>
#include <QtCore/QBuffer>
#include <QtCore/QElapsedTimer>
#include <QtGui/QImage>
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
#include <linux/input.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include "sketch-smudge.h"
#include "sketch-material.h"
#include "sketch-pen.h"
#include "sketch-display.h"
#include <QtCore/QTimer>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>

class SketchRaster:public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool fastDisplay READ fastDisplay WRITE setFastDisplay NOTIFY displayModeChanged)
    Q_PROPERTY(bool materialAvailable READ available CONSTANT)
    Q_PROPERTY(bool penInRange READ penInRange NOTIFY proximityChanged)
    Q_PROPERTY(int maxSmudgeMs READ maxSmudgeMs NOTIFY timingChanged)
public:
    bool displayFast=true;
    bool fastDisplay()const{return displayFast;}
    void setFastDisplay(bool value){if(displayFast==value)return;displayFast=value;emit displayModeChanged();emit changed(image.rect());}
    PaperPen penSamples;double inputX=0,inputY=0,inputScaleX=1,inputScaleY=1;int pressureMatches=0,pressureFallbacks=0;
    Q_INVOKABLE void setInputTransform(double x,double y,double sx,double sy){inputX=x;inputY=y;inputScaleX=sx;inputScaleY=sy;}
    Q_INVOKABLE double pressureAt(double x,double y,double fallback){double p=penSamples.at(inputX+x*inputScaleX,inputY+y*inputScaleY);if(p>=0){pressureMatches++;return std::clamp(p,.04,1.0);}pressureFallbacks++;return penPressure(fallback);}
    Q_INVOKABLE QVariantList pressureMatchCounts()const{return {pressureMatches,pressureFallbacks};}
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
    void ensureMaterial(){
        physics.init(1200,1600);
        if(!materialReady){material=QImage(1200,1600,QImage::Format_RGB32);physics.import(reinterpret_cast<const uint32_t*>(image.constBits()),reinterpret_cast<uint32_t*>(material.bits()));materialReady=true;}
        if(finger.isNull()){finger=QImage(82,81,QImage::Format_Grayscale16);finger.fill(0);}
    }
    void publishDirty(QRect dirty){if(!dirty.isEmpty())emit changed(dirty);}
    Q_INVOKABLE QString pageMetadata()const{return loadedMeta;}
    QString cacheNamespace="PaperDeskSketch";QString cacheDirectory;
    int slowest=0;QRect pendingDirty;bool unpublished=false;
    struct SaveJob {QString cache,file,json;QByteArray document;QImage snapshot,mass,fingertip;};
    std::mutex saveMutex;std::condition_variable saveWake;std::deque<SaveJob> saves;
    bool stopping=false,writing=false,writeError=false;std::thread writer;
    static bool atomicWrite(const QString &path,const QByteArray &bytes){
        QSaveFile f(path);return f.open(QIODevice::WriteOnly) && f.write(bytes)==bytes.size() && f.commit();
    }
    void writeLoop(){
        for(;;){
            SaveJob job;
            {std::unique_lock<std::mutex> lock(saveMutex);saveWake.wait(lock,[this]{return stopping||!saves.empty();});
             if(saves.empty()&&stopping)return;job=std::move(saves.front());saves.pop_front();writing=true;}
            QDir().mkpath(cacheDirectory);bool ok=true;
            // An atomic page contains both optical pixels and physical pigment.
            QByteArray raw;raw.reserve(1200*1600*8+82*81*2);
            raw.append(reinterpret_cast<const char*>(job.mass.constBits()),1200*1600*4);
            raw.append(reinterpret_cast<const char*>(job.snapshot.constBits()),1200*1600*4);
            for(int y=0;y<81;y++)raw.append(reinterpret_cast<const char*>(job.fingertip.constScanLine(y)),82*2);
            job.snapshot=QImage();job.mass=QImage();job.fingertip=QImage();
            QByteArray bytes="PaperSketch material 1\n"+job.json.toUtf8()+"\n"+qCompress(raw,1);
            ok=atomicWrite(job.cache+".material",bytes);
            if(ok && !job.file.isEmpty())ok=atomicWrite(job.file,job.document);
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
    SketchRaster(QObject *parent=nullptr,QString directory="/home/root/.local/share/paperdesk/sketch"):QObject(parent),cacheDirectory(directory){image.fill(Qt::white);proximityTimer.setInterval(40);connect(&proximityTimer,&QTimer::timeout,this,[this]{bool nearby=penSamples.nearby.load();if(nearby!=penNearby){if(nearby&&tentativeTouch)cancel();penNearby=nearby;emit proximityChanged();}});proximityTimer.start();writer=std::thread([this]{writeLoop();});}
    ~SketchRaster() override {{std::lock_guard<std::mutex> lock(saveMutex);stopping=true;}saveWake.notify_one();writer.join();if(pressureFd>=0)close(pressureFd);}
    mutable int pressureFd=-1;mutable double pressureLast=.5;mutable QElapsedTimer pressureAge;
    Q_INVOKABLE double penPressure(double fallback)const{
        if(pressureFd<0){
            int fd=open("/dev/input/event1",O_RDONLY|O_NONBLOCK|O_CLOEXEC);char name[128]={0};
            if(fd>=0 && ioctl(fd,EVIOCGNAME(sizeof name),name)>=0 && strstr(name,"Wacom"))pressureFd=fd;
            else if(fd>=0)close(fd);
        }
        input_absinfo pressure{};
        if(pressureFd>=0 && ioctl(pressureFd,EVIOCGABS(ABS_PRESSURE),&pressure)==0 && pressure.maximum>pressure.minimum && pressure.value>pressure.minimum)
            {pressureLast=sk_clamp(double(pressure.value-pressure.minimum)/(pressure.maximum-pressure.minimum),0.05,1);pressureAge.start();return pressureLast;}
        if(pressureAge.isValid()&&pressureAge.elapsed()<100)return pressureLast;
        return fallback;
    }
    bool available()const{return true;}
    int maxSmudgeMs()const{return slowest;}
    Q_INVOKABLE bool importPixels(QJSValue pixels) {
        if(pixels.property("length").toInt()!=1200*1600*4)return false;
        QImage next(1200,1600,QImage::Format_RGB32);
        for(int y=0;y<1600;y++){auto row=reinterpret_cast<QRgb*>(next.scanLine(y));for(int x=0;x<1200;x++){int v=pixels.property((y*1200+x)*4).toInt();row[x]=qRgb(v,v,v);}}
        currentPatches.clear();image=next;materialReady=false;ensureMaterial();emit changed(QRect(0,0,1200,1600));return true;
    }
    Q_INVOKABLE void setNamespace(QString name){cacheNamespace=name;penSamples.activate();proximityTimer.start();}
    Q_INVOKABLE void release(){penSamples.pause();proximityTimer.stop();image=QImage();material=QImage();finger=QImage();currentFinger=QImage();currentPatches.clear();materialReady=false;}
    Q_INVOKABLE void resetWhite(){currentPatches.clear();currentFinger=QImage();tentativeTouch=false;if(image.size()!=QSize(1200,1600))image=QImage(1200,1600,QImage::Format_RGB32);image.fill(Qt::white);materialReady=false;ensureMaterial();finger.fill(0);slowest=0;emit timingChanged();emit changed(image.rect());}
    Q_INVOKABLE void clearPage(){image.fill(Qt::white);ensureMaterial();material.fill(0);finger.fill(0);emit changed(image.rect());}
    Q_INVOKABLE void begin(bool tentative=false){pressureMatches=0;pressureFallbacks=0;ensureMaterial();tentativeTouch=tentative;currentFinger=tentative?finger:QImage();captured.fill(false);currentPatches.clear();physics.untilNext=0;pendingDirty=QRect();unpublished=false;}
    Q_INVOKABLE void finish(){currentPatches.clear();currentFinger=QImage();tentativeTouch=false;if(unpublished&&!pendingDirty.isEmpty())emit changed(pendingDirty);pendingDirty=QRect();unpublished=false;}
    Q_INVOKABLE void cancel(){
        if(!tentativeTouch)return;QRect dirty;for(const auto &p:currentPatches)dirty=dirty.united(p.rect);
        swapPatches(currentPatches);currentPatches.clear();finger=currentFinger;currentFinger=QImage();tentativeTouch=false;pendingDirty=QRect();if(!dirty.isEmpty())emit changed(dirty);
    }
    Q_INVOKABLE QVariantList pixels(int x,int y,int w,int h)const {
        QVariantList out;if(w<0||h<0||w*h>4096)return out;out.reserve(w*h*4);
        for(int py=y;py<y+h;py++)for(int px=x;px<x+w;px++){auto c=image.valid(px,py)?image.pixel(px,py):qRgb(255,255,255);out<<qRed(c)<<qGreen(c)<<qBlue(c)<<255;}return out;
    }
    Q_INVOKABLE QString opticalDigest()const{return QString::fromLatin1(QCryptographicHash::hash(QByteArray::fromRawData(reinterpret_cast<const char*>(image.constBits()),image.sizeInBytes()),QCryptographicHash::Sha256).toHex());}
    Q_INVOKABLE bool save(const QString&path)const{return image.save(path,"PNG");}
    QString cachePath(int page)const{return (cacheDirectory+QStringLiteral("/cache-%1-%2.bin")).arg(QString::fromLatin1(QCryptographicHash::hash(cacheNamespace.toUtf8(),QCryptographicHash::Sha256).toHex().left(12))).arg(page);}
    Q_INVOKABLE bool loadCache(int page,const QString&json){
        loadedMeta.clear();currentPatches.clear();
        QFile mf(cachePath(page)+".material");
        if(mf.open(QIODevice::ReadOnly)&&mf.size()<32*1024*1024 && mf.readLine()=="PaperSketch material 1\n"){
            auto meta=QString::fromUtf8(mf.readLine()).trimmed();
            auto desired=QJsonDocument::fromJson(json.toUtf8()).object(),stored=QJsonDocument::fromJson(meta.toUtf8()).object();
            if(meta==json || (desired.value("bitmap").toBool() && stored.value("bitmap").toBool() && stored.value("revision").toInt()>=desired.value("revision").toInt())){
                auto raw=qUncompress(mf.readAll());
                if(raw.size()==1200*1600*8+82*81*2){
                    image=QImage(1200,1600,QImage::Format_RGB32);material=QImage(1200,1600,QImage::Format_RGB32);finger=QImage(82,81,QImage::Format_Grayscale16);
                    memcpy(material.bits(),raw.constData(),1200*1600*4);memcpy(image.bits(),raw.constData()+1200*1600*4,1200*1600*4);
                    for(int y=0;y<81;y++)memcpy(finger.scanLine(y),raw.constData()+1200*1600*8+y*82*2,82*2);
                    materialReady=true;physics.init(1200,1600);loadedMeta=meta;emit changed(image.rect());return true;
                }
            }
        }
        QFile f(cachePath(page));if(!f.open(QIODevice::ReadOnly)||f.size()>12*1024*1024)return false;
        auto key=QCryptographicHash::hash(json.toUtf8(),QCryptographicHash::Sha256).toHex();
        if(f.readLine().trimmed()!=key)return false;QImage next=QImage::fromData(f.readAll(),"PNG");
        if(next.size()!=QSize(1200,1600))return false;image=next.convertToFormat(QImage::Format_RGB32);materialReady=false;ensureMaterial();emit changed(image.rect());return true;
    }
    QString notebookPath()const{return cachePath(0)+".material-notebook.json";}
    Q_INVOKABLE QString loadNotebook()const{QFile f(notebookPath());if(!f.exists())f.setFileName(cachePath(0)+".notebook.json");if(!f.open(QIODevice::ReadOnly)||f.size()>16*1024*1024)return QString();return QString::fromUtf8(f.readAll());}
    Q_INVOKABLE bool saveCache(int page,const QString&json){ensureMaterial();enqueue({cachePath(page),QString(),json,QByteArray(),image,material,finger});return true;}
    Q_INVOKABLE bool flushSaves(){std::unique_lock<std::mutex> lock(saveMutex);saveWake.wait(lock,[this]{return saves.empty()&&!writing;});return !writeError;}
    Q_INVOKABLE bool saveNotebook(const QString&document,int page,const QString&json){ensureMaterial();enqueue({cachePath(page),notebookPath(),json,document.toUtf8(),image,material,finger});return true;}
    double lastX=0,lastY=0,lastP=.5;
    Q_INVOKABLE bool advance(int tool,double size,double strength,double x,double y,double p,bool first){
        if(tool<0||tool>7||!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(p)||size<1||size>80||strength<.05||strength>1)return false;
        x=std::clamp(x,0.0,1200.0);y=std::clamp(y,0.0,1600.0);p=std::clamp(p,.04,1.0);
        double threshold=std::clamp(size*.08,1.0,3.0),dx=x-lastX,dy=y-lastY;
        if(!first && dx*dx+dy*dy<threshold*threshold)return false;
        double ax=first?x:lastX,ay=first?y:lastY,ap=first?p:lastP;
        double radius=(tool==7?std::clamp(size/2,6.0,40.0):std::max(.8,size*(.18+.82*std::max(ap,p))/2))+2;
        auto dirty=QRectF(QPointF(std::min(ax,x)-radius,std::min(ay,y)-radius),QPointF(std::max(ax,x)+radius,std::max(ay,y)+radius)).toAlignedRect().intersected(image.rect());
        ensureMaterial();QElapsedTimer timer;timer.start();if(tentativeTouch)capture(dirty);
        physics.segment(reinterpret_cast<uint32_t*>(material.bits()),reinterpret_cast<uint32_t*>(image.bits()),reinterpret_cast<uint16_t*>(finger.bits()),tool,size,0,strength,ax,ay,ap,x,y,p,first?0:1);
        int elapsed=timer.elapsed();if(elapsed>slowest){slowest=elapsed;emit timingChanged();}
        pendingDirty=pendingDirty.united(dirty);publishDirty(dirty);lastX=x;lastY=y;lastP=p;return true;
    }
    static double noise(double x,double y,quint32 seed){double v=sin(x*12.9898+y*78.233+(seed%65536)*0.017)*43758.5453;return v-floor(v);}
    Q_INVOKABLE bool segment(QVariantList spec,QVariantList av,QVariantList bv,bool publish) {
        if(spec.size()!=7||av.size()!=3||bv.size()!=3)return false;
        int tool=spec[0].toInt(),index=spec[6].toInt();double size=spec[1].toDouble(),tone=spec[2].toDouble(),strength=spec[3].toDouble();
        quint32 seed=spec[5].toUInt();QPointF a(av[0].toDouble(),av[1].toDouble()),b(bv[0].toDouble(),bv[1].toDouble());
        if(tool<0||tool>7||!std::isfinite(size)||size<1||size>80||!std::isfinite(strength)||strength<0.05||strength>1||a.x()<0||a.x()>1200||a.y()<0||a.y()>1600||b.x()<0||b.x()>1200||b.y()<0||b.y()>1600)return false;
        double radius=(tool==7?sk_clamp(size/2,6,40):std::max(0.4,size*(0.18+0.82*std::max(av[2].toDouble(),bv[2].toDouble()))/2))+2;
        QRect dirty=QRectF(QPointF(std::min(a.x(),b.x())-radius,std::min(a.y(),b.y())-radius),QPointF(std::max(a.x(),b.x())+radius,std::max(a.y(),b.y())+radius)).toAlignedRect().intersected(image.rect());
        if(spec[4].toInt()>=8){
            ensureMaterial();QElapsedTimer timer;timer.start();if(tentativeTouch)capture(dirty);
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
        pendingDirty=pendingDirty.united(dirty);if(publish)emit changed(dirty);else unpublished=true;return true;
    }
signals:
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
        if(board)connect(board,&SketchRaster::changed,this,[this](QRect rect){
            auto local=rect.intersected(QRect(sx,sy,(int)width(),(int)height())).translated(-sx,-sy);
            if(!local.isEmpty()){pendingDamage+=local;update(local);}
        });
        update();
    }
    void paint(QPainter *painter)override{
        if(!board)return;
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
