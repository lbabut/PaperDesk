import QtQuick 2.15
import QtTest 1.3
Item {
    id:scene;width:1052;height:1218
    property var graph:null
    TestCase {
        name:"CalcGraph";when:windowShown
        function init(){
            var c=Qt.createComponent('../../product/payload/apps/papercalc/ui/GraphPanel.qml');
            compare(c.status,Component.Ready,c.errorString());
            scene.graph=c.createObject(scene,{width:1052,height:1218});
            verify(scene.graph!==null);waitForRendering(scene.graph);
        }
        function cleanup(){scene.graph.destroy();scene.graph=null;}
        function tap(name){var k=findChild(scene.graph,name);verify(k!==null,name);mouseClick(k,k.width/2,k.height/2);}
        function near(a,b){verify(Math.abs(a-b)<1e-7, a+' != '+b);}
        function type(labels){var all=['x','sin','cos','tan','^','(',')','7','8','9','÷','√','ln','π','4','5','6','×','abs','log','e','1','2','3','−','.','⌫','AC','0','+','x²','x³','1/x','exp','DRAW'];for(var i=0;i<labels.length;i++)tap('graphKey'+all.indexOf(labels[i]));}
        function test_enter_draw_three_functions(){
            var g=scene.graph;
            tap('graphFunction0');type(['AC','x','x²','−','4','DRAW']);compare(g.formulas[0],'x^2−4');
            compare(g.curves[0].length,401);near(g.curves[0][200].y,-4);near(g.curves[0][240].y,0);
            tap('graphFunction1');type(['AC','sin','x',')','DRAW']);near(g.curves[1][240].y,Math.sin(2));
            tap('graphFunction2');type(['AC','x','x³','DRAW']);compare(g.curves[2].length,0);
            tap('graphEnabled2');compare(g.curves[2].length,401);near(g.curves[2][240].y,8);
            tap('graphEnabled0');compare(g.curves[0].length,0);compare(g.curves[1].length,401);
        }
        function test_edit_delete_and_redraw(){
            var g=scene.graph;var old=g.curves[0][200].y;
            tap('graphFunction0');type(['AC','x','+','9','⌫','2']);compare(g.formulas[0],'x+2');
            compare(g.curves[0][200].y,old);tap('graphDraw');near(g.curves[0][200].y,2);
        }
        function test_range_keypad(){
            var g=scene.graph;
            tap('graphRange0');type(['AC','−','5']);tap('graphDraw');compare(g.bounds[0],-5);compare(g.rangeField,-1);
            tap('graphRange1');type(['AC','5','DRAW']);compare(g.bounds[1],5);near(g.curves[0][200].x,0);
            tap('graphRange2');type(['AC','−','2','DRAW']);compare(g.bounds[2],-2);
            tap('graphRange3');type(['AC','8','DRAW']);compare(g.bounds[3],8);
            tap('graphRange1');type(['AC','−','9','DRAW']);compare(g.bounds[1],5);compare(g.rangeField,1);verify(g.notice.indexOf('Invalid window')>=0);
            type(['AC','DRAW']);compare(g.bounds[1],5);verify(g.notice.indexOf('finite number')>=0);
        }
        function test_invalid_windows_data(){return [
            {tag:'inverted',b:[10,-10,-10,10]}, {tag:'zero',b:[0,0,-10,10]},
            {tag:'tiny',b:[0,1e-10,-10,10]}, {tag:'infinite',b:[-10,Infinity,-10,10]},
            {tag:'nan',b:[-10,10,NaN,10]}, {tag:'huge',b:[-1e13,10,-10,10]}];}
        function test_invalid_windows(d){var g=scene.graph;verify(!g.setBounds(d.b));compare(JSON.stringify(g.bounds),'[-10,10,-10,10]');}
        function test_zoom_and_standard(){
            var g=scene.graph;g.setBounds([-4,8,-2,10]);
            tap('graphZoomIn');compare(JSON.stringify(g.bounds),'[-1,5,1,7]');
            tap('graphZoomOut');compare(JSON.stringify(g.bounds),'[-4,8,-2,10]');
            tap('graphStandard');compare(JSON.stringify(g.bounds),'[-10,10,-10,10]');
        }
        function test_trace_mouse_and_arrows(){
            var g=scene.graph,p=findChild(g,'functionPlot');
            mouseClick(p,65+(p.width-90)*0.6,150);verify(Math.abs(g.traceX-2)<=20/(p.width-90),'Trace must match the touched pixel');
            var touched=g.traceX;verify(g.traceLabel.indexOf('y = '+g.label(touched*touched-4))>=0);
            tap('traceRight');near(g.traceX,touched+0.5);tap('traceLeft');near(g.traceX,touched);
            mouseClick(p,p.width-1,150);compare(g.traceX,10);tap('traceRight');compare(g.traceX,10);
            mouseClick(p,0,150);compare(g.traceX,-10);tap('traceLeft');compare(g.traceX,-10);
        }
        function test_table_values_and_disabled(){
            var g=scene.graph;g.formulas=['x^2','1/x','sqrt(x)'];g.enabledCurves=[true,true,true];g.traceX=0;g.draw();
            tap('graphTable');verify(g.table);compare(findChild(g,'functionPlot').visible,false);
            compare(findChild(g,'graphCell3_0').text,'0');compare(findChild(g,'graphCell3_1').text,'0');
            compare(findChild(g,'graphCell3_2').text,'undefined');compare(findChild(g,'graphCell2_3').text,'undefined');
            compare(findChild(g,'graphCell5_1').text,'1');compare(findChild(g,'graphCell5_2').text,'1');
            tap('graphEnabled2');compare(findChild(g,'graphCell5_3').text,'—');
            tap('traceRight');compare(findChild(g,'graphCell3_0').text,'0.5');compare(findChild(g,'graphCell3_1').text,'0.25');
            tap('graphTable');verify(!g.table);verify(findChild(g,'functionPlot').visible);
        }
        function test_degrees_and_radians(){
            var g=scene.graph;g.formulas=['sin(x)','cos(x)','tan(x)'];g.enabledCurves=[true,true,true];g.traceX=90;g.setBounds([0,180,-2,2]);
            tap('graphAngles');compare(g.angleMode,'DEG');near(g.curves[0][200].y,1);near(g.curves[1][200].y,0);compare(g.curves[2][200].y,null);
            tap('graphAngles');compare(g.angleMode,'RAD');near(g.curves[0][200].y,Math.sin(90));
        }
        function test_domains_and_invalid_formula(){
            var g=scene.graph;g.formulas=['1/x','sqrt(x)','sin('];g.enabledCurves=[true,true,true];g.draw();
            compare(g.curves[0][200].y,null);verify(g.curves[1].slice(0,200).every(function(p){return p.y===null;}));
            verify(g.curves[2].every(function(p){return p.y===null;}));verify(g.notice.indexOf('Y3:')>=0);
            tap('graphFunction2');type(['AC','x','DRAW']);near(g.curves[2][240].y,2);verify(g.notice.indexOf('Drawn')===0);
        }
        function test_nearest_zero_and_poles(){
            var g=scene.graph;g.traceX=1;tap('graphFindZero');near(g.traceX,2);
            g.traceX=-1;tap('graphFindZero');near(g.traceX,-2);
            g.formulas=['1/x','x^2+1',''];g.setBounds([-.9,1,-10,10]);g.traceX=.1;tap('graphFindZero');near(g.traceX,.1);verify(g.notice.indexOf('No sign-changing root')>=0);
            tap('graphFunction1');tap('graphFindZero');verify(g.notice.indexOf('No sign-changing root')>=0);
        }
        function test_canvas_repaints(){
            var p=findChild(scene.graph,'functionPlot');tryVerify(function(){return p.available;});
            var spy=Qt.createQmlObject('import QtTest 1.3; SignalSpy {}',scene);spy.target=p;spy.signalName='paint';verify(spy.valid);
            p.requestPaint();tryVerify(function(){return spy.count>0;});spy.clear();
            tap('graphZoomIn');tryVerify(function(){return spy.count>0;});spy.destroy();
        }
    }
}
