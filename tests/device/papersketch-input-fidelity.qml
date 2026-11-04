import QtQuick 2.15
import QtQuick.Window 2.15
import net.asivery.AppLoad 1.0
Rectangle{
 id:bench;anchors.fill:parent;color:"white";signal close
 property bool extendedCases:false
 property var cover:null
 property string backgroundDigest:""
 property int resumeBefore:0
 property int previewBefore:0
 property var stalledPreview:null
 property int shadingSize:32;property real tickAt:0;property real maxShadingGap:0;
 property int phase:0;property real at:Date.now();property int before:0;property bool stalled:false;property var result:({})
 function previewStatus(){try{var x=new XMLHttpRequest();x.open("GET","file:///tmp/papersketch-ink-status",false);x.send();return JSON.parse(x.responseText);}catch(e){return null;}}
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var r=find(item.children[i],name);if(r)return r;}return null;}
 function move(n){phase=n;at=Date.now();}
 function inject(pattern,id,x0,y0,x1,y1){var surface=find(subject.item,"drawingCanvas"),win=bench.Window.window;
  var p=surface.mapToItem(win.contentItem,x0,y0),q=surface.mapToItem(win.contentItem,x1,y1);
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"pen",pattern:pattern,id:id,start:[p.x,p.y],end:[q.x,q.y]}));}
 function findCare(item){if(!item)return null;if(item.appName==="PaperDesk Care"&&typeof item.requestClose==="function"&&!item.closing)return item;var children=item.children||[];for(var i=0;i<children.length;i++){var hit=findCare(children[i]);if(hit)return hit;}return null;}
 function findAction(item,label){if(!item)return null;if(item.label===label&&item.visible&&item.enabled)return item;var children=item.children||[];for(var i=0;i<children.length;i++){var hit=findAction(children[i],label);if(hit)return hit;}return null;}
 function tapAction(item,id){if(!item){finish(false,"UI action missing: "+id);return false;}var p=item.mapToItem(bench.Window.window.contentItem,item.width/2,item.height/2);console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"finger",pattern:"tap",id:id,start:[p.x,p.y],end:[p.x,p.y]}));return true;}
 function meanPatch(a){var values=a.nativeRaster.pixels(560,596,64,8),sum=0;for(var i=0;i<values.length;i+=4)sum+=values[i];return sum/(values.length/4);}
 function layerCases(a){
  result.layers=[];a.fastPenPreview=false;
  for(var paper=0;paper<3;paper++){
   var first=[];
   for(var tool=4;tool<=5;tool++){
    a.confirmation="clear";a.confirmAction();a.paperKind=paper;a.nativeRaster.setMaterialOptions(paper,false);a.selectTool(tool);a.brushSize=48;a.strength=1;a.nativeRaster.sharpen(tool);
    var levels=[],previous=255;
    for(var pass=0;pass<5;pass++){
     a.beginStroke(Qt.point(250,600),"pen",tool,.5,false,[1,250,600,.5,0,0,false,100+pass]);
     for(var k=1;k<=70;k++)a.extendStroke(Qt.point(250+k*10,600),"pen",.5,[2,250+k*10,600,.5,0,0,false,100+pass]);
     a.finishStroke();var gray=meanPatch(a);levels.push(gray);
     if(!(gray<previous-.5))return "Layer did not visibly darken: paper "+paper+" tool "+tool;
     previous=gray;
    }
    if(!(levels[4]<levels[0]-25))return "Insufficient five-layer darkening";
    first.push(levels[0]);result.layers.push({paper:paper,tool:tool,mean_grays:levels,pigment:a.nativeRaster.pigmentDiagnostics()});
   }
   if(!(first[1]<first[0]-20))return "Charcoal types are not visually distinct";
  }
  return "";
 }
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
   if(!(result.shading.strokes===1&&result.shading.input_samples>=1200&&result.shading.raw_stats[1]===0)){finish(false,"Fast shading input loss");return;}
   if(!extendedCases){finish(true,"");return;}move(5);return;
  }
  if(phase===5){
   var error=layerCases(a);if(error){finish(false,error);return;}
   a.fastPenPreview=true;a.selectTool(1);a.brushSize=3;
   if(tapAction(findAction(a,"Clear page"),"clear-ui-open"))move(51);return;
  }
  if(phase===51&&a.confirmation==="clear"&&Date.now()-at>200){
   if(tapAction(find(a,"confirmPageAction"),"clear-ui-confirm"))move(52);return;
  }
  if(phase===52&&a.confirmation===""&&Date.now()-at>350){
   result.clear_ui={blank:a.nativeRaster.pigmentDiagnostics(),stayed_foreground:a.enabled&&!findCare(bench.Window.window.contentItem)};
   if(result.clear_ui.blank.mass_sum!==0||!result.clear_ui.stayed_foreground){finish(false,"Clear UI did not leave a blank foreground Sketch");return;}
   a.nativeHeartbeat();backgroundDigest=a.nativeRaster.opticalDigest();resumeBefore=a.rawPenStrokes;
   previewBefore=(previewStatus()||{}).fine_strokes||0;AppLoadLauncher.launchApplication("papercare",[],{},false);move(6);return;
  }
  if(phase===6){
   cover=findCare(bench.Window.window.contentItem);if(!cover||Date.now()-at<500)return;
   if(a.enabled||a.rawPenEnabled||a.nativeRaster.pointerFilterStats().enabled||(previewStatus()||{}).armed){finish(false,"Sketch retained input while Care covered it");return;}
   result.background={raw_disabled:true,preview_off:true,digest_before:backgroundDigest};inject("fidelity-dots","background-no-ink",400,1000,900,1000);move(7);return;
  }
  if(phase===7&&Date.now()-at>1800){
   result.background.digest_after=a.nativeRaster.opticalDigest();result.background.strokes_unchanged=a.rawPenStrokes===resumeBefore;
   if(result.background.digest_after!==backgroundDigest||!result.background.strokes_unchanged){finish(false,"Background pen contacts changed Sketch artwork");return;}
   cover.requestClose(false);move(8);return;
  }
  if(phase===8&&a.enabled&&a.rawPenEnabled&&Date.now()-at>700){
   if(!(previewStatus()||{}).armed)return;
   previewBefore=(previewStatus()||{}).fine_strokes||0;inject("fidelity-dots","foreground-resume",200,1400,980,1400);move(9);return;
  }
  if(phase===9&&a.rawPenStrokes>=resumeBefore+40&&a.activeStroke===null){
   var status=previewStatus()||{};result.foreground={strokes:a.rawPenStrokes-resumeBefore,preview_contacts:status.fine_strokes-previewBefore,digest_changed:a.nativeRaster.opticalDigest()!==backgroundDigest};
   finish(result.foreground.strokes===40&&result.foreground.preview_contacts===40&&result.foreground.digest_changed,"Foreground input did not resume cleanly");
  }
 }
 Connections{target:subject.item;ignoreUnknownSignals:true;function onRawPenContactChanged(){
  if(bench.phase===2&&!bench.stalled&&subject.item.rawPenContact>0){bench.stalled=true;var until=Date.now()+150;while(Date.now()<until){};bench.stalledPreview=bench.previewStatus();}}}
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
