import QtQuick 2.15
import Qt.labs.settings 1.1
import net.asivery.ApploadUtils
import "../calc.js" as Calc
import "../office.js" as Office
Rectangle {
    id:root;anchors.fill:parent;color:"white";signal close
    DisplayMethodArea { anchors.fill:parent;displayMethod:DisplayMethodArea.Fast;z:-1 }
    property string settingsFile:""
    property string mode:"Desk"
    readonly property bool scientific:mode==="Science"
    property string angleMode:"DEG"
    property real lastAnswer:0
    property string expression:""
    property string result:"0"
    property string scienceExpression:""
    property bool scienceDisplayPending:false
    onExpressionChanged:if(deskDisplayReady)scheduleScienceDisplay()
    onModeChanged:if(scientific)flushScienceDisplay()
    Timer {
        id:scienceDisplayPace;interval:80
        onTriggered:if(root.scienceDisplayPending){root.scienceExpression=root.expression;root.scienceDisplayPending=false;restart();}
    }
    function scheduleScienceDisplay(){
        if(!scienceDisplayPace.running){scienceExpression=expression;scienceDisplayPending=false;scienceDisplayPace.start();}
        else scienceDisplayPending=true;
    }
    function flushScienceDisplay(){scienceExpression=expression;scienceDisplayPending=false;scienceDisplayPace.stop();}
    property string notice:"Office mode · immediate execution · 12 significant digits"
    property bool completed:false
    property var desk:Office.fresh()
    property var deskDisplay:Office.fresh()
    property bool deskDisplayReady:false
    property bool deskDisplayPending:false
    onDeskChanged:if(deskDisplayReady)scheduleDeskDisplay()
    // Accept every contact immediately; bound repaint requests during a burst.
    Timer {
        id:deskDisplayPace;interval:80
        onTriggered:if(root.deskDisplayPending){root.deskDisplay=root.desk;root.deskDisplayPending=false;restart();}
    }
    function scheduleDeskDisplay(){
        if(!deskDisplayPace.running){deskDisplay=desk;deskDisplayPending=false;deskDisplayPace.start();}
        else deskDisplayPending=true;
    }
    function flushDeskDisplay(){deskDisplay=desk;deskDisplayPending=false;deskDisplayPace.stop();}
    property var history:[]
    property bool showHistory:false
    Settings {id:saved;fileName:root.settingsFile;category:"PaperCalc";property string recent:"[]";property string angles:"DEG";property real memory:0;property string graphs:'["x^2-4","sin(x)",""]';property string graphAngles:"RAD";property string graphEnabled:"[true,true,false]";property string graphWindow:"[-10,10,-10,10]"}
    Component.onCompleted:{
        angleMode=saved.angles==='RAD'?'RAD':'DEG';
        var d=Office.fresh();d.memory=isFinite(saved.memory)?saved.memory:0;desk=d;
        try{var h=JSON.parse(saved.recent);if(Array.isArray(h))history=h.filter(function(v){return typeof v==='string';});}catch(e){}
        try{var f=JSON.parse(saved.graphs);if(Array.isArray(f)&&f.length===3&&f.every(function(v){return typeof v==='string'&&v.length<=160;}))graph.formulas=f;}catch(e){}
        graph.angleMode=saved.graphAngles==='DEG'?'DEG':'RAD';
        try{var en=JSON.parse(saved.graphEnabled);if(Array.isArray(en)&&en.length===3)graph.enabledCurves=en.map(function(v){return v===true;});}catch(e){}
        try{var b=JSON.parse(saved.graphWindow);if(Array.isArray(b)&&b.length===4&&b.every(function(v){return typeof v==='number';}))graph.setBounds(b);}catch(e){}
        graph.draw();
        deskDisplay=desk;deskDisplayReady=true;
        Qt.callLater(function(){root.forceActiveFocus();});
        console.log("PaperCalc ready offline, PaperDesk desk/science/graphs");
    }
    function unloading(){saved.memory=desk.memory;saved.angles=angleMode;}
    function addHistory(entry){history=[entry].concat(history);saved.recent=JSON.stringify(history);}
    function officeKey(k){
        desk=Office.press(desk,k);if(k==='AC'||k==='='||desk.error)flushDeskDisplay();saved.memory=desk.memory;if(desk.record)addHistory(desk.record);
        notice=desk.error||'Office mode · immediate execution';
    }
    function reset() { expression="";result="0";completed=false;flushScienceDisplay();notice="Expression mode · × and ÷ before + and − · "+angleMode; }
    function solve() {
        var answer=Calc.calculate(expression,{angleMode:angleMode,ans:lastAnswer}); result=answer.text;
        if(answer.ok) {
            lastAnswer=answer.value;completed=true;
            var entry=expression+" = "+result+(scientific || /(?:sin|cos|tan)\s*\(/i.test(expression)?" ["+angleMode+"]":"");
            addHistory(entry);
            notice="Result rounded to 12 significant digits.";
        } else notice=answer.text;
        flushScienceDisplay();
    }
    function key(value) {
        if(value==="C" || value==="AC"){reset();return;}
        if(value==="="){solve();return;}
        if(completed){if(!/[+−×÷^!]/.test(value.charAt(0)))expression="";else expression=result;completed=false;}
        if(value==="⌫")expression=expression.slice(0,-1);
        else if(expression.length+value.length<=160)expression+=value;
    }
    function scienceKey(label) {
        if(label === "DEG / RAD") { angleMode=angleMode==="DEG"?"RAD":"DEG";saved.angles=angleMode;notice="Angles: "+(angleMode==="DEG"?"degrees (DEG)":"radians (RAD)");return; }
        var insert={"√":"sqrt(","x²":"^2","xʸ":"^","10ˣ":"10^(","1/x":"1/(","π":"π","e":"e","n!":"!","Ans":"ans"};
        key(insert[label]!==undefined?insert[label]:label+"(");
    }

    Item {
        id:face;width:1100;height:1466
        scale:Math.min(root.width/width,root.height/height)
        x:(root.width-width*scale)/2;y:(root.height-height*scale)/2
        transformOrigin:Item.TopLeft
        Rectangle {x:24;y:20;width:1052;height:100;color:"black";radius:8
            Text {x:26;y:16;text:"PAPER CALC";color:"white";font.pixelSize:36;font.bold:true}
            Text {x:28;y:65;text:"PAPERDESK / OFFICE CALCULATOR";color:"white";font.pixelSize:17;font.letterSpacing:2}
            CalcKey {objectName:"calcClose";x:850;y:18;width:180;height:64;label:"Close";onTapped:root.close()}
        }
        Row {x:24;y:136;spacing:12
            Repeater {model:["Desk","Science","Graph"]
                CalcKey {objectName:"calcMode"+modelData;width:254;height:68;label:modelData;active:root.mode===modelData;textSize:25;onTapped:{root.mode=modelData;root.notice=modelData==='Science'?'Expression mode · × and ÷ before + and − · '+root.angleMode:'Office mode · immediate execution';}}
            }
            CalcKey {objectName:"calcHistory";width:254;height:68;label:"History ("+root.history.length+")";textSize:23;onTapped:root.showHistory=true}
        }
        GraphPanel {id:graph;objectName:"calcGraphPanel";x:24;y:224;width:1052;height:1218;visible:root.mode==='Graph';onEdited:{saved.graphs=JSON.stringify(formulas);saved.graphAngles=angleMode;saved.graphEnabled=JSON.stringify(enabledCurves);saved.graphWindow=JSON.stringify(bounds);}}
        Item {visible:root.mode!=='Graph';x:24;y:224;width:1052;height:1218
            Rectangle {id:display;width:parent.width;height:root.scientific?206:270;color:"white";border.width:3;radius:8
                Text {x:24;y:18;width:parent.width-48;height:36;text:root.mode==='Desk'?(root.deskDisplay.memory!==0?'M   ':'')+(root.deskDisplay.op?'Pending: '+root.deskDisplay.left+' '+root.deskDisplay.op:'DESK'):('SCIENCE / '+root.angleMode);font.pixelSize:21;font.bold:true}
                Flickable {
                    id:receipt;objectName:"calcReceipt";x:24;y:58;width:parent.width-48;height:root.scientific?35:104
                    clip:true;contentWidth:width;contentHeight:receiptText.height;boundsBehavior:Flickable.StopAtBounds
                    Text {id:receiptText;objectName:"calcReceiptText";width:receipt.width;text:root.scientific?root.scienceExpression:root.deskDisplay.tape;font.pixelSize:26;horizontalAlignment:Text.AlignRight;wrapMode:Text.WrapAnywhere
                        onHeightChanged:receipt.contentY=Math.max(0,height-receipt.height)
                        onTextChanged:Qt.callLater(function(){receipt.contentY=Math.max(0,receiptText.height-receipt.height);})
                    }
                }
                Text {objectName:"calcDisplay";x:24;y:root.scientific?102:172;width:parent.width-48;height:85;text:root.mode==='Desk'?(root.deskDisplay.error?'Error':root.deskDisplay.input):root.result;font.pixelSize:62;font.family:"DejaVu Sans Mono";horizontalAlignment:Text.AlignRight;verticalAlignment:Text.AlignVCenter;fontSizeMode:Text.Fit;minimumPixelSize:24}
            }
            Text {visible:root.scientific;x:8;y:220;width:1036;height:56;text:root.notice;font.pixelSize:22;wrapMode:Text.WordWrap}
            Item {visible:root.mode==='Desk';y:292;width:1052;height:926
                Item {width:1052;height:900
                    Repeater {model:["MC","MR","M+","M−","GT","AC","CE","⌫","±","√","7","8","9","÷","%","4","5","6","×","−","1","2","3","+","=","0","00",".","+","="]
                        CalcKey {objectName:"deskKey"+index;x:(index%5)*212.8;y:Math.floor(index/5)*152;visible:index<28;width:200.8;height:index===23||index===24?292:140;label:modelData;textSize:39;active:modelData==='=';onTapped:{if(modelData==='00'){root.officeKey('0');root.officeKey('0');}else root.officeKey(modelData);}}
                    }
                }
            }
            Item {visible:root.scientific;y:292;width:1052;height:916
                Grid {columns:5;spacing:12
                    Repeater {model:["sin","cos","tan","DEG / RAD","π","asin","acos","atan","ln","log","√","x²","xʸ","10ˣ","e","n!","abs","exp","1/x","Ans"]
                        CalcKey {objectName:"calcSci"+modelData;width:200.8;height:78;label:modelData==='DEG / RAD'?root.angleMode:modelData;textSize:28;onTapped:root.scienceKey(modelData)}
                    }
                }
                Grid {y:368;columns:5;spacing:12
                    Repeater {model:["7","8","9","(",")","4","5","6","×","÷","1","2","3","+","−","0",".","⌫","C","="]
                        CalcKey {objectName:"calcKey"+modelData;width:200.8;height:124;label:modelData;textSize:39;active:modelData==='=';onTapped:root.key(modelData)}
                    }
                }
            }
        }
        Rectangle {visible:root.showHistory;anchors.fill:parent;color:"white";z:10
            Text {x:24;y:30;text:"Calculation tape";font.pixelSize:38;font.bold:true}
            Text {x:24;y:88;text:"Full calculations · scroll to read · tap a result to reuse it";font.pixelSize:22}
            CalcKey {x:860;y:25;width:216;height:70;label:"Back";onTapped:root.showHistory=false}
            ListView {id:tape;objectName:"calcTape";x:24;y:140;width:1052;height:1300;clip:true;model:root.history;spacing:12
                header:Text {width:tape.width;bottomPadding:24;text:root.desk.tape?'Current: '+root.desk.tape:'';font.pixelSize:28;wrapMode:Text.WrapAnywhere}
                delegate:Rectangle {width:tape.width;height:Math.max(110,historyText.implicitHeight+36);border.width:2;radius:8;color:"white"
                    Text {id:historyText;x:18;y:18;width:parent.width-36;text:modelData;font.pixelSize:28;color:"black";wrapMode:Text.WrapAnywhere}
                    MouseArea {id:tapHistory;anchors.fill:parent;onClicked:{var parts=modelData.split(' = '),raw=parts[parts.length-1].replace(/ \[.*$/,'');var n=Number(raw);if(isFinite(n)){root.lastAnswer=n;root.result=String(n);root.expression=String(n);root.completed=true;root.flushScienceDisplay();var d=Office.fresh();d.memory=root.desk.memory;d.total=root.desk.total;d.input=String(n);root.desk=d;root.showHistory=false;}}}
                }
            }
        }
    }
}
