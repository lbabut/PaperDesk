import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle{
 id:bench;anchors.fill:parent;color:"white";signal close
 property int phase:0
 property int caseIndex:0
 property real waitAt:0
 property real lastTick:0
 property real maxGap:0
 property real activeGap:0
 property bool wasActive:false
 property var slowTicks:[]
 property real firstRaster:0
 property real firstTile:0
 property int blankFrames:0
 property var cases:[]
 property var definitions:[{id:"pen-graphite",tool:1,size:12,y0:400,y1:500,fullscreen:false},{id:"pen-charcoal",tool:4,size:38,y0:900,y1:1200,fullscreen:true}]
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var v=find(item.children[i],name);if(v)return v;}return null;}
 function gray(x,y,tile){
  var a=subject.item;if(!tile)return a.nativeRaster.pixels(x,y,1,1)[0];
  var size=a.artTileSize,c=Math.floor(x/size),r=Math.floor(y/size),cell=find(a,"artTile"+(r*a.artColumns+c));
  var block=cell.displayPixels(x-c*size,y-r*size,8,8),sum=0;for(var i=0;i<block.length;i+=4)sum+=block[i];return block.length?sum/(block.length/4):255;
 }
 function ready(){
  var d=definitions[caseIndex],a=subject.item,surface=find(a,"drawingCanvas"),win=bench.Window.window;
  var p=surface.mapToItem(win.contentItem,120,d.y0),q=surface.mapToItem(win.contentItem,1080,d.y1);
  firstRaster=0;firstTile=0;blankFrames=0;maxGap=0;activeGap=0;wasActive=false;slowTicks=[];phase=3;
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"pen",id:d.id,pattern:"shade",start:[p.x,p.y],end:[q.x,q.y]}));
 }
 function step(){
  var now=Date.now(),a=subject.item;if(lastTick && phase===3){var gap=now-lastTick,contact=!!(a&&a.activeSource==="pen");maxGap=Math.max(maxGap,gap);if(contact||wasActive)activeGap=Math.max(activeGap,gap);if(gap>=80)slowTicks.push({gap_ms:gap,contact:contact,previous_contact:wasActive});wasActive=contact;}lastTick=now;
  if(!a || !a.ready || a.replaying || !a.bitmapMode)return;
  if(phase===0){waitAt=now;phase=1;return;}
  if(phase===1 && now-waitAt>4000){
   a.confirmation="book";a.confirmAction();phase=2;waitAt=now;
   var d=definitions[caseIndex];a.tool=d.tool;a.brushSize=d.size;a.strength=1;a.fullScreen=d.fullscreen;return;
  }
  if(phase===2 && now-waitAt>1500){ready();return;}
  if(phase===3){
   var d=definitions[caseIndex],mx=600,my=(d.y0+d.y1)/2;
   if(!firstRaster && gray(mx,my,false)<245)firstRaster=now;
   if(!firstTile && gray(mx,my,true)<245)firstTile=now;
   if(firstTile && gray(mx,my,true)>=245)blankFrames++;
   if(a.activeStroke!==null || !a.lastStroke || a.lastStroke.tool!==d.tool || !firstTile)return;
   var s=a.lastStroke,points=s.points,first=points[0],last=points[points.length-1];
   var matched=a.nativeRaster.pressureMatchCounts(),cell=find(a,"artTile"+(Math.floor(my/128)*a.artColumns+Math.floor(mx/128)));
   var display=cell.displayPixels(mx%128,my%128,32,32),raw=a.nativeRaster.pixels(mx,my,32,32),displaySum=0,rawSum=0,binary=true,grays=false;
   for(var pi=0;pi<display.length;pi+=4){var value=display[pi];binary=binary&&(value===0||value===255);displaySum+=value;rawSum+=raw[pi];grays=grays||(raw[pi]>0&&raw[pi]<255);}
   var item={active_input_tick_gap_ms:activeGap,slow_ticks:slowTicks,display_probe:"8x8 mean of actual binary tile display pixels",fast_display:a.fastDisplay,pressure_matches:matched[0],pressure_fallbacks:matched[1],display_binary:binary,display_has_samples:display.length===4096,optical_has_grays:grays,display_mean:displaySum/1024,optical_mean:rawSum/1024,id:d.id,tool:d.tool,points:s.samples||points.length,first:first,last:last,raster_seen_ms:firstRaster,tile_seen_ms:firstTile,max_input_tick_gap_ms:maxGap,blank_frames_after_visible:blankFrames,full_screen:a.fullScreen,max_material_segment_ms:a.nativePatchMaxMs,retained_points:points.length,metadata_bytes:JSON.stringify(a.notebook).length};
   item.passed=a.fastDisplay && binary && display.length===4096 && grays && Math.abs(displaySum-rawSum)/1024<12 && matched[0]>4*matched[1] && (s.samples||points.length)>=100 && Math.abs(first[0]-120)<15 && Math.abs(first[1]-d.y0)<15 && Math.abs(last[0]-1080)<15 && Math.abs(last[1]-d.y1)<15 && blankFrames===0 && maxGap<200;
   cases.push(item);console.log("PAPERSKETCH_NATIVE_CASE "+JSON.stringify(item));
   caseIndex++;waitAt=now;phase=4;return;
  }
  if(phase===4 && now-waitAt>1000){
   if(caseIndex<definitions.length){
    var d=definitions[caseIndex];a.lastStroke=null;a.tool=d.tool;a.brushSize=d.size;a.fullScreen=d.fullscreen;phase=2;waitAt=now;return;
   }
   var result={cases:cases,no_automatic_save:a.nativeRaster.loadNotebook()==="",passed:cases.every(function(c){return c.passed;})};
   result.passed=result.passed&&result.no_automatic_save;
   console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"long fast Linux evdev shading through production handlers",shading_probe:result,cases:cases}));ticker.stop();phase=5;
  }
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
