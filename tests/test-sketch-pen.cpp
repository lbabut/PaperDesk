#include "../product/payload/apps/papersketch/native/sketch-pen.h"
#include <cassert>
#include <cstdio>
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

 // Closed contacts survive a stalled GUI, even at exactly the same position.
 pen.pause();pen.enableInput(true);int wakes=0;pen.setInputWake([&]{wakes++;});
 for(unsigned c=100;c<200;c++){
  pen.frame(100.125,200.0625,0,c,.1,-.2,false,true);
  pen.frame(100.1875,200.0625,.8,c,.1,-.2,false,true);
  pen.frame(100.1875,200.0625,0,c,.1,-.2,false,false);
 }
 assert(wakes==1);unsigned received=0,closed=0;uint64_t previous=0;
 while(pen.inputPending()){
  auto batch=pen.takeInput();assert(batch.size()<=64);
  for(const auto &event:batch){assert(event.sample.id>previous);previous=event.sample.id;
   assert(event.sample.contact==100+received/3);assert(event.phase==int(received%3)+1);
   assert(event.sample.tiltX==.1&&event.sample.tiltY==-.2);if(event.phase==3)closed++;received++;
  }
 }
 assert(received==300&&closed==100&&pen.inputStats()[1]==0);
 // The contact keeps its original viewport; toolbar taps are excluded.
 pen.setViewport(10,20,2,2);
 pen.frame(610.25,820.125,.5,300,0,0,true,true);
 pen.setViewport(100,200,1,1);
 pen.frame(610.25,820.125,0,300,0,0,true,false);
 auto geometry=pen.takeInput();assert(geometry.size()==2);
 assert(geometry[0].sample.x==300.125&&geometry[0].sample.y==400.0625&&geometry[0].sample.eraser);
 assert(geometry[1].sample.x==300.125);
 pen.frame(50,50,.5,301,0,0,false,true);pen.frame(150,250,.5,301,0,0,false,true);pen.frame(150,250,0,301,0,0,false,false);
 assert(!pen.inputPending()); // Entering from a toolbar cannot start a stroke.
 pen.enableInput(false);pen.frame(200,300,.5,302,0,0,false,true);
 pen.enableInput(true);pen.frame(210,310,.6,302,0,0,false,true);pen.frame(210,310,0,302,0,0,false,false);
 assert(!pen.inputPending()); // Arming does not capture a half-finished contact.
 pen.frame(200,300,.5,303,0,0,false,true);pen.frame(200,300,0,303,0,0,false,false);
 assert(pen.takeInput().size()==2);

 pen.frame(200,300,.5,304,0,0,false,true);pen.takeInput();pen.discontinuity();
 auto boundary=pen.takeInput();assert(boundary.size()==1&&boundary[0].phase==4);
 pen.frame(205,300,.6,304,0,0,false,true);pen.frame(205,300,0,304,0,0,false,false);assert(!pen.inputPending());
 pen.frame(210,300,.6,305,0,0,false,true);pen.frame(210,300,0,305,0,0,false,false);assert(pen.takeInput().size()==2);

 pen.setViewport(0,0,1,1);
 pen.frame(200,300,.5,400,0,0,false,true);
 for(int i=0;i<8200;i++)pen.frame(200+i*.001,300,.5,400,0,0,false,true);
 auto overrun=pen.takeInput();assert(overrun.size()==1&&overrun[0].phase==4);
 pen.frame(210,300,0,400,0,0,false,false);
 pen.frame(200,300,.5,401,0,0,false,true);pen.frame(200,300,0,401,0,0,false,false);
 assert(pen.takeInput().size()==2);
 puts("PASS ordered closed-contact queue, bounded drains without truncation, subpixel geometry and canvas gating");
}
