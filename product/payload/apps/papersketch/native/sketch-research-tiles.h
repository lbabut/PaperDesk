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
 struct Batch{uint64_t revision=0;std::map<int,std::shared_ptr<const Pixels>> tiles;uint64_t page=1;};
private:
 static int count(int extent,int tile){if(extent<=0||tile<=0)throw std::invalid_argument("geometry");return 1+(extent-1)/tile;}
 const int width,height,size,columns,rows;
 std::vector<std::shared_ptr<const Pixels>> latest;
 std::mutex mutex;
 Batch pending;
 uint64_t producerRevision=0;
 uint64_t producerPage=1;
 std::vector<bool> dirty;
public:
 uint64_t copiedBytes=0; // Producer-owned diagnostic, read only after barrier.
 uint64_t inspectedTiles=0;
 DirtyTilesPrototype(int w,int h,int tile=128):width(w),height(h),size(tile),columns(count(w,tile)),rows(count(h,tile)){
  if(w<=0||h<=0||tile<=0)throw std::invalid_argument("geometry");
  for(int y=0;y<rows;y++)for(int x=0;x<columns;x++)
   latest.push_back(std::make_shared<const Pixels>(std::min(size,width-x*size)*std::min(size,height-y*size),0xffffffffu));
  dirty.assign(latest.size(),false);
 }
 bool publish(uint64_t revision,const Pixels &image){
  return publishForPage(producerPage,revision,image,false);
 }
 // Producer only, after prior page's accepted commands have reached a barrier.
 bool beginPage(uint64_t page){
  if(page<=producerPage)return false;
  for(auto &tile:latest)tile=std::make_shared<const Pixels>(tile->size(),0xffffffffu);
  std::fill(dirty.begin(),dirty.end(),false);producerPage=page;producerRevision=0;
  std::lock_guard<std::mutex> lock(mutex);pending=Batch{};pending.page=page;return true;
 }
 bool markRect(uint64_t page,int left,int top,int right,int bottom){
  if(page!=producerPage)return false;
  left=std::max(0,left);top=std::max(0,top);right=std::min(width-1,right);bottom=std::min(height-1,bottom);
  if(left>right||top>bottom)return true;
  for(int y=top/size;y<=bottom/size;y++)for(int x=left/size;x<=right/size;x++)dirty[y*columns+x]=true;
  return true;
 }
 bool publishForPage(uint64_t page,uint64_t revision,const Pixels &image,bool markedOnly=true){
  if(page!=producerPage)return false;
  if(image.size()!=size_t(width)*height)throw std::invalid_argument("image");
  if(revision<=producerRevision)return false;
  std::map<int,std::shared_ptr<const Pixels>> changed;
  for(int ty=0;ty<rows;ty++)for(int tx=0;tx<columns;tx++){
   int index=ty*columns+tx,tw=std::min(size,width-tx*size),th=std::min(size,height-ty*size);bool same=true;
   if(markedOnly&&!dirty[index])continue;
   inspectedTiles++;
   const auto &old=*latest[index];
   for(int y=0;y<th&&same;y++)same=std::equal(old.begin()+y*tw,old.begin()+(y+1)*tw,image.begin()+(ty*size+y)*width+tx*size);
   if(same)continue;
   auto tile=std::make_shared<Pixels>();tile->reserve(tw*th);
   for(int y=0;y<th;y++){auto first=image.begin()+(ty*size+y)*width+tx*size;tile->insert(tile->end(),first,first+tw);}
   copiedBytes+=tile->size()*sizeof(uint32_t);latest[index]=tile;changed[index]=std::move(tile);
  }
  producerRevision=revision;
  std::fill(dirty.begin(),dirty.end(),false);
  // No material/image scan or allocation under the consumer lock except map nodes.
  std::lock_guard<std::mutex> lock(mutex);
  for(auto &entry:changed)pending.tiles[entry.first]=std::move(entry.second);
  pending.revision=revision;pending.page=page;return true;
 }
 Batch take(){std::lock_guard<std::mutex> lock(mutex);Batch result;std::swap(result,pending);return result;}
 bool apply(const Batch &batch,Pixels &canvas,uint64_t expectedPage=1)const{
  if(batch.page!=expectedPage)return false;
  if(canvas.size()!=size_t(width)*height)throw std::invalid_argument("canvas");
  for(const auto &entry:batch.tiles){
   if(entry.first<0||size_t(entry.first)>=latest.size()||!entry.second)throw std::invalid_argument("tile");
   int tx=entry.first%columns,ty=entry.first/columns,tw=std::min(size,width-tx*size),th=std::min(size,height-ty*size);
   if(entry.second->size()!=size_t(tw)*th)throw std::invalid_argument("tile pixels");
   for(int y=0;y<th;y++)std::copy_n(entry.second->begin()+y*tw,tw,canvas.begin()+(ty*size+y)*width+tx*size);
  }
  return true;
 }
 size_t tileCount()const{return latest.size();}
};
