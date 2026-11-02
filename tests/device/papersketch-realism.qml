import QtQuick 2.15
import QtQuick.Window 2.15

Rectangle {
 id:bench;anchors.fill:parent;color:"white";signal close
 property int phase:0
 property real at:0
 property real startedAt:Date.now()
 property var result:({real_device:true,physical_panel_latency_measured:false,ui_controls:{},calibration_samples:[]})
 property string cleanFingerDigest:""
 property string blankSurfaceDigest:""
 property string beforeCalibrationDigest:""
 property string beforeCalibrationBook:""
 property string beforeCalibrationEnvelope:""
 property bool beforeCalibrationDirty:false
 property var beforeCalibrationState:null
 property string savedCalibrationSummary:""
 property var finalState:null
 property string finalDigest:""
 property string contactBeforeDigest:""
 property bool penProximitySeen:false
 property bool fingerSuppressed:false
 property bool fingerSuppressionViolation:false
 property int kneadedBefore:0
 property int kneadedFirst:0
 property bool kneadedLive:false
 property real lastTick:0
 property real uprightMaxTickGap:0
 property real tiltMaxTickGap:0
 property var uprightGaps:[]
 property var tiltGaps:[]
 property var uprightEmission:null
 property var tiltEmission:null

 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var found=find(item.children[i],name);if(found)return found;}return null;}
 function move(next){phase=next;at=Date.now();}
 function snapshot(value){return JSON.parse(JSON.stringify(value));}
 function stateEqual(left,right){
  if(!left||!right||left.surface_digest!==right.surface_digest||left.finger_digest!==right.finger_digest||left.paper_kind!==right.paper_kind||left.wear.length!==right.wear.length)return false;
  for(var i=0;i<left.wear.length;i++)if(Math.abs(left.wear[i]-right.wear[i])>1e-12)return false;
  return true;
 }
 function finish(passed,error){
  result.passed=passed;if(error)result.error=error;result.last_phase=phase;result.runtime_ms=Date.now()-startedAt;
  console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"real tablet material controls, isolated pressure wizard, tilt and contact geometry through production input handlers",realism_probe:result,cases:[]}));
  phase=99;ticker.stop();
 }
 function tap(name,id){
  var item=find(subject.item,name);
  if(!item||!item.visible||item.available===false){finish(false,"Required UI control unavailable: "+name);return false;}
  var p=item.mapToItem(bench.Window.window.contentItem,item.width/2,item.height/2);
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"finger",pattern:"tap",id:id,start:[p.x,p.y],end:[p.x,p.y]}));return true;
 }
 function stroke(mode,pattern,id,item,a,b){
  var p=item.mapToItem(bench.Window.window.contentItem,a.x,a.y),q=item.mapToItem(bench.Window.window.contentItem,b.x,b.y);
  if(id==="upright"||id==="tilt"){
   var origin=item.mapToItem(bench.Window.window.contentItem,0,0),corner=item.mapToItem(bench.Window.window.contentItem,1200,1600);
   var info={emitted_ms:Date.now(),start:[p.x,p.y],end:[q.x,q.y],canvas_origin:[origin.x,origin.y],canvas_scale:[(corner.x-origin.x)/1200,(corner.y-origin.y)/1600],drawing_scale:subject.item.drawingScale};
   if(id==="upright")uprightEmission=info;else tiltEmission=info;
  }
  console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:mode,pattern:pattern,id:id,start:[p.x,p.y],end:[q.x,q.y]}));
 }
 function practice(pattern){
  var pad=find(subject.item,"calibrationPad");
  stroke("pen",pattern,pattern,pad,Qt.point(100,pad.height/2),Qt.point(pad.width-100,pad.height/2));
 }
 function fixtureLine(a,tool,x,y,endX,endY,pressure){
  a.tool=tool;a.brushSize=24;a.beginStroke(Qt.point(x,y),"pen",tool,pressure);
  a.extendStroke(Qt.point(endX,endY),"pen",pressure);a.finishStroke();
 }
 function resetStrokeFixture(a){
  a.paperKind=0;a.kneadedEraser=false;a.confirmation="clear";a.confirmAction();
  a.tool=1;a.brushSize=40;a.nativeRaster.sharpen(1);a.lastStroke=null;
 }
 function band(a){
  var pixels=a.nativeRaster.pixels(590,850,20,100),rows=0,mass=0;
  for(var y=0;y<100;y++){var marked=false;for(var x=0;x<20;x++){var gray=pixels[(y*20+x)*4];mass+=255-gray;if(gray<245)marked=true;}if(marked)rows++;}
  return {rows:rows,darkness_sum:mass,source:"native optical pigment image"};
 }
 function observePalmGate(a){
  if(a.penNearby){penProximitySeen=true;if(a.fingerInputEnabled===true)fingerSuppressionViolation=true;else if(a.fingerInputEnabled===false)fingerSuppressed=true;}
 }
 function step(){
  if(phase===99)return;
  var now=Date.now();
  if(lastTick&&(phase===18||phase===20)){
   var gap=now-lastTick,entry={gap_ms:gap,since_emission_ms:now-at,pen_nearby:!!(subject.item&&subject.item.penNearby),active_source:subject.item?subject.item.activeSource:""};
   if(phase===18){uprightMaxTickGap=Math.max(uprightMaxTickGap,gap);if(gap>70&&uprightGaps.length<24)uprightGaps.push(entry);}
   else{tiltMaxTickGap=Math.max(tiltMaxTickGap,gap);if(gap>70&&tiltGaps.length<24)tiltGaps.push(entry);}
  }
  lastTick=now;
  if(now-startedAt>112000){finish(false,"Realism probe exceeded its 112-second budget.");return;}
  if(at&&now-at>16000){var current=subject.item;finish(false,"Timed out in phase "+phase+(current&&current.calibrationMessage?": "+current.calibrationMessage:""));return;}
  if(phase===16||phase===23){if(now-at>600){subject.active=true;move(phase===16?17:24);}return;}
  var a=subject.item;if(!a||!a.ready||a.replaying||!a.bitmapMode)return;
  if(phase===0){
   if(!at){at=now;return;}if(now-at<4000)return;
   a.confirmation="book";a.confirmAction();a.paperKind=0;a.kneadedEraser=false;
   var blank=a.nativeRaster.materialState();cleanFingerDigest=blank.finger_digest;blankSurfaceDigest=blank.surface_digest;
   // Programmatic marks only create a repeatable physical-state fixture. Every
   // new materials control and every pressure/tilt/contact input uses evdev.
   for(var row=0;row<5;row++)fixtureLine(a,1,180,310+row*3,950,310+row*3,1);
   fixtureLine(a,4,360,500,360,700,1);
   a.beginStroke(Qt.point(330,600),"finger",7,.7);a.extendStroke(Qt.point(420,600),"finger",.7);a.finishStroke();
   a.tool=1;a.brushSize=24;
   var fixture=a.nativeRaster.materialState();
   result.fixture_surface_changed=fixture.surface_digest!==blankSurfaceDigest;
   result.fixture_finger_loaded=fixture.finger_digest!==cleanFingerDigest;
   result.fixture_tip_worn=a.nativeRaster.toolWear(1)>0;
   if(tap("materialsButton","materials-open"))move(1);return;
  }
  if(phase===1&&a.materialsDialog){if(tap("paperTexture2","paper-rough"))move(2);return;}
  if(phase===2&&a.paperKind===2){result.ui_controls.rough_paper=a.nativeRaster.materialPaperKind()===2;if(tap("sharpenButton","tip-sharpen"))move(3);return;}
  if(phase===3&&a.nativeRaster.toolWear(1)===0){result.ui_controls.sharpen_tip=result.fixture_tip_worn&&a.notice==="Tip sharpened";if(tap("cleanFingerButton","finger-clean"))move(4);return;}
  if(phase===4&&a.notice==="Finger cleaned"){result.ui_controls.clean_finger=result.fixture_finger_loaded&&a.nativeRaster.materialState().finger_digest===cleanFingerDigest;if(tap("kneadedEraserButton","eraser-kneaded"))move(5);return;}
  if(phase===5&&a.kneadedEraser&&a.tool===6){result.ui_controls.kneaded_eraser=true;if(tap("closeMaterials","materials-done"))move(6);return;}
  if(phase===6&&!a.materialsDialog){
   // Only seed this isolated fixture programmatically. Erasing uses real evdev input.
   for(var row=0;row<7;row++)fixtureLine(a,4,400,890+row*3,800,890+row*3,1);
   a.tool=6;a.brushSize=40;a.lastStroke=null;
   kneadedBefore=a.nativeRaster.pixels(600,900,1,1)[0];move(26);return;
  }
  if(phase===26&&now-at>500){
   stroke("pen","pressure-ramp","kneaded-pressure",find(a,"drawingCanvas"),Qt.point(600,900),Qt.point(600,900));move(27);return;
  }
  if(phase===27){
   var gray=a.nativeRaster.pixels(600,900,1,1)[0];
   if(a.activeStroke!==null&&gray>kneadedBefore){kneadedLive=true;if(!kneadedFirst)kneadedFirst=gray;}
   if(!a.lastStroke||a.lastStroke.tool!==6||a.activeStroke!==null||now-at<1400)return;
   result.kneaded_pressure={before:kneadedBefore,first_visible:kneadedFirst,after:gray,live:kneadedLive,samples:a.lastStroke.samples,pressure_min:a.lastStroke.pressureMin,pressure_max:a.lastStroke.pressureMax,matches:a.nativeRaster.pressureMatchCounts()};
   if(gray<kneadedBefore+12||!kneadedLive||a.lastStroke.pressureMax-a.lastStroke.pressureMin<.3){finish(false,"Kneaded eraser did not visibly lift pigment with increasing real pressure.");return;}
   a.lastStroke=null;kneadedBefore=a.nativeRaster.pixels(730,900,1,1)[0];move(28);return;
  }
  if(phase===28&&now-at>400){stroke("pen","upright","kneaded-drag",find(a,"drawingCanvas"),Qt.point(420,900),Qt.point(780,900));move(29);return;}
  if(phase===29){
   if(!a.lastStroke||a.lastStroke.tool!==6||a.activeStroke!==null||now-at<1400)return;
   var gray=a.nativeRaster.pixels(730,900,1,1)[0];
   result.kneaded_drag={before:kneadedBefore,after:gray,samples:a.lastStroke.samples};
   if(gray<kneadedBefore+8){finish(false,"Kneaded eraser did not lift pigment along its path.");return;}
   if(tap("saveButton","fixture-save"))move(7);return;
  }
  if(phase===7&&!a.dirty&&a.nativeRaster.loadNotebook()!==""){
   result.fixture_saved=true;beforeCalibrationDigest=a.nativeRaster.opticalDigest();beforeCalibrationBook=JSON.stringify(a.notebook);beforeCalibrationEnvelope=a.nativeRaster.loadNotebook();beforeCalibrationDirty=a.dirty;beforeCalibrationState=snapshot(a.nativeRaster.materialState());
   if(tap("materialsButton","calibration-open-materials"))move(8);return;
  }
  if(phase===8&&a.materialsDialog){if(tap("calibratePressureButton","calibration-open"))move(9);return;}
  if(phase===9&&a.calibrationDialog&&a.nativeRaster.calibrationActive&&a.calibrationStage===0){result.ui_controls.calibration_wizard=true;practice("calibration-light");move(10);return;}
  if(phase===10&&a.calibrationSamples>=16&&!a.calibrationStroke){result.calibration_samples.push({stage:0,delivered:a.calibrationSamples,pressure_matches:a.nativeRaster.pressureMatchCounts()});if(tap("nextCalibrationButton","calibration-next-light"))move(11);return;}
  if(phase===11&&a.calibrationStage===1){practice("calibration-normal");move(12);return;}
  if(phase===12&&a.calibrationSamples>=16&&!a.calibrationStroke){result.calibration_samples.push({stage:1,delivered:a.calibrationSamples,pressure_matches:a.nativeRaster.pressureMatchCounts()});if(tap("nextCalibrationButton","calibration-next-normal"))move(13);return;}
  if(phase===13&&a.calibrationStage===2){practice("calibration-firm");move(14);return;}
  if(phase===14&&a.calibrationSamples>=16&&!a.calibrationStroke){result.calibration_samples.push({stage:2,delivered:a.calibrationSamples,pressure_matches:a.nativeRaster.pressureMatchCounts()});if(tap("nextCalibrationButton","calibration-save"))move(15);return;}
  if(phase===15&&!a.calibrationDialog&&a.materialsDialog){
   savedCalibrationSummary=a.nativeRaster.calibrationSummary();result.calibration_summary=savedCalibrationSummary;
   result.calibration_saved=a.nativeRaster.contactStats().calibrated===true;
   result.calibration_optical_unchanged=a.nativeRaster.opticalDigest()===beforeCalibrationDigest;
   result.calibration_physical_state_unchanged=stateEqual(beforeCalibrationState,a.nativeRaster.materialState());
   result.calibration_dirty_unchanged=a.dirty===beforeCalibrationDirty;
   result.calibration_notebook_unchanged=JSON.stringify(a.notebook)===beforeCalibrationBook&&a.nativeRaster.loadNotebook()===beforeCalibrationEnvelope;
   move(16);subject.active=false;return;
  }
  if(phase===17){
   result.calibration_restored=a.nativeRaster.calibrationSummary()===savedCalibrationSummary&&a.nativeRaster.contactStats().calibrated===true;
   result.fixture_reload_exact=stateEqual(beforeCalibrationState,a.nativeRaster.materialState())&&a.nativeRaster.opticalDigest()===beforeCalibrationDigest&&!a.dirty&&a.paperKind===2&&a.kneadedEraser;
   resetStrokeFixture(a);move(25);return;
  }
  if(phase===25&&now-at>600){stroke("pen","upright","upright",find(a,"drawingCanvas"),Qt.point(220,900),Qt.point(980,900));move(18);return;}
  if(phase===18){
   observePalmGate(a);if(!a.lastStroke||a.lastStroke.tool!==1||a.activeStroke!==null||now-at<1200)return;
   result.upright={raw_input:a.lastStroke.rawInput===true,input_samples:a.lastStroke.inputSamples||0,profile:band(a),contact:snapshot(a.nativeRaster.contactStats()),pressure_min:a.lastStroke.pressureMin,pressure_max:a.lastStroke.pressureMax,samples:a.lastStroke.samples,pressure_matches:a.nativeRaster.pressureMatchCounts(),raw_replay:a.nativeRaster.rawReplayStats(),first:a.lastStroke.points[0],last:a.lastStroke.points[a.lastStroke.points.length-1],emission:uprightEmission,max_probe_tick_gap_ms:uprightMaxTickGap,gaps_over_70ms:uprightGaps};
   resetStrokeFixture(a);move(19);return;
  }
  if(phase===19&&now-at>400){stroke("pen","tilt","tilt",find(a,"drawingCanvas"),Qt.point(220,900),Qt.point(980,900));move(20);return;}
  if(phase===20){
   observePalmGate(a);if(!a.lastStroke||a.lastStroke.tool!==1||a.activeStroke!==null||now-at<1200)return;
   result.tilt={raw_input:a.lastStroke.rawInput===true,input_samples:a.lastStroke.inputSamples||0,profile:band(a),contact:snapshot(a.nativeRaster.contactStats()),pressure_min:a.lastStroke.pressureMin,pressure_max:a.lastStroke.pressureMax,samples:a.lastStroke.samples,pressure_matches:a.nativeRaster.pressureMatchCounts(),raw_replay:a.nativeRaster.rawReplayStats(),first:a.lastStroke.points[0],last:a.lastStroke.points[a.lastStroke.points.length-1],emission:tiltEmission,max_probe_tick_gap_ms:tiltMaxTickGap,gaps_over_70ms:tiltGaps};
   result.tilt_pressure_matched=(result.upright.raw_input?result.upright.input_samples>=16:result.upright.pressure_matches[0]>=16&&result.upright.pressure_matches[0]>result.upright.pressure_matches[1]*4)&&(result.tilt.raw_input?result.tilt.input_samples>=16:result.tilt.pressure_matches[0]>=16&&result.tilt.pressure_matches[0]>result.tilt.pressure_matches[1]*4);
   result.tilt_effect=result.tilt_pressure_matched&&result.upright.profile.rows>0&&result.tilt.profile.rows>=result.upright.profile.rows+2&&result.tilt.contact.tilt_samples>0&&(Math.abs(result.tilt.contact.tilt_x)>.3||Math.abs(result.tilt.contact.tilt_y)>.3)&&result.upright.contact.tilt_samples===0&&Math.abs(result.upright.pressure_min-result.tilt.pressure_min)<.02&&Math.abs(result.upright.pressure_max-result.tilt.pressure_max)<.02;
   result.palm_gate={pen_proximity_observed:penProximitySeen,finger_disabled_while_pen_nearby:fingerSuppressed&&!fingerSuppressionViolation,simultaneous_physical_palm_contact_tested:false};
   a.confirmation="clear";a.confirmAction();a.nativeRaster.cleanFinger();fixtureLine(a,4,600,900,600,1100,1);a.lastStroke=null;contactBeforeDigest=a.nativeRaster.opticalDigest();move(21);return;
  }
  if(phase===21&&now-at>600){stroke("finger","contact","finger-contact",find(a,"drawingCanvas"),Qt.point(530,1000),Qt.point(670,1000));move(22);return;}
  if(phase===22){
   if(!a.lastStroke||a.lastStroke.tool!==7||a.activeStroke!==null||now-at<1200)return;
   result.finger_contact=snapshot(a.nativeRaster.contactStats());
   result.finger_geometry=result.finger_contact.finger_geometry_matches>0&&a.nativeRaster.opticalDigest()!==contactBeforeDigest&&a.nativeRaster.materialState().finger_digest!==cleanFingerDigest;
   result.physical_state_saved=a.saveBook();finalState=snapshot(a.nativeRaster.materialState());finalDigest=a.nativeRaster.opticalDigest();result.saved_physical_state=finalState;
   move(23);subject.active=false;return;
  }
  if(phase===24){
   var restored=a.nativeRaster.materialState();result.restored_physical_state=snapshot(restored);
   result.physical_state_reload_exact=stateEqual(finalState,restored)&&a.nativeRaster.opticalDigest()===finalDigest&&!a.dirty&&restored.surface_digest!==blankSurfaceDigest&&restored.finger_digest!==cleanFingerDigest&&restored.wear[4]>0;
   result.calibration_survives_second_reload=a.nativeRaster.calibrationSummary()===savedCalibrationSummary&&a.nativeRaster.contactStats().calibrated===true;
   var controls=result.ui_controls,matched=true;
   for(var i=0;i<result.calibration_samples.length;i++){var counts=result.calibration_samples[i].pressure_matches;matched=matched&&counts[0]>=16&&counts[0]>counts[1]*4;}
   result.calibration_raw_pressure_matched=matched&&result.calibration_samples.length===3;
   finish(result.fixture_surface_changed&&result.fixture_finger_loaded&&result.fixture_tip_worn&&result.fixture_saved&&controls.rough_paper&&controls.sharpen_tip&&controls.clean_finger&&controls.kneaded_eraser&&controls.calibration_wizard&&result.calibration_saved&&result.calibration_raw_pressure_matched&&result.calibration_optical_unchanged&&result.calibration_physical_state_unchanged&&result.calibration_dirty_unchanged&&result.calibration_notebook_unchanged&&result.calibration_restored&&result.fixture_reload_exact&&result.tilt_effect&&result.finger_geometry&&result.palm_gate.pen_proximity_observed&&result.palm_gate.finger_disabled_while_pen_nearby&&result.physical_state_saved&&result.physical_state_reload_exact&&result.calibration_survives_second_reload);return;
  }
 }
 Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
 Timer{id:ticker;interval:32;repeat:true;running:true;onTriggered:bench.step()}
}
