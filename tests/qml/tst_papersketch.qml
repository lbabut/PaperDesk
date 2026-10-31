import QtQuick 2.15
import QtTest 1.3
import "../../product/payload/apps/papersketch/engine.js" as Ink

Item {
    id: scene
    width:1404;height:1872
    property var app:null
    TestCase {
        name:"PaperSketch"
        when:windowShown
        function initTestCase() {
            var component=Qt.createComponent("../../product/payload/apps/papersketch/ui/main.qml");
            compare(component.status,Component.Ready,component.errorString());
            scene.app=component.createObject(scene);
            verify(scene.app!==null,component.errorString());
            tryCompare(scene.app,"replaying",false,10000);
        }
        function cleanupTestCase(){scene.app.destroy()}
        function init(){
            scene.app.confirmation="book";scene.app.confirmAction();
            tryCompare(scene.app,"replaying",false,10000);
        }
        function line(tool,x,y,p) {
            scene.app.tool=tool;scene.app.brushSize=Ink.tools[tool].size;
            scene.app.beginStroke(Qt.point(x,y),"pen",tool);
            for(var i=1;i<30;i++)scene.app.extendStroke(Qt.point(x+i*5,y+i*2),"pen",p);
            scene.app.finishStroke();wait(150);
        }
        function test_pressure_undo_redo_and_roundtrip() {
            line(1,100,100,0.25);line(4,300,300,0.9);
            compare(scene.app.page.strokes.length,2);
            var raw=JSON.stringify(scene.app.notebook),decoded=Ink.decode(raw);
            compare(decoded.pages[0].strokes.length,2);
            verify(decoded.pages[0].strokes[0].points[1][2]<decoded.pages[0].strokes[1].points[1][2]);
            scene.app.undo();tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.page.strokes.length,1);
            scene.app.redo();tryCompare(scene.app,"replaying",false,10000);
            compare(JSON.stringify(scene.app.notebook),raw);
        }
        function test_pages_and_clear_undo() {
            line(2,100,100,0.7);
            scene.app.newPage();tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.pageIndex,1);compare(scene.app.page.strokes.length,0);
            line(5,200,200,0.6);
            scene.app.selectPage(0);tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.page.strokes[0].tool,2);
            scene.app.confirmation="clear";scene.app.confirmAction();
            tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.page.strokes.length,0);
            scene.app.undo();tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.page.strokes.length,1);
        }
        function test_real_mouse_input() {
            var canvas=findChild(scene.app,"drawingCanvas");
            mousePress(canvas,200,300,Qt.LeftButton);
            mouseMove(canvas,250,340,30);
            mouseMove(canvas,300,380,30);
            mouseRelease(canvas,300,380,Qt.LeftButton);
            wait(200);
            compare(scene.app.page.strokes.length,1);
            var points=scene.app.page.strokes[0].points;
            verify(points.length>=2);
            compare(points[0][0],200);compare(points[0][1],300);
            verify(points.some(function(p){return p[0]>=250 && p[1]>=340;}));
            verify(points.every(function(p){return p[0]>0 && p[1]>0;}));
        }
        function test_pen_tap_has_real_coordinates() {
            var canvas=findChild(scene.app,"drawingCanvas");
            mouseClick(canvas,420,530,Qt.LeftButton);wait(100);
            compare(scene.app.page.strokes.length,1);
            compare(scene.app.page.strokes[0].points[0][0],420);
            compare(scene.app.page.strokes[0].points[0][1],530);
        }
        function test_smudge_transfers_gray_and_keeps_white_clean() {
            var canvas=findChild(scene.app,"drawingCanvas"),c=canvas.getContext("2d");
            c.fillStyle="white";c.fillRect(0,0,1200,1600);
            Ink.smudge(c,[100,100,0.7],[110,100,0.7],40,1);
            compare(c.getImageData(110,100,1,1).data[0],255);
            c.fillStyle="black";c.fillRect(90,80,20,40);
            compare(c.getImageData(115,100,1,1).data[0],255);
            Ink.smudge(c,[105,100,0.7],[115,100,0.7],40,1);
            var v=c.getImageData(115,100,1,1).data[0];
            verify(v>0 && v<255,"Actual pixel blending: "+v);
        }
        function test_touch_uses_smudge_and_pen_suppresses_touch() {
            wait(650);
            var canvas=findChild(scene.app,"drawingCanvas");
            touchEvent(canvas).press(0,canvas,200,300).commit();wait(30);
            touchEvent(canvas).move(0,canvas,230,300).commit();wait(30);
            touchEvent(canvas).move(0,canvas,280,310).commit();wait(30);
            touchEvent(canvas).release(0,canvas,300,320).commit();wait(100);
            compare(scene.app.page.strokes.length,1);
            compare(scene.app.page.strokes[0].tool,7);
            mousePress(canvas,400,300,Qt.LeftButton);wait(20);
            touchEvent(canvas).press(0,canvas,200,500).commit();
            touchEvent(canvas).move(0,canvas,280,550).commit();
            touchEvent(canvas).release(0,canvas,280,550).commit();
            mouseMove(canvas,450,340,20);mouseRelease(canvas,450,340,Qt.LeftButton);wait(100);
            compare(scene.app.page.strokes.length,2);
            compare(scene.app.page.strokes[1].tool,scene.app.tool);
        }
        function test_persistence_serializes_complete_book() {
            line(3,150,300,0.75);scene.app.saveBook();
            var settings=findChild(scene.app,"sketchSettings");
            var reopened=Ink.decode(settings.document);
            compare(reopened.pages[0].strokes.length,1);
            compare(reopened.pages[0].strokes[0].tool,3);
        }
        function test_export_png() {
            var canvas=findChild(scene.app,"drawingCanvas");
            verify(canvas.save("/home/lukasz/Documents/Codex/PaperDesk/work/papersketch-tests/export.png"));
        }
        function test_sparse_smudge_follows_the_entire_drag() {
            var canvas=findChild(scene.app,"drawingCanvas"),c=canvas.getContext("2d");
            c.fillStyle="white";c.fillRect(0,0,1200,1600);
            c.fillStyle="black";c.fillRect(295,260,10,80);
            Ink.smudge(c,[200,300,0.7],[500,300,0.7],64,1);
            var moved=c.getImageData(325,300,1,1).data[0];
            verify(moved<250,"Pigment must move even when the event jumps across the line: "+moved);
            var untouched=c.getImageData(600,300,1,1).data[0];
            compare(untouched,255);
        }
        function test_touch_smears_actual_pencil_after_pen_up() {
            scene.app.tool=3;scene.app.brushSize=35;scene.app.strength=1;
            var canvas=findChild(scene.app,"drawingCanvas");
            mousePress(canvas,400,240,Qt.LeftButton);
            mouseMove(canvas,400,300,30);mouseMove(canvas,400,360,30);
            mouseRelease(canvas,400,360,Qt.LeftButton);wait(30);
            var c=canvas.getContext("2d"),before=c.getImageData(425,300,1,1).data[0];
            touchEvent(canvas).press(0,canvas,300,300).commit();wait(30);
            touchEvent(canvas).move(0,canvas,310,300).commit();wait(30);
            touchEvent(canvas).move(0,canvas,500,300).commit();wait(30);
            touchEvent(canvas).release(0,canvas,500,300).commit();
            tryCompare(scene.app,"painting",false,5000);
            compare(scene.app.page.strokes.length,2);
            compare(scene.app.page.strokes[1].tool,7);
            var after=c.getImageData(425,300,1,1).data[0];
            verify(after<before,"Real touch must move pencil pigment: "+before+" -> "+after);
        }
        function test_render_cost_comparison() {
            var canvas=findChild(scene.app,"drawingCanvas"),c=canvas.getContext("2d");
            var modern=Ink.stroke(4,24,0,0.8,42);
            for(var i=0;i<600;i++)modern.points.push([50+(i%200)*2,600+Math.floor(i/200)*50,0.7]);
            var old=JSON.parse(JSON.stringify(modern));delete old.renderer;
            var times=[];
            for(var mode=0;mode<2;mode++) {
                var s=mode?modern:old,start=Date.now();
                for(var j=0;j<s.points.length;j++)Ink.segment(c,s,j);
                c.getImageData(0,0,1,1);
                times.push(Date.now()-start);
            }
            console.log("PaperSketch 600 point benchmark",times[0],"ms original",times[1],"ms optimized");
            verify(times[0]>=0 && times[1]>=0);
        }
        function test_legacy_stroke_keeps_its_rendering_version() {
            var s=Ink.stroke(1,5,0,0.5,7);delete s.renderer;
            s.points=[[100,100,0.5],[120,120,0.7]];
            var b=Ink.book();b.pages[0].strokes.push(s);
            var old=Ink.decode(JSON.stringify(b));
            compare(old.pages[0].strokes[0].renderer,undefined);
            compare(Ink.stroke(1,5,0,0.5,7).renderer,2);
        }
        function test_validation() {
            var b=Ink.book(),s=Ink.stroke(0,5,0,0.5,1);
            s.points.push(Ink.point(-1,1800,2));b.pages[0].strokes.push(s);
            compare(Ink.decode(JSON.stringify(b)).pages[0].strokes[0].points[0][0],0);
            s.points[0][0]=-3;
            var failed=false;try {Ink.decode(JSON.stringify(b))}catch(e){failed=true}
            verify(failed);
        }
        function test_z_preview() {
            line(0,160,210,0.25);line(1,160,270,0.5);line(3,160,340,0.8);line(4,160,430,0.8);
            scene.app.tool=4;scene.app.brushSize=30;
            for(var row=0;row<8;row++) {
                scene.app.beginStroke(Qt.point(500,450+row*5),"pen",4);
                for(var i=0;i<80;i++) {
                    var x=500+i*4,y=450+row*5+80*Math.sin(i/25);
                    scene.app.extendStroke(Qt.point(x,y),"pen",0.6);
                }
                scene.app.finishStroke();
            }
            wait(400);
            grabImage(scene).save("/home/lukasz/Documents/Codex/PaperDesk/work/papersketch-tests/preview.png");
        }
    }
}
