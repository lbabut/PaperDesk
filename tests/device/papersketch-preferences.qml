import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle{
 id:bench;anchors.fill:parent;color:"white";signal close
 property int phase:0;property real at:Date.now();property string before:"";property var result:({})
 function move(n){phase=n;at=Date.now();}
 function finish(ok,error){result.passed=ok;result.error=ok?"":error;console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({preferences_probe:result,cases:[]}));ticker.stop();}
 function step(){
  if(Date.now()-at>30000){finish(false,"Preference phase timeout "+phase);return;}
  var a=subject.item;
  if(phase===2){if(Date.now()-at>200){subject.active=true;move(3);}return;}
  if(!a||!a.ready||a.replaying||!a.bitmapMode||!a.toolPreferencesReady)return;
  if(phase===0){
   a.confirmation="book";a.confirmAction();
   a.beginStroke(Qt.point(200,300),"pen",4,.7);a.extendStroke(Qt.point(450,300),"pen",.7);a.finishStroke();
   before=a.nativeRaster.opticalDigest();
   a.selectTool(1);a.brushSize=7;a.selectTool(4);a.brushSize=43;a.selectTool(6);a.brushSize=24;a.kneadedEraser=true;a.selectTool(8);a.brushSize=2;
   result.saved_without_save_button=a.flushToolPreferences();
   result.artwork_unchanged=a.nativeRaster.opticalDigest()===before;
   result.no_notebook_saved=a.nativeRaster.loadNotebook()==="";
   move(1);return;
  }
  if(phase===1&&Date.now()-at>700){a.unloading();subject.active=false;move(2);return;}
  if(phase===3){
   result.restored={selected:a.tool,size:a.brushSize,sizes:a.toolSizes,kneaded:a.kneadedEraser};
   var valid=a.tool===8&&a.brushSize===2&&a.toolSizes[1]===7&&a.toolSizes[4]===43&&a.toolSizes[6]===24&&a.kneadedEraser;
   a.selectTool(1);valid=valid&&a.brushSize===7;a.selectTool(4);valid=valid&&a.brushSize===43;a.selectTool(6);valid=valid&&a.brushSize===24;
   result.tool_switching_preserved=valid;
   finish(valid&&result.saved_without_save_button&&result.artwork_unchanged&&result.no_notebook_saved,"Tool settings were not preserved independently of the sketchbook");
  }
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
