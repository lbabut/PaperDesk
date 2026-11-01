import QtQuick 2.15
import QtQuick.Controls 2.15
import QtTest 1.3
import "../../product/payload/apps/papersketch/engine.js" as Ink

Item {
    id: scene
    width:1404;height:1872
    property var app:null
    Component {
        id:realismBackend
        QtObject {
            property bool materialAvailable:false
            property bool fastDisplay:false
            property bool penInRange:false
            property int maxSmudgeMs:0
            property int paperKind:0
            property bool kneaded:false
            property int sharpenedTool:-1
            property int cleanCount:0
            property int beginCount:0
            property int finishCount:0
            property int samples:0
            property bool calibrationActive:false
            property int calibrationStage:0
            property bool calibrationSaved:false
            property string calibrationError:""
            property bool resetFails:false
            property bool nextFails:false
            property int flushCount:0
            function setMaterialOptions(paper,eraser){paperKind=paper;kneaded=eraser}
            function materialPaperKind(){return paperKind}
            function sharpen(tool){sharpenedTool=tool}
            function cleanFinger(){cleanCount++}
            function toolWear(tool){return .5}
            function documentsDirectory(){return "Documents"}
            function saveNotebook(document,page,metadata){return false}
            function flushSaves(){flushCount++;return true}
            function startCalibration(){calibrationActive=true;calibrationStage=0;samples=0}
            function nextCalibration(){if(nextFails)return false;calibrationStage++;return true}
            function finishCalibration(){if(calibrationError)return {ok:false,error:calibrationError};calibrationActive=false;calibrationSaved=true;return {ok:true}}
            function cancelCalibration(){calibrationActive=false}
            function resetCalibration(){if(resetFails)return false;calibrationSaved=false;return true}
            function calibrationSummary(){return calibrationSaved?"Your pressure response":"Standard pressure response"}
            function begin(tentative){beginCount++}
            function finish(){finishCount++}
            function setInputTransform(x,y,sx,sy){}
            function pressureAt(x,y,fallback){return fallback}
            function advance(tool,size,strength,x,y,p,first){samples++;return true}
        }
    }
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
        function artifactPath(name){return Qt.resolvedUrl("../../work/papersketch-tests/"+name).toString().replace(/^file:\/\//,"")}
        function init(){
            scene.app.materialsDialog=false;scene.app.calibrationDialog=false;
            scene.app.fullScreen=false;scene.app.confirmation="book";scene.app.confirmAction();
            tryCompare(scene.app,"replaying",false,10000);
        }
        function line(tool,x,y,p) {
            scene.app.tool=tool;scene.app.brushSize=Ink.tools[tool].size;
            scene.app.beginStroke(Qt.point(x,y),"pen",tool);
            for(var i=1;i<30;i++)scene.app.extendStroke(Qt.point(x+i*5,y+i*2),"pen",p);
            scene.app.finishStroke();wait(150);
        }
        function test_pressure_and_roundtrip() {
            line(1,100,100,0.25);line(4,300,300,0.9);
            compare(scene.app.page.strokes.length,2);
            var raw=JSON.stringify(scene.app.notebook),decoded=Ink.decode(raw);
            compare(decoded.pages[0].strokes.length,2);
            verify(decoded.pages[0].strokes[0].points[1][2]<decoded.pages[0].strokes[1].points[1][2]);
        }
        function test_material_initial_pressure_preserves_zero_and_light_contact() {
            if(!scene.app.bitmapMode)skip("Material input test requires the tablet runtime");
            var pressures=[0,0.01,0.04,0.5,1];
            for(var i=0;i<pressures.length;i++) {
                scene.app.beginStroke(Qt.point(200,300),"pen",1,pressures[i]);
                compare(scene.app.activeStroke.points[0][2],pressures[i]);
                scene.app.finishStroke();
            }
        }
        function test_pages_and_clear() {
            line(2,100,100,0.7);
            scene.app.saveBook();scene.app.newPage();tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.pageIndex,1);compare(scene.app.page.strokes.length,0);
            line(5,200,200,0.6);
            scene.app.saveBook();scene.app.selectPage(0);tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.page.strokes[0].tool,2);
            scene.app.confirmation="clear";scene.app.confirmAction();
            tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.page.strokes.length,0);
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
            // Test pointer injection rounds to a screen pixel after sheet scaling.
            fuzzyCompare(points[0][0],200,1/scene.app.drawingScale);
            fuzzyCompare(points[0][1],300,1/scene.app.drawingScale);
            verify(points.some(function(p){return p[0]>=250 && p[1]>=340;}));
            verify(points.every(function(p){return p[0]>0 && p[1]>0;}));
        }
        function test_pen_tap_has_real_coordinates() {
            var canvas=findChild(scene.app,"drawingCanvas");
            mouseClick(canvas,420,530,Qt.LeftButton);wait(100);
            compare(scene.app.page.strokes.length,1);
            fuzzyCompare(scene.app.page.strokes[0].points[0][0],420,1/scene.app.drawingScale);
            fuzzyCompare(scene.app.page.strokes[0].points[0][1],530,1/scene.app.drawingScale);
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
            verify(canvas.save(artifactPath("export.png")));
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
            compare(Ink.stroke(1,5,0,0.5,7).renderer,7);
        }
        function test_ink_is_visible_before_canvas_commit() {
            scene.app.tool=3;scene.app.brushSize=20;
            var canvas=findChild(scene.app,"drawingCanvas"),overlay=findChild(scene.app,"liveInk");
            var passes=scene.app.rasterPasses;
            mousePress(canvas,300,400,Qt.LeftButton);
            try {
                mouseMove(canvas,450,400,20);wait(100);
                verify(scene.app.previewCount>0);
                var position=canvas.mapToItem(scene,375,400),image=grabImage(scene);
                verify(image.red(Math.round(position.x*image.width/scene.width),
                                 Math.round(position.y*image.height/scene.height))<240,
                       "The scene must show ink while the pen is still down");
                compare(canvas.getContext("2d").getImageData(375,400,1,1).data[0],255);
                compare(scene.app.rasterPasses,passes);
            } finally {mouseRelease(canvas,450,400,Qt.LeftButton);}
            tryCompare(scene.app,"painting",false,5000);
            tryCompare(scene.app,"previewCount",0,5000);
            verify(canvas.getContext("2d").getImageData(375,400,1,1).data[0]<255);
        }
        function test_smudge_reads_the_image_once_per_segment() {
            var canvas=findChild(scene.app,"drawingCanvas"),c=canvas.getContext("2d"),reads=0;
            var wrapped={
                getImageData:function(x,y,w,h){reads++;return c.getImageData(x,y,w,h);},
                save:function(){c.save();},restore:function(){c.restore();},
                beginPath:function(){c.beginPath();},arc:function(x,y,r,a,b){c.arc(x,y,r,a,b);},
                closePath:function(){c.closePath();},moveTo:function(x,y){c.moveTo(x,y);},lineTo:function(x,y){c.lineTo(x,y);},
                putImageData:function(i,x,y,a,b,w,h){c.putImageData(i,x,y,a,b,w,h);},clip:function(){c.clip();},drawImage:function(i,x,y){c.drawImage(i,x,y);}
            };
            Ink.smudge(wrapped,[100,100,0.7],[900,100,0.7],64,0.8);
            compare(reads,1);
        }
        function test_long_live_stroke_keeps_history_and_bounds_preview() {
            scene.app.tool=3;scene.app.brushSize=10;
            scene.app.beginStroke(Qt.point(100,400),"pen",3,0.7);
            var passes=scene.app.rasterPasses;
            for(var i=1;i<1800;i++)
                scene.app.extendStroke(Qt.point(100+(i%400)*2,400+60*Math.sin(i*0.1)),"pen",0.7);
            verify(scene.app.previewCount<=512);
            verify(scene.app.activeStroke.points.length>1500);
            compare(scene.app.rasterPasses,passes);
            scene.app.finishStroke();
            tryCompare(scene.app,"painting",false,10000);
            verify(scene.app.page.strokes[0].points.length>1500);
        }
        function test_smudge_softens_the_original_line_and_deposits_graphite() {
            var c=findChild(scene.app,"drawingCanvas").getContext("2d");
            c.fillStyle="white";c.fillRect(0,0,1200,1600);
            c.fillStyle="black";c.fillRect(292,240,16,120);
            var original=c.getImageData(300,300,1,1).data[0];
            Ink.smudge(c,[240,300,0.7],[360,300,0.7],64,1);
            var center=c.getImageData(300,300,1,1).data[0];
            var beside=c.getImageData(327,300,1,1).data[0];
            verify(center>original+10,"The original black line must soften: "+center);
            verify(center<245,"Smudge must retain some original graphite");
            verify(beside<220,"Graphite must spread onto adjacent white paper: "+beside);
            compare(c.getImageData(500,500,1,1).data[0],255);
        }
        function test_smudge_has_a_soft_continuous_cross_section() {
            var c=findChild(scene.app,"drawingCanvas").getContext("2d");
            c.fillStyle="white";c.fillRect(0,0,1200,1600);
            c.fillStyle="black";c.fillRect(292,240,16,120);
            Ink.smudge(c,[240,300,0.7],[360,300,0.7],64,1);
            var profile=[],maxJump=0;
            for(var y=264;y<=336;y++)profile.push(c.getImageData(319,y,1,1).data[0]);
            for(var i=1;i<profile.length;i++)maxJump=Math.max(maxJump,Math.abs(profile[i]-profile[i-1]));
            verify(maxJump<24,"Smudge edge must feather continuously, largest step="+maxJump);
            verify(Math.min.apply(null,profile)<220,"A soft edge must still carry graphite");
            findChild(scene.app,"drawingCanvas").save(artifactPath("smudge-transport.png"));
            console.log("PaperSketch smudge feather",maxJump,"maximum adjacent pixel jump");
        }
        function test_smudge_pressure_and_legacy_replay() {
            var c=findChild(scene.app,"drawingCanvas").getContext("2d");
            function core(renderer,pressure){
                c.fillStyle="white";c.fillRect(0,0,1200,1600);
                c.fillStyle="black";c.fillRect(292,240,16,120);
                var s=Ink.stroke(7,64,0,1,55);s.renderer=renderer;
                s.points=[[240,300,pressure],[360,300,pressure]];
                Ink.segment(c,s,1);return c.getImageData(300,300,1,1).data[0];
            }
            verify(core(7,1)>core(7,0.1)+20,"More pressure must soften the original line more");
            compare(core(6,0.1),core(6,1),"Saved renderer 6 must retain its original appearance");
        }
        function test_native_preview_rasterizes_without_waiting_for_pen_up() {
            if(!scene.app.nativeRasterActive)skip("Native raster test requires the tablet runtime");
            scene.app.tool=3;scene.app.brushSize=20;scene.app.nativeArmed=true;
            var canvas=findChild(scene.app,"drawingCanvas"),passes=scene.app.rasterPasses;
            scene.app.beginStroke(Qt.point(100,400),"pen",3,1);
            try {
                for(var i=1;i<=50;i++)scene.app.extendStroke(Qt.point(100+i*5,400),"pen",1);
                compare(scene.app.rasterPasses,passes);compare(scene.app.pending.length,0);
                verify(canvas.getContext("2d").getImageData(225,400,1,1).data[0]<240);
                var tile=findChild(scene.app,"artTile31");
                compare(tile.getContext("2d").getImageData(97,16,1,1).data[0],255);
            } finally {scene.app.finishStroke();scene.app.nativeArmed=false;}
            tryVerify(function(){return findChild(scene.app,"artTile31").getContext("2d").getImageData(97,16,1,1).data[0]<240;},5000);
        }
        function test_simple_tools_without_history_or_opacity_controls() {
            verify(findChild(scene.app,"undoButton")===null);
            verify(findChild(scene.app,"redoButton")===null);
            verify(findChild(scene.app,"strengthSlider")===null);
            verify(findChild(scene.app,"sizeSlider")!==null);
            compare(typeof scene.app.undo,"undefined");compare(typeof scene.app.redo,"undefined");
        }
        function test_icon_tools_select_the_material_and_default_size() {
            for(var i=0;i<Ink.tools.length;i++) {
                var button=findChild(scene.app,"tool"+i),icon=findChild(scene.app,"tool"+i+"Icon");
                verify(button!==null);verify(icon!==null);
                verify(button.width>=60 && button.height>=60,"Tool touch target must remain usable");
                verify(button.accessibleName.length>0,"Icon tools must have semantic names on tablet builds without Accessible");
                compare(button.ToolTip.text,button.accessibleName);
                verify(button.iconName.length>0);
                tryCompare(icon,"available",true);
                mouseClick(button,button.width/2,button.height/2,Qt.LeftButton);
                compare(scene.app.tool,i);compare(scene.app.brushSize,Ink.tools[i].size);
                verify(button.selected);
                verify(icon.inverted,"Selected tool must have a contrasting icon");
            }
        }
        function test_size_and_icons_share_one_compact_middle_bar() {
            var panel=findChild(scene.app,"sketchTools"),slider=findChild(scene.app,"sizeSlider");
            compare(panel.height,84);
            var widths=[1404,1024,800];
            try {
                for(var i=0;i<widths.length;i++) {
                    scene.width=widths[i];wait(40);
                    var first=findChild(scene.app,"tool0"),last=findChild(scene.app,"tool7");
                    var a=first.mapToItem(panel,0,0),b=last.mapToItem(panel,last.width,last.height),s=slider.mapToItem(panel,0,0);
                    verify(a.x>=0 && a.y>=0 && b.y<=panel.height);
                    verify(s.x>b.x,"Tool icons and size control must not overlap");
                    compare(s.y,a.y);compare(slider.height,first.height);
                    verify(s.x+slider.width<=panel.width,"Size slider must stay inside the middle bar");
                    verify(slider.width>=96,"Size control must retain a usable drag range");
                }
            } finally {scene.width=1404;wait(40);}
        }
        function test_integrated_size_slider_responds_to_pointer_drag() {
            var slider=findChild(scene.app,"sizeSlider");
            scene.app.brushSize=1;wait(20);
            mousePress(slider,20,slider.height/2,Qt.LeftButton);
            mouseMove(slider,slider.width/2,slider.height/2,30);
            mouseMove(slider,slider.width-20,slider.height/2,30);
            mouseRelease(slider,slider.width-20,slider.height/2,Qt.LeftButton);
            verify(scene.app.brushSize>70,"Dragging the integrated slider must change the actual tool size");
            compare(findChild(scene.app,"sizeLabel").text,"Size "+Math.round(scene.app.brushSize));
        }
        function test_material_panel_actions_and_saved_options_restore() {
            var original=scene.app.nativeRaster,backend=realismBackend.createObject(scene);
            try {
                scene.app.nativeRaster=backend;scene.app.paperKind=0;scene.app.kneadedEraser=false;
                var materials=findChild(scene.app,"materialsButton");
                verify(materials.iconName.length>0);compare(materials.ToolTip.text,"Materials");
                mouseClick(materials,materials.width/2,materials.height/2,Qt.LeftButton);
                verify(scene.app.materialsDialog);
                var rough=findChild(scene.app,"paperTexture2");mouseClick(rough,rough.width/2,rough.height/2,Qt.LeftButton);
                compare(scene.app.paperKind,2);compare(backend.paperKind,2);compare(scene.app.page.materialPaperKind,2);
                scene.app.tool=4;
                var sharpen=findChild(scene.app,"sharpenButton");mouseClick(sharpen,100,30,Qt.LeftButton);compare(backend.sharpenedTool,4);
                var clean=findChild(scene.app,"cleanFingerButton");mouseClick(clean,100,30,Qt.LeftButton);compare(backend.cleanCount,1);
                var kneaded=findChild(scene.app,"kneadedEraserButton");mouseClick(kneaded,100,30,Qt.LeftButton);
                compare(scene.app.tool,6);verify(scene.app.kneadedEraser);verify(backend.kneaded);verify(!sharpen.available);
                verify(scene.app.dirty,"Physical material changes must be saved with the drawing");
                grabImage(scene).save(artifactPath("materials-panel-v41.png"));
                var done=findChild(scene.app,"closeMaterials");mouseClick(done,70,30,Qt.LeftButton);verify(!scene.app.materialsDialog);
                verify(scene.app.saveBook());
                var saved=findChild(scene.app,"sketchSettings");
                compare(saved.paperKind,2);verify(saved.kneadedEraser);
                var stored={selectedTool:saved.selectedTool,selectedSize:saved.selectedSize,paperKind:saved.paperKind,kneadedEraser:saved.kneadedEraser},book=Ink.decode(saved.document);
                compare(book.pages[0].materialPaperKind,2);
                // The desktop Settings test double has no disk storage. Exercise
                // the same serialized preference restore path used on startup.
                scene.app.materialOptionsLoading=true;scene.app.paperKind=0;scene.app.kneadedEraser=false;scene.app.materialOptionsLoading=false;
                scene.app.restoreToolPreferences(stored);
                compare(scene.app.paperKind,2);verify(scene.app.kneadedEraser);compare(backend.paperKind,2);verify(backend.kneaded);
                scene.app.page.materialPaperKind=1;scene.app.restoreMaterialOptions(false);compare(scene.app.paperKind,1);compare(backend.paperKind,1);
            } finally {
                scene.app.nativeRaster=original;backend.destroy();
                scene.app.materialsDialog=false;scene.app.paperKind=0;scene.app.kneadedEraser=false;
            }
        }
        function test_material_preferences_wait_for_explicit_save() {
            var original=scene.app.nativeRaster,backend=realismBackend.createObject(scene),saved=findChild(scene.app,"sketchSettings");
            var oldPaper=saved.paperKind,oldEraser=saved.kneadedEraser,nextPaper=(oldPaper+1)%3,nextEraser=!oldEraser;
            try {
                scene.app.nativeRaster=backend;
                scene.app.paperKind=nextPaper;scene.app.kneadedEraser=nextEraser;
                compare(saved.paperKind,oldPaper);compare(saved.kneadedEraser,oldEraser);
                verify(scene.app.dirty);compare(backend.paperKind,nextPaper);compare(backend.kneaded,nextEraser);
                delete scene.app.page.materialPaperKind;scene.app.restoreMaterialOptions(false);
                compare(scene.app.paperKind,nextPaper,"A new page inherits the current in-memory paper choice");
                compare(saved.paperKind,oldPaper);compare(saved.kneadedEraser,oldEraser);
                verify(scene.app.saveBook());compare(saved.paperKind,nextPaper);compare(saved.kneadedEraser,nextEraser);
            } finally {
                scene.app.nativeRaster=original;backend.destroy();saved.paperKind=oldPaper;saved.kneadedEraser=oldEraser;
                scene.app.materialOptionsLoading=true;scene.app.paperKind=oldPaper;scene.app.kneadedEraser=oldEraser;scene.app.materialOptionsLoading=false;
            }
        }
        function test_calibration_pad_isolated_three_stages_save_reset_and_cancel() {
            line(1,100,100,.6);scene.app.saveBook();
            var original=scene.app.nativeRaster,backend=realismBackend.createObject(scene),before=JSON.stringify(scene.app.notebook),wasDirty=scene.app.dirty;
            try {
                scene.app.nativeRaster=backend;scene.app.openMaterials();
                var calibrate=findChild(scene.app,"calibratePressureButton");mouseClick(calibrate,100,30,Qt.LeftButton);
                verify(scene.app.calibrationDialog);verify(backend.calibrationActive);verify(!scene.app.materialsDialog);
                var pad=findChild(scene.app,"calibrationPad"),next=findChild(scene.app,"nextCalibrationButton");
                verify(!next.available);verify(!findChild(scene.app,"penInput").enabled);verify(!findChild(scene.app,"fingerInput").enabled);
                // Exercise the dedicated pointer path before completing each stage.
                mousePress(pad,80,80,Qt.LeftButton);mouseMove(pad,150,100,20);mouseMove(pad,220,120,20);mouseRelease(pad,220,120,Qt.LeftButton);
                verify(backend.samples>0);verify(backend.beginCount>0);verify(backend.finishCount>0);
                for(var stage=0;stage<3;stage++) {
                    compare(scene.app.calibrationStage,stage);
                    verify(findChild(scene.app,"calibrationPrompt").text.indexOf((stage+1)+" of 3")===0);
                    for(var i=0;i<20;i++)scene.app.sampleCalibration(Qt.point(100+i*8,130+stage*20),.15+stage*.3,i===0);
                    scene.app.finishCalibrationStroke();verify(next.available);
                    if(stage===2)grabImage(scene).save(artifactPath("pressure-calibration-v41.png"));
                    mouseClick(next,100,30,Qt.LeftButton);
                }
                verify(!scene.app.calibrationDialog);verify(scene.app.materialsDialog);verify(backend.calibrationSaved);
                compare(JSON.stringify(scene.app.notebook),before);compare(scene.app.dirty,wasDirty);
                compare(scene.app.activeStroke,null);
                var reset=findChild(scene.app,"resetPressureButton");mouseClick(reset,100,30,Qt.LeftButton);verify(!backend.calibrationSaved);
                backend.calibrationSaved=true;scene.app.startPressureCalibration();
                scene.app.sampleCalibration(Qt.point(100,100),.25,true);scene.app.finishCalibrationStroke();
                var cancel=findChild(scene.app,"cancelCalibrationButton");mouseClick(cancel,100,30,Qt.LeftButton);
                verify(!scene.app.calibrationDialog);verify(!backend.calibrationActive);verify(backend.calibrationSaved);
                compare(JSON.stringify(scene.app.notebook),before);compare(scene.app.dirty,wasDirty);
            } finally {
                scene.app.nativeRaster=original;backend.destroy();scene.app.materialsDialog=false;scene.app.calibrationDialog=false;
            }
        }
        function test_calibration_validation_error_can_restart() {
            var original=scene.app.nativeRaster,backend=realismBackend.createObject(scene);
            try {
                scene.app.nativeRaster=backend;scene.app.startPressureCalibration();backend.calibrationStage=2;
                backend.calibrationError="Use distinct light, normal and firm pressure.";
                for(var i=0;i<20;i++)scene.app.sampleCalibration(Qt.point(80+i*5,100),.5,i===0);
                scene.app.nextPressureCalibration();
                verify(scene.app.calibrationDialog);verify(!backend.calibrationSaved);
                compare(findChild(scene.app,"calibrationError").text,backend.calibrationError);
                var restart=findChild(scene.app,"restartCalibrationButton");verify(restart.visible);mouseClick(restart,100,30,Qt.LeftButton);
                compare(scene.app.calibrationStage,0);compare(scene.app.calibrationSamples,0);compare(scene.app.calibrationMessage,"");
                scene.app.cancelPressureCalibration();
            } finally {scene.app.nativeRaster=original;backend.destroy();scene.app.materialsDialog=false;scene.app.calibrationDialog=false;}
        }
        function test_calibration_rejected_step_and_failed_reset_preserve_profile() {
            var original=scene.app.nativeRaster,backend=realismBackend.createObject(scene);
            try {
                scene.app.nativeRaster=backend;backend.calibrationSaved=true;backend.resetFails=true;
                scene.app.resetPressureCalibration();verify(backend.calibrationSaved);
                verify(scene.app.notice.indexOf("could not be reset")>=0);
                scene.app.startPressureCalibration();backend.nextFails=true;
                for(var i=0;i<20;i++)scene.app.sampleCalibration(Qt.point(80+i*5,100),.2,i===0);
                scene.app.nextPressureCalibration();compare(scene.app.calibrationStage,0);compare(scene.app.calibrationSamples,20);
                verify(scene.app.calibrationMessage.indexOf("more lines")>=0);verify(backend.calibrationSaved);
                scene.app.cancelPressureCalibration();
            } finally {scene.app.nativeRaster=original;backend.destroy();scene.app.materialsDialog=false;scene.app.calibrationDialog=false;}
        }
        function test_failed_page_load_blocks_material_mutation_and_save() {
            var original=scene.app.nativeRaster,backend=realismBackend.createObject(scene),blocked=scene.app.saveBlocked;
            try {
                scene.app.nativeRaster=backend;scene.app.saveBlocked=true;
                verify(!findChild(scene.app,"materialsButton").available);verify(!scene.app.materialsAvailable);
                scene.app.openMaterials();verify(!scene.app.materialsDialog);
                scene.app.tool=1;scene.app.sharpenTool();scene.app.cleanFinger();scene.app.startPressureCalibration();
                compare(backend.sharpenedTool,-1);compare(backend.cleanCount,0);verify(!backend.calibrationActive);verify(!scene.app.calibrationDialog);
                verify(!scene.app.saveBook(),"A failed bitmap load must never save a replacement blank page");
                scene.app.materialsDialog=true;
                verify(!findChild(scene.app,"paperTexture2").available);verify(!findChild(scene.app,"calibratePressureButton").available);
            } finally {scene.app.nativeRaster=original;backend.destroy();scene.app.saveBlocked=blocked;scene.app.materialsDialog=false;scene.app.calibrationDialog=false;}
        }
        function test_native_rejected_save_keeps_dirty_drawing() {
            var original=scene.app.nativeRaster,wasActive=scene.app.nativeRasterActive,backend=realismBackend.createObject(scene);
            try {
                scene.app.nativeRaster=backend;scene.app.nativeRasterActive=true;scene.app.dirty=true;
                var document=JSON.stringify(scene.app.notebook);
                verify(!scene.app.saveBook());verify(scene.app.dirty);compare(backend.flushCount,0);
                verify(scene.app.notice.indexOf("Save failed")===0);compare(JSON.stringify(scene.app.notebook),document);
            } finally {scene.app.nativeRasterActive=wasActive;scene.app.nativeRaster=original;backend.destroy();}
        }
        function test_device_realism_harness_compiles() {
            var component=Qt.createComponent("../device/papersketch-realism.qml");
            compare(component.status,Component.Ready,component.errorString());
        }
        function test_manual_save_and_cancel_discard_page_prompt() {
            line(1,120,120,0.7);verify(scene.app.dirty);
            scene.app.requestClose();compare(scene.app.confirmation,"leave");
            scene.app.resolveLeave("cancel");verify(scene.app.dirty);verify(!scene.app.closing);
            scene.app.saveBook();verify(!scene.app.dirty);
            scene.app.newPage();compare(scene.app.pageIndex,1);
            line(4,300,300,0.7);scene.app.selectPage(0);compare(scene.app.confirmation,"leave");compare(scene.app.pageIndex,1);
            scene.app.resolveLeave("discard");compare(scene.app.pageIndex,0);compare(scene.app.pageCount,1);
            compare(scene.app.page.strokes.length,1);
        }
        function test_full_screen_and_round_menu_button() {
            scene.app.fullScreen=true;wait(80);
            compare(findChild(scene.app,"sketchHeader").height,0);
            compare(findChild(scene.app,"sketchFooter").height,0);
            var button=findChild(scene.app,"exitFullScreen");verify(button.visible);
            mouseClick(button,28,28,Qt.LeftButton);wait(50);verify(!scene.app.fullScreen);
            compare(findChild(scene.app,"sketchHeader").height,88);
        }
        function test_single_book_always_on_finger_and_delete_control() {
            verify(scene.app.fingerSmudge);verify(findChild(scene.app,"deletePageButton")!==null);
            function labels(item){var out=[];if(item.label!==undefined)out.push(item.label);for(var i=0;i<item.children.length;i++)out=out.concat(labels(item.children[i]));return out;}
            var all=labels(scene.app);verify(all.indexOf("New book")<0);verify(all.indexOf("Finger: smudge")<0);verify(all.indexOf("Finger: off")<0);
        }
        function test_delete_middle_preserves_page_identity_and_discard() {
            line(1,100,100,.7);scene.app.saveBook();scene.app.newPage();tryCompare(scene.app,"replaying",false,10000);
            line(4,300,300,.7);scene.app.saveBook();scene.app.newPage();tryCompare(scene.app,"replaying",false,10000);
            line(3,600,600,.7);scene.app.saveBook();scene.app.selectPage(1);tryCompare(scene.app,"replaying",false,10000);
            scene.app.confirmation="delete";scene.app.confirmAction();tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.pageCount,2);compare(scene.app.pageIndex,1);compare(scene.app.page.cacheSlot,2);
            compare(scene.app.page.strokes[0].tool,3);verify(scene.app.dirty);
            scene.app.requestLeave({kind:"page",index:0});scene.app.resolveLeave("discard");tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.pageCount,3);compare(scene.app.notebook.pages[1].cacheSlot,1);
            scene.app.selectPage(1);tryCompare(scene.app,"replaying",false,10000);scene.app.confirmation="delete";scene.app.confirmAction();tryCompare(scene.app,"replaying",false,10000);scene.app.saveBook();
            scene.app.newPage();tryCompare(scene.app,"replaying",false,10000);compare(scene.app.page.cacheSlot,3);
            scene.app.requestLeave({kind:"page",index:0});scene.app.resolveLeave("discard");tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.pageCount,2);compare(scene.app.notebook.pages[1].cacheSlot,2);
        }
        function test_delete_last_keeps_one_blank_page_until_discard() {
            line(1,100,100,.7);scene.app.saveBook();var slot=scene.app.page.cacheSlot;
            scene.app.confirmation="delete";scene.app.confirmAction();tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.pageCount,1);compare(scene.app.page.strokes.length,0);verify(scene.app.page.cacheSlot>slot);
            scene.app.requestLeave({kind:"page",index:0});scene.app.resolveLeave("discard");tryCompare(scene.app,"replaying",false,10000);
            compare(scene.app.page.cacheSlot,slot);compare(scene.app.page.strokes.length,1);
        }
        function test_named_export_dialog_and_cancel() {
            scene.app.exportPage();verify(scene.app.exportDialog);
            var name=findChild(scene.app,"exportName");verify(name.visible);name.text="My drawing";
            scene.app.closeExport();verify(!scene.app.exportDialog);
        }
        function test_duplicate_cache_identity_is_rejected() {
            var b=Ink.book();b.pages.push({strokes:[],paper:"plain",cacheSlot:0});
            var failed=false;try{Ink.decode(JSON.stringify(b))}catch(e){failed=true}verify(failed);
        }
        function test_material_paper_kind_validation_keeps_legacy_pages() {
            var legacy=Ink.book();compare(Ink.decode(JSON.stringify(legacy)).pages[0].materialPaperKind,undefined);
            for(var i=0;i<3;i++){legacy.pages[0].materialPaperKind=i;compare(Ink.decode(JSON.stringify(legacy)).pages[0].materialPaperKind,i);}
            var bad=[-1,3,.5,"1",null];
            for(var j=0;j<bad.length;j++){legacy.pages[0].materialPaperKind=bad[j];var rejected=false;try{Ink.decode(JSON.stringify(legacy))}catch(e){rejected=true}verify(rejected,"Invalid material paper kind must be rejected");}
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
            grabImage(scene).save(artifactPath("preview.png"));
        }
    }
}
