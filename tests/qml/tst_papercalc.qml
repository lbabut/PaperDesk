import QtQuick 2.15
import QtTest 1.3
import "../../product/payload/apps/papercalc/calc.js" as Calc
Item {
    id:scene;width:1404;height:1872
    property var app:null
    TestCase {
        name:"PaperCalc";when:windowShown
        function initTestCase(){var c=Qt.createComponent('../../product/payload/apps/papercalc/ui/main.qml');compare(c.status,Component.Ready,c.errorString());scene.app=c.createObject(scene,{settingsFile:Qt.resolvedUrl("../../work/test-settings.ini").toString().replace("file://", "")});verify(scene.app!==null);waitForRendering(scene.app);}
        function cleanupTestCase(){scene.app.destroy();}
        function tap(name){var k=findChild(scene.app,name);verify(k!==null,name);mouseClick(k,k.width/2,k.height/2);}
        function test_desk(){tap('calcModeDesk');scene.app.officeKey('AC');['1','0','0','+','1','0','%','='].forEach(function(k){scene.app.officeKey(k);});compare(scene.app.desk.input,'110');verify(scene.app.history.length>0);tap('deskKey5');tap('deskKey20');tap('deskKey23');tap('deskKey21');tap('deskKey24');compare(scene.app.desk.input,'3');}
        function test_key_response(){
            tap('calcModeDesk');scene.app.officeKey('AC');
            var k=findChild(scene.app,'deskKey20'),before=k.color;
            mousePress(k,k.width/2,k.height/2);compare(scene.app.desk.input,'1');compare(scene.app.deskDisplay.input,'1');compare(k.color,before);
            mouseRelease(k,k.width/2,k.height/2);compare(scene.app.desk.input,'1');compare(k.color,before);
            for(var i=0;i<8;i++)mouseClick(k,k.width/2,k.height/2);
            compare(scene.app.desk.input,'111111111');
        }
        function test_fast_amount_entry(){
            tap('calcModeDesk');scene.app.officeKey('AC');
            var keys={};for(var j=0;j<28;j++){var k=findChild(scene.app,'deskKey'+j);keys[k.label]=k;}
            var sequence='11.11+22.22+33.33+44.44+55.55+66.66+77.77+88.88+99.99+12.34+56.78+90.12=';
            var t=touchEvent(scene.app);
            for(var i=0;i<sequence.length;i++){
                var key=keys[sequence.charAt(i)];
                t.press(0,key,key.width/2,key.height/2).commit();
                t.release(0,key,key.width/2,key.height/2).commit();
            }
            compare(scene.app.desk.input,'659.19');
            compare(scene.app.history[0],sequence.slice(0,-1).split('+').join(' + ')+' = 659.19');
            tryVerify(function(){return scene.app.deskDisplay.input==='659.19';},150);
        }
        function test_history_full_receipt(){
            scene.app.mode='Desk';scene.app.officeKey('AC');
            var keys='12.50+8.20+3.00';
            for(var i=0;i<keys.length;i++)scene.app.officeKey(keys[i]);
            wait(170);
            compare(findChild(scene.app,'calcReceiptText').text,'12.50 + 8.20 + 3.00');
            scene.app.officeKey('=');compare(scene.app.history[0],'12.50 + 8.20 + 3.00 = 23.7');
            var longEntry=Array(101).join('12.50 + ')+'0 = 1250';
            scene.app.addHistory(longEntry);scene.app.showHistory=true;wait(30);
            var list=findChild(scene.app,'calcTape');
            verify(list.itemAtIndex(0).height>110,'Full long receipt must wrap without truncation');
            scene.app.showHistory=false;
        }
        function test_overlapping_touches(){
            tap('calcModeDesk');scene.app.officeKey('AC');
            var k1=findChild(scene.app,'deskKey20'),k2=findChild(scene.app,'deskKey21');
            var t=touchEvent(scene.app);
            t.press(0,k1,k1.width/2,k1.height/2).commit();wait(10);
            t.stationary(0).press(1,k2,k2.width/2,k2.height/2).commit();wait(10);
            t.release(0,k1,k1.width/2,k1.height/2).stationary(1).commit();wait(10);
            t.release(1,k2,k2.width/2,k2.height/2).commit();wait(10);
            compare(scene.app.desk.input,'12');
        }
        function test_persistence(){
            var a=scene.app;a.mode='Desk';a.officeKey('MC');a.officeKey('AC');a.officeKey('4');a.officeKey('2');a.officeKey('M+');a.addHistory('40 + 2 = 42');
            var g=findChild(a,'calcGraphPanel');g.formulas=['x^3','cos(x)',''];g.enabledCurves=[true,false,false];g.setBounds([-8,8,-4,4]);g.edited();
            var f=a.settingsFile;a.unloading();a.destroy();wait(50);
            var c=Qt.createComponent('../../product/payload/apps/papercalc/ui/main.qml');scene.app=c.createObject(scene,{settingsFile:f});waitForRendering(scene.app);
            compare(scene.app.desk.memory,42);compare(scene.app.history[0],'40 + 2 = 42');g=findChild(scene.app,'calcGraphPanel');compare(g.formulas[0],'x^3');compare(g.bounds[0],-8);compare(g.enabledCurves[1],false);
        }
        function test_science(){tap('calcModeScience');scene.app.reset();tap('calcScisin');tap('calcKey3');tap('calcKey0');tap('calcKey)');tap('calcKey=');compare(scene.app.result,'0.5');tap('calcKey2');compare(scene.app.expression,'2');scene.app.key('^');scene.app.key('3');scene.app.solve();compare(scene.app.result,'8');}
        function test_science_fast_touch(){
            tap('calcModeScience');scene.app.reset();
            var spy=Qt.createQmlObject('import QtTest 1.3; SignalSpy {}',scene);spy.target=scene.app;spy.signalName='scienceExpressionChanged';verify(spy.valid);
            var sequence='11.11+22.22+33.33+44.44+55.55+66.66+77.77+88.88+99.99+12.34+56.78+90.12';
            var t=touchEvent(scene.app),started=Date.now();
            for(var i=0;i<sequence.length;i++){
                var k=findChild(scene.app,'calcKey'+sequence.charAt(i));
                t.press(0,k,k.width/2,k.height/2).commit();t.release(0,k,k.width/2,k.height/2).commit();
            }
            compare(scene.app.expression,sequence);
            tryCompare(scene.app,'scienceExpression',sequence,180);
            verify(spy.count<=Math.ceil((Date.now()-started)/80)+2,'Display updates should be coalesced: '+spy.count);
            var eq=findChild(scene.app,'calcKey=');t.press(0,eq,eq.width/2,eq.height/2).commit();
            compare(scene.app.result,'659.19');compare(scene.app.scienceExpression,sequence);
            t.release(0,eq,eq.width/2,eq.height/2).commit();
            compare(findChild(scene.app,'calcDisplay').text,'659.19');spy.destroy();
        }
        function test_science_overlapping_touches(){
            tap('calcModeScience');scene.app.reset();
            var k1=findChild(scene.app,'calcKey1'),k2=findChild(scene.app,'calcKey2'),t=touchEvent(scene.app);
            t.press(0,k1,k1.width/2,k1.height/2).commit();wait(10);
            t.stationary(0).press(1,k2,k2.width/2,k2.height/2).commit();wait(10);
            t.release(0,k1,k1.width/2,k1.height/2).stationary(1).commit();t.release(1,k2,k2.width/2,k2.height/2).commit();
            compare(scene.app.expression,'12');tryCompare(scene.app,'scienceExpression','12',180);
        }
        function test_science_pacing_and_clear(){
            tap('calcModeScience');scene.app.reset();
            scene.app.key('1');compare(scene.app.scienceExpression,'1');
            for(var i=0;i<30;i++)scene.app.key('+1');
            verify(scene.app.scienceExpression!==scene.app.expression);
            scene.app.key('=');compare(scene.app.scienceExpression,scene.app.expression);compare(scene.app.result,'31');
            scene.app.key('2');scene.app.key('+');scene.app.key('3');scene.app.key('C');
            compare(scene.app.expression,'');compare(scene.app.scienceExpression,'');compare(scene.app.result,'0');
            wait(120);compare(scene.app.scienceExpression,'');
            scene.app.key('1');scene.app.key('÷');scene.app.key('0');scene.app.key('=');
            compare(scene.app.scienceExpression,'1÷0');verify(scene.app.result.indexOf('zero')>=0);
        }
        function test_graph(){tap('calcModeGraph');var g=findChild(scene.app,'calcGraphPanel');verify(g!==null);g.draw();compare(g.curves.length,3);compare(g.curves[0].length,401);g.selected=0;g.traceX=1;g.findRoot();verify(Math.abs(g.traceX-2)<1e-7,g.notice);g.formulas=['1/x','sqrt(x)','sin(x)'];g.draw();compare(g.curves[0][200].y,null);verify(!g.setBounds([10,-10,-10,10]));verify(g.setBounds([-5,5,-5,5]));g.selected=2;g.traceX=0;tap('traceRight');verify(g.traceX>0);g.table=true;wait(20);g.table=false;}
        function test_layout_data(){return [{tag:'tablet',w:1404,h:1872},{tag:'small',w:800,h:1024},{tag:'wide',w:1872,h:1404}];}
        function test_layout(d){scene.width=d.w;scene.height=d.h;wait(30);['Desk','Science','Graph'].forEach(function(mode){scene.app.mode=mode;wait(20);var k=findChild(scene.app,mode==='Desk'?'deskKey24':mode==='Science'?'calcKey=':'graphKey34');verify(k.visible,mode);var p=k.mapToItem(scene,0,k.height);verify(p.y<=scene.height+1,mode+' bottom '+p.y);verify(k.width>0&&k.height>0);});scene.width=1404;scene.height=1872;}
        function test_z_preview(){scene.width=1404;scene.height=1872;scene.app.mode='Desk';scene.app.officeKey('MC');scene.app.officeKey('AC');'29.95+14.50+8.20+45.90+22.40='.split('').forEach(function(k){scene.app.officeKey(k);});wait(120);var done=false;scene.app.grabToImage(function(r){verify(r.saveToFile(Qt.resolvedUrl("../../work/papercalc-desk.png").toString().replace("file://", "")));done=true;});tryVerify(function(){return done;});scene.app.mode='Graph';var g=findChild(scene.app,'calcGraphPanel');g.formulas=['x^2-4','sin(x)',''];g.enabledCurves=[true,true,false];g.selected=0;g.setBounds([-5,5,-5,5]);g.traceX=2;g.draw();wait(50);done=false;scene.app.grabToImage(function(r){verify(r.saveToFile(Qt.resolvedUrl("../../work/papercalc-graph.png").toString().replace("file://", "")));done=true;});tryVerify(function(){return done;});}
    }
}
