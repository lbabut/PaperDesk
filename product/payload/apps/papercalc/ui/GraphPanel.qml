import QtQuick 2.15
import "../calc.js" as Calc
Item {
    id: graph
    property var formulas: ["x^2-4", "sin(x)", ""]
    property var enabledCurves: [true,true,false]
    property string angleMode: "RAD"
    property int selected: 0
    property int rangeField: -1
    property string rangeInput: ""
    property var bounds: [-10,10,-10,10]
    property var curves: []
    property real traceX: 0
    property bool table: false
    property string notice: "Select Y1–Y3, enter a function, then DRAW. Use × explicitly: 2×x."
    property string traceLabel: ""
    signal edited
    function label(n){return String(Number(n.toPrecision(7)));}
    function readTrace(){
        var r=Calc.calculate(formulas[selected],{x:traceX,angleMode:angleMode});
        traceLabel="Y"+(selected+1)+"   x = "+label(traceX)+"    y = "+(r.ok?label(r.value):"undefined");
    }
    function draw(){
        var a=[],errors=[];
        for(var i=0;i<3;i++) {
            a.push(enabledCurves[i]&&formulas[i].trim()?Calc.sample(formulas[i],bounds[0],bounds[1],401,angleMode):[]);
            if(a[i].length && !a[i].some(function(p){return p.y!==null;}))errors.push("Y"+(i+1)+": "+Calc.calculate(formulas[i],{x:traceX,angleMode:angleMode}).text);
        }
        curves=a;readTrace();plot.requestPaint();
        notice=errors.length?errors.join(" · "):"Drawn in "+angleMode+" · Y1 solid / Y2 dashed / Y3 dotted. Tap the plot to trace.";
    }
    function edit(k){
        if(rangeField>=0){
            if(k==='AC')rangeInput='';else if(k==='⌫')rangeInput=rangeInput.slice(0,-1);
            else if(/^[0-9.−+e]$/.test(k))rangeInput+=k;
            return;
        }
        var f=formulas.slice(),s=f[selected];
        if(k==='AC')s='';else if(k==='⌫')s=s.slice(0,-1);
        else {var v={sin:'sin(',cos:'cos(',tan:'tan(',ln:'ln(',log:'log(',"√":'sqrt(',abs:'abs(',exp:'exp(',"x²":'^2',"x³":'^3',"1/x":'1/('};if(s.length+(v[k]||k).length<=160)s+=v[k]||k;}
        f[selected]=s;formulas=f;edited();notice="Edited Y"+(selected+1)+". Press DRAW to update the plot.";
    }
    function setBounds(b){
        if(b.some(function(v){return !isFinite(v)||Math.abs(v)>1e12;}) || b[0]>=b[1] || b[2]>=b[3] || b[1]-b[0]<1e-8 || b[3]-b[2]<1e-8){notice="Invalid window: minimum must be smaller than maximum (range 1e-8 to 1e12).";return false;}
        bounds=b;edited();traceX=Math.max(b[0],Math.min(b[1],traceX));draw();return true;
    }
    function applyRange(){if(rangeField<0)return;var n=Number(rangeInput.replace(/−/g,'-'));if(!rangeInput.trim()||!isFinite(n)){notice="Enter a finite number for the selected limit.";return;}var b=bounds.slice();b[rangeField]=n;if(setBounds(b))rangeField=-1;}
    function zoom(factor){var b=bounds,cx=(b[0]+b[1])/2,cy=(b[2]+b[3])/2,dx=(b[1]-b[0])*factor/2,dy=(b[3]-b[2])*factor/2;setBounds([cx-dx,cx+dx,cy-dy,cy+dy]);}
    function traceStep(direction){traceX=Math.max(bounds[0],Math.min(bounds[1],traceX+direction*(bounds[1]-bounds[0])/40));readTrace();plot.requestPaint();}
    function findRoot(){
        var p=Calc.sample(formulas[selected],bounds[0],bounds[1],401,angleMode),best=null;
        for(var i=1;i<p.length;i++)if(p[i-1].y!==null && p[i].y!==null && p[i-1].y*p[i].y<=0){
            var r=Calc.rootBetween(formulas[selected],p[i-1].x,p[i].x,angleMode);
            if(r!==null && (best===null||Math.abs(r-traceX)<Math.abs(best-traceX)))best=r;
        }
        if(best===null){notice="No sign-changing root found in this window. Tangent roots may be missed.";return;}
        traceX=best;readTrace();plot.requestPaint();notice="Approximate root of Y"+(selected+1)+": x = "+label(best);
    }
    Component.onCompleted:draw()
    Column {
        width:parent.width;spacing:10
        Repeater {
            model:3
            Row {
                spacing:10
                CalcKey {objectName:"graphEnabled"+index;width:90;height:58;label:"Y"+(index+1);active:graph.enabledCurves[index];textSize:23;onTapped:{var a=graph.enabledCurves.slice();a[index]=!a[index];graph.enabledCurves=a;graph.draw();graph.edited();}}
                CalcKey {objectName:"graphFunction"+index;width:graph.width-100;height:58;label:graph.formulas[index]||"Enter function of x";active:graph.selected===index&&graph.rangeField<0;textSize:25;onTapped:{graph.selected=index;graph.rangeField=-1;graph.readTrace();plot.requestPaint();}}
            }
        }
        Row {
            spacing:10
            Repeater {model:["X min","X max","Y min","Y max"]
                CalcKey {objectName:"graphRange"+index;width:(graph.width-30)/4;height:60;textSize:19;active:graph.rangeField===index;label:modelData+": "+(graph.rangeField===index?graph.rangeInput:graph.label(graph.bounds[index]));onTapped:{graph.rangeField=index;graph.rangeInput=String(graph.bounds[index]);graph.notice="Edit "+modelData+" with the keypad, then APPLY. AC clears the value.";}}
            }
        }
        Row {spacing:10
            CalcKey {objectName:"graphDraw";width:160;height:58;label:graph.rangeField>=0?"APPLY":"DRAW";active:true;textSize:23;onTapped:graph.rangeField>=0?graph.applyRange():graph.draw()}
            CalcKey {objectName:"graphZoomIn";width:140;height:58;label:"Zoom +";textSize:22;onTapped:graph.zoom(0.5)}
            CalcKey {objectName:"graphZoomOut";width:140;height:58;label:"Zoom −";textSize:22;onTapped:graph.zoom(2)}
            CalcKey {objectName:"graphStandard";width:170;height:58;label:"Standard";textSize:22;onTapped:{graph.rangeField=-1;graph.setBounds([-10,10,-10,10]);}}
            CalcKey {objectName:"graphTable";width:180;height:58;label:graph.table?"Graph":"Table";textSize:22;onTapped:graph.table=!graph.table}
            CalcKey {objectName:"graphAngles";width:180;height:58;label:graph.angleMode;textSize:22;onTapped:{graph.angleMode=graph.angleMode==='RAD'?'DEG':'RAD';graph.draw();graph.edited();}}
        }
        Rectangle {
            width:graph.width;height:365;border.width:2;color:"white";clip:true
            Canvas {
                id:plot;objectName:"functionPlot";anchors.fill:parent;visible:!graph.table
                onVisibleChanged:if(visible)requestPaint()
                onPaint:{
                    var c=getContext('2d');c.reset();c.fillStyle='white';c.fillRect(0,0,width,height);
                    var l=65,t=18,w=width-90,h=height-54,b=graph.bounds;
                    function px(x){return l+(x-b[0])/(b[1]-b[0])*w;}
                    function py(y){return t+h-(y-b[2])/(b[3]-b[2])*h;}
                    c.font='17px sans-serif';c.fillStyle='black';c.lineWidth=1;c.strokeStyle='#b0b0b0';
                    for(var i=0;i<=4;i++){var x=l+w*i/4,y=t+h*i/4;c.beginPath();c.moveTo(x,t);c.lineTo(x,t+h);c.stroke();c.beginPath();c.moveTo(l,y);c.lineTo(l+w,y);c.stroke();c.fillText(graph.label(b[0]+(b[1]-b[0])*i/4),Math.min(width-65,x-15),height-10);c.fillText(graph.label(b[3]-(b[3]-b[2])*i/4),3,y+6);}
                    c.save();c.beginPath();c.rect(l,t,w,h);c.clip();c.strokeStyle='black';c.lineWidth=2;
                    if(b[0]<=0&&b[1]>=0){c.beginPath();c.moveTo(px(0),t);c.lineTo(px(0),t+h);c.stroke();}
                    if(b[2]<=0&&b[3]>=0){c.beginPath();c.moveTo(l,py(0));c.lineTo(l+w,py(0));c.stroke();}
                    for(var k=0;k<graph.curves.length;k++){
                        var points=graph.curves[k],last=null;c.lineWidth=3;c.beginPath();
                        for(var j=0;j<points.length;j++){
                            var p=points[j];if(p.y===null){last=null;continue;}
                            var x1=px(p.x),y1=py(p.y);
                            // A segment crossing a pole would leap across the entire viewport.
                            if(last && Math.abs(y1-last[1])<h*0.65 && (k===0 || (k===1?j%12<8:j%6<2)))c.lineTo(x1,y1);else c.moveTo(x1,y1);
                            last=[x1,y1];
                        }c.stroke();
                    }
                    var r=Calc.calculate(graph.formulas[graph.selected],{x:graph.traceX,angleMode:graph.angleMode});
                    c.lineWidth=1;c.beginPath();c.moveTo(px(graph.traceX),t);c.lineTo(px(graph.traceX),t+h);c.stroke();
                    if(r.ok){c.fillStyle='black';c.beginPath();c.arc(px(graph.traceX),py(r.value),6,0,Math.PI*2);c.fill();}c.restore();
                }
                MouseArea {anchors.fill:parent;onClicked:function(mouse){graph.traceX=graph.bounds[0]+Math.max(0,Math.min(1,(mouse.x-65)/(width-90)))*(graph.bounds[1]-graph.bounds[0]);graph.readTrace();plot.requestPaint();}}
            }
            Column {visible:graph.table;anchors.fill:parent;anchors.margins:14;spacing:0
                Text {width:parent.width;height:38;text:"x                       Y1                      Y2                      Y3";font.family:"monospace";font.pixelSize:21;font.bold:true}
                Repeater {model:7
                    Row {width:graph.width-28;height:42
                        property int rowIndex:index
                        property real xv:graph.traceX+(index-3)*(graph.bounds[1]-graph.bounds[0])/40
                        Repeater {model:4
                            Text {objectName:"graphCell"+parent.rowIndex+"_"+index;width:(graph.width-28)/4;height:42;font.pixelSize:22;font.family:"monospace";text:{if(index===0)return graph.label(parent.xv);if(!graph.enabledCurves[index-1]||!graph.formulas[index-1])return "—";var r=Calc.calculate(graph.formulas[index-1],{x:parent.xv,angleMode:graph.angleMode});return r.ok?graph.label(r.value):"undefined";}}
                        }
                    }
                }
            }
        }
        Row {spacing:10
            CalcKey {objectName:"traceLeft";width:100;height:58;label:"←";onTapped:graph.traceStep(-1)}
            CalcKey {objectName:"traceRight";width:100;height:58;label:"→";onTapped:graph.traceStep(1)}
            Text {width:graph.width-400;height:58;text:graph.traceLabel;font.pixelSize:22;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight}
            CalcKey {objectName:"graphFindZero";width:170;height:58;label:"Find zero";textSize:22;onTapped:graph.findRoot()}
        }
        Text {width:graph.width;height:52;text:graph.notice;font.pixelSize:20;wrapMode:Text.WordWrap}
        Grid {columns:7;spacing:10
            Repeater {model:["x","sin","cos","tan","^","(",")","7","8","9","÷","√","ln","π","4","5","6","×","abs","log","e","1","2","3","−",".","⌫","AC","0","+","x²","x³","1/x","exp","DRAW"]
                CalcKey {objectName:"graphKey"+index;width:(graph.width-60)/7;height:70;label:modelData;textSize:28;active:modelData==='DRAW';onTapped:{if(modelData==='DRAW'){if(graph.rangeField>=0)graph.applyRange();else graph.draw();}else graph.edit(modelData);}}
            }
        }
    }
}
