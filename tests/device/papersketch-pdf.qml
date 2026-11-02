import QtQuick 2.15
import QtQuick.Window 2.15
Rectangle{
 id:bench;anchors.fill:parent;color:"white";signal close
 property int phase:0
 property real waitAt:0
 property string title:"PaperSketch PDF test Łąka 100% # "+Date.now()
 property string beforeDigest:""
 property bool keyboardVisible:false
 property bool diagnosed:false
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var v=find(item.children[i],name);if(v)return v;}return null;}
 function emitTap(item){
  var p=item.mapToItem(bench.Window.window.contentItem,item.width/2,item.height/2);
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({id:"pdf-add",mode:"finger",pattern:"tap",start:[p.x,p.y],end:[p.x,p.y]}));
 }
 function step(){
  var a=subject.item;if(!a)return;
  if(phase<2&&(!a.ready||a.replaying||!a.nativeRasterActive))return;
  if(phase===0){if(!waitAt)waitAt=Date.now();if(Date.now()-waitAt<6000)return;
   a.confirmation="book";a.confirmAction();a.tool=3;a.brushSize=24;
   a.beginStroke(Qt.point(400,300),"pen",3,.9);a.extendStroke(Qt.point(400,650),"pen",.9);a.finishStroke();
   beforeDigest=a.nativeRaster.opticalDigest();waitAt=Date.now();phase=1;return;
  }
  if(phase===1&&Date.now()-waitAt>600){
   a.exportPage();find(a,"exportName").text=title;waitAt=Date.now();phase=2;return;
  }
  if(phase===2&&Date.now()-waitAt>800){
   keyboardVisible=Qt.inputMethod.visible;emitTap(find(a,"saveExport"));waitAt=Date.now();phase=3;return;
  }
  if(phase===3&&Date.now()-waitAt>20000){
   console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({cases:[],pdf_probe:{passed:false,message:a.exportMessage,path:a.exportPath,pending:a.pendingPdfExport,diagnosed:diagnosed}}));phase=4;ticker.stop();return;
  }
  if(phase===3&&a.exportedDocumentId&&a.pendingPdfExport===null){
   var entry=a.exportBridge.lib.entryForId(a.exportedDocumentId);
   var result={execution:"real AppLoad, PDF writer, evdev Add PDF tap and native DocumentImporter",document_id:a.exportedDocumentId,optical_digest:beforeDigest,title:title,library_name:entry?entry.visibleName:"",library_entry_visible:!!entry&&!entry.isTrashed,pdf_staging_path:a.exportPath,keyboard_visible:keyboardVisible,drawing_unchanged:a.nativeRaster.opticalDigest()===beforeDigest,no_automatic_save:a.nativeRaster.loadNotebook()==="",drawing_still_dirty:a.dirty,dialog_closed:!a.exportDialog};
   result.passed=result.library_entry_visible&&result.library_name===title&&result.drawing_unchanged&&result.no_automatic_save&&result.drawing_still_dirty&&result.dialog_closed&&result.keyboard_visible;
   console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:result.execution,cases:[],pdf_probe:result}));phase=4;ticker.stop();
  }
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:30;repeat:true;running:true;onTriggered:bench.step()}
}
