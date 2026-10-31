import QtQuick 2.15
import QtQuick.Controls 2.15
import Qt.labs.settings 1.1
import "../engine.js" as Ink

Rectangle {
    id: root
    color: "#e3e3e3"
    anchors.fill: parent
    signal close
    property var notebook: Ink.book()
    property int tool: 1
    property real brushSize: Ink.tools[tool].size
    property real strength: 0.8
    property int tone: 0
    property bool fingerSmudge: true
    property bool controlsVisible: true
    property bool ready: false
    property bool saveBlocked: false
    property string notice: ""
    property string confirmation: ""
    property var activeStroke: null
    property string activeSource: ""
    property var redoStrokes: []
    property var clearedStrokes: null
    property int revision: 0
    property int pageIndex: 0
    readonly property int pageCount: revision>=0 ? notebook.pages.length : 0
    property int totalPoints: 0
    property bool replaying: false
    property int replayStroke: 0
    property int replayPoint: 0
    property var pending: []
    property bool resetCanvas: true
    property bool exportPending: false
    property string exportPath: ""
    property bool penBlocked: penInput.active || penDot.pressed || penHover.hovered || palmTimer.running
    readonly property var page: notebook.pages[pageIndex]
    readonly property bool busy: replaying || activeStroke!==null
    readonly property real drawingScale: Math.min((workspace.width-24)/Ink.WIDTH,(workspace.height-24)/Ink.HEIGHT)

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
    Timer { id: palmTimer; interval: 550 }
    Timer { id: autosave; interval: 800; onTriggered: root.saveBook() }
    Timer { id: paintTimer; interval: 16; onTriggered: paper.requestPaint() }

    function unloading() { finishStroke(); saveBook() }
    function saveBook() {
        if(!ready || saveBlocked) return false;
        saved.checkpoint=saved.document;
        saved.document=JSON.stringify(notebook);
        saved.selectedTool=tool; saved.selectedSize=brushSize;
        saved.selectedStrength=strength;saved.selectedTone=tone;saved.useFinger=fingerSmudge;
        return true;
    }
    function redraw() {
        pending=[];resetCanvas=true;replaying=true;replayStroke=0;replayPoint=0;
        paper.requestPaint();guide.requestPaint();
    }
    function beginStroke(p,source,selected,pressure) {
        if(!ready || busy || saveBlocked || confirmation) return;
        if(totalPoints>=Ink.MAX_POINTS) {notice="Sketchbook full. Export your pages before starting a new book.";return;}
        activeSource=source;
        activeStroke=Ink.stroke(selected,selected===7?Math.max(brushSize,32):brushSize,tone,strength,Date.now());
        activeStroke.points.push(Ink.point(p.x,p.y,source==="finger"?0.7:(pressure===undefined?penInput.centroid.pressure:pressure)));
        pending.push({stroke:activeStroke,index:0});
        paper.requestPaint();notice="";
    }
    function extendStroke(p,source,pressure) {
        if(activeStroke===null || activeSource!==source) return;
        if(totalPoints+activeStroke.points.length>=Ink.MAX_POINTS) {finishStroke();notice="Sketchbook full";return;}
        var q=Ink.point(p.x,p.y,pressure),prev=activeStroke.points[activeStroke.points.length-1];
        var dx=q[0]-prev[0],dy=q[1]-prev[1];
        if(dx*dx+dy*dy<1) return;
        activeStroke.points.push(q);
        pending.push({stroke:activeStroke,index:activeStroke.points.length-1});
        paper.requestPaint();
    }
    function finishStroke() {
        if(activeStroke===null) return;
        page.strokes.push(activeStroke);totalPoints+=activeStroke.points.length;
        activeStroke=null;activeSource="";redoStrokes=[];clearedStrokes=null;revision++;
        autosave.restart();
    }
    function undo() {
        if(busy) return;
        if(clearedStrokes!==null) {page.strokes=clearedStrokes;clearedStrokes=null;}
        else if(page.strokes.length) redoStrokes.push(page.strokes.pop());
        else return;
        totalPoints=Ink.count(notebook);revision++;redraw();autosave.restart();
    }
    function redo() {
        if(busy || !redoStrokes.length) return;
        page.strokes.push(redoStrokes.pop());totalPoints=Ink.count(notebook);
        revision++;redraw();autosave.restart();
    }
    function selectPage(index) {
        if(busy) return;
        saveBook();notebook.index=index;pageIndex=index;redoStrokes=[];clearedStrokes=null;revision++;
        redraw();autosave.restart();
    }
    function newPage() {
        if(busy) return;
        if(notebook.pages.length>=12) {notice="12 pages per sketchbook. Export pages before starting a new book.";return;}
        notebook.pages.push({strokes:[],paper:"plain"});selectPage(notebook.pages.length-1);
    }
    function confirmAction() {
        var action=confirmation;confirmation="";
        if(action==="clear") {clearedStrokes=page.strokes;page.strokes=[];redoStrokes=[];}
        if(action==="book") {
            if(saveBlocked) {saved.checkpoint=saved.document;saveBlocked=false;}
            notebook=Ink.book();pageIndex=0;clearedStrokes=null;redoStrokes=[];
        }
        totalPoints=Ink.count(notebook);revision++;redraw();autosave.restart();
    }
    function exportPage() {
        if(busy) return;
        exportPath="/home/root/.local/share/paperdesk/sketch/PaperSketch-"+Date.now()+"-page-"+(pageIndex+1)+".png";
        exportPending=true;paper.requestPaint();
    }
    Component.onCompleted: {
        if(saved.document) {
            try {notebook=Ink.decode(saved.document);}
            catch(e) {
                try {notebook=Ink.decode(saved.checkpoint);notice="Recovered the previous autosave.";}
                catch(e2) {saveBlocked=true;notice="Saved book could not be read. Original data retained; use New book to begin.";}
            }
        }
        tool=Ink.clamp(saved.selectedTool,0,7);
        brushSize=Ink.clamp(saved.selectedSize,1,80);
        strength=Ink.clamp(saved.selectedStrength,0.05,1);
        tone=Ink.clamp(saved.selectedTone,0,238);fingerSmudge=saved.useFinger;
        pageIndex=notebook.index;totalPoints=Ink.count(notebook);ready=true;redraw();
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
        TapHandler { id: tap; enabled: action.available; onTapped: action.triggered() }
    }
    Rectangle {
        id: header
        anchors.top: parent.top;width: parent.width;height: 88;color:"white"
        Row {
            anchors.left: parent.left;anchors.leftMargin: 20;anchors.verticalCenter: parent.verticalCenter;spacing:12
            Text {text:"Paper Sketch";font.pixelSize:32;font.bold:true;width:236;anchors.verticalCenter:parent.verticalCenter}
            Action {label:"Undo";objectName:"undoButton";available:!root.busy && (root.revision>=0 && (root.page.strokes.length>0 || root.clearedStrokes!==null));onTriggered:root.undo()}
            Action {label:"Redo";objectName:"redoButton";available:!root.busy && (root.revision>=0 && root.redoStrokes.length>0);onTriggered:root.redo()}
            Action {label:"Export PNG";width:154;objectName:"exportButton";available:!root.busy;onTriggered:root.exportPage()}
            Action {label:root.controlsVisible?"Hide tools":"Tools";width:154;onTriggered:root.controlsVisible=!root.controlsVisible}
        }
        Action {
            anchors.right:parent.right;anchors.rightMargin:20;anchors.verticalCenter:parent.verticalCenter
            label:"Close";width:100;onTriggered:{root.unloading();root.close()}
        }
        Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:2;color:"black"}
    }
    Column {
        id: toolsPanel
        anchors.top:header.bottom;width:parent.width
        visible:root.controlsVisible
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
                        objectName:"sizeSlider";width:220;height:52;from:1;to:80;value:root.brushSize
                        onMoved:root.brushSize=value
                        background:Rectangle {x:10;y:24;width:parent.width-20;height:3;color:"#888888"}
                        handle:Rectangle {x:parent.leftPadding+parent.visualPosition*(parent.availableWidth-width);y:10;width:28;height:32;radius:4;color:"black"}
                    }
                }
                Column {
                    Text {text:root.tool===7?"Smudge strength":"Strength  "+Math.round(root.strength*100)+"%";font.pixelSize:19;font.bold:true}
                    Slider {
                        objectName:"strengthSlider";width:220;height:52;from:0.05;to:1;value:root.strength
                        onMoved:root.strength=value
                        background:Rectangle {x:10;y:24;width:parent.width-20;height:3;color:"#888888"}
                        handle:Rectangle {x:parent.leftPadding+parent.visualPosition*(parent.availableWidth-width);y:10;width:28;height:32;radius:4;color:"black"}
                    }
                }
                Column {
                    Text {text:"Graphite shade";font.pixelSize:19;font.bold:true}
                    Row {
                        spacing:8
                        Repeater {
                            model:[0,51,102,153,204]
                            Rectangle {
                                width:48;height:48;color:Qt.rgba(modelData/255,modelData/255,modelData/255,1)
                                border.width:root.tone===modelData?5:1;border.color:root.tone===modelData?"#777777":"black"
                                Rectangle {anchors.centerIn:parent;width:12;height:12;radius:6;color:"white";border.color:"black";visible:root.tone===modelData}
                                TapHandler {onTapped:root.tone=modelData}
                            }
                        }
                    }
                }
                Action {
                    label:root.fingerSmudge?"Finger: smudge":"Finger: off";width:216;height:64
                    selected:root.fingerSmudge
                    onTriggered:{root.fingerSmudge=!root.fingerSmudge;autosave.restart()}
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
            Canvas {
                id:paper;objectName:"drawingCanvas";anchors.fill:parent
                renderTarget:Canvas.Image
                onPaint:{
                    var c=getContext("2d");
                    if(root.resetCanvas) {Ink.background(c,"plain");root.resetCanvas=false;}
                    var budget=32, started=Date.now();
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
                        while(root.pending.length && budget>0 && Date.now()-started<14) {
                            var job=root.pending.shift();Ink.segment(c,job.stroke,job.index);budget--;
                        }
                    }
                    if(root.exportPending && !root.replaying && !root.pending.length) {
                        root.exportPending=false;
                        var ok=save(root.exportPath);
                        root.notice=ok?"PNG saved: "+root.exportPath:"PNG export failed. Your drawing is still saved in the sketchbook.";
                        console.log("PaperSketch export",ok,root.exportPath);
                    }
                    if(root.replaying || root.pending.length) paintTimer.restart();
                }
            }
            Canvas {
                id:guide;anchors.fill:parent
                onPaint:{var c=getContext("2d");c.clearRect(0,0,width,height);Ink.guides(c,root.page.paper)}
            }
            HoverHandler {
                id:penHover;acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush
                onHoveredChanged:if(!hovered) palmTimer.restart()
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
                        palmTimer.restart();
                        root.beginStroke(centroid.pressPosition,"pen",root.tool,centroid.pressure);
                        root.extendStroke(centroid.position,"pen",centroid.pressure);
                    } else if(root.activeSource==="pen") {
                        root.finishStroke();palmTimer.restart();
                    }
                }
                onCentroidChanged:if(active) root.extendStroke(centroid.position,"pen",centroid.pressure)
            }
            TapHandler {
                id:penDot
                acceptedDevices:PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.Mouse
                acceptedButtons:Qt.LeftButton
                enabled:!root.replaying && !root.saveBlocked && !root.confirmation
                onPressedChanged:if(pressed) palmTimer.restart()
                onTapped:function(eventPoint,button) {
                    root.beginStroke(eventPoint.position,"pen",root.tool,eventPoint.pressure);
                    root.finishStroke();palmTimer.restart();
                }
            }
            DragHandler {
                id:fingerInput;objectName:"fingerInput";target:null
                acceptedDevices:PointerDevice.TouchScreen
                minimumPointCount:1;maximumPointCount:1
                dragThreshold:10
                enabled:root.fingerSmudge && !root.penBlocked && !root.replaying && !root.saveBlocked && !root.confirmation
                onActiveChanged:{
                    if(active) root.beginStroke(centroid.position,"finger",7);
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
        id:footer
        anchors.bottom:parent.bottom;width:parent.width;height:138;color:"white"
        Rectangle {width:parent.width;height:2;color:"black"}
        Row {
            anchors.left:parent.left;anchors.leftMargin:18;y:12;spacing:12
            Action {label:"‹";width:64;available:!root.busy && root.pageIndex>0;onTriggered:root.selectPage(root.pageIndex-1)}
            Text {text:"Page "+(root.pageIndex+1)+" / "+root.pageCount;width:146;font.pixelSize:22;anchors.verticalCenter:parent.verticalCenter}
            Action {label:"›";width:64;available:!root.busy && root.pageIndex<root.pageCount-1;onTriggered:root.selectPage(root.pageIndex+1)}
            Action {label:"New page";width:144;available:!root.busy;onTriggered:root.newPage()}
            Action {
                label:root.page.paper==="plain"?"Plain":root.page.paper==="dots"?"Dots":"Grid"
                width:110;available:!root.busy
                onTriggered:{var kinds=["plain","dots","grid"];root.page.paper=kinds[(kinds.indexOf(root.page.paper)+1)%3];root.revision++;guide.requestPaint();autosave.restart()}
            }
            Action {label:"Clear page";width:150;available:!root.busy;onTriggered:root.confirmation="clear"}
            Action {label:"New book";width:146;available:!root.busy;onTriggered:root.confirmation="book"}
        }
        Text {
            anchors.left:parent.left;anchors.right:parent.right;anchors.margins:20;y:91
            text:root.notice || (root.saveBlocked?"Save paused":root.activeSource==="finger"?"Smudging with your finger":root.busy?"Drawing…":Ink.tools[root.tool].name+" · Pressure-sensitive pen · Finger smudge "+(root.fingerSmudge?"on":"off")+" · Autosave")
            elide:Text.ElideMiddle;font.pixelSize:19;color:"#444444"
        }
    }
    Rectangle {
        anchors.fill:parent;color:"#eeeeee";visible:root.confirmation!=="";z:10
        Column {
            anchors.centerIn:parent;spacing:30
            Text {
                width:840;wrapMode:Text.WordWrap;font.pixelSize:32;font.bold:true
                text:root.confirmation==="clear"?"Clear this page? You can Undo until your next stroke.":"Start a new sketchbook? Export any drawings you want to keep first."
            }
            Text {
                width:840;wrapMode:Text.WordWrap;font.pixelSize:23
                text:root.confirmation==="book"?"This replaces the current sketchbook. PNG exports remain on the tablet.":"Other pages will stay in your sketchbook."
            }
            Row {
                spacing:20
                Action {label:"Cancel";width:220;onTriggered:root.confirmation=""}
                Action {label:root.confirmation==="clear"?"Clear page":"New book";width:240;onTriggered:root.confirmAction()}
            }
        }
    }
}
