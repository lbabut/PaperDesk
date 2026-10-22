import QtQuick 2.15
import QtTest 1.3
import net.asivery.AppLoad 1.0

Item {
    id:scene
    width:1404;height:1872
    property var app:null
    property var calls:[]
    property var importedUrls:[]
    property var defaultWorker:null
    QtObject {
        id:fakeImporter
        signal imported(var document,var collection,var source)
        signal failed(var source)
        function importFromUrls(urls,folder){scene.importedUrls=urls}
    }
    QtObject {
        id:fakeLibrary
        signal entryAdded(var entryId)
        signal entryImported(var entryId,var visibleName,var errorMessage)
        function entryForId(id){return {visibleName:"test"}}
    }
    QtObject {id:bridge;property var importer:fakeImporter;property var lib:fakeLibrary}
    TestCase {
        name:"WebNativeDownloads";when:windowShown
        function init(){
            var c=Qt.createComponent("../../product/payload/apps/paperweb/ui/main.qml")
            compare(c.status,Component.Ready,c.errorString());scene.app=c.createObject(scene)
            verify(scene.app!==null);scene.calls=[];scene.importedUrls=[]
            scene.defaultWorker=scene.app.downloadPanel.launchWorker
            scene.app.downloadPanel.bridge=bridge
            scene.app.downloadPanel.launchWorker=function(args){scene.calls.push(args)}
            scene.app.downloadPanel.requestFactory=function(){return {open:function(){},send:function(){},abort:function(){}}}
            waitForRendering(scene.app)
        }
        function cleanup(){scene.app.downloadPanel.forgetUncertain();scene.app.destroy();scene.app=null}
        function tap(name){wait(50);var b=findChild(scene.app,name);verify(b!==null&&b.visible);mouseClick(b,b.width/2,b.height/2,Qt.LeftButton)}
        function offer(){scene.app.navigate("https://example.com/test.pdf",true);compare(scene.app.downloadPanel.phase,"offered")}
        function test_offer_cancel_never_starts_transfer(){offer();tap("webDownloadCancelButton");compare(scene.calls.length,0);compare(scene.app.downloadPanel.phase,"idle")}
        function test_confirm_and_cancel_transfer(){offer();tap("webDownloadConfirmButton");compare(scene.calls.length,1);compare(scene.app.downloadPanel.phase,"downloading");tap("webDownloadCancelButton");compare(scene.calls[1][0],"--cancel");compare(scene.app.downloadPanel.phase,"idle")}
        function test_default_appload_launcher_binding(){
            AppLoadLauncher.reset();scene.app.downloadPanel.launchWorker=scene.defaultWorker
            offer();tap("webDownloadConfirmButton");compare(scene.app.downloadPanel.phase,"downloading")
            compare(AppLoadLauncher.lastApplicationId,"external::paperweb-download");compare(AppLoadLauncher.launchCount,1)
            tap("webDownloadCancelButton");compare(AppLoadLauncher.lastArgs[0],"--cancel")
        }
        function test_size_and_protocol_errors_before_worker(){
            verify(!scene.app.downloadPanel.offer("https://example.com/a.pdf","a",67108865));compare(scene.app.downloadPanel.phase,"error");compare(scene.calls.length,0)
            verify(!scene.app.downloadPanel.offer("http://example.com/a.pdf","a",10));compare(scene.calls.length,0)
            verify(scene.app.downloadPanel.offer("HTTPS://example.com/a.pdf#page=5","a",10));compare(scene.app.downloadPanel.url,"https://example.com/a.pdf")
        }
        function test_native_completion_matches_source_and_library_wrapper(){
            offer();tap("webDownloadConfirmButton")
            var p=scene.app.downloadPanel,path="/home/root/.local/share/paperdesk/web-inbox/"+p.job.token+"/test.pdf"
            p.receiveStatus({state:"ready",path:path});compare(p.phase,"importing");compare(scene.importedUrls.length,1)
            fakeImporter.imported({},"","file:///another.pdf");compare(p.phase,"importing")
            fakeLibrary.entryAdded("12345678-1234-1234-1234-123456789abc");compare(p.phase,"importing")
            fakeImporter.imported({},"","file://"+path);compare(p.phase,"done");compare(scene.calls[1][0],"--clean")
        }
        function test_unsafe_worker_path_is_never_imported(){
            offer();tap("webDownloadConfirmButton");scene.app.downloadPanel.receiveStatus({state:"ready",path:"/etc/passwd.pdf"});compare(scene.app.downloadPanel.phase,"error");compare(scene.importedUrls.length,0)
        }
        function test_close_cancels_transfer_only_once(){
            offer();tap("webDownloadConfirmButton");scene.app.unloading();scene.app.unloading();compare(scene.calls.length,2);compare(scene.calls[1][0],"--cancel")
        }
        function test_unknown_attachment_and_oversize_headers(){
            scene.app.offerFileDownload("https://example.com/get",{getResponseHeader:function(n){return n==="Content-Type"?"application/pdf":n==="Content-Length"?"999999999":"attachment; filename=test.pdf"}})
            compare(scene.app.downloadPanel.phase,"error");compare(scene.calls.length,0)
        }
        function test_binary_headers_abort_only_after_callback_and_never_read_body(){
            var callbackActive=false,readBody=false,aborted=false,abortedInside=false
            var xhr={readyState:0,responseURL:"https://example.com/get",status:200,
                open:function(){},setRequestHeader:function(){},
                getResponseHeader:function(name){return name==="Content-Type"?"application/pdf":name==="Content-Length"?"12345":"attachment; filename=test.pdf"},
                send:function(){callbackActive=true;this.readyState=2;this.onreadystatechange();callbackActive=false},
                abort:function(){aborted=true;abortedInside=callbackActive}}
            Object.defineProperty(xhr,"responseText",{get:function(){readBody=true;throw new Error("Must not read binary body")}})
            scene.app.requestFactory=function(){return xhr}
            scene.app.navigate("https://example.com/get",true)
            verify(!aborted);verify(!readBody)
            tryCompare(scene.app.downloadPanel,"phase","offered")
            verify(aborted);verify(!abortedInside);verify(!readBody);compare(scene.calls.length,0)
        }
    }
}
