import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle{
 id:bench;anchors.fill:parent;color:"white";signal close
 property var stalledPreview:null
 property int shadingSize:32;property real tickAt:0;property real maxShadingGap:0;
 property int phase:0;property real at:Date.now();property int before:0;property bool stalled:false;property var result:({})
 function previewStatus(){try{var x=new XMLHttpRequest();x.open("GET","file:///tmp/papersketch-ink-status",false);x.send();return JSON.parse(x.responseText);}catch(e){return null;}}
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var r=find(item.children[i],name);if(r)return r;}return null;}
 function move(n){phase=n;at=Date.now();}
 function inject(pattern,id,x0,y0,x1,y1){var surface=find(subject.item,"drawingCanvas"),win=bench.Window.window;
  var p=surface.mapToItem(win.contentItem,x0,y0),q=surface.mapToItem(win.contentItem,x1,y1);
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"pen",pattern:pattern,id:id,start:[p.x,p.y],end:[q.x,q.y]}));}
 function finish(ok,error){result.passed=ok;result.error=ok?"":error;console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({fidelity_probe:result,cases:[]}));ticker.stop();}
 function step(){var now=Date.now();if(phase===4&&tickAt)maxShadingGap=Math.max(maxShadingGap,now-tickAt);tickAt=now;var a=subject.item;if(!a||!a.ready||a.replaying||!a.bitmapMode)return;
  if(Date.now()-at>60000){finish(false,"Timeout phase "+phase);return;}
  if(phase===0){if(!a.rawPenMode)return;a.confirmation="book";a.confirmAction();result.blank_new_book=a.nativeRaster.pigmentDiagnostics();if(!a.saveBook()){finish(false,"Fresh book save failed");return;}a.newPage();if(a.pageCount!==2){finish(false,"New page action failed");return;}result.blank_new=a.nativeRaster.pigmentDiagnostics();if(result.blank_new.mass_sum!==0 || result.blank_new.optical_mismatches!==0){finish(false,"New page pigment is not empty");return;}a.tool=1;a.brushSize=3;a.strength=1;before=a.rawPenStrokes;move(1);return;}
  if(phase===1&&Date.now()-at>500){inject("fidelity-dots","tiny-contacts",200,650,980,650);move(2);return;}
  if(phase===2&&a.rawPenStrokes>=before+40&&a.activeStroke===null){
   var visible=0;for(var i=0;i<40;i++){var x=Math.round(200+780*i/39);var pixels=a.nativeRaster.pixels(x-1,648,3,5);for(var k=0;k<pixels.length;k+=4)if(pixels[k]<250){visible++;break;}}
   result.tiny={strokes:a.rawPenStrokes-before,visible:visible,gui_stall:stalled,native_preview_at_gui_resume:stalledPreview,native_preview_status:previewStatus()};
   if(result.tiny.strokes!==40||visible!==40){finish(false,"Short contacts lost");return;}
   a.confirmation="clear";a.confirmAction();result.blank_clear=a.nativeRaster.pigmentDiagnostics();
   if(result.blank_clear.mass_sum!==0 || result.blank_clear.optical_mismatches!==0){finish(false,"Cleared page pigment is not empty");return;}
   a.tool=4;a.brushSize=shadingSize;before=a.rawPenStrokes;move(3);return;}
  if(phase===3&&Date.now()-at>500){inject("fidelity-shade","fast-shading",200,800,980,1250);move(4);return;}
  if(phase===4&&a.rawPenStrokes>=before+1&&a.activeStroke===null){
   result.shading={pigment_diagnostics:a.nativeRaster.pigmentDiagnostics(),contact_stats:a.nativeRaster.contactStats(),optical_digest:a.nativeRaster.opticalDigest(),physical_state:a.nativeRaster.materialState(),queue_latency:typeof a.nativeRaster.penQueueLatencyStats==="function"?a.nativeRaster.penQueueLatencyStats():null,native_preview_status:previewStatus(),size:shadingSize,max_gui_gap_ms:maxShadingGap,native_stats:a.nativeRaster.latencyStats(),strokes:a.rawPenStrokes-before,input_samples:a.lastStroke.inputSamples,raw_stats:a.nativeRaster.penInputStats(),finished_ms:Date.now()};
   var patch=a.nativeRaster.pixels(560,1000,32,32),low=255,high=0;for(var k=0;k<patch.length;k+=4){low=Math.min(low,patch[k]);high=Math.max(high,patch[k]);}
   result.shading.texture={low:low,high:high};if(result.shading.pigment_diagnostics.optical_mismatches!==0 || high-low<30){finish(false,"Charcoal pigment or tonal range mismatch");return;}
   finish(result.shading.strokes===1&&result.shading.input_samples>=1200&&result.shading.raw_stats[1]===0,"Fast shading input loss");}
 }
 Connections{target:subject.item;ignoreUnknownSignals:true;function onRawPenContactChanged(){
  if(bench.phase===2&&!bench.stalled&&subject.item.rawPenContact>0){bench.stalled=true;var until=Date.now()+150;while(Date.now()<until){};bench.stalledPreview=bench.previewStatus();}}}
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
