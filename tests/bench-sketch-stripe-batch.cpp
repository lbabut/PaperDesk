// Offline CPU prototype, never installed. No GUI, raw input or persistence.
#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <chrono>
#include <cstdio>
struct Point{int tool;double size,strength,ax,ay,ap,x,y,p,tx,ty;bool first;};
struct Surface{
 PaperMaterial physics;std::vector<uint32_t> mass,image;std::vector<uint16_t> finger;
 Surface(int w,int h):mass(w*h),image(w*h,0xffffffffu),finger(82*81){physics.init(w,h);}
};
static void advance(PaperMaterial &p,Surface &s,const Point &c){
 p.tiltX=c.tx;p.tiltY=c.ty;p.contactAspect=1;p.contactAngle=0;
 p.segment(s.mass.data(),s.image.data(),s.finger.data(),c.tool,c.size,0,c.strength,c.ax,c.ay,c.ap,c.x,c.y,c.p,c.first?0:1);
}
struct Striped{
 Surface &surface;PaperMaterial second;
 explicit Striped(Surface &s):surface(s),second(s.physics){}
 void batch(const std::vector<Point> &points,size_t begin,size_t end){
  auto lane=[&](int index,PaperMaterial &physics){
   PaperMaterialRows::SerialScope serial;PaperMaterialRows::ResearchStripeScope stripe(index);
   for(size_t i=begin;i<end;i++){assert(points[i].tool==4||points[i].tool==5);advance(physics,surface,points[i]);}
  };
  PaperMaterialRows::instance().run([&]{lane(1,second);},[&]{lane(0,surface.physics);});
 }
 void merge(){
  auto &a=surface.physics;assert(a.wear==second.wear&&a.untilNext==second.untilNext);
  for(int y=0;y<a.height;y++)if((y/8)&1)std::copy_n(second.burnish.begin()+y*a.width,a.width,a.burnish.begin()+y*a.width);
 }
};
static void equal(const Surface &a,const Surface &b){
 assert(a.mass==b.mass&&a.image==b.image&&a.finger==b.finger);
 assert(a.physics.tooth==b.physics.tooth&&a.physics.burnish==b.physics.burnish&&a.physics.ink==b.physics.ink);
 assert(a.physics.wear==b.physics.wear&&a.physics.untilNext==b.physics.untilNext&&a.physics.hasInk==b.physics.hasInk);
}
static std::vector<Point> trace(int w,int h,int tool,int count,bool varied){
 std::vector<Point> out;double ax=20,ay=20,ap=.2;
 for(int i=0;i<count;i++){
  const auto hash=PaperMaterial::hash(i,82);
  double x=varied?double(hash%unsigned(w+32))-16.125:20.+(w-40.)*i/(count-1),
         y=varied?double((hash>>16)%unsigned(h+32))-16.375:h*.5+40*std::sin(i*.16),
         p=.05+.95*(i%83)/82.,tx=varied?.95*std::sin(i*.07):.8,ty=varied?.4*std::cos(i*.11):.15;
  out.push_back({tool,varied?1.+(hash%7900)/100.:38.,varied?.2+.8*(i%11)/10.:1.,ax,ay,ap,x,y,p,tx,ty,i==0});
  ax=x;ay=y;ap=p;
 }
 return out;
}
static void correctness(){
 int checked=0;
 for(int paper=0;paper<3;paper++)for(int tool:{4,5})for(int batch:{1,8,24}){
  Surface a(128,128),b(128,128);a.physics.setPaperKind(paper);b.physics.setPaperKind(paper);
  // Nonwhite, polished and ink-bearing starting page, not only blank paper.
  for(size_t i=0;i<a.mass.size();i++){
   a.mass[i]=b.mass[i]=(uint32_t(i%400)<<16)|uint32_t(i%300);
   a.physics.burnish[i]=b.physics.burnish[i]=i%96;
   a.physics.ink[i]=b.physics.ink[i]=i%71==0?170:0;
   int gray=a.physics.optical[(i%400)+(i%300)];gray=(gray*(255-a.physics.ink[i])+127)/255;
   a.image[i]=b.image[i]=0xff000000u|uint32_t(gray)*0x010101u;
  }
  a.physics.hasInk=b.physics.hasInk=true;
  for(int stroke=0;stroke<2;stroke++){
   auto points=trace(128,128,tool,97,true);Striped striped(b);
   for(size_t i=0;i<points.size();i+=batch){
    const size_t end=std::min(points.size(),i+batch);
    for(size_t k=i;k<end;k++)advance(a.physics,a,points[k]);
    striped.batch(points,i,end);striped.merge();equal(a,b);checked++;
   }
  }
 }
 assert(PaperMaterialRows::researchRowStripe()==-1&&PaperMaterialRows::threadParallelAllowed());
 printf("PASS %d exact chunk states: repeated charcoal, papers, pressure, tilt, clipped edges, ink and burnish\n",checked);fflush(stdout);
}
static long long run(Surface &s,const std::vector<Point> &points,int batch){
 auto started=std::chrono::steady_clock::now();
 if(!batch){for(const auto &c:points)advance(s.physics,s,c);}
 else{Striped striped(s);for(size_t i=0;i<points.size();i+=batch)striped.batch(points,i,std::min(points.size(),i+batch));striped.merge();}
 return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-started).count();
}
int main(){
 correctness();
 for(int repeat=0;repeat<2;repeat++)for(int tool:{4,5})for(int batch:{8,24}){
  Surface a(1200,1600),b(1200,1600);auto points=trace(1200,1600,tool,1260,false);
  long long baseline,candidate;
  if(repeat){candidate=run(b,points,batch);baseline=run(a,points,0);}
  else{baseline=run(a,points,0);candidate=run(b,points,batch);}
  equal(a,b);
  printf("{\"repeat\":%d,\"tool\":%d,\"batch\":%d,\"baseline_us\":%lld,\"candidate_us\":%lld,\"ratio\":%.6f}\n",repeat,tool,batch,baseline,candidate,double(candidate)/baseline);fflush(stdout);
 }
}
