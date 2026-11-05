import QtQuick 2.15
Item {
    id:probe;anchors.fill:parent;signal close
    property int step:0
    property var checks:[]
    property var samples:[]
    property int updates:0
    property int paintCount:0
    property var canvas:null
    property var cases:[{interval:40,hold:20},{interval:60,hold:80}]
    property string sequence:'11.11+22.22+33.33+44.44+55.55+66.66+77.77+88.88+99.99+12.34+56.78+90.12='
    function find(item,name){if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var r=find(item.children[i],name);if(r)return r;}return null;}
    function check(name,ok){checks.push({name:name,passed:!!ok});}
    function near(a,b){return Math.abs(a-b)<1e-7;}
    function tap(name){var k=find(subject.item,name);if(!k)throw Error(name);k.tapped();}
    function graphTests(){
        try {
            var a=subject.item;a.mode='Graph';var g=find(a,'calcGraphPanel');canvas=find(g,'functionPlot');
            tap('graphFunction0');tap('graphKey27');tap('graphKey0');tap('graphKey30');tap('graphKey24');tap('graphKey14');tap('graphDraw');
            check('keypad x^2-4',g.formulas[0]==='x^2−4'&&g.curves[0].length===401&&near(g.curves[0][240].y,0));
            tap('graphRange0');tap('graphKey27');tap('graphKey24');tap('graphKey15');tap('graphDraw');
            check('range keypad',g.bounds[0]===-5&&g.rangeField===-1);
            tap('graphStandard');tap('graphZoomIn');check('zoom in',g.bounds[0]===-5&&g.bounds[1]===5);
            tap('graphZoomOut');check('zoom out',g.bounds[0]===-10&&g.bounds[1]===10);
            check('invalid window rejected',!g.setBounds([10,-10,-10,10])&&g.bounds[0]===-10);
            g.traceX=1;tap('graphFindZero');check('positive root',near(g.traceX,2));
            g.traceX=-1;tap('graphFindZero');check('negative root',near(g.traceX,-2));
            g.traceX=0;tap('traceRight');check('trace arrow',near(g.traceX,.5));tap('traceLeft');check('trace return',near(g.traceX,0));
            g.formulas=['x^2','1/x','sqrt(x)'];g.enabledCurves=[true,true,true];g.draw();tap('graphTable');
            check('table values and domain',find(g,'graphCell3_1').text==='0'&&find(g,'graphCell3_2').text==='undefined'&&find(g,'graphCell5_1').text==='1');
            tap('graphEnabled2');check('disabled curve',g.curves[2].length===0&&find(g,'graphCell5_3').text==='—');
            tap('graphTable');g.formulas=['sin(x)','cos(x)','tan(x)'];g.enabledCurves=[true,true,true];g.angleMode='RAD';g.setBounds([0,180,-2,2]);tap('graphAngles');
            check('DEG trig',near(g.curves[0][200].y,1)&&near(g.curves[1][200].y,0)&&g.curves[2][200].y===null);
            tap('graphAngles');check('RAD trig',near(g.curves[0][200].y,Math.sin(90)));
            g.formulas=['1/x','sqrt(x)','sin('];g.setBounds([-10,10,-10,10]);
            check('domain gaps and syntax',g.curves[0][200].y===null&&g.curves[1][0].y===null&&g.curves[2].every(function(p){return p.y===null;})&&g.notice.indexOf('Y3:')>=0);
            g.setBounds([-.9,1,-10,10]);g.selected=0;g.traceX=.1;tap('graphFindZero');check('pole is not a root',near(g.traceX,.1)&&g.notice.indexOf('No sign-changing root')>=0);
            g.formulas=['x^2-4','sin(x)',''];g.enabledCurves=[true,true,false];g.setBounds([-5,5,-5,5]);
            graphSettle.start();
        } catch(e){check('graph exception: '+e.message,false);finish();}
    }
    function request(){
        if(step===cases.length){finish();return;}
        var a=subject.item;a.mode='Science';a.reset();a.probeKeys=[];updates=0;
        var points=[];
        for(var i=0;i<sequence.length;i++){var k=find(a,'calcKey'+sequence.charAt(i)),p=k.mapToItem(null,k.width/2,k.height/2);points.push([Math.round(p.x),1871-Math.round(p.y)]);}
        settle.interval=sequence.length*cases[step].interval+1800;settle.start();
        console.log('CALC_PROBE_TARGET '+JSON.stringify({id:String(step),points:points,interval:cases[step].interval,hold:cases[step].hold}));
    }
    function finish(){console.log('CALC_PROBE_RESULT '+JSON.stringify({checks:checks,samples:samples,passed:checks.length>=16&&checks.every(function(c){return c.passed;})&&samples.length===2&&samples.every(function(s){return s.correct;})}));}
    Loader {id:subject;anchors.fill:parent;onLoaded:warmup.start()}
    Connections {target:subject.item;function onScienceExpressionChanged(){probe.updates++;}}
    Connections {target:probe.canvas;function onPaint(){probe.paintCount++;}}
    Component.onCompleted:subject.setSource('subject/ui/main.qml',{settingsFile:'CONFIG/probe.ini'})
    Timer {id:warmup;interval:1000;onTriggered:{console.log('CALC_PROBE_ACTIVATE');activateWait.start();}}
    Timer {id:activateWait;interval:1200;onTriggered:probe.graphTests()}
    Timer {id:graphSettle;interval:800;onTriggered:{probe.check('canvas painted',probe.canvas.available&&probe.paintCount>0);probe.request();}}
    Timer {id:settle;onTriggered:{
        var a=subject.item,expression=probe.sequence.slice(0,-1);
        probe.samples.push({interval_ms:probe.cases[probe.step].interval,hold_ms:probe.cases[probe.step].hold,presses:a.probeKeys.length,display_updates:probe.updates,result:a.result,correct:a.probeKeys.join('')===probe.sequence&&a.expression===expression&&a.scienceExpression===expression&&a.result==='659.19'&&probe.updates<=Math.ceil(probe.sequence.length*probe.cases[probe.step].interval/80)+3});
        probe.step++;probe.request();
    }}
}
