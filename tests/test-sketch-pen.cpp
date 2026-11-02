#include "../product/payload/apps/papersketch/native/sketch-pen.h"
#include <cassert>
int main(){
 PaperPen pen;pen.push(100,200,.2,4);auto first=pen.match(100,200);
 pen.push(110,210,.5,4);pen.push(120,200,.9,4);auto last=pen.match(120,200);
 assert(pen.at(100,200)==.2&&pen.at(120,200)==.9&&pen.at(300,300)<0);
 std::array<PaperPen::Sample,64> path;auto n=pen.between(first.id,last,path);assert(n==2&&path[0].x==110&&path[1].x==120);
 pen.push(140,220,.4,5);auto separate=pen.match(140,220);n=pen.between(first.id,separate,path);assert(n==1&&path[0].contact==5);
 for(int i=0;i<100;i++)pen.push(i,300,.5,6);
 auto end=pen.match(99,300);n=pen.between(0,end,path);assert(n==64&&path[63].id==end.id&&path[0].id==end.id-63);
 pen.pause();assert(pen.at(100,200)<0);
 pen.push(100,200,.5,8,.6,-.3);auto tilted=pen.match(100,200);
 assert(tilted.tiltX==.6&&tilted.tiltY==-.3);
 pen.push(145,230,.6,9,0,0,true);auto rubber=pen.match(145,230);assert(rubber.eraser);
 pen.push(150,240,.7,10);assert(!pen.match(150,240).eraser);
 pen.eraserNearby=true;pen.pause();assert(!pen.eraserNearby.load());
 pen.pause();pen.resetMatchDiagnostics();assert(pen.matchDiagnostics().calls==0);
 pen.push(123,456,.5,20);
 {std::lock_guard<std::mutex> lock(pen.mutex);pen.samples[(pen.head+pen.samples.size()-1)%pen.samples.size()].time-=1500;}
 assert(pen.match(123,456).p<0); // Existing1000ms acceptance window is unchanged.
 auto stats=pen.matchDiagnostics();
 assert(stats.calls==1&&stats.misses==1&&stats.stalePositionMisses==1&&stats.samplesAtMiss==1);
 assert(stats.nearestMissAge>=1500&&stats.youngestMissAge>=1500&&stats.nearestMissDistance==0&&stats.maxStaleAge>=1500);
 pen.resetMatchDiagnostics();assert(pen.matchDiagnostics().misses==0);
 assert(pen.match(500,500).p<0&&pen.matchDiagnostics().stalePositionMisses==0);
}
