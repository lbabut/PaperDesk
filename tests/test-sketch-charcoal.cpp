
#define PaperMaterial OldMaterial
#include "fixtures/sketch-material-4.2.7.h"
#undef PaperMaterial
#undef PAPER_SKETCH_MATERIAL_H
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <QtGui/QGuiApplication>
#include <QtGui/QImage>
#include <QtGui/QPainter>
#include <cassert>
template<class M> struct Canvas{
 M p;std::vector<uint32_t> mass,image;std::vector<uint16_t> finger;
 Canvas():mass(500*640),image(500*640,0xffffffffu),finger(82*81){p.init(500,640);}
 void line(int tool,int y,double pressure,double size=60){
  p.segment(mass.data(),image.data(),finger.data(),tool,size,0,1,40,y,pressure,40,y,pressure,0);
  p.segment(mass.data(),image.data(),finger.data(),tool,size,0,1,40,y,pressure,460,y,pressure,1);
 }
};
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);Canvas<OldMaterial> old;Canvas<PaperMaterial> now;
 for(int tool:{4,5})for(int i=0;i<4;i++){
  double pressure[]={.15,.35,.65,1};int y=50+(tool-4)*310+i*70;
  old.line(tool,y,pressure[i]);now.line(tool,y,pressure[i]);
 }
 QImage left((const uchar*)old.image.data(),500,640,2000,QImage::Format_RGB32);
 QImage right((const uchar*)now.image.data(),500,640,2000,QImage::Format_RGB32);
 QImage comparison(1000,675,QImage::Format_RGB32);comparison.fill(Qt::white);
 QPainter painter(&comparison);painter.drawImage(0,35,left);painter.drawImage(500,35,right);
 painter.drawText(20,23,"Before: charcoal / soft charcoal, pressure .15 .35 .65 1");
 painter.drawText(520,23,"After");painter.end();assert(comparison.save("work/charcoal-comparison.png"));comparison.scaledToWidth(700).save("work/charcoal-comparison.jpg","JPG",65);
 for(int tool:{4,5}){
  Canvas<PaperMaterial> light,firm;light.line(tool,160,.15);firm.line(tool,160,.8);
  uint64_t lm=0,fm=0,loose=0;
  for(size_t i=0;i<light.mass.size();i++){lm+=(light.mass[i]>>16)+(light.mass[i]&65535);fm+=(firm.mass[i]>>16)+(firm.mass[i]&65535);loose+=firm.mass[i]&65535;}
  assert(fm>lm*2&&loose>fm*.7);
  auto before=firm.mass;firm.line(tool,160,.8);
  uint64_t layered=0;for(auto m:firm.mass)layered+=(m>>16)+(m&65535);assert(layered>fm);
  Canvas<PaperMaterial> split,whole;
  whole.line(tool,320,.5);split.p.segment(split.mass.data(),split.image.data(),split.finger.data(),tool,60,0,1,40,320,.5,40,320,.5,0);
  for(int x=41;x<=460;x++)split.p.segment(split.mass.data(),split.image.data(),split.finger.data(),tool,60,0,1,x-1,320,.5,x,320,.5,1);
  assert(whole.mass==split.mass&&whole.image==split.image);
  int minimum=255,maximum=0;
  for(int y=316;y<325;y++)for(int x=100;x<400;x++){int gray=whole.image[y*500+x]&255;minimum=std::min(minimum,gray);maximum=std::max(maximum,gray);}
  assert(maximum-minimum>60);printf("charcoal %d texture gray range %d..%d\n",tool,minimum,maximum);
 }

 for(int paper=0;paper<3;paper++){
  double first[2]={0,0};
  for(int tool:{4,5}){
   Canvas<PaperMaterial> layers;layers.p.setPaperKind(paper);double previous=255;
   for(int pass=0;pass<5;pass++){
    layers.line(tool,320,.5,48);double sum=0;int count=0;
    for(int y=316;y<=324;y++)for(int x=100;x<400;x++){sum+=layers.image[y*500+x]&255;count++;}
    double gray=sum/count;if(pass==0)first[tool-4]=gray;
    assert(gray<previous-.5);previous=gray;
   }
   assert(previous<first[tool-4]-25);
  }
  assert(first[1]<first[0]-20);
 }
 puts("PASS five visibly darker layers and distinct normal/soft charcoal on all three papers");
 puts("PASS pressure, loose dust, layered darkening, broad grain and event invariance");
}
