import QtQuick 2.15
import QtQuick.Window 2.15

// Run only in the diagnostic app's unique Settings/cache namespace. The launcher
// must retain/restore xochitl.conf and saved artwork, as run-sketch-native does.
// No Save, export, calibration or load of the user's sketchbook occurs here.
Rectangle {
    id:bench;anchors.fill:parent;color:"white";signal close
    property int phase:0
    property int caseIndex:0
    property real phaseAt:Date.now()
    property real lastTick:0
    property real measureAt:0
    property real firstInputAt:0
    property real firstPublishedAt:0
    property real firstRasterAt:0
    property real firstTileAt:0
    property real firstFrameAt:0
    property real strokeDoneAt:0
    property var gaps:[]
    property var pollCosts:[]
    property var handlerCosts:[]
    property var results:[]
    property var baselineRaster:[]
    property var baselineTile:[]
    property var probeTile:null
    property int fixtureRow:0
    property int fixtureStrokes:0
    property real fixtureMs:0
    property int syntheticStep:0
    property string savedEnvelope:""
    property string activeCase:""
    property bool freshOnly:false
    property var definitions:freshOnly?allDefinitions.slice(0,2):allDefinitions
    property var allDefinitions:[
        {id:"latency-fresh-hb",tool:1,size:12,surface:"fresh"},
        {id:"latency-fresh-charcoal",tool:4,size:38,surface:"fresh"},
        {id:"latency-layered-hb",tool:1,size:12,surface:"layered"},
        {id:"latency-layered-charcoal",tool:4,size:38,surface:"layered"}
    ]
    function find(item,name) {
        if(!item)return null;if(item.objectName===name)return item;
        for(var i=0;i<item.children.length;i++){var hit=find(item.children[i],name);if(hit)return hit;}
        return null;
    }
    function percentile(values,q) {
        if(!values.length)return null;
        var sorted=values.slice().sort(function(a,b){return a-b;});
        return sorted[Math.min(sorted.length-1,Math.floor(q*sorted.length))];
    }
    function stats(values) {
        return {count:values.length,p50_ms:percentile(values,.5),p95_ms:percentile(values,.95),max_ms:percentile(values,1)};
    }
    function different(a,b) {
        if(a.length!==b.length)return true;
        for(var i=0;i<a.length;i++)if(a[i]!==b[i])return true;
        return false;
    }
    function rasterProbe() {return subject.item.nativeRaster.pixels(116,356,12,12);}
    function tileProbe() {
        if(!probeTile)return [];
        var s=subject.item.artTileSize;
        return probeTile.displayPixels(116% s,356% s,12,12);
    }
    function inspectPixels(now) {
        if(!firstInputAt)return;
        var started=Date.now();
        if(!firstRasterAt && different(rasterProbe(),baselineRaster))firstRasterAt=now;
        if(!firstTileAt && different(tileProbe(),baselineTile))firstTileAt=now;
        if(pollCosts.length<1024)pollCosts.push(Date.now()-started);
    }
    function configure() {
        var a=subject.item,d=definitions[caseIndex];
        a.tool=d.tool;a.brushSize=d.size;a.strength=1;a.fullScreen=false;
        a.nativeRaster.sharpen(d.tool);a.nativeRaster.cleanFinger();a.lastStroke=null;
    }
    function resetPage() {
        var a=subject.item;
        // Diagnostic namespace only; replacing in-memory page does not persist it.
        a.confirmation="book";a.confirmAction();a.tool=4;a.brushSize=38;a.strength=.35;
        fixtureRow=0;fixtureStrokes=0;fixtureMs=0;
    }
    function buildFixtureRow() {
        var a=subject.item,row=fixtureRow%48,pass=Math.floor(fixtureRow/48);
        var y=100+row*28,x0=pass?1080:120,x1=pass?120:1080,started=Date.now();
        a.beginStroke(Qt.point(x0,y),"pen",4,.55);
        // Several segments avoid a single pathological full-width GUI task.
        for(var i=1;i<=8;i++)a.extendStroke(Qt.point(x0+(x1-x0)*i/8,y),"pen",.55);
        a.finishStroke();fixtureMs+=Date.now()-started;fixtureRow++;fixtureStrokes++;
    }
    function requestInput() {
        var a=subject.item,d=definitions[caseIndex],surface=find(a,"drawingCanvas"),w=bench.Window.window;
        var p=surface.mapToItem(w.contentItem,120,360),q=surface.mapToItem(w.contentItem,1080,620);
        var c=Math.floor(116/a.artTileSize),r=Math.floor(356/a.artTileSize);
        probeTile=find(a,"artTile"+(r*a.artColumns+c));
        baselineRaster=rasterProbe();baselineTile=tileProbe();
        firstInputAt=0;firstPublishedAt=0;firstRasterAt=0;firstTileAt=0;firstFrameAt=0;strokeDoneAt=0;
        gaps=[];pollCosts=[];handlerCosts=[];lastTick=Date.now();measureAt=lastTick;activeCase=d.id;phase=4;
        console.log("PAPERSKETCH_INPUT_READY "+JSON.stringify({mode:"pen",id:d.id,pattern:"upright",start:[p.x,p.y],end:[q.x,q.y]}));
    }
    function captureCase() {
        var a=subject.item,d=definitions[caseIndex],s=a.lastStroke;
        var item={id:d.id,tool:d.tool,size:d.size,surface:d.surface,
            measured_input:"Linux evdev via production pen handlers; fixed upright 0.55 pressure",
            first_input_observed_ms:firstInputAt,first_damage_published_ms:firstPublishedAt,
            raster_seen_ms:firstRasterAt,tile_seen_ms:firstTileAt,first_frame_after_tile_ms:firstFrameAt,
            qt_input_to_raster_upper_ms:firstRasterAt-firstInputAt,
            qt_input_to_tile_upper_ms:firstTileAt-firstInputAt,
            qt_input_to_submitted_frame_upper_ms:firstFrameAt-firstInputAt,
            event_loop_gaps:stats(gaps),gaps_over_50ms:gaps.filter(function(v){return v>=50;}),
            pixel_probe_cost:stats(pollCosts),polling_granularity_ms:16,
            native_segment_peak_ms:a.nativePatchMaxMs,
            native_latency_stats:typeof a.nativeRaster.latencyStats==="function"?a.nativeRaster.latencyStats():null,
            native_segment_peak_scope:"maximum internal material segment since page reset; layered cases include fixture work",
            raw_replay:a.nativeRaster.rawReplayStats(),pressure_matches:a.nativeRaster.pressureMatchCounts(),
            delivered_points:s?(s.samples||s.points.length):0,retained_points:s?s.points.length:0,
            metadata_bytes:JSON.stringify(a.notebook).length,
            fixture_strokes:fixtureStrokes,fixture_cpu_wall_ms:fixtureMs,
            first_paint_metric:"changed bytes in native RasterTile display snapshot; upper bound sampled by GUI timer",
            frame_metric:"Qt frameSwapped after changed tile snapshot; callback delivery can be delayed",
            physical_panel_latency_measured:false};
        item.passed=!!(firstInputAt && firstRasterAt && firstTileAt && firstFrameAt && s && s.tool===d.tool && item.delivered_points>=20 && a.nativeRasterActive);
        // Correctness gate only. A slow result must remain visible in the report.
        results.push(item);syntheticStep=0;handlerCosts=[];phase=6;
        a.beginStroke(Qt.point(200,1000),"pen",d.tool,.55);
    }
    function diagnostics(reason) {
        var a=subject.item,board=a?a.nativeRaster:null;
        return {reason:reason||"",case_index:caseIndex,case_id:activeCase,phase:phase,
            firstInputAt:firstInputAt,firstPublishedAt:firstPublishedAt,
            firstRasterAt:firstRasterAt,firstTileAt:firstTileAt,firstFrameAt:firstFrameAt,
            activeSource:a?a.activeSource:null,lastStroke:a?(a.lastStroke||null):null,
            activeStroke:a?(a.activeStroke||null):null,busy:a?a.busy:null,
            ready:a?a.ready:null,bitmapMode:a?a.bitmapMode:null,
            nativeLatencyStats:board && typeof board.latencyStats==="function"?board.latencyStats():null,
            pressureCounts:board && typeof board.pressureMatchCounts==="function"?board.pressureMatchCounts():null,
            rawReplay:board && typeof board.rawReplayStats==="function"?board.rawReplayStats():null};
    }
    function finishAll(reason) {
        var a=subject.item,unchanged=a && a.nativeRaster && a.nativeRaster.loadNotebook()===savedEnvelope;
        var diagnostic=diagnostics(reason);
        if(reason && caseIndex<definitions.length && !results.some(function(c){return c.id===definitions[caseIndex].id;})){
            var d=definitions[caseIndex];
            results.push({id:d.id,tool:d.tool,size:d.size,surface:d.surface,passed:false,error:reason,
                first_input_observed_ms:firstInputAt,first_damage_published_ms:firstPublishedAt,
                raster_seen_ms:firstRasterAt,tile_seen_ms:firstTileAt,first_frame_after_tile_ms:firstFrameAt,
                native_latency_stats:diagnostic.nativeLatencyStats,
                event_loop_gaps:stats(gaps),gaps_over_50ms:gaps.filter(function(v){return v>=50;}),
                pixel_probe_cost:stats(pollCosts),diagnostics:diagnostic,physical_panel_latency_measured:false});
        }
        var passed=!reason && results.length===definitions.length && unchanged && results.every(function(c){return c.passed;});
        var probe={passed:passed,error:reason||"",cases:results,scope:freshOnly?"fresh-only":"fresh-and-layered",planned_cases:definitions.map(function(d){return d.id;}),diagnostics:diagnostic,no_automatic_save:unchanged,
            physical_panel_latency_measured:false,
            limitations:"Software input/raster/tile/frame timestamps only; no camera or optical panel measurement. Date.now has millisecond resolution. Synthetic handler costs are separate from evdev timings. "+(freshOnly?"Fresh-only scope skips the layered fixture.":"Layered fixture has 96 in-memory charcoal strokes and is never saved.")};
        console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"isolated fresh/layered software latency diagnostic",cases:results,latency_probe:probe}));
        ticker.stop();phase=9;
    }
    function step() {
        var now=Date.now(),a=subject.item;
        if(phase===4 && lastTick && firstInputAt && !strokeDoneAt && gaps.length<4096)gaps.push(now-lastTick);
        lastTick=now;
        if(now-phaseAt>110000){finishAll("diagnostic timeout");return;}
        if(!a || !a.ready || a.replaying || !a.bitmapMode)return;
        if(phase===0){savedEnvelope=a.nativeRaster.loadNotebook();phaseAt=now;phase=1;return;}
        if(phase===1 && now-phaseAt>3000){resetPage();configure();phaseAt=now;phase=2;return;}
        if(phase===2 && now-phaseAt>500){
            if(definitions[caseIndex].surface==="layered"){a.tool=4;a.brushSize=38;a.strength=.35;phase=3;}
            else {configure();requestInput();}
            return;
        }
        if(phase===3){
            if(fixtureRow<96){buildFixtureRow();return;}
            configure();phaseAt=now;phase=31;return;
        }
        if(phase===31 && now-phaseAt>500){requestInput();return;}
        if(phase===4){
            inspectPixels(now);
            if(firstInputAt && a.activeStroke===null && a.lastStroke && a.lastStroke.tool===definitions[caseIndex].tool){
                if(!strokeDoneAt)strokeDoneAt=now;
                if(firstTileAt && firstFrameAt && now-strokeDoneAt>100){captureCase();return;}
            }
            if(now-measureAt>15000){finishAll("input or first software paint missing for "+activeCase);return;}
        }
        if(phase===6){
            var d=definitions[caseIndex],started=Date.now();
            a.extendStroke(Qt.point(200+(syntheticStep+1)*12,1000+16*Math.sin(syntheticStep*.4)),"pen",.55);
            handlerCosts.push(Date.now()-started);syntheticStep++;
            if(syntheticStep>=48){
                a.finishStroke();
                results[results.length-1].synthetic_production_extend_cost=stats(handlerCosts);
                results[results.length-1].synthetic_cost_scope="48 direct production extendStroke calls, one per timer; includes pressure lookup and advance, excludes evdev delivery; 12px steps at pressure0.55";
                console.log("PAPERSKETCH_NATIVE_CASE "+JSON.stringify(results[results.length-1]));
                caseIndex++;if(caseIndex>=definitions.length){finishAll("");return;}
                phase=1;phaseAt=now-2600;
            }
        }
    }
    Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
    Connections {
        target:subject.item
        function onActiveSourceChanged() {
            if(bench.phase===4 && subject.item.activeSource==="pen" && !bench.firstInputAt)bench.firstInputAt=Date.now();
        }
    }
    Connections {
        target:subject.item?subject.item.nativeRaster:null
        function onChanged(rect) {
            if(bench.phase===4 && bench.firstInputAt && !bench.firstPublishedAt)bench.firstPublishedAt=Date.now();
        }
    }
    Connections {
        target:bench.Window.window
        function onFrameSwapped() {
            if(bench.phase!==4 || !bench.firstInputAt || bench.firstFrameAt)return;
            var now=Date.now();bench.inspectPixels(now);
            if(bench.firstTileAt)bench.firstFrameAt=now;
        }
    }
    Timer{id:ticker;interval:16;repeat:true;running:true;onTriggered:bench.step()}
}
