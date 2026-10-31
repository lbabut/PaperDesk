import QtQuick 2.15
import QtQuick.Window 2.15

Rectangle {
    id:bench
    anchors.fill:parent
    color:"white"
    signal close
    property int variant:0
    property int caseIndex:0
    property int phase:0
    property int tick:0
    property real lastTick:0
    property real caseStart:0
    property real finishAt:0
    property real waitingFrame:0
    property int firstRaster:0
    property var gaps:[]
    property var frameDelays:[]
    property var results:[]
    property var variantNames:["baseline","constant-fast"]
    property var caseNames:["hb","charcoal","smudge"]
    function percentile(values,f) {
        if(!values.length)return null;
        var sorted=values.slice().sort(function(a,b){return a-b});
        return sorted[Math.min(sorted.length-1,Math.floor(sorted.length*f))];
    }
    function startCase() {
        var a=subject.item;
        tick=0;gaps=[];frameDelays=[];waitingFrame=0;
        a.tool=caseIndex===0?1:caseIndex===1?4:7;
        a.brushSize=caseIndex===0?5:caseIndex===1?40:64;
        a.strength=0.8;a.tone=0;
        firstRaster=a.rasterPasses;
        a.beginStroke(Qt.point(200,500),caseIndex===2?"finger":"pen",a.tool,0.7);
        caseStart=Date.now();lastTick=caseStart;phase=2;
        console.log("PAPERSKETCH_NATIVE_CASE",variantNames[variant],caseNames[caseIndex]);
    }
    function step() {
        var a=subject.item,now=Date.now();
        if(phase===0) {
            if(!a || !a.ready || a.replaying)return;
            a.notebook={version:1,index:0,pages:[{strokes:[],paper:"plain"}]};
            a.pageIndex=0;a.totalPoints=0;a.redraw();phase=1;return;
        }
        if(phase===1) {
            if(a.replaying)return;
            startCase();return;
        }
        if(phase===2) {
            gaps.push(now-lastTick);lastTick=now;
            if(!waitingFrame)waitingFrame=now;
            tick++;
            var count=caseIndex===2?90:180;
            var x=200+tick*3.5,y=caseIndex===2?500:500+100*Math.sin(tick*0.055);
            a.extendStroke(Qt.point(x,y),caseIndex===2?"finger":"pen",0.7);
            if(tick>=count) {
                var inputMs=now-caseStart,passes=a.rasterPasses-firstRaster;
                results.push({variant:variantNames[variant],case_name:caseNames[caseIndex],
                    synthetic_input_samples:tick,input_wall_ms:inputMs,
                    timer_gap_p50_ms:percentile(gaps,0.5),timer_gap_p95_ms:percentile(gaps,0.95),
                    timer_gap_max_ms:percentile(gaps,1),
                    submitted_frame_delay_p50_ms:percentile(frameDelays,0.5),
                    submitted_frame_delay_p95_ms:percentile(frameDelays,0.95),
                    submitted_frame_delay_max_ms:percentile(frameDelays,1),
                    bitmap_passes_during_input:passes});
                a.finishStroke();finishAt=Date.now();phase=3;
            }
            return;
        }
        if(phase===3) {
            if(a.painting)return;
            results[results.length-1].bitmap_commit_ms=Date.now()-finishAt;
            results[results.length-1].max_bitmap_paint_ms=a.maxPaintMs;
            results[results.length-1].max_bitmap_queue_ms=a.maxQueueWaitMs;
            if(caseIndex<2) {caseIndex++;phase=1;return;}
            if(variant===0) {
                variant=1;caseIndex=0;phase=0;
                subject.source="constant-fast/ui/main.qml";return;
            }
            phase=4;
            console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({
                execution:"reMarkable Xochitl AppLoad",
                input:"synthetic calls to the production stroke functions, timed on the tablet",
                frame_metric:"Qt window frameSwapped; not physical e-ink pixel latency",
                cases:results}));
            ticker.stop();
        }
    }
    Loader {
        id:subject
        anchors.fill:parent
        source:"baseline/ui/main.qml"
    }
    Connections {
        target:bench.Window.window
        function onFrameSwapped() {
            if(bench.phase===2 && bench.waitingFrame) {
                bench.frameDelays.push(Date.now()-bench.waitingFrame);
                bench.waitingFrame=0;
            }
        }
    }
    Timer {id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
    Rectangle {
        anchors.top:parent.top;width:parent.width;height:88;color:"white";z:20;border.color:"black";border.width:2
        Text {
            anchors.centerIn:parent
            text:bench.phase===4?"Diagnostics complete":"Paper Sketch diagnostics: "+bench.variantNames[bench.variant]+" / "+bench.caseNames[bench.caseIndex]
            font.pixelSize:28;color:"black"
        }
    }
}
