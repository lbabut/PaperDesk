#include <QtCore/QObject>
#include <QtCore/QVariantList>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDir>
#include <QtCore/QSaveFile>
#include <QtCore/QBuffer>
#include <QtCore/QElapsedTimer>
#include <QtGui/QImage>
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
#include <linux/input.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include "sketch-smudge.h"

class SketchRaster:public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(int maxSmudgeMs READ maxSmudgeMs NOTIFY timingChanged)
public:
    QImage image{1200,1600,QImage::Format_RGB32};
    QImage before;
    QList<QImage> undoImages,redoImages;
    QString cacheNamespace="PaperDeskSketch";QString cacheDirectory;
    int slowest=0;QRect pendingDirty;bool unpublished=false;
    struct SaveJob {QString cache,file,json;QByteArray document;QImage snapshot;};
    std::mutex saveMutex;std::condition_variable saveWake;std::deque<SaveJob> saves;
    bool stopping=false;std::thread writer;
    static bool atomicWrite(const QString &path,const QByteArray &bytes){
        QSaveFile f(path);return f.open(QIODevice::WriteOnly) && f.write(bytes)==bytes.size() && f.commit();
    }
    void writeLoop(){
        for(;;){
            SaveJob job;
            {std::unique_lock<std::mutex> lock(saveMutex);saveWake.wait(lock,[this]{return stopping||!saves.empty();});
             if(saves.empty()&&stopping)return;job=std::move(saves.front());saves.pop_front();}
            QDir().mkpath(cacheDirectory);bool ok=true;
            // Commit the authoritative stroke document first. A stale cache is rejected by its hash.
            if(!job.file.isEmpty())ok=atomicWrite(job.file,job.document);
            if(ok){
                QSaveFile f(job.cache);ok=f.open(QIODevice::WriteOnly);
                if(ok){f.write(QCryptographicHash::hash(job.json.toUtf8(),QCryptographicHash::Sha256).toHex()+"\n");ok=job.snapshot.save(&f,"PNG")&&f.commit();}
            }
            if(!ok)emit saveFailed();else emit saveCompleted();
        }
    }
    void enqueue(SaveJob job){
        {std::lock_guard<std::mutex> lock(saveMutex);
         // Only replace pending work for the same page; other pages remain durable.
         for(auto it=saves.begin();it!=saves.end();){if(it->cache==job.cache && (it->file.isEmpty()||!job.file.isEmpty()))it=saves.erase(it);else ++it;}
         saves.push_back(std::move(job));}
        saveWake.notify_one();
    }
    SketchRaster(QObject *parent=nullptr,QString directory="/home/root/.local/share/paperdesk/sketch"):QObject(parent),cacheDirectory(directory){image.fill(Qt::white);writer=std::thread([this]{writeLoop();});}
    ~SketchRaster() override {{std::lock_guard<std::mutex> lock(saveMutex);stopping=true;}saveWake.notify_one();writer.join();if(pressureFd>=0)close(pressureFd);}
    mutable int pressureFd=-1;
    Q_INVOKABLE double penPressure(double fallback)const{
        if(pressureFd<0){
            int fd=open("/dev/input/event1",O_RDONLY|O_NONBLOCK|O_CLOEXEC);char name[128]={0};
            if(fd>=0 && ioctl(fd,EVIOCGNAME(sizeof name),name)>=0 && strstr(name,"Wacom"))pressureFd=fd;
            else if(fd>=0)close(fd);
        }
        input_absinfo pressure{};
        if(pressureFd>=0 && ioctl(pressureFd,EVIOCGABS(ABS_PRESSURE),&pressure)==0 && pressure.maximum>pressure.minimum && pressure.value>pressure.minimum)
            return sk_clamp(double(pressure.value-pressure.minimum)/(pressure.maximum-pressure.minimum),0.05,1);
        return fallback;
    }
    bool available()const{return true;}
    int maxSmudgeMs()const{return slowest;}
    Q_INVOKABLE bool importPixels(QJSValue pixels) {
        if(pixels.property("length").toInt()!=1200*1600*4)return false;
        QImage next(1200,1600,QImage::Format_RGB32);
        for(int y=0;y<1600;y++){auto row=reinterpret_cast<QRgb*>(next.scanLine(y));for(int x=0;x<1200;x++){int v=pixels.property((y*1200+x)*4).toInt();row[x]=qRgb(v,v,v);}}
        image=next;undoImages.clear();redoImages.clear();before=QImage();emit changed(QRect(0,0,1200,1600));return true;
    }
    Q_INVOKABLE void setNamespace(QString name){cacheNamespace=name;}
    Q_INVOKABLE void release(){image=QImage();before=QImage();undoImages.clear();redoImages.clear();}
    Q_INVOKABLE void resetWhite(){if(image.size()!=QSize(1200,1600))image=QImage(1200,1600,QImage::Format_RGB32);image.fill(Qt::white);before=QImage();undoImages.clear();redoImages.clear();slowest=0;emit timingChanged();emit changed(image.rect());}
    Q_INVOKABLE void begin(){before=image;pendingDirty=QRect();unpublished=false;}
    Q_INVOKABLE void finish(){if(!before.isNull()){undoImages.append(before);while(undoImages.size()>8)undoImages.removeFirst();before=QImage();redoImages.clear();}if(unpublished && !pendingDirty.isEmpty())emit changed(pendingDirty);pendingDirty=QRect();unpublished=false;}
    Q_INVOKABLE bool undo(){if(undoImages.isEmpty())return false;redoImages.append(image);image=undoImages.takeLast();emit changed(QRect(0,0,1200,1600));return true;}
    Q_INVOKABLE bool redo(){if(redoImages.isEmpty())return false;undoImages.append(image);image=redoImages.takeLast();emit changed(QRect(0,0,1200,1600));return true;}
    Q_INVOKABLE QVariantList pixels(int x,int y,int w,int h)const {
        QVariantList out;if(w<0||h<0||w*h>4096)return out;out.reserve(w*h*4);
        for(int py=y;py<y+h;py++)for(int px=x;px<x+w;px++){auto c=image.valid(px,py)?image.pixel(px,py):qRgb(255,255,255);out<<qRed(c)<<qGreen(c)<<qBlue(c)<<255;}return out;
    }
    Q_INVOKABLE bool save(const QString&path)const{return image.save(path,"PNG");}
    QString cachePath(int page)const{return (cacheDirectory+QStringLiteral("/cache-%1-%2.bin")).arg(QString::fromLatin1(QCryptographicHash::hash(cacheNamespace.toUtf8(),QCryptographicHash::Sha256).toHex().left(12))).arg(page);}
    Q_INVOKABLE bool loadCache(int page,const QString&json){
        QFile f(cachePath(page));if(!f.open(QIODevice::ReadOnly)||f.size()>12*1024*1024)return false;
        auto key=QCryptographicHash::hash(json.toUtf8(),QCryptographicHash::Sha256).toHex();
        if(f.readLine().trimmed()!=key)return false;QImage next=QImage::fromData(f.readAll(),"PNG");
        if(next.size()!=QSize(1200,1600))return false;image=next.convertToFormat(QImage::Format_RGB32);undoImages.clear();redoImages.clear();before=QImage();emit changed(image.rect());return true;
    }
    QString notebookPath()const{return cachePath(0)+".notebook.json";}
    Q_INVOKABLE QString loadNotebook()const{QFile f(notebookPath());if(!f.open(QIODevice::ReadOnly)||f.size()>16*1024*1024)return QString();return QString::fromUtf8(f.readAll());}
    Q_INVOKABLE bool saveCache(int page,const QString&json){enqueue({cachePath(page),QString(),json,QByteArray(),image});return true;}
    Q_INVOKABLE bool saveNotebook(const QString&document,int page,const QString&json){enqueue({cachePath(page),notebookPath(),json,document.toUtf8(),image});return true;}
    static double noise(double x,double y,quint32 seed){double v=sin(x*12.9898+y*78.233+(seed%65536)*0.017)*43758.5453;return v-floor(v);}
    Q_INVOKABLE bool segment(QVariantList spec,QVariantList av,QVariantList bv,bool publish) {
        if(spec.size()!=7||av.size()!=3||bv.size()!=3)return false;
        int tool=spec[0].toInt(),index=spec[6].toInt();double size=spec[1].toDouble(),tone=spec[2].toDouble(),strength=spec[3].toDouble();
        quint32 seed=spec[5].toUInt();QPointF a(av[0].toDouble(),av[1].toDouble()),b(bv[0].toDouble(),bv[1].toDouble());
        if(tool<0||tool>7||!std::isfinite(size)||size<1||size>80||!std::isfinite(strength)||strength<0.05||strength>1||a.x()<0||a.x()>1200||a.y()<0||a.y()>1600||b.x()<0||b.x()>1200||b.y()<0||b.y()>1600)return false;
        double radius=(tool==7?sk_clamp(size/2,6,40):std::max(0.4,size*(0.18+0.82*std::max(av[2].toDouble(),bv[2].toDouble()))/2))+2;
        QRect dirty=QRectF(QPointF(std::min(a.x(),b.x())-radius,std::min(a.y(),b.y())-radius),QPointF(std::max(a.x(),b.x())+radius,std::max(a.y(),b.y())+radius)).toAlignedRect().intersected(image.rect());
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
    SketchRaster *board=nullptr;int sx=0,sy=0;QImage painted;
public:
    SketchTile(QQuickItem *parent=nullptr):QQuickPaintedItem(parent){setRenderTarget(QQuickPaintedItem::Image);setOpaquePainting(true);}
    QObject* raster()const{return board;}
    void setRaster(QObject*obj){if(board)disconnect(board,nullptr,this,nullptr);board=qobject_cast<SketchRaster*>(obj);if(board)connect(board,&SketchRaster::changed,this,[this](QRect rect){if(rect.intersects(QRect(sx,sy,(int)width(),(int)height())))update();});update();}
    void paint(QPainter *painter)override{if(!board)return;painted=board->image.copy(sx,sy,(int)width(),(int)height());painter->drawImage(0,0,painted);}
    Q_INVOKABLE QVariantList pixels(int x,int y,int w,int h)const{QVariantList out;if(w<0||h<0||w*h>4096)return out;for(int py=y;py<y+h;py++)for(int px=x;px<x+w;px++){auto c=painted.valid(px,py)?painted.pixel(px,py):qRgb(255,255,255);out<<qRed(c)<<qGreen(c)<<qBlue(c)<<255;}return out;}
};
extern "C" void _xovi_construct(){
    qmlRegisterSingletonType<SketchRaster>("PaperSketch.Native",1,0,"Raster",[](QQmlEngine*,QJSEngine*)->QObject*{return new SketchRaster;});
    qmlRegisterType<SketchTile>("PaperSketch.Native",1,0,"RasterTile");
    fprintf(stderr,"[papersketch-raster] native image engine registered\n");
}
#include "papersketch-raster.moc"
