import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle {
 id:bench;anchors.fill:parent;color:"white";signal close
 property int phase:-1
 property real settledAt:0
 property real waitAt:0
 property var result:({execution:"reMarkable evdev input through production pointer handlers",physical_panel_latency_measured:false})
 property real lastTick:0
 property real idleMaxGap:0
 property real clearMaxGap:0
 property real inputMaxGap:0
 property real debugAt:0
 property real firstRasterAt:0
 property real firstTileAt:0
 property real penFinishedAt:0
 property int blankFrames:0
 property string savedEnvelope:""
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var v=find(item.children[i],name);if(v)return v;}return null;}
 function gray(x,y,tile){
  var a=subject.item;if(!tile)return a.nativeRaster.pixels(x,y,1,1)[0];
  var size=a.artTileSize,cols=a.artColumns,c=Math.floor(x/size),r=Math.floor(y/size);
  var cell=find(a,"artTile"+(r*cols+c));
  return cell.getContext("2d").getImageData(x-c*size,y-r*size,1,1).data[0];
 }
 function emitReady(mode,a,b){
  var surface=find(subject.item,"drawingCanvas"),win=bench.Window.window;
  var p=surface.mapToItem(win.contentItem,a.x,a.y),q=surface.mapToItem(win.contentItem,b.x,b.y);
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:mode,start:[p.x,p.y],end:[q.x,q.y]}));
 }
 function step(){
  var now=Date.now();if(lastTick && phase===1){if(now-waitAt<2000)clearMaxGap=Math.max(clearMaxGap,now-lastTick);else idleMaxGap=Math.max(idleMaxGap,now-lastTick);}
  if(lastTick && (phase===2 || phase===5))inputMaxGap=Math.max(inputMaxGap,now-lastTick);lastTick=now;
  var a=subject.item;if(!a || !a.ready || a.replaying || !a.nativeRasterActive)return;
  if(phase===-1){if(!settledAt)settledAt=Date.now();if(Date.now()-settledAt<6000)return;phase=0;}
  if(phase===0){
   a.confirmation="book";a.confirmAction();a.tool=3;a.brushSize=24;a.strength=1;a.tone=0;
   a.beginStroke(Qt.point(400,300),"pen",3,1);a.extendStroke(Qt.point(400,500),"pen",1);a.finishStroke();
   waitAt=Date.now();phase=1;return;
  }
  if(phase===1 && Date.now()-waitAt>7000){
   result.idle_max_tick_gap_ms=idleMaxGap;result.new_book_max_tick_gap_ms=clearMaxGap;
   result.no_automatic_save=a.nativeRaster.loadNotebook()==="";
   result.dirty_before_save=a.dirty;
   var saveStarted=Date.now();result.manual_save_ok=a.saveBook();result.manual_save_ms=Date.now()-saveStarted;
   savedEnvelope=a.nativeRaster.loadNotebook();var saved=JSON.parse(savedEnvelope);result.clean_after_save=!a.dirty;
   result.autosave_document_matches=saved.document===JSON.stringify(a.notebook);
   result.autosave_cache_matches=a.nativeRaster.loadCache(a.pageIndex,JSON.stringify(a.page));
   result.autosave_reload_matches=result.autosave_document_matches && result.autosave_cache_matches;
   phase=11;waitAt=Date.now();return;
  }
  if(phase===11 && Date.now()-waitAt>1000){
   result.touch_before={core:gray(400,400,false),beside:gray(425,400,false)};
   phase=2;waitAt=Date.now();emitReady("finger",Qt.point(330,400),Qt.point(470,400));return;
  }
  if(phase===2){
   if(Date.now()-debugAt>2500){debugAt=Date.now();console.log("PAPERSKETCH_INPUT_STATE "+JSON.stringify({phase:phase,strokes:a.page.strokes.length,source:a.activeSource,blocked:a.penBlocked}));}
   if((a.bitmapMode?(!a.lastStroke || a.lastStroke.tool!==7):a.page.strokes.length<2) || a.activeStroke!==null)return;
   var s=a.bitmapMode?a.lastStroke:a.page.strokes[a.page.strokes.length-1];
   var touchMatches=a.nativeRaster.touchPressureMatchCounts();
   result.touch={matched_pressure_samples:touchMatches[0],fallback_pressure_samples:touchMatches[1],pressure_min:s.pressureMin,pressure_max:s.pressureMax,tool:s.tool,points:s.samples||s.points.length,first:s.points[0],last:s.points[s.points.length-1],
     core:gray(400,400,false),beside:gray(425,400,false),tile_core:gray(400,400,true),tile_beside:gray(425,400,true)};
   waitAt=Date.now();phase=3;return;
  }
  if(phase===3 && Date.now()-waitAt>300){
   result.touch.tile_core=gray(400,400,true);result.touch.tile_beside=gray(425,400,true);
   a.nativeRaster.save("/tmp/papersketch-input-touch.png");
   a.tool=4;a.brushSize=24;a.strength=1;waitAt=Date.now();phase=4;return;
  }
  if(phase===4 && Date.now()-waitAt>600){phase=5;waitAt=Date.now();emitReady("pen",Qt.point(700,700),Qt.point(900,720));return;}
  if(phase===5){
   if(!firstRasterAt && gray(800,710,false)<245)firstRasterAt=Date.now();
   if(!firstTileAt && gray(800,710,true)<245)firstTileAt=Date.now();
   if(firstTileAt && gray(800,710,true)>245)blankFrames++;
   if((a.bitmapMode?(!a.lastStroke || a.lastStroke.tool!==4):a.page.strokes.length<3) || a.activeStroke!==null || !firstTileAt)return;
   if(!penFinishedAt)penFinishedAt=Date.now();if(Date.now()-penFinishedAt<250)return;
   var s=a.bitmapMode?a.lastStroke:a.page.strokes[a.page.strokes.length-1];
   var pressures=s.points.map(function(p){return p[2]});
   var matched=a.nativeRaster.pressureMatchCounts();
   result.pen={raw_input:s.rawInput===true,input_samples:s.inputSamples||0,matched_pressure_samples:matched[0],fallback_pressure_samples:matched[1],blank_frames_after_visible:blankFrames,pressure_min:s.pressureMin||Math.min.apply(Math,pressures),pressure_max:s.pressureMax||Math.max.apply(Math,pressures),tool:s.tool,points:s.samples||s.points.length,first:s.points[0],last:s.points[s.points.length-1],raster_seen_ms:firstRasterAt,tile_seen_ms:firstTileAt};
   var t=result.touch;
   t.passed=t.matched_pressure_samples>t.fallback_pressure_samples*4 && t.pressure_min<0.25 && t.pressure_max>0.75 && t.tool===7 && t.points>=3 && Math.abs(t.first[0]-330)<8 && Math.abs(t.first[1]-400)<8
    && Math.abs(t.last[0]-470)<8 && Math.abs(t.last[1]-400)<8 && t.core>result.touch_before.core+60 && t.beside<result.touch_before.beside-40
    && t.core===t.tile_core && t.beside===t.tile_beside;
   var p=result.pen;
   p.passed=(p.raw_input?p.input_samples>=10:p.matched_pressure_samples>p.fallback_pressure_samples*4) && blankFrames===0 && p.pressure_min<0.25 && p.pressure_max>0.75 && p.tool===4 && p.points>=10 && Math.abs(p.first[0]-700)<8 && Math.abs(p.first[1]-700)<8 && Math.abs(p.last[0]-900)<8 && Math.abs(p.last[1]-720)<8;
   result.disk_unchanged_during_drawing=a.nativeRaster.loadNotebook()===savedEnvelope;
   result.active_input_max_tick_gap_ms=inputMaxGap;result.fast_display=a.fastDisplay;result.tile_values="painted optical snapshot before display halftone";result.bitmap_mode=a.bitmapMode;result.serialized_book_bytes=JSON.stringify(a.notebook).length;result.native_raster_active=a.nativeRasterActive;result.passed=t.passed && p.passed && result.autosave_reload_matches && result.no_automatic_save && result.manual_save_ok && result.disk_unchanged_during_drawing && idleMaxGap<250;
   console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:result.execution,cases:[],input_probe:result}));
   phase=6;ticker.stop();
  }
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
 Rectangle{anchors.top:parent.top;width:parent.width;height:88;color:"white";z:20
  Text{anchors.centerIn:parent;text:"Paper Sketch — input diagnostics";font.pixelSize:28}}
}
