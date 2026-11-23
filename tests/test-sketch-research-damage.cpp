#include "../product/payload/apps/papersketch/native/sketch-research-tiles.h"
#include <cassert>
int main(){
 DirtyTilesPrototype t(256,256);DirtyTilesPrototype::Pixels image(256*256,0xffffffffu),canvas=image;
 image[5*256+4]=0xff000000;t.markRect(1,4,5,4,5);assert(t.publishForPage(1,1,image));
 image[10*256+11]=0xff000000;t.markRect(1,11,10,11,10);assert(t.publishForPage(1,2,image));
 auto b=t.take();assert(b.tiles.size()==1&&b.damage.size()==1);auto r=b.damage.at(0);assert(r.left==4&&r.top==5&&r.right==11&&r.bottom==10);assert(t.apply(b,canvas)&&canvas==image);
 image[130*256+140]=0xff111111;t.markRect(1,140,130,140,130);assert(t.publishForPage(1,3,image));b=t.take();assert(b.damage.size()==1&&b.damage.count(3));assert(t.apply(b,canvas)&&canvas==image);
 assert(t.beginPage(2));assert(t.take().damage.empty());assert(!t.markRect(1,0,0,255,255));assert(t.publishForPage(2,1,image,false));b=t.take();assert(b.damage.at(0).right==127&&b.damage.at(3).right==255);
}
