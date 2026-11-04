import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.settings 1.1
import net.asivery.ApploadUtils
import "../engine.js" as Ink

Rectangle {
    id: root
    color: "#e3e3e3"
    anchors.fill: parent
    signal close
    property var notebook: Ink.book()
    property int tool: 1
    property real brushSize: Ink.tools[1].size
    property var toolSizes:Ink.tools.map(function(t){return t.size;})
    property bool toolPreferencesReady:false
    property bool toolPreferencesLoading:false
    property bool toolPreferencesDirty:false
    property real strength: 1.0
    property int tone: 0
    property int paperKind: 0
    property bool kneadedEraser: false
    property bool materialOptionsLoading: false
    property bool materialsDialog: false
    property bool calibrationDialog: false
    property string calibrationMessage: ""
    property int calibrationRevision: 0
    property int calibrationSamples: 0
    property real calibrationPressure: 0
    property bool calibrationStroke: false
    readonly property bool materialsAvailable:!saveBlocked && nativeRaster!==null && typeof nativeRaster.setMaterialOptions==="function"
    readonly property int calibrationStage:calibrationRevision>=0 && nativeRaster && nativeRaster.calibrationStage!==undefined?nativeRaster.calibrationStage:0
    readonly property string calibrationStatus:calibrationRevision>=0 && nativeRaster && typeof nativeRaster.calibrationSummary==="function"?nativeRaster.calibrationSummary():"Standard pressure response"
    onPaperKindChanged:if(ready && !materialOptionsLoading)applyMaterialOptions(true)
    onKneadedEraserChanged:{if(ready && !materialOptionsLoading)applyMaterialOptions(false);rememberToolPreferences();}
    readonly property bool fingerSmudge: true
    property string lastSavedDocument:""
    property var exportBridge:null
    property var pendingPdfExport:null
    property bool exportBusy:false
    property string exportedDocumentId:""
    property bool exportDialog:false
    property bool exportOverwrite:false
    property string exportMessage:""
    property bool fullScreen:false
    onFullScreenChanged:{if(ready)nativeWrite("off");Qt.callLater(syncInputTransform)}
    property bool dirty:false
    property string pageDiskMetadata:""
    property bool newUnsavedPage:false
    property var pendingLeave:null
    property bool controlsVisible: true
    property bool ready: false
    property bool saveBlocked: false
    property string notice: ""
    property string confirmation: ""
    readonly property bool bitmapMode:nativeRasterActive && nativeRaster && nativeRaster.materialAvailable===true
    readonly property bool rawPenMode:bitmapMode && nativeRaster && nativeRaster.rawPenInputAvailable===true
    readonly property bool rawPenEnabled:rawPenMode && ready && visible && !closing && !replaying && !saveBlocked && !confirmation && !exportDialog && !materialsDialog && !calibrationDialog
    readonly property bool rawHoverBlocked:typeof rawPenHover.blocking==="boolean" && rawPenHover.blocking
    property bool rawPenDraining:false
    property int rawPenContact:0
    property int rawPenStrokes:0
    onRawPenEnabledChanged:{
        if(ready && !rawPenEnabled)nativeWrite("off");
        if(!rawPenEnabled && activeStroke && activeStroke.rawInput)finishStroke();
        if(ready)Qt.callLater(nativeHeartbeat);
        if(nativeRaster && typeof nativeRaster.setRawPenInputEnabled==="function"){
            if(rawPenEnabled)syncInputTransform();
            nativeRaster.setRawPenInputEnabled(rawPenEnabled);
        }
    }
    function rawInputOverControl(p){
        if(!fullScreen || !exitFullScreenButton.visible)return false;
        var local=exitFullScreenButton.mapFromItem(inputSurface,p.x,p.y);
        return local.x>=0 && local.y>=0 && local.x<exitFullScreenButton.width && local.y<exitFullScreenButton.height;
    }
    function drainPenInput(){
        if(!rawPenEnabled || rawPenDraining)return;
        rawPenDraining=true;syncInputTransform();
        var events=nativeRaster.takePenInput();
        for(var i=0;i<events.length;i++){
            var e=events[i],p=Qt.point(e[1],e[2]);
            if(e[0]===4){
                if(activeStroke && activeStroke.rawInput)finishStroke();
                rawPenContact=0;notice="Pen input was interrupted. Lift the pen and continue.";
            }else if(e[0]===1){
                if(activeStroke && activeStroke.rawInput)finishStroke();
                rawPenContact=0;
                if(p.x<0 || p.y<0 || p.x>=Ink.WIDTH || p.y>=Ink.HEIGHT || rawInputOverControl(p))continue;
                beginStroke(p,"pen",tool,e[3],e[6],e);
                if(activeStroke && activeStroke.rawInput)rawPenContact=e[7];
            }else if(rawPenContact===e[7] && activeStroke && activeStroke.rawInput){
                if(e[0]===3){finishStroke();rawPenContact=0;rawPenStrokes++;}
                else extendStroke(p,"pen",e[3],e);
            }
        }
        rawPenDraining=false;
    }
    Connections{target:root.nativeRaster;ignoreUnknownSignals:true;function onPenInputReady(){root.drainPenInput();}}
    readonly property bool fastDisplay:bitmapMode && nativeRaster.fastDisplay===true
    readonly property bool penNearby:bitmapMode && nativeRaster.penInRange
    onPenNearbyChanged:if(penNearby && activeSource==="finger"){
        nativeRaster.cancel();activeStroke=null;activeSource="";nativeStroke=false;pending=[];paintTimer.stop();
    }
    property var lastStroke:null
    property var activeStroke: null
    property string activeSource: ""
    property int revision: 0
    property int pageIndex: 0
    readonly property int pageCount: revision>=0 ? notebook.pages.length : 0
    property int totalPoints: 0
    property bool replaying: false
    property int replayStroke: 0
    property int replayPoint: 0
    property var pending: []
    readonly property int previewCount: liveSegments.count
    property var previewJobs: []
    property var previewTileMap: ({})
    property var paintBounds: null
    readonly property int artTileSize:128
    readonly property int artColumns:Math.ceil(Ink.WIDTH/artTileSize)
    property int rasterPasses: 0
    property bool painting: false
    property int maxPaintMs: 0
    property int maxQueueWaitMs: 0
    property bool resetCanvas: true
    property bool exportPending: false
    property string exportPath: ""
    property bool penBlocked: penInput.active || penDot.pressed || activeSource==="pen"
    readonly property bool fingerInputEnabled:fingerInput.enabled
    readonly property var page: notebook.pages[pageIndex]
    readonly property bool busy: replaying || activeStroke!==null
    readonly property real drawingScale: Math.min((workspace.width-24)/Ink.WIDTH,(workspace.height-24)/Ink.HEIGHT)
    onDrawingScaleChanged:{if(ready)nativeWrite("off");Qt.callLater(syncInputTransform)}

    // Native preview is optional and gated by the extension's fresh acknowledgement.
    property bool fastPenPreview:true
    property bool nativeFinePreview:false
    property bool nativeShadeStrength:false
    property bool nativeWidePreview:false
    onFastPenPreviewChanged:if(ready)nativeHeartbeat()
    function finePreviewTool(selected,size){return isFinite(size) && size>=1 && size<=80 && ((selected>=0 && selected<6 && selected===Math.floor(selected))||selected===8);}
    function finePreviewEligible(){return bitmapMode && typeof nativeRaster.writePreviewPermit==="function" && typeof nativeRaster.previewPressureAnchors==="function" && typeof nativeRaster.repairPreview==="function" && fastPenPreview && rawPenEnabled && (brushSize<=16 || nativeWidePreview) && finePreviewTool(tool,brushSize) && isFinite(strength) && strength>=.05 && strength<=1 && (strength===1 || nativeShadeStrength || tool===8);}
    property bool nativeReady: false
    property bool nativeArmed: false
    property bool nativeStroke: false
    property var nativeRequest: null
    property string nativeState: ""
    property bool closing: false
    onToolChanged:{
        if(toolPreferencesReady && !toolPreferencesLoading){
            toolPreferencesLoading=true;brushSize=toolSize(tool);toolPreferencesLoading=false;
            rememberToolPreferences();
        }
        if(ready)nativeHeartbeat();
    }
    onBrushSizeChanged:{
        if(toolPreferencesReady && !toolPreferencesLoading){
            var sizes=toolSizes.slice();sizes[tool]=Ink.clamp(brushSize,1,80);toolSizes=sizes;
            rememberToolPreferences();
        }
        if(ready && !sizeSlider.pressed)nativeHeartbeat();
    }
    onControlsVisibleChanged:if(ready) {nativeArmed=false;nativeWrite("off");}
    Timer { interval:400;running:root.visible && !root.closing && (!root.bitmapMode||(root.fastPenPreview&&root.finePreviewTool(root.tool,root.brushSize)));repeat:true;triggeredOnStart:true;onTriggered:root.nativeHeartbeat() }
    function nativeWrite(value) {
        if(nativeRaster && typeof nativeRaster.writePreviewPermit==="function"){
            if(!nativeRaster.writePreviewPermit(value))nativeArmed=false;
            return;
        }
        try {
            var x=new XMLHttpRequest();nativeRequest=x;
            x.onreadystatechange=function(){if(x.readyState===XMLHttpRequest.DONE && nativeRequest===x)nativeRequest=null;};
            x.open("PUT","file:///tmp/papersketch-ink");x.send(value);
        }
        catch(e) {nativeArmed=false;}
    }
    function nativeHeartbeat() {
        if(sizeSlider.pressed)return;
        if(bitmapMode&&!fastPenPreview){nativeWrite("off");nativeReady=false;nativeArmed=false;return;}
        try {
            var x=new XMLHttpRequest();x.open("GET","file:///tmp/papersketch-ink-status",false);x.send();
            var status=JSON.parse(x.responseText);
            nativeReady=status.ready===true && Math.abs(Date.now()-status.time_ms)<1500;
            nativeArmed=nativeReady && status.armed===true;nativeFinePreview=nativeReady && status.fine_preview===true;nativeShadeStrength=nativeReady && status.shade_strength===true;nativeWidePreview=nativeReady && status.wide_preview===true;
        } catch(e) {nativeReady=false;nativeArmed=false;nativeShadeStrength=false;nativeWidePreview=false;}
        if(!nativeReady)return;
        var win=root.Window.window;
        var state=(win?win.width+"x"+win.height:"no window")+" ready="+ready+" replay="+replaying+" armed="+nativeArmed+" tool="+tool+" size="+brushSize+" strength="+strength+" tone="+tone+" raw="+rawPenEnabled+" bitmap="+bitmapMode+" fine="+finePreviewEligible();
        if(nativeState!==state) {nativeState=state;console.log("PaperSketch native",state);}

        if((bitmapMode && (!finePreviewEligible() || !nativeFinePreview)) || !win || win.width!==1404 || win.height!==1872 || !visible || closing || !ready || replaying || (painting && activeStroke===null) || saveBlocked || confirmation || materialsDialog || calibrationDialog || tool===7 || activeSource==="finger") {
            nativeWrite("off");nativeArmed=false;return;
        }
        var origin=inputSurface.mapToItem(win.contentItem,0,0);
        var corner=inputSurface.mapToItem(win.contentItem,inputSurface.width,inputSurface.height);
        var x0=Math.ceil(origin.x),y0=Math.ceil(origin.y);
        var w=Math.floor(corner.x)-x0,h=Math.floor(corner.y)-y0;
        if(x0<0 || y0<0 || w<=0 || h<=0 || x0+w>1404 || y0+h>1872) {nativeWrite("off");nativeArmed=false;return;}
        var size=Math.max(1,brushSize*drawingScale);
        if(bitmapMode){
            var anchors=nativeRaster.previewPressureAnchors();
            nativeWrite("fine "+x0+" "+y0+" "+w+" "+h+" "+size+" "+tool+" "+anchors.join(" ")+" "+strength);return;
        }
        nativeWrite("on "+x0+" "+y0+" "+w+" "+h+" "+size+" "+(tool===6?1:0)+" "+Math.min(80,size/2));
    }


    property var nativeRaster:null
    property bool nativeRasterActive:false
    readonly property bool nativeSmudgeAvailable:nativeRasterActive && nativeRaster!==null
    property bool nativeSmudgeFailed:false
    readonly property int nativePatchMaxMs:nativeRaster?nativeRaster.maxSmudgeMs:0
    function initNativeRaster() {
        try {
            var proxy=Qt.createQmlObject('import QtQml 2.15; import PaperSketch.Native 1.0; QtObject { readonly property var raster: Raster }',root);
            nativeRaster=proxy.raster;nativeRaster.setNamespace(saved.category);
            if(nativeRaster.materialAvailable)nativeWrite("off");
            console.log("PaperSketch native raster available");
        } catch(e) {nativeRaster=null;console.log("PaperSketch native raster unavailable");}
    }
    function materialStateChanged() {
        dirty=true;revision++;
        if(bitmapMode)page.revision=(page.revision||0)+1;
    }
    function applyMaterialOptions(changed) {
        paperKind=Ink.clamp(Math.round(paperKind),0,2);
        // Paper texture belongs to the page and is committed with explicit Save.
        // Tool choices use their own small preference file.
        if(changed)page.materialPaperKind=paperKind;
        if(materialsAvailable){nativeRaster.setMaterialOptions(paperKind,kneadedEraser);if(changed)materialStateChanged();}
    }
    function restoreMaterialOptions(fromCache) {
        var kind=page.materialPaperKind;
        if(kind===undefined && fromCache && nativeRaster && typeof nativeRaster.materialPaperKind==="function")kind=nativeRaster.materialPaperKind();
        materialOptionsLoading=true;
        paperKind=Ink.clamp(kind===undefined?paperKind:kind,0,2);
        materialOptionsLoading=false;applyMaterialOptions(false);
    }
    function toolSize(index){var n=toolSizes[index];return isFinite(n)?Ink.clamp(n,1,80):(Ink.tools[index]||Ink.tools[1]).size;}
    function selectTool(index){tool=index;brushSize=toolSize(index);}
    function rememberToolPreferences(){
        if(!toolPreferencesReady || toolPreferencesLoading || materialOptionsLoading)return;
        toolPreferencesDirty=true;toolPreferencesTimer.restart();
    }
    function toolPreferencesDocument(){return JSON.stringify({version:1,selectedTool:tool,sizes:toolSizes,kneadedEraser:kneadedEraser});}
    function flushToolPreferences(){
        if(!toolPreferencesReady || !toolPreferencesDirty)return true;
        if(busy){toolPreferencesTimer.restart();return false;}
        var raw=toolPreferencesDocument(),ok=true;
        if(nativeRaster && typeof nativeRaster.saveToolPreferences==="function")ok=nativeRaster.saveToolPreferences(raw);
        else {fallbackToolPreferences.document=raw;if(typeof fallbackToolPreferences.sync==="function")fallbackToolPreferences.sync();}
        if(ok)toolPreferencesDirty=false;
        else {notice="Tool settings could not be saved.";toolPreferencesTimer.restart();}
        return ok;
    }
    function loadPersistentToolPreferences(){
        var raw=nativeRaster && typeof nativeRaster.loadToolPreferences==="function"?nativeRaster.loadToolPreferences():fallbackToolPreferences.document;
        var p=null;
        try {
            var candidate=JSON.parse(raw);
            if(candidate.version===1 && Number.isInteger(candidate.selectedTool) && candidate.selectedTool>=0 && candidate.selectedTool<Ink.tools.length &&
               Array.isArray(candidate.sizes) && candidate.sizes.length===Ink.tools.length && candidate.sizes.every(function(n){return typeof n==="number"&&isFinite(n)&&n>=1&&n<=80;}) &&
               typeof candidate.kneadedEraser==="boolean")p=candidate;
        }catch(e){}
        if(p){
            toolPreferencesLoading=true;materialOptionsLoading=true;
            toolSizes=p.sizes.slice();tool=p.selectedTool;brushSize=toolSize(tool);kneadedEraser=p.kneadedEraser;
            materialOptionsLoading=false;toolPreferencesLoading=false;applyMaterialOptions(false);
        }
        toolPreferencesReady=true;toolPreferencesDirty=false;
        if(!p)rememberToolPreferences();
    }
    function restoreToolPreferences(preferences) {
        toolPreferencesLoading=true;materialOptionsLoading=true;
        var selected=preferences.selectedTool;
        tool=typeof selected==="number"&&isFinite(selected)?Ink.clamp(Math.round(selected),0,Ink.tools.length-1):1;
        var sizes=Ink.tools.map(function(t){return t.size;});
        if(Array.isArray(preferences.toolSizes) && preferences.toolSizes.length===Ink.tools.length)
            for(var i=0;i<sizes.length;i++)if(isFinite(preferences.toolSizes[i]))sizes[i]=Ink.clamp(preferences.toolSizes[i],1,80);
        var size=preferences.selectedSize;
        if(typeof size==="number"&&isFinite(size))sizes[tool]=Ink.clamp(size,1,80);
        toolSizes=sizes;brushSize=toolSize(tool);
        strength=1;tone=0;
        paperKind=preferences.paperKind===undefined?saved.paperKind:Ink.clamp(preferences.paperKind,0,2);
        kneadedEraser=preferences.kneadedEraser===undefined?saved.kneadedEraser:preferences.kneadedEraser===true;
        materialOptionsLoading=false;toolPreferencesLoading=false;applyMaterialOptions(false);
    }
    function openMaterials() {
        if(busy || replaying || saveBlocked)return;
        materialsDialog=true;calibrationRevision++;
        if(nativeArmed){nativeWrite("off");nativeArmed=false;}
    }
    function sharpenTool() {
        if(!materialsAvailable || tool>5)return;
        nativeRaster.sharpen(tool);materialStateChanged();calibrationRevision++;notice="Tip sharpened";
    }
    function cleanFinger() {
        if(!materialsAvailable)return;
        nativeRaster.cleanFinger();materialStateChanged();calibrationRevision++;notice="Finger cleaned";
    }
    function startPressureCalibration() {
        if(!materialsAvailable || typeof nativeRaster.startCalibration!=="function")return;
        materialsDialog=false;calibrationMessage="";calibrationSamples=0;calibrationPressure=0;calibrationStroke=false;
        nativeRaster.startCalibration();calibrationRevision++;calibrationDialog=true;calibrationPad.clear();
    }
    function sampleCalibration(p,pressure,first) {
        if(!calibrationDialog || !nativeRaster)return;
        if(first)nativeRaster.begin(false);
        var win=root.Window.window;
        if(win){var origin=calibrationPad.mapToItem(win.contentItem,0,0);nativeRaster.setInputTransform(origin.x,origin.y,1,1);}
        var value=nativeRaster.pressureAt(p.x,p.y,pressure);
        nativeRaster.advance(tool,brushSize,strength,p.x,p.y,value,first);
        calibrationStroke=true;calibrationPressure=value;calibrationSamples++;
        calibrationPad.addPoint(p.x,p.y,value,first);
    }
    function finishCalibrationStroke() {
        if(!calibrationStroke)return;
        nativeRaster.finish();calibrationStroke=false;
    }
    function nextPressureCalibration() {
        finishCalibrationStroke();
        if(calibrationStage<2){
            if(nativeRaster.nextCalibration()===false){calibrationMessage="Draw a few more lines with your pen before continuing.";return;}
            calibrationRevision++;calibrationSamples=0;calibrationMessage="";calibrationPad.clear();return;
        }
        var result=nativeRaster.finishCalibration();calibrationRevision++;
        if(result.ok){calibrationDialog=false;materialsDialog=true;calibrationMessage="";notice="Pressure response saved";syncInputTransform();}
        else calibrationMessage=result.error || "Draw several lines in each step, then try again.";
    }
    function cancelPressureCalibration() {
        finishCalibrationStroke();
        if(nativeRaster && typeof nativeRaster.cancelCalibration==="function")nativeRaster.cancelCalibration();
        calibrationDialog=false;materialsDialog=true;calibrationMessage="";calibrationRevision++;syncInputTransform();
    }
    function resetPressureCalibration() {
        if(!materialsAvailable || typeof nativeRaster.resetCalibration!=="function")return;
        if(nativeRaster.resetCalibration()===false){notice="Pressure response could not be reset. Your saved response is unchanged.";return;}
        calibrationRevision++;notice="Standard pressure response restored";
    }
    function flattenBitmap() {
        if(nativeRaster && nativeRaster.materialAvailable && !page.bitmap){
            page.bitmap=true;page.revision=0;page.strokes=[];totalPoints=0;revision++;
            console.log("PaperSketch bitmap migration complete");
        }
    }
    function importNativeRaster(c) {
        if(!nativeRaster)return;
        nativeRasterActive=nativeRaster.importPixels(c.getImageData(0,0,Ink.WIDTH,Ink.HEIGHT).data);
        if(nativeRasterActive){restoreMaterialOptions(false);flattenBitmap();console.log("PaperSketch optical digest",nativeRaster.opticalDigest());}
    }
    function nativeContext() {
        return {getImageData:function(x,y,w,h){return {data:nativeRaster.pixels(x,y,w,h)};}};
    }

    Connections {target:root.nativeRaster;ignoreUnknownSignals:true;function onSaveFailed(){root.notice="Save failed. Your drawing is still in memory.";console.log("PaperSketch native save FAILED");}function onCalibrationChanged(){root.calibrationRevision++;}}
    Settings {
        id: saved
        objectName:"sketchSettings"
        category: "PaperDeskSketch"
        property string document: ""
        property string checkpoint: ""
        property int selectedTool: 1
        property real selectedSize: 5
        property real selectedStrength: 0.8
        property int selectedTone: 0
        property bool useFinger: true
        property int paperKind: 0
        property bool kneadedEraser: false
    }
    Settings {id:fallbackToolPreferences;category:saved.category+".ToolPreferences";property string document:""}
    Timer{id:toolPreferencesTimer;interval:500;onTriggered:if(sizeSlider.pressed)restart();else root.flushToolPreferences()}
    ListModel { id:liveSegments }
    Timer {
        id:clearPreviewTimer;interval:80
        onTriggered:if(!root.busy && !root.painting)root.clearPreview()
    }
    Timer { id:previewRepairTimer;interval:40;onTriggered:if(root.nativeRaster)root.nativeRaster.repairPreview() }
    Timer { id: paintTimer; interval: 0; onTriggered: root.requestPendingPaint() }
    Timer {
        id:penEndTimer;interval:0
        onTriggered:if(root.activeSource==="pen" && root.activeStroke && !root.activeStroke.rawInput && !penInput.active && !penDot.pressed)root.finishStroke()
    }

    function requestPendingPaint() {
        if(activeStroke!==null && activeStroke.tool!==7)return;
        if(replaying || resetCanvas || pending.some(function(job){return job.stroke.tool===7;})) {paper.requestPaint();return;}
        for(var i=0;i<pending.length;i++) {
            var job=pending[i],r=Ink.dirtyBounds(job.stroke,job.index);
            paper.markDirty(Qt.rect(r.x,r.y,r.width,r.height));
        }
    }
    function clearPreview() {
        liveSegments.clear();previewJobs=[];previewTileMap=({});
    }
    function refreshArtTiles(bounds) {
        for(var i=0;i<artTiles.count;i++) {
            var tile=artTiles.itemAt(i);
            if(tile && (!bounds || (tile.x<bounds.x+bounds.width && tile.x+tile.width>bounds.x &&
                                  tile.y<bounds.y+bounds.height && tile.y+tile.height>bounds.y)))
                tile.requestPaint();
        }
    }
    function combineBounds(a,b) {
        if(!a)return b;
        var x=Math.min(a.x,b.x),y=Math.min(a.y,b.y);
        return {x:x,y:y,width:Math.max(a.x+a.width,b.x+b.width)-x,
                height:Math.max(a.y+a.height,b.y+b.height)-y};
    }
    function previewInk(s,index) {
        if(s.tool===7 || nativeStroke)return;
        var bounds=Ink.dirtyBounds(s,index);
        previewJobs.push({stroke:s,index:index,bounds:bounds});
        var left=Math.max(0,Math.floor(bounds.x/64)),top=Math.max(0,Math.floor(bounds.y/64));
        var right=Math.min(18,Math.floor((bounds.x+bounds.width)/64));
        var bottom=Math.min(24,Math.floor((bounds.y+bounds.height)/64));
        for(var row=top;row<=bottom;row++)for(var col=left;col<=right;col++) {
            var key=row*19+col,n=previewTileMap[key];
            if(n===undefined) {
                n=liveSegments.count;previewTileMap[key]=n;
                liveSegments.append({tileX:col*64,tileY:row*64});
            }
            var tile=liveTiles.itemAt(n);
            if(tile)tile.requestPaint();
        }
    }
    function queueInk(s,index) {
        if(nativeRasterActive) {
            var b=s.points[index],a=index?s.points[index-1]:b;
            nativeRaster.segment([s.tool,s.size,s.tone,s.strength,s.renderer,s.seed,index],a,b,bitmapMode || s.tool===7);
            if(s.tool!==7 && !nativeStroke)previewInk(s,index);
            return;
        }
        painting=true;paintBounds=combineBounds(paintBounds,Ink.dirtyBounds(s,index));
        pending.push({stroke:s,index:index,queuedAt:Date.now()});previewInk(s,index);
        if(activeStroke!==null && activeStroke.tool!==7)return;
        paper.requestPaint();
    }
    function unloading() { flushToolPreferences();if(calibrationDialog && nativeRaster)nativeRaster.cancelCalibration();closing=true;nativeWrite("off");if(nativeRaster)nativeRaster.release() }
    function saveBook() {
        if(!ready || saveBlocked || busy) return false;
        var saveStarted=Date.now();
        if(nativeRasterActive){
            if(nativeRaster.saveNotebook(JSON.stringify({document:JSON.stringify(notebook),selectedTool:tool,selectedSize:brushSize,toolSizes:toolSizes,selectedStrength:strength,selectedTone:tone,useFinger:true,paperKind:paperKind,kneadedEraser:kneadedEraser}),pageSlot(pageIndex),cacheMetadata())===false){
                notice="Save failed. Your drawing is still in memory.";return false;
            }
            if(!nativeRaster.flushSaves()){notice="Save failed. Your drawing is still in memory.";return false;}
            dirty=false;newUnsavedPage=false;pageDiskMetadata=JSON.stringify(page);lastSavedDocument=JSON.stringify(notebook);notice="Saved";
            flushToolPreferences();console.log("PaperSketch manual save",Date.now()-saveStarted,"ms");return true;
        }
        saved.checkpoint=saved.document;
        saved.document=JSON.stringify(notebook);
        saved.selectedTool=tool; saved.selectedSize=brushSize;
        saved.selectedStrength=strength;saved.selectedTone=tone;saved.useFinger=fingerSmudge;
        saved.paperKind=paperKind;saved.kneadedEraser=kneadedEraser;
        dirty=false;newUnsavedPage=false;pageDiskMetadata=JSON.stringify(page);lastSavedDocument=JSON.stringify(notebook);notice="Saved";
        console.log("PaperSketch manual save",Date.now()-saveStarted,"ms");
        return true;
    }
    function redraw(entering) {
        if(entering){pageDiskMetadata=JSON.stringify(page);newUnsavedPage=false;}
        
        pending=[];paintBounds=null;clearPreview();
        if(nativeRaster && !page.strokes.length && !page.bitmap){nativeRaster.resetWhite();nativeRasterActive=true;restoreMaterialOptions(false);resetCanvas=false;replaying=false;guide.requestPaint();return;}
        if(nativeRaster && nativeRaster.loadCache(pageSlot(pageIndex),cacheMetadata())){
            nativeRasterActive=true;resetCanvas=false;replaying=false;
            var meta=nativeRaster.materialAvailable?nativeRaster.pageMetadata():"";
            if(meta && page.bitmap && meta!==cacheMetadata()){
                var slot=pageSlot(pageIndex),updated=JSON.parse(meta),pages=notebook.pages.slice(),book={};
                updated.cacheSlot=slot;pages[pageIndex]=updated;
                for(var key in notebook)book[key]=notebook[key];book.pages=pages;notebook=book;
            }
            restoreMaterialOptions(true);flattenBitmap();console.log("PaperSketch optical digest",nativeRaster.opticalDigest());guide.requestPaint();return;
        }
        if(page.bitmap){saveBlocked=true;notice="Bitmap could not be loaded. Original files retained.";replaying=false;return;}
        nativeRasterActive=false;
        restoreMaterialOptions(false);
        resetCanvas=true;replaying=true;replayStroke=0;replayPoint=0;
        paper.requestPaint();guide.requestPaint();
    }
    function syncInputTransform(){
        var win=root.Window.window;if(!nativeRaster || !win)return;
        if(typeof nativeRaster.setInputWindow==="function")nativeRaster.setInputWindow(root.fullScreen?null:win);
        var a=inputSurface.mapToItem(win.contentItem,0,0),b=inputSurface.mapToItem(win.contentItem,Ink.WIDTH,Ink.HEIGHT);
        nativeRaster.setInputTransform(a.x,a.y,(b.x-a.x)/Ink.WIDTH,(b.y-a.y)/Ink.HEIGHT);
        if(typeof nativeRaster.setInputExclusion==="function"){
            if(fullScreen && exitFullScreenButton.visible){
                var c=exitFullScreenButton.mapToItem(win.contentItem,0,0),d=exitFullScreenButton.mapToItem(win.contentItem,exitFullScreenButton.width,exitFullScreenButton.height);
                nativeRaster.setInputExclusion(c.x,c.y,d.x-c.x,d.y-c.y);
            }else nativeRaster.setInputExclusion(0,0,0,0);
        }
    }
    function beginStroke(p,source,selected,pressure,eraserHint,rawPoint) {
        var fromRaw=rawPoint!==undefined && rawPoint!==null;
        if(materialsDialog || calibrationDialog)return;
        if(source==="pen" && activeSource==="finger"){if(bitmapMode)nativeRaster.cancel();activeStroke=null;activeSource="";}
        if(!ready || busy || saveBlocked || confirmation) return;
        if(!bitmapMode && totalPoints>=Ink.MAX_POINTS) {notice="Sketchbook full. Export your pages before starting a new book.";return;}
        if(bitmapMode || (source==="pen" && nativeRaster))syncInputTransform();
        var hardwareEraser=source==="pen" && (fromRaw ? eraserHint===true : (eraserHint===true || (nativeRaster && typeof nativeRaster.eraserActive==="function" && nativeRaster.eraserActive(p.x,p.y))));
        if(hardwareEraser)selected=6;
        paintTimer.stop();clearPreviewTimer.stop();
        if(nativeRasterActive)clearPreview();
        maxPaintMs=0;maxQueueWaitMs=0;
        nativeStroke=bitmapMode || (source==="pen" && selected!==7 && nativeArmed);
        activeSource=source;
        activeStroke=Ink.stroke(selected,hardwareEraser?toolSize(6):(selected===7?Math.max(brushSize,source==="finger"?64:32):brushSize),tone,hardwareEraser?1:strength,Date.now());
        activeStroke.fastPreview=bitmapMode && !hardwareEraser && finePreviewEligible() && nativeFinePreview;
        activeStroke.hardwareEraser=hardwareEraser;activeStroke.rawInput=fromRaw;activeStroke.inputSamples=fromRaw?1:0;
        if(hardwareEraser && materialsAvailable)nativeRaster.setMaterialOptions(paperKind,false);
        if(bitmapMode)activeStroke.renderer=8;
        if(nativeRasterActive)nativeRaster.begin(source==="finger",hardwareEraser);
        var penPressure=pressure===undefined?penInput.centroid.pressure:pressure;
        if(source==="pen" && nativeRaster && !fromRaw){if(bitmapMode)penPressure=nativeRaster.pressureAt(p.x,p.y,penPressure);else penPressure=nativeRaster.penPressure(penPressure);}
        if(source==="finger" && bitmapMode)penPressure=nativeRaster.touchPressureAt(p.x,p.y,penPressure);
        var initial=fromRaw?[p.x,p.y,penPressure]:Ink.point(p.x,p.y,penPressure);
        if(bitmapMode){
            // Legacy vector notebooks use a nonzero minimum; the material nib
            // must receive real zero/light pressure without that substitution.
            if(source!=="finger" && isFinite(penPressure))initial[2]=Ink.clamp(penPressure,0,1);
            activeStroke.points=[initial,[initial[0],initial[1],initial[2]]];activeStroke.samples=1;
            activeStroke.pressureMin=initial[2];activeStroke.pressureMax=initial[2];
            if(fromRaw)nativeRaster.advancePenInput(selected,activeStroke.size,activeStroke.strength,initial[0],initial[1],initial[2],true,rawPoint[4],rawPoint[5]);
            else nativeRaster.advance(selected,activeStroke.size,activeStroke.strength,initial[0],initial[1],initial[2],true);
        }else{activeStroke.points.push(initial);queueInk(activeStroke,0);}
        notice="";
    }
    function extendStroke(p,source,pressure,rawPoint) {
        var fromRaw=rawPoint!==undefined && rawPoint!==null;
        if(activeStroke===null || activeSource!==source) return;
        if(fromRaw)activeStroke.inputSamples++;
        if(!bitmapMode && totalPoints+activeStroke.points.length>=Ink.MAX_POINTS) {finishStroke();notice="Sketchbook full";return;}
        if(source==="pen" && nativeRaster && !fromRaw)pressure=bitmapMode?nativeRaster.pressureAt(p.x,p.y,pressure===undefined?1:pressure):nativeRaster.penPressure(pressure===undefined?1:pressure);
        if(bitmapMode){
            var pressureValue=source==="finger"?nativeRaster.touchPressureAt(p.x,p.y,pressure):pressure;
            var changed=fromRaw?nativeRaster.advancePenInput(activeStroke.tool,activeStroke.size,activeStroke.strength,p.x,p.y,pressureValue,false,rawPoint[4],rawPoint[5]):nativeRaster.advance(activeStroke.tool,activeStroke.size,activeStroke.strength,p.x,p.y,pressureValue,false);
            if(changed){
                var last=activeStroke.points[1];last[0]=Math.round(Ink.clamp(p.x,0,Ink.WIDTH)*10)/10;
                last[1]=Math.round(Ink.clamp(p.y,0,Ink.HEIGHT)*10)/10;last[2]=Math.round(pressureValue*100)/100;
                activeStroke.samples++;activeStroke.pressureMin=Math.min(activeStroke.pressureMin,last[2]);activeStroke.pressureMax=Math.max(activeStroke.pressureMax,last[2]);
            }
            return;
        }
        var q=Ink.point(p.x,p.y,pressure),prev=activeStroke.points[activeStroke.points.length-1];
        var dx=q[0]-prev[0],dy=q[1]-prev[1];
        var threshold=Math.max(1,Math.min(3,activeStroke.size*0.08));
        if(dx*dx+dy*dy<threshold*threshold) return;
        activeStroke.points.push(q);
        queueInk(activeStroke,activeStroke.points.length-1);
    }
    function finishStroke() {
        if(activeStroke===null) return;
        if(nativeRasterActive){if(activeStroke.fastPreview)nativeRaster.finish(true);else nativeRaster.finish();clearPreviewTimer.restart();if(activeStroke.fastPreview)previewRepairTimer.restart();}
        if(activeStroke.hardwareEraser && materialsAvailable)nativeRaster.setMaterialOptions(paperKind,kneadedEraser);
        lastStroke=activeStroke;
        if(bitmapMode){page.bitmap=true;page.revision=(page.revision||0)+1;page.strokes=[];totalPoints=0;}
        else {page.strokes.push(activeStroke);totalPoints+=activeStroke.points.length;}
        activeStroke=null;activeSource="";nativeStroke=false;revision++;
        for(var i=0;i<pending.length;i++)pending[i].queuedAt=Date.now();
        paintTimer.restart();dirty=true;
    }
    function requestLeave(action) {
        if(replaying || painting)return;
        finishStroke();pendingLeave=action;
        if(dirty)confirmation="leave";else executeLeave();
    }
    function requestClose(){requestLeave({kind:"close"});}
    function resolveLeave(choice) {
        if(choice==="cancel"){confirmation="";pendingLeave=null;return;}
        if(choice==="save" && !saveBook())return;
        if(choice==="discard"){
            if(nativeRaster && typeof nativeRaster.restoreSavedTools==="function")nativeRaster.restoreSavedTools();
            pageIndex=0;notebook=Ink.decode(lastSavedDocument||JSON.stringify(Ink.book()));
            dirty=false;newUnsavedPage=false;
        }
        confirmation="";executeLeave();
    }
    function executeLeave(){
        var action=pendingLeave;pendingLeave=null;if(!action)return;
        if(action.kind==="close"){unloading();close();return;}
        if(action.kind==="new"){
            if(notebook.pages.length>=12){notice="12 pages per sketchbook.";return;}
            notebook.pages.push(blankPage());performPage(notebook.pages.length-1);newUnsavedPage=true;dirty=true;return;
        }
        performPage(Math.max(0,Math.min(action.index,notebook.pages.length-1)));
    }
    function performPage(index){
        notebook.index=index;pageIndex=index;revision++;lastStroke=null;dirty=false;notice="";redraw(true);
    }
    function selectPage(index){if(index!==pageIndex)requestLeave({kind:"page",index:index});}
    function newPage(){requestLeave({kind:"new"});}
    function pageSlot(index){var value=notebook.pages[index].cacheSlot;return value===undefined?index:value;}
    function cacheMetadata(){
        var data={};for(var key in page)if(key!=="cacheSlot")data[key]=page[key];
        return JSON.stringify(data);
    }
    function blankPage(){var slot=notebook.nextCacheSlot||notebook.pages.length;notebook.nextCacheSlot=slot+1;return {strokes:[],paper:"plain",cacheSlot:slot};}
    function deletePage(){
        var index=pageIndex,pages=notebook.pages.slice(),next=notebook.nextCacheSlot;
        pages.splice(index,1);
        if(!pages.length){pages=[blankPage()];next=notebook.nextCacheSlot;}
        pageIndex=0;notebook={version:1,index:Math.min(index,pages.length-1),pages:pages,nextCacheSlot:next};
        performPage(notebook.index);dirty=true;notice="Page deleted · Save to keep this change";
    }
    function confirmAction() {
        var action=confirmation;confirmation="";
        if(action==="delete"){deletePage();return;}
        if(action==="clear" && bitmapMode){nativeRaster.clearPage();page.revision++;revision++;dirty=true;return;}
        if(action==="clear") {page.strokes=[];}
        if(action==="book") {
            if(saveBlocked)saveBlocked=false;
            pageIndex=0;notebook=Ink.book();lastSavedDocument=JSON.stringify(notebook);
        }
        totalPoints=Ink.count(notebook);revision++;redraw(action==="book");dirty=true;
    }
    function pdfImporter(){
        if(exportBridge && exportBridge.importer)return exportBridge.importer;
        try{
            exportBridge=Qt.createQmlObject('import QtQml; import xofm.libs.library; QtObject { property var importer: DocumentImporter; property var lib: Library }',root,"PaperSketchPdfBridge");
            if(exportBridge.importer && typeof exportBridge.importer.importFromUrls==="function")return exportBridge.importer;
            exportBridge.destroy();exportBridge=null;
        }catch(e){exportBridge=null;}
        return null;
    }
    function exportPage() {
        if(busy)return;
        exportMessage=pendingPdfExport?"A PDF import is still pending. Check My files before exporting again.":"";
        if(!pendingPdfExport)exportName.text="Sketch-"+(pageIndex+1);
        exportDialog=true;
        if(!pendingPdfExport){exportName.forceActiveFocus();Qt.inputMethod.show();}
    }
    function closeExport(){exportDialog=false;Qt.inputMethod.hide();root.forceActiveFocus();}
    function saveExport(){
        if(pendingPdfExport)return;
        if(!nativeRasterActive){exportMessage="Export is unavailable until the bitmap renderer is ready.";return;}
        var importer=pdfImporter();
        if(!importer){exportMessage="My files is unavailable in this session. The drawing is still in Paper Sketch.";return;}
        var result=nativeRaster.exportPdf(exportName.text);
        if(!result.ok){exportMessage=result.error;return;}
        exportPath=result.path;exportedDocumentId="";
        pendingPdfExport={path:result.path,title:result.title,started:Date.now(),reported:false,candidates:[],timedOut:false};
        exportBusy=true;exportMessage="Adding PDF to My files…";Qt.inputMethod.hide();
        var url="file://"+result.path.split("/").map(encodeURIComponent).join("/");
        try{importer.importFromUrls([url],"");}
        catch(e){exportBusy=false;pendingPdfExport=null;exportMessage="Could not start import. PDF kept at "+exportPath;}
    }
    function pdfSourceMatches(source){
        if(!pendingPdfExport||!source)return false;
        var value=String(source);if(value==="file://"+pendingPdfExport.path)return true;
        try{return decodeURIComponent(value)==="file://"+pendingPdfExport.path;}catch(e){return false;}
    }
    function pdfImported(document,collection,source){
        if(!pdfSourceMatches(source))return;
        pendingPdfExport.reported=true;
        resolvePdfImport();
    }
    function pdfEntryAdded(entryId){
        if(!pendingPdfExport||!exportBridge)return;
        var id=String(entryId).replace(/^\{|\}$/g,"");
        if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return;
        var entry=exportBridge.lib.entryForId(id);
        if(!entry||entry.isTrashed||entry.visibleName!==pendingPdfExport.title)return;
        if(pendingPdfExport.candidates.indexOf(id)<0)pendingPdfExport.candidates.push(id);
        resolvePdfImport();
    }
    function resolvePdfImport(){
        var job=pendingPdfExport;
        if(!job||!job.reported||job.candidates.length!==1)return;
        var entry=exportBridge.lib.entryForId(job.candidates[0]);
        if(!entry||entry.isTrashed||entry.visibleName!==job.title)return;
        exportedDocumentId=job.candidates[0];pendingPdfExport=null;exportBusy=false;
        nativeRaster.discardPdfExport(job.path);
        notice="PDF added to My files · "+job.title+". It can sync to the reMarkable app.";
        console.log("PaperSketch PDF imported",exportedDocumentId,job.title);
        closeExport();
    }
    function pdfImportFailed(source){
        if(!pdfSourceMatches(source))return;
        pendingPdfExport=null;exportBusy=false;
        exportMessage="The PDF could not be added to My files. A copy is kept at "+exportPath;
        notice=exportMessage;
    }
    Connections{
        target:root.exportBridge?root.exportBridge.importer:null;ignoreUnknownSignals:true
        function onImported(document,collection,source){root.pdfImported(document,collection,source);}
        function onFailed(source){root.pdfImportFailed(source);}
    }
    Connections{
        target:root.exportBridge?root.exportBridge.lib:null;ignoreUnknownSignals:true
        function onEntryAdded(entryId){root.pdfEntryAdded(entryId);}
        function onEntryImported(entryId,visibleName,errorMessage){if(!errorMessage)root.pdfEntryAdded(entryId);}
    }
    Timer{
        interval:1000;repeat:true;running:root.pendingPdfExport!==null
        onTriggered:{
            var job=root.pendingPdfExport;
            if(job&&!job.timedOut&&Date.now()-job.started>30000){
                job.timedOut=true;root.exportBusy=false;
                root.exportMessage="Import has not been confirmed. Check My files before trying again. PDF kept at "+job.path;
                root.notice=root.exportMessage;
            }
        }
    }
    Component.onCompleted: {
        initNativeRaster();
        var preferences=saved,loadedNative=false;
        if(nativeRaster){
            var stored=nativeRaster.loadNotebook();
            if(stored){try{var parsed=JSON.parse(stored);notebook=Ink.decode(parsed.document);preferences=parsed;loadedNative=true;}
            catch(e){saveBlocked=true;notice="Saved bitmap could not be read. Original files retained.";}}
        }
        if(!loadedNative && saved.document) {
            try {notebook=Ink.decode(saved.document);}
            catch(e) {
                try {notebook=Ink.decode(saved.checkpoint);notice="Recovered the previous saved drawing.";}
                catch(e2) {saveBlocked=true;notice="Saved book could not be read. Original files retained.";}
            }
        }
        restoreToolPreferences(preferences);
        pageIndex=notebook.index;totalPoints=Ink.count(notebook);ready=true;redraw(true);dirty=false;lastSavedDocument=JSON.stringify(notebook);loadPersistentToolPreferences();
        console.log("PaperSketch opened",notebook.pages.length,"pages",totalPoints,"points",saveBlocked?"save-blocked":"ready");
    }

    component Action: Rectangle {
        id: action
        property string label: ""
        property string iconName: ""
        // The tablet's Qt build omits the Accessible attached object. Keep
        // semantic names available to automation without that load dependency.
        property string accessibleName: label
        property bool selected: false
        property bool available: true
        signal triggered
        width: 124;height: 64;radius: 6
        color: selected || tap.pressed ? "black" : "white"
        border.color: available ? "black" : "#aaaaaa";border.width: 2
        activeFocusOnTab: true
        Keys.onPressed: function(event) {
            if(event.key===Qt.Key_Space || event.key===Qt.Key_Return || event.key===Qt.Key_Enter) {
                if(available && !root.busy)triggered();
                event.accepted=true;
            }
        }
        Text {
            anchors.centerIn: parent
            visible:action.iconName===""
            text: action.label;font.pixelSize: 21;font.bold: true
            color: !action.available?"#999999":action.selected || tap.pressed?"white":"black"
        }
        ToolIcon {
            objectName:action.objectName+"Icon"
            anchors.centerIn:parent;width:56;height:50
            visible:action.iconName!==""
            iconName:action.iconName
            inverted:action.selected || tap.pressed
        }
        Rectangle {anchors.fill:parent;anchors.margins:4;radius:3;color:"transparent";border.width:2;border.color:action.selected?"white":"black";visible:action.activeFocus}
        HoverHandler {id:hover}
        ToolTip.visible: iconName!=="" && (hover.hovered || tap.pressed)
        ToolTip.delay: tap.pressed?650:400
        ToolTip.timeout: 2400
        ToolTip.text: label
        TapHandler { id: tap; enabled: action.available && !root.busy; onTapped: action.triggered() }
    }
    Rectangle {
        id: header;objectName:"sketchHeader"
        visible:!root.fullScreen
        anchors.top: parent.top;width: parent.width;height:root.fullScreen?0:88;color:"white"
        Row {
            anchors.left: parent.left;anchors.leftMargin: 20;anchors.verticalCenter: parent.verticalCenter;spacing:12
            Text {text:"Paper Sketch";font.pixelSize:root.width<1000?24:32;font.bold:true;width:root.width<1000?120:236;anchors.verticalCenter:parent.verticalCenter}
            Action {label:"Save";width:112;objectName:"saveButton";available:!root.saveBlocked;onTriggered:root.saveBook()}
            Action {label:"Export PDF";width:154;objectName:"exportButton";available:true;onTriggered:root.exportPage()}
            Action {label:"Full screen";width:156;objectName:"fullScreenButton";available:true;onTriggered:root.fullScreen=true}
        }
        Action {
            id:headerClose
            anchors.right:parent.right;anchors.rightMargin:20;anchors.verticalCenter:parent.verticalCenter
            label:"Close";width:100;objectName:"closeButton";onTriggered:root.requestClose()
        }
        Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:2;color:"black"}
    }
    Rectangle {
        id:toolsPanel;objectName:"sketchTools"
        anchors.top:header.bottom;width:parent.width
        visible:root.controlsVisible && !root.fullScreen
        height:visible?84:0;color:"white"
        Row {
            id:toolControls
            anchors.fill:parent;anchors.margins:toolsPanel.width<1000?8:12;spacing:toolsPanel.width<1000?8:16
            Row {
                id:toolButtons;objectName:"toolButtons";spacing:toolsPanel.width<1000?4:6
                anchors.verticalCenter:parent.verticalCenter
                Action {
                    label:"Materials";iconName:"materials";width:64;height:60;objectName:"materialsButton"
                    available:!root.saveBlocked;selected:root.materialsDialog;onTriggered:root.openMaterials()
                }
                Repeater {
                    model:Ink.tools
                    Action {
                        width:Math.min(72,Math.max(60,(toolsPanel.width-360)/Ink.tools.length));height:60
                        available:index!==8||root.bitmapMode
                        label:modelData.name+(modelData.kind==="pencil"?" pencil":"")
                        iconName:["pencil-2h","pencil-hb","pencil-2b","pencil-6b","charcoal","soft-charcoal","eraser","smudge","rapidograph"][index]
                        selected:root.tool===index
                        objectName:"tool"+index
                        onTriggered:root.selectTool(index)
                    }
                }
            }
            Rectangle {width:2;height:48;color:"black";anchors.verticalCenter:parent.verticalCenter}
            Row {
                width:toolControls.width-toolButtons.width-2-toolControls.spacing*2
                height:60;spacing:toolsPanel.width<900?0:(toolsPanel.width<1000?8:12);anchors.verticalCenter:parent.verticalCenter
                Text {
                    id:sizeLabel;objectName:"sizeLabel";visible:toolsPanel.width>=900;width:visible?(toolsPanel.width<1000?64:82):0;anchors.verticalCenter:parent.verticalCenter
                    text:"Size "+Math.round(root.brushSize);font.pixelSize:20;font.bold:true
                }
                Slider {
                    id:sizeSlider;objectName:"sizeSlider"
                    width:parent.width-sizeLabel.width-parent.spacing;height:60;from:1;to:80;stepSize:1;value:root.brushSize
                    property string accessibleName:"Tool size"
                    property string accessibleDescription:"Size of the selected pencil, charcoal, eraser or smudge tool"
                    onMoved:root.brushSize=value
                    onPressedChanged:if(root.ready){
                        if(pressed){root.nativeWrite("off");root.nativeArmed=false;}
                        else root.nativeHeartbeat();
                    }
                    DisplayMethodArea{anchors.fill:parent;displayMethod:typeof DisplayMethodArea.UFast==="number"?DisplayMethodArea.UFast:DisplayMethodArea.Fast}
                    Text{visible:toolsPanel.width<900;text:"Size "+Math.round(root.brushSize);font.pixelSize:16;anchors.top:parent.top;anchors.horizontalCenter:parent.horizontalCenter}
                    background:Rectangle {x:14;y:29;width:parent.width-28;height:3;color:"black"}
                    handle:Rectangle {x:sizeSlider.leftPadding+sizeSlider.visualPosition*(sizeSlider.availableWidth-width);y:8;width:32;height:44;radius:4;color:"black"}
                }
            }
        }
        Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:2;color:"black"}
    }
    Item {
        id:workspace
        anchors.top:toolsPanel.bottom;anchors.bottom:footer.top;width:parent.width
        Rectangle {
            id:sheet
            width:Ink.WIDTH;height:Ink.HEIGHT;color:"white"
            x:(workspace.width-width*root.drawingScale)/2
            y:(workspace.height-height*root.drawingScale)/2
            scale:root.drawingScale;transformOrigin:Item.TopLeft
            clip:true
            Item {
                id:inputSurface;objectName:"drawingCanvas";anchors.fill:parent
                function getContext(kind) {return root.nativeRasterActive?root.nativeContext():paper.getContext(kind)}
                function save(path) {return root.nativeRasterActive?root.nativeRaster.save(path):paper.save(path)}
            }
            // Painted artwork never receives pointer input. Prune this entire
            // tile subtree from Qt hit testing; drawing handlers stay on sheet.
            Item {
                objectName:"passiveArtwork";anchors.fill:parent;enabled:false
            Repeater {
                id:artTiles
                model:root.artColumns*Math.ceil(Ink.HEIGHT/root.artTileSize)
                Item {
                    id:tileCell
                    objectName:"artTile"+index
                    x:(index%root.artColumns)*root.artTileSize;y:Math.floor(index/root.artColumns)*root.artTileSize
                    width:Math.min(root.artTileSize,Ink.WIDTH-x);height:Math.min(root.artTileSize,Ink.HEIGHT-y)
                    function displayPixels(x,y,w,h){return tileNative.item?tileNative.item.pixels(x,y,w,h):[];}
                    function requestPaint(){if(!root.nativeRasterActive)tileFallback.requestPaint();}
                    function getContext(kind){
                        if(root.nativeRasterActive && tileNative.item)return {getImageData:function(x,y,w,h){return {data:(tileNative.item.opticalPixels?tileNative.item.opticalPixels(x,y,w,h):tileNative.item.pixels(x,y,w,h))};}};
                        return tileFallback.getContext(kind);
                    }
                    Canvas {
                        id:tileFallback;anchors.fill:parent;visible:!root.nativeRasterActive
                        renderTarget:Canvas.Image
                        onPaint:{
                            var source=paper.getContext("2d");if(!source)return;
                            var c=getContext("2d");c.drawImage(source.getImageData(tileCell.x,tileCell.y,width,height),0,0);
                        }
                    }
                    Loader {
                        id:tileNative;objectName:"nativeTileLoader"+index;anchors.left:parent.left;anchors.top:parent.top
                        width:Math.min(tileCell.width+1,Ink.WIDTH-tileCell.x)
                        height:Math.min(tileCell.height+1,Ink.HEIGHT-tileCell.y)
                        active:root.nativeRasterActive;source:"native-tile.qml"
                        onLoaded:{item.sourceX=tileCell.x;item.sourceY=tileCell.y;item.raster=root.nativeRaster;}
                    }
                }
            }
            }
            Item {
                width:1;height:1;clip:true;enabled:false
                Canvas {
                id:paper;objectName:"rasterCanvas"
                x:-2000;y:-2000;width:Ink.WIDTH;height:Ink.HEIGHT
                renderTarget:Canvas.Image
                onPaint:{
                    if(root.activeStroke!==null && root.activeStroke.tool!==7)return;
                    root.rasterPasses++;
                    var c=getContext("2d");
                    if(root.resetCanvas) {Ink.background(c,"plain");root.resetCanvas=false;}
                    var budget=root.replaying?256:8192, started=Date.now(), hadPending=root.pending.length>0, wasReplaying=root.replaying, changed=null;
                    var paintBudget=root.replaying?14:80;
                    if(root.replaying) {
                        while(root.replayStroke<root.page.strokes.length && budget>0 && Date.now()-started<14) {
                            var s=root.page.strokes[root.replayStroke];
                            while(root.replayPoint<s.points.length && budget>0 && Date.now()-started<14) {
                                Ink.segment(c,s,root.replayPoint++);budget--;
                            }
                            if(root.replayPoint>=s.points.length) {root.replayStroke++;root.replayPoint=0;}
                        }
                        if(root.replayStroke>=root.page.strokes.length) root.replaying=false;
                    } else {
                        while(root.pending.length && budget>0 && Date.now()-started<paintBudget) {
                            var job=root.pending.shift();
                            root.maxQueueWaitMs=Math.max(root.maxQueueWaitMs,Date.now()-job.queuedAt);
                            Ink.segment(c,job.stroke,job.index);budget--;
                            changed=root.combineBounds(changed,Ink.dirtyBounds(job.stroke,job.index));
                        }
                    }
                    if(root.exportPending && !root.replaying && !root.pending.length) {
                        root.exportPending=false;
                        var ok=save(root.exportPath);
                        root.notice=ok?"PNG saved: "+root.exportPath:"PNG export failed. Your drawing is still saved in the sketchbook.";
                        console.log("PaperSketch export",ok,root.exportPath);
                    }
                    root.painting=root.pending.length>0;
                    if(wasReplaying && !root.replaying){root.importNativeRaster(c);root.refreshArtTiles(null);}
                    else if(changed && (!root.pending.length || (root.activeStroke!==null && root.activeStroke.tool===7))) {
                        root.refreshArtTiles(root.paintBounds || changed);root.paintBounds=null;
                    }
                    if(!root.pending.length && root.activeStroke===null)clearPreviewTimer.restart();
                    root.maxPaintMs=Math.max(root.maxPaintMs,Date.now()-started);
                    if(hadPending && !root.pending.length && root.activeStroke===null)
                        console.log("PaperSketch raster",root.maxPaintMs,"ms paint",root.maxQueueWaitMs,"ms queue");
                    if(root.replaying || root.pending.length) paintTimer.restart();
                }
            }
            }
            Canvas {
                id:guide;anchors.fill:parent;enabled:false
                onPaint:{var c=getContext("2d");c.clearRect(0,0,width,height);Ink.guides(c,root.page.paper)}
            }
            Item {
                id:liveInk
                enabled:false
                objectName:"liveInk"
                anchors.fill:parent
                Repeater {
                    id:liveTiles
                    model:liveSegments
                    Canvas {
                        property int consumed:0
                        x:tileX;y:tileY
                        width:Math.min(64,Ink.WIDTH-x);height:Math.min(64,Ink.HEIGHT-y)
                        renderTarget:Canvas.Image
                        Component.onCompleted:requestPaint()
                        onPaint:{
                            var c=getContext("2d");c.save();c.translate(-x,-y);
                            for(var i=consumed;i<root.previewJobs.length;i++) {
                                var job=root.previewJobs[i],r=job.bounds;
                                if(x<r.x+r.width && x+width>r.x && y<r.y+r.height && y+height>r.y)
                                    Ink.previewSegment(c,job.stroke,job.index);
                            }
                            consumed=root.previewJobs.length;c.restore();
                        }
                    }
                }
            }
            // Consume the GUI's duplicate stylus stream above the artwork.
            // Exact samples still come from the native reader. An exclusive
            // drag avoids repeated scene-wide hit testing while the pen moves.
            Item {
                objectName:"rawPenEventSink";anchors.fill:parent;z:5
                visible:root.rawPenEnabled
                HoverHandler {
                    id:rawPenHover;acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                    Component.onCompleted:if(typeof rawPenHover.blocking==="boolean")rawPenHover.blocking=true
                }
                DragHandler {
                    objectName:"rawPenGrab";target:null;dragThreshold:0
                    acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                    acceptedButtons:Qt.LeftButton
                }
            }
            DragHandler {
                id:penInput
                objectName:"penInput"
                target:null
                acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                acceptedButtons:Qt.LeftButton
                dragThreshold:0
                enabled:!root.rawPenMode && !root.replaying && !root.saveBlocked && !root.confirmation && !root.exportDialog && !root.materialsDialog && !root.calibrationDialog
                onActiveChanged:{
                    if(active) {
                        if(root.activeSource!=="pen")root.beginStroke(centroid.pressPosition,"pen",root.tool,centroid.pressure,centroid.device && centroid.device.pointerType===PointerDevice.Eraser);
                        root.extendStroke(centroid.position,"pen",centroid.pressure);
                    } else if(root.activeSource==="pen") {
                        root.finishStroke();
                    }
                }
                onCentroidChanged:if(active) root.extendStroke(centroid.position,"pen",centroid.pressure)
            }
            TapHandler {
                id:penDot
                acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                acceptedButtons:Qt.LeftButton
                enabled:penInput.enabled
                onGrabChanged:function(transition,eventPoint) {
                    // Use this event's coordinates: handlerPoint may still be
                    // stale for tablet-synthesized mouse events on the device.
                    if(transition===PointerDevice.GrabPassive && root.activeSource!=="pen")
                        root.beginStroke(eventPoint.position,"pen",root.tool,eventPoint.pressure,eventPoint.device && eventPoint.device.pointerType===PointerDevice.Eraser);
                }
                onPressedChanged:if(!pressed)penEndTimer.restart()
                onTapped:function(eventPoint,button) {
                    if(root.activeSource==="pen")root.finishStroke();
                }
            }
            DragHandler {
                id:fingerInput;objectName:"fingerInput";target:null
                acceptedDevices:PointerDevice.TouchScreen
                minimumPointCount:1;maximumPointCount:1
                dragThreshold:10
                enabled:root.fingerSmudge && !root.penNearby && !root.penBlocked && !root.replaying && !root.saveBlocked && !root.confirmation && !root.exportDialog && !root.materialsDialog && !root.calibrationDialog
                onActiveChanged:{
                    if(active) {
                        root.beginStroke(centroid.pressPosition,"finger",7,centroid.pressure);
                        root.extendStroke(centroid.position,"finger",centroid.pressure);
                    }
                    else if(root.activeSource==="finger") root.finishStroke()
                }
                onCentroidChanged:if(active) root.extendStroke(centroid.position,"finger",centroid.pressure)
            }
        }
        Text {
            visible:root.replaying;anchors.centerIn:parent
            text:"Restoring drawing…";font.pixelSize:28;color:"black"
            Rectangle {anchors.fill:parent;anchors.margins:-16;color:"white";z:-1}
        }
    }
    Rectangle {
        id:footer;objectName:"sketchFooter"
        visible:!root.fullScreen
        anchors.bottom:parent.bottom;width:parent.width;height:root.fullScreen?0:138;color:"white"
        Rectangle {width:parent.width;height:2;color:"black"}
        Row {
            anchors.left:parent.left;anchors.leftMargin:18;y:12;spacing:12
            Action {label:"‹";width:64;available:root.pageIndex>0;onTriggered:root.selectPage(root.pageIndex-1)}
            Text {text:"Page "+(root.pageIndex+1)+" / "+root.pageCount;width:146;font.pixelSize:22;anchors.verticalCenter:parent.verticalCenter}
            Action {label:"›";width:64;available:root.pageIndex<root.pageCount-1;onTriggered:root.selectPage(root.pageIndex+1)}
            Action {label:"New page";width:144;available:true;onTriggered:root.newPage()}
            Action {
                label:root.page.paper==="plain"?"Plain":root.page.paper==="dots"?"Dots":"Grid"
                width:110;available:true
                onTriggered:{var kinds=["plain","dots","grid"];root.page.paper=kinds[(kinds.indexOf(root.page.paper)+1)%3];root.revision++;guide.requestPaint();root.dirty=true}
            }
            Action {label:"Clear page";width:150;available:true;onTriggered:root.confirmation="clear"}
            Action {label:"Delete page";objectName:"deletePageButton";width:156;available:true;onTriggered:root.confirmation="delete"}
        }
        Text {
            anchors.left:parent.left;anchors.right:parent.right;anchors.margins:20;y:91
            text:root.notice || (root.saveBlocked?"Save paused":Ink.tools[root.tool].name+" · Finger smudge"+(root.dirty?" · Unsaved changes":" · Saved"))
            elide:Text.ElideMiddle;font.pixelSize:19;color:"#444444"
        }
    }
    Rectangle{
        id:exitFullScreenButton;objectName:"exitFullScreen";visible:root.fullScreen && !root.confirmation;z:8
        anchors.top:parent.top;anchors.right:parent.right;anchors.margins:16
        width:56;height:56;radius:28;color:"white";border.color:"black";border.width:2
        Repeater{model:3;Rectangle{x:17;y:18+index*8;width:22;height:2;color:"black"}}
        TapHandler{onTapped:{root.finishStroke();root.fullScreen=false;root.controlsVisible=true;}}
    }
    DisplayMethodArea {
        anchors.fill:parent
        z:-1
        displayMethod:root.fastDisplay && typeof DisplayMethodArea.UFast==="number"?DisplayMethodArea.UFast:DisplayMethodArea.Fast
    }
    Rectangle {
        objectName:"materialsDialog";anchors.fill:parent;color:"white";visible:root.materialsDialog;z:11
        MouseArea{anchors.fill:parent}
        Column {
            width:Math.min(parent.width-80,1000);anchors.horizontalCenter:parent.horizontalCenter;y:60;spacing:24
            Row {
                width:parent.width
                Text{text:"Materials";width:parent.width-150;font.pixelSize:36;font.bold:true;anchors.verticalCenter:parent.verticalCenter}
                Action{label:"Done";width:150;objectName:"closeMaterials";onTriggered:{root.materialsDialog=false;root.nativeHeartbeat()}}
            }
            Text{width:parent.width;wrapMode:Text.Wrap;text:"Choose the paper and prepare your tools.";font.pixelSize:23}
            Text{width:parent.width;wrapMode:Text.Wrap;text:"Material controls are unavailable in this session.";font.pixelSize:23;visible:!root.materialsAvailable}
            Rectangle{width:parent.width;height:2;color:"black"}
            Text{text:"Paper texture";font.pixelSize:27;font.bold:true}
            Row {
                width:parent.width;spacing:12
                Repeater {
                    model:["Plain","Smooth","Rough"]
                    Action{label:modelData;width:(parent.width-24)/3;objectName:"paperTexture"+index;selected:root.paperKind===index;available:root.materialsAvailable;onTriggered:root.paperKind=index}
                }
            }
            Text{width:parent.width;wrapMode:Text.Wrap;text:"The grain catches pigment. Firm strokes gradually smooth the surface.";font.pixelSize:22}
            Rectangle{width:parent.width;height:2;color:"black"}
            Text{text:"Pencil and charcoal";font.pixelSize:27;font.bold:true}
            Row {
                spacing:20
                Action{label:"Sharpen tip";width:230;objectName:"sharpenButton";available:root.materialsAvailable && root.tool<6;onTriggered:root.sharpenTool()}
                Text{width:parent.parent.width-250;wrapMode:Text.Wrap;anchors.verticalCenter:parent.verticalCenter;text:root.tool<6?Ink.tools[root.tool].name+(root.materialsAvailable && root.calibrationRevision>=0 && typeof root.nativeRaster.toolWear==="function"?" · "+Math.round(root.nativeRaster.toolWear(root.tool)*100)+"% worn":" selected"):"Select a pencil or charcoal";font.pixelSize:22}
            }
            Text{width:parent.width;wrapMode:Text.Wrap;text:"The tip wears as you draw. Tilt the pen to shade with its side.";font.pixelSize:22}
            Rectangle{width:parent.width;height:2;color:"black"}
            Text{text:"Finger and eraser";font.pixelSize:27;font.bold:true}
            Row {
                spacing:20
                Action{label:"Clean finger";width:230;objectName:"cleanFingerButton";available:root.materialsAvailable;onTriggered:root.cleanFinger()}
                Text{width:parent.parent.width-250;wrapMode:Text.Wrap;anchors.verticalCenter:parent.verticalCenter;text:"A dirty finger carries pigment to the next stroke.";font.pixelSize:22}
            }
            Row {
                spacing:16
                Action{label:"Hard eraser";width:230;objectName:"hardEraserButton";selected:!root.kneadedEraser;available:root.materialsAvailable;onTriggered:{root.kneadedEraser=false;root.selectTool(6)}}
                Action{label:"Kneaded eraser";width:250;objectName:"kneadedEraserButton";selected:root.kneadedEraser;available:root.materialsAvailable;onTriggered:{root.kneadedEraser=true;root.selectTool(6)}}
            }
            Text{width:parent.width;wrapMode:Text.Wrap;text:root.kneadedEraser?"Press to lift pigment gently. Press harder or move to lift more. Lift and dab again.":"Rub to remove pigment and bring back highlights.";font.pixelSize:22}
            Rectangle{width:parent.width;height:2;color:"black"}
            Text{text:"Pen pressure";font.pixelSize:27;font.bold:true}
            Text{objectName:"calibrationSummary";width:parent.width;wrapMode:Text.Wrap;text:root.calibrationStatus;font.pixelSize:22}
            Row {
                spacing:16
                Action{label:"Calibrate pressure";width:270;objectName:"calibratePressureButton";available:root.materialsAvailable;onTriggered:root.startPressureCalibration()}
                Action{label:"Reset pressure";width:230;objectName:"resetPressureButton";available:root.materialsAvailable;onTriggered:root.resetPressureCalibration()}
            }
            Text{width:parent.width;wrapMode:Text.Wrap;text:"Three short steps match light, normal and firm strokes to your hand.";font.pixelSize:22}
        }
    }
    Rectangle {
        objectName:"pressureCalibrationDialog";anchors.fill:parent;color:"white";visible:root.calibrationDialog;z:13
        MouseArea{anchors.fill:parent}
        Column {
            width:Math.min(parent.width-80,1000);anchors.horizontalCenter:parent.horizontalCenter;y:60;spacing:26
            Text{text:"Calibrate pen pressure";font.pixelSize:36;font.bold:true}
            Text{objectName:"calibrationPrompt";width:parent.width;wrapMode:Text.Wrap;font.pixelSize:28;font.bold:true;text:["1 of 3 · Draw several very light lines","2 of 3 · Draw several lines at your normal pressure","3 of 3 · Draw several comfortably firm lines"][Math.max(0,Math.min(2,root.calibrationStage))]}
            Text{width:parent.width;wrapMode:Text.Wrap;font.pixelSize:23;text:"Use your pen in the box. These practice marks stay separate from your drawing. You can cancel without changing your pressure response."}
            Canvas {
                id:calibrationPad;objectName:"calibrationPad";width:parent.width;height:Math.max(180,Math.min(540,root.height-650))
                property var marks:[]
                property int painted:0
                function clear(){marks=[];painted=0;requestPaint()}
                function addPoint(x,y,p,first){
                    if(marks.length>=2048){marks=marks.slice(-1023);marks[0].first=true;painted=0;}
                    marks.push({x:x,y:y,p:p,first:first});requestPaint();
                }
                onPaint:{
                    var c=getContext("2d");
                    if(painted===0){c.reset();c.fillStyle="white";c.fillRect(0,0,width,height);c.strokeStyle="black";c.lineWidth=2;c.strokeRect(1,1,width-2,height-2);}
                    c.strokeStyle="black";c.fillStyle="black";c.lineCap="round";
                    for(var i=painted;i<marks.length;i++){
                        var p=marks[i];c.lineWidth=1+3*Math.max(0,Math.min(1,p.p));c.beginPath();
                        if(p.first || i===0){c.arc(p.x,p.y,c.lineWidth/2,0,Math.PI*2);c.fill();}
                        else{c.moveTo(marks[i-1].x,marks[i-1].y);c.lineTo(p.x,p.y);c.stroke();}
                    }
                    painted=marks.length;
                }
                DragHandler {
                    id:calibrationPen;objectName:"calibrationPen";target:null
                    acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                    acceptedButtons:Qt.LeftButton;dragThreshold:0;enabled:root.calibrationDialog
                    onActiveChanged:if(active){root.sampleCalibration(centroid.pressPosition,centroid.pressure,true);root.sampleCalibration(centroid.position,centroid.pressure,false)}else root.finishCalibrationStroke()
                    onCentroidChanged:if(active)root.sampleCalibration(centroid.position,centroid.pressure,false)
                }
                TapHandler {
                    acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                    acceptedButtons:Qt.LeftButton;enabled:root.calibrationDialog
                    onTapped:function(eventPoint,button){root.sampleCalibration(eventPoint.position,eventPoint.pressure,true);root.finishCalibrationStroke()}
                }
            }
            Text{objectName:"calibrationLiveStatus";width:parent.width;wrapMode:Text.Wrap;font.pixelSize:22;text:root.calibrationSamples?"Pen samples received: "+root.calibrationSamples:"Draw a few lines before continuing."}
            Text{objectName:"calibrationError";width:parent.width;wrapMode:Text.Wrap;font.pixelSize:23;visible:root.calibrationMessage!=="";text:root.calibrationMessage}
            Action{label:"Start again";width:220;objectName:"restartCalibrationButton";visible:root.calibrationMessage!=="";onTriggered:{root.nativeRaster.cancelCalibration();root.startPressureCalibration()}}
            Row {
                spacing:24
                Action{label:"Cancel";width:220;objectName:"cancelCalibrationButton";onTriggered:root.cancelPressureCalibration()}
                Action{label:root.calibrationStage<2?"Next":"Save response";width:250;objectName:"nextCalibrationButton";available:root.calibrationSamples>=16;onTriggered:root.nextPressureCalibration()}
            }
        }
    }
    Rectangle {
        anchors.fill:parent;color:"#eeeeee";visible:root.confirmation!=="";z:10
        MouseArea{anchors.fill:parent}
        Column {
            anchors.centerIn:parent;spacing:30
            Text {
                width:840;wrapMode:Text.WordWrap;font.pixelSize:32;font.bold:true
                text:root.confirmation==="leave"?"Save changes before continuing?":root.confirmation==="delete"?"Delete this page?":"Clear this page permanently?"
            }
            Text {
                width:840;wrapMode:Text.WordWrap;font.pixelSize:23
                text:root.confirmation==="leave"?"Your drawing is in memory. Choose Save, Discard or Cancel.":"The current page and its unsaved marks will be removed. Other pages stay in your sketchbook. Choose Save afterward to keep this change."
            }
            Row {
                spacing:20
                Action {label:"Cancel";width:220;objectName:"cancelLeave";onTriggered:root.confirmation==="leave"?root.resolveLeave("cancel"):root.confirmation=""}
                Action {label:"Discard";width:220;objectName:"discardLeave";visible:root.confirmation==="leave";onTriggered:root.resolveLeave("discard")}
                Action {label:"Save";width:220;objectName:"saveLeave";visible:root.confirmation==="leave";onTriggered:root.resolveLeave("save")}
                Action {label:root.confirmation==="delete"?"Delete page":"Clear page";objectName:"confirmPageAction";visible:root.confirmation!=="leave";width:240;onTriggered:root.confirmAction()}
            }
        }
    }
    Rectangle {
        anchors.fill:parent;color:"white";visible:root.exportDialog;z:12
        MouseArea{anchors.fill:parent}
        Column {
            width:Math.min(parent.width-80,1000);anchors.horizontalCenter:parent.horizontalCenter;y:100;spacing:26
            Text{text:"Export PDF";font.pixelSize:36;font.bold:true}
            Text{width:parent.width;wrapMode:Text.Wrap;text:"Add a PDF copy of this page to My files. It can sync to the reMarkable app for sharing.";font.pixelSize:23}
            TextField {
                id:exportName;objectName:"exportName";width:parent.width;height:86;font.pixelSize:29;color:"black"
                placeholderText:"Document name";enabled:!root.pendingPdfExport;inputMethodHints:Qt.ImhNoPredictiveText|Qt.ImhNoAutoUppercase
                background:Rectangle{color:"white";border.color:"black";border.width:2;radius:5}
                onTextEdited:root.exportMessage=""
                onAccepted:root.saveExport()
                onActiveFocusChanged:if(activeFocus&&root.exportDialog)Qt.inputMethod.show()
            }
            Text{width:parent.width;wrapMode:Text.Wrap;text:root.exportMessage;font.pixelSize:24;visible:text!==""}
            Row{spacing:24
                Action{label:"Cancel";objectName:"cancelExport";width:220;onTriggered:root.closeExport()}
                Action{label:root.exportBusy?"Adding PDF…":"Add PDF";available:!root.pendingPdfExport;objectName:"saveExport";width:240;onTriggered:root.saveExport()}
            }
        }
    }

}
