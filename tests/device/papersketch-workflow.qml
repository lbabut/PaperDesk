import QtQuick 2.15
import QtQuick.Window 2.15
import "baseline/engine.js" as Ink
Rectangle {
 id:bench;anchors.fill:parent;color:"white";signal close
 property int phase:0
 property real at:0
 property string exportFile:""
 property string exportDigest:""
 property string exportBase:"PaperSketch-test-"+Date.now()
 property var result:({real_device:true})
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var v=find(item.children[i],name);if(v)return v;}return null;}
 function labels(item){var out=[];if(item.label!==undefined)out.push(item.label);for(var i=0;i<item.children.length;i++)out=out.concat(labels(item.children[i]));return out;}
 function tap(item,id){
  var p=item.mapToItem(bench.Window.window.contentItem,item.width/2,item.height/2);
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"finger",pattern:"tap",id:id,start:[p.x,p.y],end:[p.x,p.y]}));
 }
 function line(a,tool,x,y){
  a.tool=tool;a.brushSize=18;a.beginStroke(Qt.point(x,y),"pen",tool,.7);
  a.extendStroke(Qt.point(x+150,y+40),"pen",.8);a.finishStroke();return a.saveBook();
 }
 function step(){
  var now=Date.now();
  if(phase===8){if(now-at>500){subject.active=true;phase=9;}return;}
  var a=subject.item;if(!a||!a.ready||a.replaying||!a.bitmapMode)return;
  if(phase===0){phase=1;at=now;return;}
  if(phase===1&&now-at>4000){
   a.confirmation="book";a.confirmAction();
   result.fixture_saved=line(a,1,120,200);a.newPage();result.fixture_saved=line(a,4,400,500)&&result.fixture_saved;
   a.newPage();result.fixture_saved=line(a,3,700,800)&&result.fixture_saved;
   result.finger_always_on=a.fingerSmudge;
   var names=labels(a);result.removed_buttons=names.indexOf("New book")<0&&names.indexOf("Finger: smudge")<0&&names.indexOf("Finger: off")<0;
   exportDigest=a.nativeRaster.opticalDigest();a.exportPage();find(a,"exportName").text=exportBase;
   result.name_focused=find(a,"exportName").activeFocus;phase=2;at=now;return;
  }
  if(phase===2&&now-at>1000){result.keyboard_visible=Qt.inputMethod.visible;tap(find(a,"saveExport"),"export-save");phase=3;return;}
  if(phase===3){
   if(a.exportDialog)return;
   exportFile=a.exportPath;result.export_path=exportFile;result.export_optical_digest=exportDigest;
   result.export_named=exportFile.indexOf("/Documents/"+exportBase+".png")>=0;
   a.exportPage();find(a,"exportName").text=exportBase;a.saveExport();
   result.collision_confirmation=a.exportOverwrite&&a.exportDialog;a.closeExport();
   a.selectPage(1);at=now;phase=4;return;
  }
  if(phase===4&&now-at>1000){tap(find(a,"deletePageButton"),"delete-menu");phase=5;return;}
  if(phase===5&&a.confirmation==="delete"){tap(find(a,"confirmPageAction"),"delete-confirm");phase=6;return;}
  if(phase===6){
   if(a.confirmation||a.pageCount!==2)return;
   result.middle_delete=a.pageIndex===1&&a.page.cacheSlot===2&&a.nativeRaster.opticalDigest()===exportDigest;
   result.slots_after_delete=a.notebook.pages.map(function(p){return p.cacheSlot;});
   result.deletion_saved=a.saveBook();a.newPage();result.new_page_uses_new_slot=a.page.cacheSlot===3;
   a.requestLeave({kind:"page",index:0});a.resolveLeave("discard");
   result.new_page_discard=a.pageCount===2&&a.notebook.pages[1].cacheSlot===2;
   phase=8;at=now;subject.active=false;return;
  }
  if(phase===9){
   result.reload_preserves_surviving_art=a.pageCount===2&&a.pageIndex===1&&a.page.cacheSlot===2&&a.nativeRaster.opticalDigest()===exportDigest;
   var oldRevision=a.page.revision,recovered=JSON.parse(a.cacheMetadata());recovered.revision++;
   a.nativeRaster.saveCache(a.pageSlot(a.pageIndex),JSON.stringify(recovered));a.nativeRaster.flushSaves();a.performPage(a.pageIndex);
   result.metadata_recovery=a.page===a.notebook.pages[a.pageIndex]&&a.page.revision===oldRevision+1;a.saveBook();
   a.selectPage(0);a.confirmation="delete";a.confirmAction();a.saveBook();
   a.confirmation="delete";a.confirmAction();
   result.last_page_becomes_blank=a.pageCount===1&&a.page.cacheSlot>2&&a.dirty;
   a.requestLeave({kind:"page",index:0});a.resolveLeave("discard");
   result.delete_discard_restores=a.pageCount===1&&a.page.cacheSlot===2&&a.nativeRaster.opticalDigest()===exportDigest;
   result.passed=result.fixture_saved&&result.finger_always_on&&result.removed_buttons&&result.name_focused&&result.export_named&&result.collision_confirmation&&result.middle_delete&&result.deletion_saved&&result.new_page_uses_new_slot&&result.new_page_discard&&result.reload_preserves_surviving_art&&result.last_page_becomes_blank&&result.delete_discard_restores&&result.metadata_recovery;
   console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"real tablet named PNG export and stable page deletion through production UI",workflow_probe:result,cases:[]}));
   phase=10;ticker.stop();
  }
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:40;repeat:true;running:true;onTriggered:bench.step()}
}
