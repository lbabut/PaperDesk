import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle {
 id:bench;anchors.fill:parent;color:"white";signal close
 property int phase:0
 property real at:Date.now()
 property int before:0
 property var result:({})
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var x=find(item.children[i],name);if(x)return x;}return null;}
 function move(n){phase=n;at=Date.now();}
 function inject(pattern,id,x0,y0,x1,y1){var surface=find(subject.item,"drawingCanvas"),win=bench.Window.window;
  var p=surface.mapToItem(win.contentItem,x0,y0),q=surface.mapToItem(win.contentItem,x1,y1);
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"pen",pattern:pattern,id:id,start:[p.x,p.y],end:[q.x,q.y]}));}
 function gray(x,y){return subject.item.nativeRaster.pixels(x,y,1,1)[0];}
 function finish(ok,error){result.passed=ok;result.error=ok?"":(error||"");console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"rear Wacom rubber and normal pen through production handlers",eraser_probe:result,cases:[]}));ticker.stop();}
 function unchanged(){var a=subject.item;return a.tool===1&&a.brushSize===5&&a.strength===.6&&a.kneadedEraser;}
 function step(){var a=subject.item;if(!a||!a.ready||a.replaying||!a.nativeRasterActive)return;
  if(Date.now()-at>30000){finish(false,"Timeout in phase "+phase);return;}
  if(phase===0){a.confirmation="book";a.confirmAction();a.brushSize=24;a.strength=1;
   for(var y=888;y<=912;y+=3){a.beginStroke(Qt.point(400,y),"pen",4,1);a.extendStroke(Qt.point(800,y),"pen",1);a.finishStroke();}
   a.tool=1;a.brushSize=5;a.strength=.6;a.kneadedEraser=true;a.lastStroke=null;before=gray(600,900);result.before_tap=before;move(1);return;}
  if(phase===1&&Date.now()-at>1000){inject("eraser","rear-tap",600,900,600,900);move(2);return;}
  if(phase===2&&a.lastStroke&&a.activeStroke===null){result.tap={tool:a.lastStroke.tool,rear:a.lastStroke.hardwareEraser,before:before,after:gray(600,900),settings_preserved:unchanged()};
   if(!a.lastStroke.hardwareEraser||a.lastStroke.tool!==6||gray(600,900)<=before+10||!unchanged()){finish(false,"Rear tap did not erase or changed selected tool");return;}
   a.lastStroke=null;before=gray(730,900);move(3);return;}
  if(phase===3&&Date.now()-at>500){inject("eraser","rear-drag",420,900,780,900);move(4);return;}
  if(phase===4&&a.lastStroke&&a.activeStroke===null){result.drag={tool:a.lastStroke.tool,rear:a.lastStroke.hardwareEraser,before:before,after:gray(730,900),settings_preserved:unchanged()};
   if(!a.lastStroke.hardwareEraser||a.lastStroke.tool!==6||gray(730,900)<=before+10||!unchanged()){finish(false,"Rear drag did not erase");return;}
   a.lastStroke=null;move(5);return;}
  if(phase===5&&Date.now()-at>500){inject("upright","pen-after-rear",300,600,700,600);move(6);return;}
  if(phase===6&&a.lastStroke&&a.activeStroke===null){result.normal_pen={tool:a.lastStroke.tool,rear:a.lastStroke.hardwareEraser,gray:gray(500,600),settings_preserved:unchanged()};
   finish(a.lastStroke.tool===1&&!a.lastStroke.hardwareEraser&&gray(500,600)<250&&unchanged(),"Normal pen resume check");}
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
