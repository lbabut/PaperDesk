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
    property real brushSize: Ink.tools[tool].size
    property real strength: 1.0
    property int tone: 0
    property bool fingerSmudge: true
    property bool fullScreen:false
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
    property bool penBlocked: penInput.active || penDot.pressed
    readonly property var page: notebook.pages[pageIndex]
    readonly property bool busy: replaying || activeStroke!==null
    readonly property real drawingScale: Math.min((workspace.width-24)/Ink.WIDTH,(workspace.height-24)/Ink.HEIGHT)

    // Native preview is optional and gated by the extension's fresh acknowledgement.
    property bool nativeReady: false
    property bool nativeArmed: false
    property bool nativeStroke: false
    property var nativeRequest: null
    property string nativeState: ""
    property bool closing: false
    onToolChanged:if(ready && !bitmapMode)nativeHeartbeat()
    onBrushSizeChanged:if(ready && !bitmapMode)nativeHeartbeat()
    onControlsVisibleChanged:if(ready && !bitmapMode) {nativeArmed=false;if(nativeReady)nativeWrite("off");}
    Timer { interval:400;running:root.visible && !root.closing && !root.bitmapMode;repeat:true;triggeredOnStart:true;onTriggered:root.nativeHeartbeat() }
    function nativeWrite(value) {
        try {
            var x=new XMLHttpRequest();nativeRequest=x;
            x.onreadystatechange=function(){if(x.readyState===XMLHttpRequest.DONE && nativeRequest===x)nativeRequest=null;};
            x.open("PUT","file:///tmp/papersketch-ink");x.send(value);
        }
        catch(e) {nativeArmed=false;}
    }
    function nativeHeartbeat() {
        if(nativeRaster && nativeRaster.materialAvailable){nativeReady=false;nativeArmed=false;return;}
        try {
            var x=new XMLHttpRequest();x.open("GET","file:///tmp/papersketch-ink-status",false);x.send();
            var status=JSON.parse(x.responseText);
            nativeReady=status.ready===true && Math.abs(Date.now()-status.time_ms)<1500;
            nativeArmed=nativeReady && status.armed===true;
        } catch(e) {nativeReady=false;nativeArmed=false;}
        if(!nativeReady)return;
        var win=root.Window.window;
        var state=(win?win.width+"x"+win.height:"no window")+" ready="+ready+" replay="+replaying+" armed="+nativeArmed;
        if(nativeState!==state) {nativeState=state;console.log("PaperSketch native",state);}

        if(bitmapMode || !win || win.width!==1404 || win.height!==1872 || !visible || closing || !ready || replaying || (painting && activeStroke===null) || saveBlocked || confirmation || tool===7 || activeSource==="finger") {
            nativeWrite("off");nativeArmed=false;return;
        }
        var origin=inputSurface.mapToItem(win.contentItem,0,0);
        var corner=inputSurface.mapToItem(win.contentItem,inputSurface.width,inputSurface.height);
        var x0=Math.ceil(origin.x),y0=Math.ceil(origin.y);
        var w=Math.floor(corner.x)-x0,h=Math.floor(corner.y)-y0;
        if(x0<0 || y0<0 || w<=0 || h<=0 || x0+w>1404 || y0+h>1872) {nativeWrite("off");nativeArmed=false;return;}
        var size=Math.max(1,brushSize*drawingScale);
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
    function flattenBitmap() {
        if(nativeRaster && nativeRaster.materialAvailable && !page.bitmap){
            page.bitmap=true;page.revision=0;page.strokes=[];totalPoints=0;revision++;
            console.log("PaperSketch bitmap migration complete");
        }
    }
    function importNativeRaster(c) {
        if(!nativeRaster)return;
        nativeRasterActive=nativeRaster.importPixels(c.getImageData(0,0,Ink.WIDTH,Ink.HEIGHT).data);
        if(nativeRasterActive){flattenBitmap();console.log("PaperSketch optical digest",nativeRaster.opticalDigest());}
    }
    function nativeContext() {
        return {getImageData:function(x,y,w,h){return {data:nativeRaster.pixels(x,y,w,h)};}};
    }

    Connections {target:root.nativeRaster;ignoreUnknownSignals:true;function onSaveFailed(){root.notice="Save failed. Your drawing is still in memory.";console.log("PaperSketch native save FAILED");}}
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
    }
    ListModel { id:liveSegments }
    Timer {
        id:clearPreviewTimer;interval:80
        onTriggered:if(!root.busy && !root.painting)root.clearPreview()
    }
    Timer { id: paintTimer; interval: 0; onTriggered: root.requestPendingPaint() }

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
    function unloading() { closing=true;if(nativeReady)nativeWrite("off");if(nativeRaster)nativeRaster.release() }
    function saveBook() {
        if(!ready || saveBlocked || busy) return false;
        var saveStarted=Date.now();
        if(nativeRasterActive){
            nativeRaster.saveNotebook(JSON.stringify({document:JSON.stringify(notebook),selectedTool:tool,selectedSize:brushSize,selectedStrength:strength,selectedTone:tone,useFinger:fingerSmudge}),pageIndex,JSON.stringify(page));
            if(!nativeRaster.flushSaves()){notice="Save failed. Your drawing is still in memory.";return false;}
            dirty=false;newUnsavedPage=false;pageDiskMetadata=JSON.stringify(page);notice="Saved";
            console.log("PaperSketch manual save",Date.now()-saveStarted,"ms");return true;
        }
        saved.checkpoint=saved.document;
        saved.document=JSON.stringify(notebook);
        saved.selectedTool=tool; saved.selectedSize=brushSize;
        saved.selectedStrength=strength;saved.selectedTone=tone;saved.useFinger=fingerSmudge;
        dirty=false;newUnsavedPage=false;pageDiskMetadata=JSON.stringify(page);notice="Saved";
        console.log("PaperSketch manual save",Date.now()-saveStarted,"ms");
        return true;
    }
    function redraw(entering) {
        if(entering){pageDiskMetadata=JSON.stringify(page);newUnsavedPage=false;}
        
        pending=[];paintBounds=null;clearPreview();
        if(nativeRaster && !page.strokes.length && !page.bitmap){nativeRaster.resetWhite();nativeRasterActive=true;resetCanvas=false;replaying=false;guide.requestPaint();return;}
        if(nativeRaster && nativeRaster.loadCache(pageIndex,JSON.stringify(page))){
            nativeRasterActive=true;resetCanvas=false;replaying=false;
            var meta=nativeRaster.materialAvailable?nativeRaster.pageMetadata():"";
            if(meta && page.bitmap)notebook.pages[pageIndex]=JSON.parse(meta);
            flattenBitmap();console.log("PaperSketch optical digest",nativeRaster.opticalDigest());guide.requestPaint();return;
        }
        if(page.bitmap){saveBlocked=true;notice="Bitmap could not be loaded. Original files retained.";replaying=false;return;}
        nativeRasterActive=false;
        resetCanvas=true;replaying=true;replayStroke=0;replayPoint=0;
        paper.requestPaint();guide.requestPaint();
    }
    function syncInputTransform(){
        var win=root.Window.window;if(!nativeRaster || !win)return;
        var a=inputSurface.mapToItem(win.contentItem,0,0),b=inputSurface.mapToItem(win.contentItem,Ink.WIDTH,Ink.HEIGHT);
        nativeRaster.setInputTransform(a.x,a.y,(b.x-a.x)/Ink.WIDTH,(b.y-a.y)/Ink.HEIGHT);
    }
    function beginStroke(p,source,selected,pressure) {
        if(source==="pen" && activeSource==="finger"){if(bitmapMode)nativeRaster.cancel();activeStroke=null;activeSource="";}
        if(!ready || busy || saveBlocked || confirmation) return;
        if(!bitmapMode && totalPoints>=Ink.MAX_POINTS) {notice="Sketchbook full. Export your pages before starting a new book.";return;}
        paintTimer.stop();clearPreviewTimer.stop();
        if(nativeRasterActive)clearPreview();
        maxPaintMs=0;maxQueueWaitMs=0;
        nativeStroke=bitmapMode || (source==="pen" && selected!==7 && nativeArmed);
        activeSource=source;
        activeStroke=Ink.stroke(selected,selected===7?Math.max(brushSize,source==="finger"?64:32):brushSize,tone,strength,Date.now());
        if(bitmapMode)activeStroke.renderer=8;
        if(nativeRasterActive)nativeRaster.begin(source==="finger");
        var penPressure=pressure===undefined?penInput.centroid.pressure:pressure;
        if(source==="pen" && nativeRaster){if(bitmapMode){syncInputTransform();penPressure=nativeRaster.pressureAt(p.x,p.y,penPressure);}else penPressure=nativeRaster.penPressure(penPressure);}
        var initial=Ink.point(p.x,p.y,source==="finger"?0.7:penPressure);
        if(bitmapMode){
            activeStroke.points=[initial,[initial[0],initial[1],initial[2]]];activeStroke.samples=1;
            activeStroke.pressureMin=initial[2];activeStroke.pressureMax=initial[2];
            nativeRaster.advance(selected,activeStroke.size,strength,initial[0],initial[1],initial[2],true);
        }else{activeStroke.points.push(initial);queueInk(activeStroke,0);}
        notice="";
    }
    function extendStroke(p,source,pressure) {
        if(activeStroke===null || activeSource!==source) return;
        if(!bitmapMode && totalPoints+activeStroke.points.length>=Ink.MAX_POINTS) {finishStroke();notice="Sketchbook full";return;}
        if(source==="pen" && nativeRaster)pressure=bitmapMode?nativeRaster.pressureAt(p.x,p.y,pressure===undefined?1:pressure):nativeRaster.penPressure(pressure===undefined?1:pressure);
        if(bitmapMode){
            var pressureValue=source==="finger"?.7:pressure;
            if(nativeRaster.advance(activeStroke.tool,activeStroke.size,strength,p.x,p.y,pressureValue,false)){
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
        if(nativeRasterActive){nativeRaster.finish();clearPreviewTimer.restart();}
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
            if(newUnsavedPage && notebook.pages.length>1)notebook.pages.splice(pageIndex,1);
            else if(pageDiskMetadata)notebook.pages[pageIndex]=JSON.parse(pageDiskMetadata);
            dirty=false;newUnsavedPage=false;
        }
        confirmation="";executeLeave();
    }
    function executeLeave(){
        var action=pendingLeave;pendingLeave=null;if(!action)return;
        if(action.kind==="close"){unloading();close();return;}
        if(action.kind==="new"){
            if(notebook.pages.length>=12){notice="12 pages per sketchbook.";return;}
            notebook.pages.push({strokes:[],paper:"plain"});performPage(notebook.pages.length-1);newUnsavedPage=true;dirty=true;return;
        }
        performPage(Math.max(0,Math.min(action.index,notebook.pages.length-1)));
    }
    function performPage(index){
        notebook.index=index;pageIndex=index;revision++;lastStroke=null;dirty=false;notice="";redraw(true);
    }
    function selectPage(index){if(index!==pageIndex)requestLeave({kind:"page",index:index});}
    function newPage(){requestLeave({kind:"new"});}
    function confirmAction() {
        var action=confirmation;confirmation="";
        if(action==="clear" && bitmapMode){nativeRaster.clearPage();page.revision++;revision++;dirty=true;return;}
        if(action==="clear") {page.strokes=[];}
        if(action==="book") {
            if(saveBlocked)saveBlocked=false;
            notebook=Ink.book();pageIndex=0;
        }
        totalPoints=Ink.count(notebook);revision++;redraw(action==="book");dirty=true;
    }
    function exportPage() {
        if(busy) return;
        exportPath="/home/root/.local/share/paperdesk/sketch/PaperSketch-"+Date.now()+"-page-"+(pageIndex+1)+".png";
        if(nativeRasterActive){var ok=nativeRaster.save(exportPath);notice=ok?"PNG saved: "+exportPath:"PNG export failed";return;}
        exportPending=true;paper.requestPaint();
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
        tool=Ink.clamp(preferences.selectedTool,0,7);
        brushSize=Ink.clamp(preferences.selectedSize,1,80);
        strength=1;
        tone=0;fingerSmudge=preferences.useFinger;
        pageIndex=notebook.index;totalPoints=Ink.count(notebook);ready=true;redraw(true);dirty=false;
        console.log("PaperSketch opened",notebook.pages.length,"pages",totalPoints,"points",saveBlocked?"save-blocked":"ready");
    }

    component Action: Rectangle {
        id: action
        property string label: ""
        property bool selected: false
        property bool available: true
        signal triggered
        width: 124;height: 64;radius: 6
        color: selected || tap.pressed ? "black" : "white"
        border.color: available ? "black" : "#aaaaaa";border.width: 2
        Text {
            anchors.centerIn: parent
            text: action.label;font.pixelSize: 21;font.bold: true
            color: !action.available?"#999999":action.selected || tap.pressed?"white":"black"
        }
        TapHandler { id: tap; enabled: action.available && !root.busy; onTapped: action.triggered() }
    }
    Rectangle {
        id: header;objectName:"sketchHeader"
        visible:!root.fullScreen
        anchors.top: parent.top;width: parent.width;height:root.fullScreen?0:88;color:"white"
        Row {
            anchors.left: parent.left;anchors.leftMargin: 20;anchors.verticalCenter: parent.verticalCenter;spacing:12
            Text {text:"Paper Sketch";font.pixelSize:32;font.bold:true;width:236;anchors.verticalCenter:parent.verticalCenter}
            Action {label:"Save";width:112;objectName:"saveButton";available:!root.saveBlocked;onTriggered:root.saveBook()}
            Action {label:"Export PNG";width:154;objectName:"exportButton";available:true;onTriggered:root.exportPage()}
            Action {label:"Full screen";width:156;objectName:"fullScreenButton";available:true;onTriggered:root.fullScreen=true}
        }
        Action {
            anchors.right:parent.right;anchors.rightMargin:20;anchors.verticalCenter:parent.verticalCenter
            label:"Close";width:100;objectName:"closeButton";onTriggered:root.requestClose()
        }
        Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:2;color:"black"}
    }
    Column {
        id: toolsPanel
        anchors.top:header.bottom;width:parent.width
        visible:root.controlsVisible && !root.fullScreen
        height:visible?182:0
        Rectangle {
            width:parent.width;height:84;color:"white"
            Row {
                anchors.fill:parent;anchors.margins:12;spacing:8
                Repeater {
                    model:Ink.tools
                    Action {
                        width:(toolsPanel.width-80)/8;height:60
                        label:modelData.name;selected:root.tool===index
                        objectName:"tool"+index
                        onTriggered:{root.tool=index;root.brushSize=modelData.size}
                    }
                }
            }
        }
        Rectangle {
            width:parent.width;height:98;color:"white"
            Row {
                anchors.left:parent.left;anchors.leftMargin:18;anchors.verticalCenter:parent.verticalCenter;spacing:18
                Column {
                    Text {text:"Size  "+Math.round(root.brushSize);font.pixelSize:19;font.bold:true}
                    Slider {
                        objectName:"sizeSlider";width:400;height:52;from:1;to:80;stepSize:1;value:root.brushSize
                        onMoved:root.brushSize=value
                        DisplayMethodArea{anchors.fill:parent;displayMethod:typeof DisplayMethodArea.UFast==="number"?DisplayMethodArea.UFast:DisplayMethodArea.Fast}
                        background:Rectangle {x:10;y:24;width:parent.width-20;height:3;color:"#888888"}
                        handle:Rectangle {x:parent.leftPadding+parent.visualPosition*(parent.availableWidth-width);y:10;width:28;height:32;radius:4;color:"black"}
                    }
                }
                Action {
                    label:root.fingerSmudge?"Finger: smudge":"Finger: off";width:216;height:64
                    selected:root.fingerSmudge
                    onTriggered:{root.fingerSmudge=!root.fingerSmudge;}
                }
            }
        }
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
                        id:tileNative;anchors.fill:parent;active:root.nativeRasterActive;source:"native-tile.qml"
                        onLoaded:{item.sourceX=tileCell.x;item.sourceY=tileCell.y;item.raster=root.nativeRaster;}
                    }
                }
            }
            Item {
                width:1;height:1;clip:true
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
                id:guide;anchors.fill:parent
                onPaint:{var c=getContext("2d");c.clearRect(0,0,width,height);Ink.guides(c,root.page.paper)}
            }
            Item {
                id:liveInk
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
            DragHandler {
                id:penInput
                objectName:"penInput"
                target:null
                acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                acceptedButtons:Qt.LeftButton
                dragThreshold:0
                enabled:!root.replaying && !root.saveBlocked && !root.confirmation
                onActiveChanged:{
                    if(active) {
                        
                        root.beginStroke(centroid.pressPosition,"pen",root.tool,centroid.pressure);
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
                enabled:!root.replaying && !root.saveBlocked && !root.confirmation
                onTapped:function(eventPoint,button) {
                    root.beginStroke(eventPoint.position,"pen",root.tool,eventPoint.pressure);
                    root.finishStroke();
                }
            }
            DragHandler {
                id:fingerInput;objectName:"fingerInput";target:null
                acceptedDevices:PointerDevice.TouchScreen
                minimumPointCount:1;maximumPointCount:1
                dragThreshold:10
                enabled:root.fingerSmudge && !root.penNearby && !root.penBlocked && !root.replaying && !root.saveBlocked && !root.confirmation
                onActiveChanged:{
                    if(active) {
                        root.beginStroke(centroid.pressPosition,"finger",7);
                        root.extendStroke(centroid.position,"finger",0.7);
                    }
                    else if(root.activeSource==="finger") root.finishStroke()
                }
                onCentroidChanged:if(active) root.extendStroke(centroid.position,"finger",0.7)
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
                width:110;available:!root.busy
                onTriggered:{var kinds=["plain","dots","grid"];root.page.paper=kinds[(kinds.indexOf(root.page.paper)+1)%3];root.revision++;guide.requestPaint();root.dirty=true}
            }
            Action {label:"Clear page";width:150;available:true;onTriggered:root.confirmation="clear"}
            Action {label:"New book";width:146;available:true;onTriggered:root.confirmation="book"}
        }
        Text {
            anchors.left:parent.left;anchors.right:parent.right;anchors.margins:20;y:91
            text:root.notice || (root.saveBlocked?"Save paused":Ink.tools[root.tool].name+" · Pen · Finger smudge "+(root.fingerSmudge?"on":"off")+(root.dirty?" · Unsaved changes":" · Saved"))
            elide:Text.ElideMiddle;font.pixelSize:19;color:"#444444"
        }
    }
    Rectangle{
        objectName:"exitFullScreen";visible:root.fullScreen && !root.confirmation;z:8
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
        anchors.fill:parent;color:"#eeeeee";visible:root.confirmation!=="";z:10
        MouseArea{anchors.fill:parent}
        Column {
            anchors.centerIn:parent;spacing:30
            Text {
                width:840;wrapMode:Text.WordWrap;font.pixelSize:32;font.bold:true
                text:root.confirmation==="leave"?"Save changes before continuing?":root.confirmation==="clear"?"Clear this page permanently?":"Start a new sketchbook? Export any drawings you want to keep first."
            }
            Text {
                width:840;wrapMode:Text.WordWrap;font.pixelSize:23
                text:root.confirmation==="leave"?"Your drawing is in memory. Choose Save, Discard or Cancel.":root.confirmation==="book"?"This replaces the current sketchbook. PNG exports remain on the tablet.":"Other pages will stay in your sketchbook."
            }
            Row {
                spacing:20
                Action {label:"Cancel";width:220;objectName:"cancelLeave";onTriggered:root.confirmation==="leave"?root.resolveLeave("cancel"):root.confirmation=""}
                Action {label:"Discard";width:220;objectName:"discardLeave";visible:root.confirmation==="leave";onTriggered:root.resolveLeave("discard")}
                Action {label:"Save";width:220;objectName:"saveLeave";visible:root.confirmation==="leave";onTriggered:root.resolveLeave("save")}
                Action {label:root.confirmation==="clear"?"Clear page":"New book";visible:root.confirmation!=="leave";width:240;onTriggered:root.confirmAction()}
            }
        }
    }
}
