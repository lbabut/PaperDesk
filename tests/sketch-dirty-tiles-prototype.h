// Research-only immutable dirty-tile transport. One producer, one consumer.
// A slow consumer accumulates latest tile versions, NOT just the last delta.
#pragma once
#include <vector>
#include <map>
#include <memory>
#include <mutex>
#include <cstdint>
#include <stdexcept>
#include <algorithm>
class DirtyTilesPrototype {
public:
 using Pixels=std::vector<uint32_t>;
 struct Batch{uint64_t revision=0;std::map<int,std::shared_ptr<const Pixels>> tiles;};
private:
 static int count(int extent,int tile){if(extent<=0||tile<=0)throw std::invalid_argument("geometry");return 1+(extent-1)/tile;}
 const int width,height,size,columns,rows;
 std::vector<std::shared_ptr<const Pixels>> latest;
 std::mutex mutex;
 Batch pending;
 uint64_t producerRevision=0;
public:
 uint64_t copiedBytes=0; // Producer-owned diagnostic, read only after barrier.
 DirtyTilesPrototype(int w,int h,int tile=128):width(w),height(h),size(tile),columns(count(w,tile)),rows(count(h,tile)){
  if(w<=0||h<=0||tile<=0)throw std::invalid_argument("geometry");
  for(int y=0;y<rows;y++)for(int x=0;x<columns;x++)
   latest.push_back(std::make_shared<const Pixels>(std::min(size,width-x*size)*std::min(size,height-y*size),0xffffffffu));
 }
 bool publish(uint64_t revision,const Pixels &image){
  if(image.size()!=size_t(width)*height)throw std::invalid_argument("image");
  if(revision<=producerRevision)return false;
  std::map<int,std::shared_ptr<const Pixels>> changed;
  for(int ty=0;ty<rows;ty++)for(int tx=0;tx<columns;tx++){
   int index=ty*columns+tx,tw=std::min(size,width-tx*size),th=std::min(size,height-ty*size);bool same=true;
   const auto &old=*latest[index];
   for(int y=0;y<th&&same;y++)same=std::equal(old.begin()+y*tw,old.begin()+(y+1)*tw,image.begin()+(ty*size+y)*width+tx*size);
   if(same)continue;
   auto tile=std::make_shared<Pixels>();tile->reserve(tw*th);
   for(int y=0;y<th;y++){auto first=image.begin()+(ty*size+y)*width+tx*size;tile->insert(tile->end(),first,first+tw);}
   copiedBytes+=tile->size()*sizeof(uint32_t);latest[index]=tile;changed[index]=std::move(tile);
  }
  producerRevision=revision;
  // No material/image scan or allocation under the consumer lock except map nodes.
  std::lock_guard<std::mutex> lock(mutex);
  for(auto &entry:changed)pending.tiles[entry.first]=std::move(entry.second);
  pending.revision=revision;return true;
 }
 Batch take(){std::lock_guard<std::mutex> lock(mutex);Batch result;std::swap(result,pending);return result;}
 void apply(const Batch &batch,Pixels &canvas)const{
  if(canvas.size()!=size_t(width)*height)throw std::invalid_argument("canvas");
  for(const auto &entry:batch.tiles){
   if(entry.first<0||size_t(entry.first)>=latest.size()||!entry.second)throw std::invalid_argument("tile");
   int tx=entry.first%columns,ty=entry.first/columns,tw=std::min(size,width-tx*size),th=std::min(size,height-ty*size);
   if(entry.second->size()!=size_t(tw)*th)throw std::invalid_argument("tile pixels");
   for(int y=0;y<th;y++)std::copy_n(entry.second->begin()+y*tw,tw,canvas.begin()+(ty*size+y)*width+tx*size);
  }
 }
 size_t tileCount()const{return latest.size();}
};
