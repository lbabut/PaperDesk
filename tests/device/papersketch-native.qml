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
    property var pixelProbes:[]
    property bool smokeOnly:false
    property bool pixelsChecked:false
    property var pixelProbe:null
    function find(item,name) {
        if(item.objectName===name)return item;
        for(var i=0;i<item.children.length;i++) {var hit=find(item.children[i],name);if(hit)return hit;}
        return null;
    }
    function samples() {
        var master=find(subject.item,"drawingCanvas").getContext("2d");
        var size=subject.item.artTileSize || 400,columns=Math.ceil(1200/size);
        var col=Math.floor(300/size),row=Math.floor(300/size);
        var tile=find(subject.item,"artTile"+(row*columns+col)).getContext("2d");
        var raw=master.getImageData(319,264,1,73).data,profile=[];
        var traw=tile.getImageData(319-col*size,264-row*size,1,73).data,tprofile=[];
        for(var i=0;i<73;i++){profile.push(raw[i*4]);tprofile.push(traw[i*4]);}
        return {profile:profile,tileProfile:tprofile,core:master.getImageData(300,300,1,1).data[0],
                beside:master.getImageData(327,300,1,1).data[0],
                tileCore:tile.getImageData(300-col*size,300-row*size,1,1).data[0],
                tileBeside:tile.getImageData(327-col*size,300-row*size,1,1).data[0]};
    }
    function sameProfile(a,b){return a.every(function(v,i){return Math.abs(v-b[i])<=1;});}
    function samePixels(a,b) {return a.core===b.core && a.beside===b.beside && a.tileCore===b.tileCore && a.tileBeside===b.tileBeside && sameProfile(a.profile,b.profile) && sameProfile(a.tileProfile,b.tileProfile); }
    function probeStep() {
        var a=subject.item;
        if(a.painting || a.replaying || Date.now()-finishAt<250)return;
        if(phase===10) {
            pixelProbe={variant:variantNames[variant],before:samples()};
            a.brushSize=64;a.strength=1;
            a.beginStroke(Qt.point(240,300),"finger",7,1);
            a.extendStroke(Qt.point(360,300),"finger",1);a.finishStroke();
            finishAt=Date.now();phase=11;return;
        }
        if(phase===11) {
            pixelProbe.smudged=samples();
            a.brushSize=5;
            a.beginStroke(Qt.point(900,900),"pen",1,1);a.extendStroke(Qt.point(920,920),"pen",1);
            a.finishStroke();finishAt=Date.now();phase=12;return;
        }
        if(phase===12) {
            pixelProbe.afterNextStroke=samples();a.redraw();finishAt=Date.now();phase=13;return;
        }
        pixelProbe.replayed=samples();
        var p=pixelProbe;
        p.softens=p.smudged.core>p.before.core+5;
        p.transfers=p.smudged.beside<p.before.beside-5;
        p.visibleTileMatches=p.smudged.core===p.smudged.tileCore && p.smudged.beside===p.smudged.tileBeside && sameProfile(p.smudged.profile,p.smudged.tileProfile);
        p.survivesNextStroke=samePixels(p.smudged,p.afterNextStroke);
        p.survivesReplay=samePixels(p.smudged,p.replayed);
        p.passed=p.softens && p.transfers && p.visibleTileMatches && p.survivesNextStroke && p.survivesReplay;
        p.native_raster_active=a.nativeRasterActive;p.passed=p.passed && a.nativeRasterActive;
        p.native_smudge_failed=a.nativeSmudgeFailed;p.native_pipeline_max_ms=a.nativePatchMaxMs;
        pixelProbes.push(p);console.log("PAPERSKETCH_PIXEL_PROBE "+JSON.stringify(p));
        pixelsChecked=true;phase=1;
        if(smokeOnly && variant===0){variant=1;caseIndex=0;phase=0;pixelsChecked=false;subject.source="constant-fast/ui/main.qml";return;}
        if(smokeOnly){phase=4;ticker.stop();console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"reMarkable Xochitl AppLoad",cases:[],pixel_probes:pixelProbes}));}
    }
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
        if(phase>=10) {probeStep();return;}
        if(phase===0) {
            if(!a || !a.ready || a.replaying)return;
            a.notebook={version:1,index:0,pages:[{strokes:[],paper:"plain"}]};
            a.pageIndex=0;a.totalPoints=0;a.redraw();phase=1;return;
        }
        if(phase===1) {
            if(a.replaying)return;
            if(!pixelsChecked) {
                a.brushSize=24;a.strength=1;a.tone=0;
                a.beginStroke(Qt.point(300,240),"pen",3,1);
                a.extendStroke(Qt.point(300,360),"pen",1);a.finishStroke();
                finishAt=Date.now();phase=10;return;
            }
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
            results[results.length-1].native_smudge_pipeline_max_ms=a.nativePatchMaxMs;
            results[results.length-1].native_smudge_available=a.nativeSmudgeAvailable;
            results[results.length-1].native_smudge_failed=a.nativeSmudgeFailed;
            results[results.length-1].native_raster_active=a.nativeRasterActive;
            var recorded=a.page.strokes[a.page.strokes.length-1].points;
            results[results.length-1].recorded_points=recorded.length;
            results[results.length-1].final_recorded_point=recorded[recorded.length-1];
            if(caseIndex<2) {caseIndex++;phase=1;return;}
            if(variant===0) {
                variant=1;caseIndex=0;phase=0;pixelsChecked=false;
                subject.source="constant-fast/ui/main.qml";return;
            }
            phase=4;
            console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({
                execution:"reMarkable Xochitl AppLoad",
                input:"synthetic calls to the production stroke functions, timed on the tablet",
                frame_metric:"Qt window frameSwapped; not physical e-ink pixel latency",
                cases:results,pixel_probes:pixelProbes}));
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
