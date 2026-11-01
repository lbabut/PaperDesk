import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle{
 id:bench;anchors.fill:parent;signal close;color:"white"
 property int phase:0
 property real at:0
 property real lastTick:0
 property real maxGap:0
 property real activeGap:0
 property var gapEvents:[]
 property var slider:null
 property int frames:0
 property int valueUpdates:0
 property real firstUpdate:0
 property real firstPaint:0
 property var result:({})
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var v=find(item.children[i],name);if(v)return v;}return null;}
 Connections{target:bench.Window.window;function onFrameSwapped(){if(phase===2){frames++;if(firstUpdate&&!firstPaint)firstPaint=Date.now();}}}
 function step(){
  var a=subject.item,now=Date.now();if(lastTick&&phase===2){var gap=now-lastTick;maxGap=Math.max(maxGap,gap);if(slider&&slider.pressed)activeGap=Math.max(activeGap,gap);if(gap>70)gapEvents.push({ms:gap,pressed:!!(slider&&slider.pressed),since_ready:now-at});}lastTick=now;
  if(!a||!a.ready||a.replaying||!a.bitmapMode)return;
  if(phase===0){at=now;phase=1;return;}
  if(phase===1 && now-at>4000){
   slider=find(a,"sizeSlider");var win=bench.Window.window,p=slider.mapToItem(win.contentItem,20,slider.height/2),q=slider.mapToItem(win.contentItem,slider.width-20,slider.height/2);
   a.brushSize=1;phase=2;at=now;
   console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"finger",id:"size-slider",start:[p.x,p.y],end:[q.x,q.y]}));return;
  }
  if(phase===2){
   if(a.brushSize>5){valueUpdates++;if(!firstUpdate)firstUpdate=now;}
   
   if(!firstUpdate||slider.pressed||now-at<4000)return;
   result={value_updates:valueUpdates,painted_frames:frames,max_input_tick_gap_ms:activeGap,max_probe_tick_gap_ms:maxGap,gaps_over_70ms:gapEvents,final_size:a.brushSize,first_value_to_frame_ms:firstPaint-firstUpdate,real_device:true,optical_panel_latency_measured:false};
   result.passed=a.brushSize>70 && frames>=10 && activeGap<100;
   console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"real tablet size-slider pointer and rendered-frame probe",controls_probe:result,cases:[]}));phase=3;ticker.stop();
  }
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
