import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle {
 id: bench
 anchors.fill: parent
 color: "white"
 signal close
 property int phase: 0
 property int caseIndex: 0
 property real at: Date.now()
 property real tickAt: 0
 property real maxGap: 0
 property int before: 0
 property var statsBefore: []
 property var previewBefore: null
 property int contacts: 0
 property int samples: 0
 property int malformed: 0
 property int openCircles: 0
 property var cases: []
 property bool done: false
 function find(item,name) {
  if(item.objectName===name)return item;
  for(var i=0;i<item.children.length;i++){var r=find(item.children[i],name);if(r)return r;}
  return null;
 }
 function move(n){phase=n;at=Date.now();tickAt=0;}
 function finish(ok,error){
  done=true;ticker.stop();
  console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({detail_probe:{passed:ok,error:error||"",cases:cases},cases:[]}));
 }
 function previewStatus(){try{var x=new XMLHttpRequest();x.open("GET","file:///tmp/papersketch-ink-status",false);x.send();return JSON.parse(x.responseText);}catch(e){return null;}}
 function marked(a,x,y){
  var p=a.nativeRaster.pixels(Math.round(x)-1,Math.round(y)-1,3,3);
  for(var i=0;i<p.length;i+=4)if(p[i]<250)return true;
  return false;
 }
 function verifyMarks(a){
  var circles=0,hatches=0;
  for(var n=0;n<100;n++){
   var x=210+(n%10)*20,y=660+Math.floor(n/10)*20,r=2+n%3;
   if(marked(a,x+r,y)&&marked(a,x-r,y)&&marked(a,x,y+r)&&marked(a,x,y-r))circles++;
   if(marked(a,x+r+3,y))hatches++;
   if(marked(a,x-r-3,y))hatches++;
   if(marked(a,x,y+r+3))hatches++;
   if(marked(a,x,y-r-3))hatches++;
  }
  return {circles:circles,hatches:hatches};
 }
 function step(){
  if(done)return;
  var a=subject.item,now=Date.now();
  if(phase===2&&tickAt)maxGap=Math.max(maxGap,now-tickAt);
  tickAt=now;
  if(now-at>60000){finish(false,"Timeout in phase "+phase);return;}
  if(!a||!a.ready||a.replaying||!a.bitmapMode||!a.rawPenMode)return;
  if(phase===0){
   a.confirmation="book";a.confirmAction();a.tool=caseIndex===0?1:4;a.brushSize=3;a.strength=1;a.tone=0;
   before=a.rawPenStrokes;statsBefore=a.nativeRaster.penInputStats();
   contacts=0;samples=0;malformed=0;openCircles=0;maxGap=0;move(1);return;
  }
  if(phase===1&&now-at>700){
   var surface=find(a,"drawingCanvas"),win=bench.Window.window;
   var p=surface.mapToItem(win.contentItem,200,650),q=surface.mapToItem(win.contentItem,400,850);
   previewBefore=previewStatus();move(2);
   console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"pen",pattern:"detail-circles",id:caseIndex===0?"detail-hb":"detail-charcoal",start:[p.x,p.y],end:[q.x,q.y]}));return;
  }
  if(phase===2&&contacts>=500&&a.activeStroke===null){
   var stats=a.nativeRaster.penInputStats();if(stats[2]!==0)return;
   var finished=Date.now(),marks=verifyMarks(a);
   var entry={id:caseIndex===0?"detail-hb":"detail-charcoal",tool:a.tool,size:a.brushSize,
    strokes:a.rawPenStrokes-before,input_samples:samples,malformed_strokes:malformed,open_circles:openCircles,
    visible:marks,raw_stats:stats,received_delta:stats[0]-statsBefore[0],overflow_delta:stats[1]-statsBefore[1],
    native_preview_before:previewBefore,native_preview_after:previewStatus(),
    max_gui_gap_ms:maxGap,finished_ms:finished,native_stats:a.nativeRaster.latencyStats()};
   cases.push(entry);
   if(entry.strokes!==500||contacts!==500||samples!==3700||malformed||openCircles||entry.received_delta!==4200||entry.overflow_delta!==0||marks.circles!==100||marks.hatches!==400){finish(false,"Lost or malformed circle/hatch input or missing material marks");return;}
   caseIndex++;if(caseIndex===2){finish(true,"");return;}move(0);
  }
 }
 Connections {
  target: subject.item
  ignoreUnknownSignals: true
  function onRawPenStrokesChanged(){
   if(bench.phase!==2)return;
   var s=subject.item.lastStroke;if(!s)return;
   var expected=bench.contacts%5===0?17:5;
   if(s.inputSamples!==expected)bench.malformed++;
   if(bench.contacts%5===0){var p=s.points[0],q=s.points[s.points.length-1];if(Math.abs(p[0]-q[0])>1||Math.abs(p[1]-q[1])>1)bench.openCircles++;}
   bench.samples+=s.inputSamples;bench.contacts++;
  }
 }
 Loader {id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer {id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
