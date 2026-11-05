import QtQuick 2.15
Item {
 id:probe;anchors.fill:parent;signal close
 property int step:0
 property var samples:[]
 property bool injecting:false
 property var cases:[
  {interval:40,hold:20,slots:2,grouped:0},
  {interval:20,hold:10,slots:2,grouped:0},
  {interval:30,hold:20,slots:1,grouped:0},
  {interval:30,hold:30,slots:2,grouped:1},
  {interval:30,hold:30,slots:1,grouped:1},
  {interval:30,hold:50,slots:2,grouped:0},
  {interval:60,hold:90,slots:2,grouped:0},
  {interval:30,hold:20,slots:2,grouped:0,stall:true}]
 property string sequence:Array(60).join('1+')+'1='
 function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var r=find(item.children[i],name);if(r)return r;}return null;}
 function request(){
  if(step===cases.length){console.log('CALC_PROBE_RESULT '+JSON.stringify({samples:samples,passed:samples.length===cases.length&&samples.every(function(s){return s.correct;})}));return;}
  var a=subject.item;a.mode='Desk';a.officeKey('AC');a.probeKeys=[];
  var points=[];
  for(var i=0;i<sequence.length;i++){var key=sequence.charAt(i),k=find(a,key==='1'?'deskKey20':key==='+'?'deskKey23':'deskKey24'),p=k.mapToItem(null,k.width/2,k.height/2);points.push([Math.round(p.x),1871-Math.round(p.y)]);}
  var c=cases[step];settle.interval=sequence.length*c.interval+1500;injecting=true;settle.start();
  console.log('CALC_PROBE_TARGET '+JSON.stringify({id:String(step),points:points,interval:c.interval,hold:c.hold,slots:c.slots,grouped:c.grouped}));
 }
 Loader {id:subject;anchors.fill:parent;onLoaded:warmup.start()}
 Component.onCompleted:subject.setSource('subject/ui/main.qml',{settingsFile:'CONFIG/probe.ini'})
 Timer {id:warmup;interval:1000;onTriggered:{console.log('CALC_PROBE_ACTIVATE');activation.start();}}
 Timer {id:activation;interval:1200;onTriggered:probe.request()}
 Timer {interval:180;repeat:true;running:probe.injecting&&!!probe.cases[probe.step].stall;onTriggered:{var until=Date.now()+100;while(Date.now()<until){}}}
 Timer {id:settle;onTriggered:{
  probe.injecting=false;var a=subject.item;
  probe.samples.push({pattern:probe.cases[probe.step],presses:a.probeKeys.length,keys:a.probeKeys.join(''),result:a.desk.input,correct:a.probeKeys.join('')===probe.sequence&&a.desk.input==='60'});
  probe.step++;probe.request();
 }}
}
