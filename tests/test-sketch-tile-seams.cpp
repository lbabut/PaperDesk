
#include "../product/payload/apps/papersketch/native/papersketch-raster.cpp"
#include <QtGui/QGuiApplication>
#include <QtQuick/QQuickWindow>
#include <QtQuick/QSGRendererInterface>
#include <QtCore/QThread>
#include <cassert>
int main(int argc,char**argv){
 QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
 QGuiApplication app(argc,argv);QTemporaryDir directory;
 for(double scale:{.73,.87,.95,1.0,1.07,1.17}){
  SketchRaster board(nullptr,directory.path());board.image.fill(Qt::white);
  QQuickWindow window;window.resize(650,650);window.setColor(Qt::white);
  QQuickItem sheet(window.contentItem());sheet.setTransformOrigin(QQuickItem::TopLeft);
  sheet.setPosition(QPointF(.37,.61));sheet.setScale(scale);sheet.setSize(QSizeF(512,512));
  std::vector<std::unique_ptr<SketchTile>> tiles;
  for(int y=0;y<4;y++)for(int x=0;x<4;x++){
   auto tile=std::make_unique<SketchTile>(&sheet);
   tile->setPosition(QPointF(x*128,y*128));tile->setSize(QSizeF(x<3?129:128,y<3?129:128));
   tile->setProperty("sourceX",x*128);tile->setProperty("sourceY",y*128);tile->setRaster(&board);
   tiles.push_back(std::move(tile));
  }
  window.show();QElapsedTimer timer;timer.start();
  while(timer.elapsed()<150){app.processEvents();QThread::msleep(1);}
  for(int y=4;y<508;y+=9){
   for(int yy=y;yy<std::min(508,y+9);yy++)for(int x=4;x<508;x++)board.image.setPixel(x,yy,0xff000000);
   board.publishDirty(QRect(4,y,504,std::min(9,508-y)));
   QElapsedTimer paint;paint.start();while(paint.elapsed()<3){app.processEvents();QThread::msleep(1);}
  }
  timer.restart();while(timer.elapsed()<100){app.processEvents();QThread::msleep(1);}
  auto frame=window.grabWindow();assert(!frame.isNull());int light=0;
  for(int y=8;y<int(504*scale)-2;y++)for(int x=8;x<int(504*scale)-2;x++)if(qRed(frame.pixel(x,y))>10)light++;
  printf("scale %.2f light pixels %d\n",scale,light);fflush(stdout);
  assert(light==0);
 }
}
