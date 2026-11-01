#include <QtGui/QRegion>
#include <QtCore/QRect>
#include <array>
#include <vector>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <cassert>
struct Tile{QRect bounds;QRegion pending;};
std::vector<QRect> events(){std::vector<QRect> out;double ax=120,ay=900;for(int i=0;i<1260;i++){int pass=i/60,step=i%60;double x=120+960.*pass/20,y=900+300.*(pass%2?59-step:step)/59,p=.125+.75*step/59;double radius=19*(.35+.65*std::pow(p,.8))+3;out.push_back(QRectF(QPointF(std::min(ax,x)-radius,std::min(ay,y)-radius),QPointF(std::max(ax,x)+radius,std::max(ay,y)+radius)).toAlignedRect());ax=x;ay=y;}return out;}
double run(int mode,int repeat,int &touches){std::array<Tile,130> tiles;for(int i=0;i<130;i++)tiles[i].bounds=QRect(i%10*128,i/10*128,std::min(128,1200-i%10*128),std::min(128,1600-i/10*128));auto path=events();touches=0;auto start=std::chrono::steady_clock::now();for(int r=0;r<repeat;r++)for(int n=0;n<int(path.size());n++){QRegion region(path[n]);auto box=region.boundingRect();for(auto &tile:tiles){if(mode&& !box.intersects(tile.bounds))continue;if(mode==2&&region.rectCount()==1){auto local=box.intersected(tile.bounds).translated(-tile.bounds.x(),-tile.bounds.y());if(!local.isEmpty()){tile.pending+=local;touches++;}}else{auto local=region.intersected(tile.bounds).translated(-tile.bounds.x(),-tile.bounds.y());if(!local.isEmpty()){tile.pending+=local;touches++;}}}if(n%4==3)for(auto &tile:tiles)tile.pending=QRegion();}return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();}
int main(){int expected=0;for(int mode=0;mode<3;mode++){int count;run(mode,1,count);if(mode==0)expected=count;assert(count==expected);}for(int round=0;round<7;round++){printf("{\"round\":%d",round);for(int mode=0;mode<3;mode++){int count;auto ms=run(mode,120,count);assert(count==expected*120);printf(",\"mode%d_ms\":%.3f",mode,ms);}puts("}");}}
