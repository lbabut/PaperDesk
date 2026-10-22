import QtQuick 2.15
import QtQuick.Layouts 1.15
import Qt.labs.settings 1.1
import net.asivery.ApploadUtils
import net.asivery.AppLoad 1.0

Rectangle {
    id: panel
    objectName: "webNativeDownload"
    anchors.fill: parent
    color: "white"
    visible: phase !== "idle"
    z: 100
    signal closeWeb()
    property string phase: "idle"
    property string url: ""
    property string title: ""
    property string message: ""
    property var job: null
    property var bridge: null
    property var pollRequest: null
    property bool disposed: false
    property var launchWorker: function(args) { AppLoadLauncher.launchApplication("external::paperweb-download",args,{},false) }
    property var requestFactory: function() { return new XMLHttpRequest() }
    readonly property bool busy: phase === "downloading" || phase === "importing"
    Settings {
        id: saved
        category: "PaperWebDownload"
        property string uncertainToken: ""
        property string uncertainUrl: ""
    }
    function syncSaved(){if(typeof saved.sync==="function")saved.sync()}
    function stopPoll(){if(pollRequest){pollRequest.onreadystatechange=null;pollRequest.abort();pollRequest=null}}
    function nativeImporter() {
        if(bridge && bridge.importer)return bridge.importer
        try {
            bridge=Qt.createQmlObject('import QtQml; import xofm.libs.library; QtObject { property var importer: DocumentImporter; property var lib: Library }',panel,"PaperWebNativeBridge")
            if(bridge.importer && typeof bridge.importer.importFromUrls === "function")return bridge.importer
            bridge.destroy();bridge=null
        }catch(e){}
        return null
    }
    function offer(value, name, size) {
        if(disposed || busy)return false
        url=String(value).replace(/^https:\/\//i,"https://").split("#")[0];title=String(name||"PaperWeb document")
        if(!/^https:\/\//i.test(url)){phase="error";message="Downloads require a secure HTTPS link.";return false}
        if(Number(size)>67108864){phase="error";message="This file exceeds the 64 MB safety limit. Nothing was downloaded.";return false}
        if(saved.uncertainToken && saved.uncertainUrl===url){phase="uncertain";message="An earlier import may already be in My files. Check there before downloading again.";return false}
        phase="offered"
        message="Add this PDF or EPUB to My files? Maximum: 64 MB. The tablet must have at least 576 MB free. Files are checked before native import."
        return true
    }
    function start() {
        if(phase!=="offered" || disposed)return
        if(!nativeImporter()){phase="error";message="Native PDF/EPUB import is unavailable on this firmware.";return}
        var token=Date.now().toString(36)+"-"+Math.floor(Math.random()*0x7fffffff).toString(36)
        job={token:token,started:Date.now(),path:"",candidates:[],reported:false}
        phase="downloading";message="Checking free space and downloading…"
        try { launchWorker([token,url,title]) }
        catch(e){console.log("PaperWeb download worker start failed",String(e));job=null;phase="error";message="The download worker could not start."}
    }
    function forgetUncertain(){saved.uncertainToken="";saved.uncertainUrl="";syncSaved();phase="idle"}
    function cancel() {
        if(phase==="importing")return
        stopPoll()
        if(job){try{launchWorker(["--cancel",job.token])}catch(e){};job=null}
        phase="idle"
    }
    function shutdown() {
        if(disposed)return
        disposed=true
        if(job && !job.path){try{launchWorker(["--cancel",job.token])}catch(e){}}
        stopPoll()
        job=null
    }
    function poll() {
        if(!job || disposed)return
        if(Date.now()-job.started>300000){
            var importing=!!job.path
            if(!importing)launchWorker(["--cancel",job.token])
            job=null;phase=importing?"uncertain":"error"
            message=importing?"Import is taking longer than expected. Check My files before trying again.":"Download timed out. No document was imported."
            return
        }
        if(job.path || pollRequest)return
        var token=job.token,xhr=requestFactory();pollRequest=xhr
        xhr.onreadystatechange=function(){
            if(xhr.readyState!==XMLHttpRequest.DONE)return
            xhr.onreadystatechange=null
            if(pollRequest!==xhr)return
            pollRequest=null
            if(disposed || !job || job.token!==token)return
            try{receiveStatus(JSON.parse(xhr.responseText))}catch(e){}
        }
        xhr.open("GET","file:///home/root/.local/share/paperdesk/web-inbox/"+token+"/status.json",true);xhr.send()
    }
    function receiveStatus(result) {
        if(!job || job.path || disposed)return
        if(result.state==="downloading"){if(result.message && message!==result.message)message=String(result.message);return}
        if(result.state==="error"){
            var token=job.token;job=null;phase="error";message=String(result.message||"Download failed. Nothing was imported.")
            launchWorker(["--clean",token]);return
        }
        if(result.state!=="ready")return
        var prefix="/home/root/.local/share/paperdesk/web-inbox/"+job.token+"/",path=String(result.path||""),name=path.slice(prefix.length)
        if(path.indexOf(prefix)!==0 || !name || name.indexOf("/")>=0 || name.indexOf("\\")>=0 || /[\x00-\x1f]/.test(name) || !/\.(pdf|epub)$/.test(name)){
            var invalidToken=job.token;job=null;phase="error";message="The downloader returned an invalid file path. Nothing was imported."
            launchWorker(["--clean",invalidToken]);return
        }
        job.path=path;saved.uncertainToken=job.token;saved.uncertainUrl=url;syncSaved()
        phase="importing";message="Adding the document to My files. Please wait…"
        try{nativeImporter().importFromUrls(["file://"+path.split("/").map(encodeURIComponent).join("/")],"")}
        catch(e){job=null;phase="uncertain";message="The import could not be confirmed. Check My files before retrying."}
    }
    function imported(document, collection, source) {
        if(!job || !job.path || !source || decodeURIComponent(String(source))!=="file://"+job.path)return
        job.reported=true
        var id=document && document.id ? String(document.id).replace(/^\{|\}$/g,""):""
        if(/^[0-9a-fA-F-]{36}$/.test(id))finishImport();else resolveImport()
    }
    function entryAdded(entryId) {
        if(!job || !job.path || !bridge)return
        var id=String(entryId).replace(/^\{|\}$/g,""),entry=bridge.lib.entryForId(id)
        var expected=job.path.slice(job.path.lastIndexOf("/")+1).replace(/\.(pdf|epub)$/i,"")
        if(!entry || entry.visibleName!==expected)return
        if(job.candidates.indexOf(id)<0)job.candidates.push(id)
        resolveImport()
    }
    function resolveImport(){if(job && job.reported && job.candidates.length===1)finishImport()}
    function finishImport() {
        var token=job.token;job=null;saved.uncertainToken="";saved.uncertainUrl="";syncSaved()
        phase="done";message="Added to My files. Close Web and AppLoad, then tap the document to use the built-in reader."
        console.log("PaperWeb native import completed");launchWorker(["--clean",token])
    }
    Timer {interval:1000;repeat:true;running:panel.job!==null;onTriggered:panel.poll()}
    Connections {
        target:panel.bridge?panel.bridge.importer:null
        ignoreUnknownSignals:true
        function onImported(document,collection,source){panel.imported(document,collection,source)}
        function onFailed(source){
            if(!panel.job || !panel.job.path || !source || decodeURIComponent(String(source))!=="file://"+panel.job.path)return
            var token=panel.job.token;panel.job=null;panel.phase="error";panel.message="The native reader rejected this file. No existing document was replaced."
            saved.uncertainToken="";saved.uncertainUrl="";panel.syncSaved();panel.launchWorker(["--clean",token])
        }
    }
    Connections {
        target:panel.bridge?panel.bridge.lib:null
        ignoreUnknownSignals:true
        function onEntryAdded(entryId){panel.entryAdded(entryId)}
        function onEntryImported(entryId,visibleName,errorMessage){if(!errorMessage)panel.entryAdded(entryId)}
    }
    MouseArea {anchors.fill:parent}
    Rectangle {
        anchors.centerIn:parent;width:Math.min(parent.width-48,1120);height:content.implicitHeight+64
        border.color:"black";border.width:3;radius:8;color:"white"
        ColumnLayout {
            id:content;anchors.fill:parent;anchors.margins:32;spacing:24
            Text {text:panel.phase==="done"?"Saved to My files":"Download document";font.pointSize:25;font.bold:true;color:"black";Layout.fillWidth:true;wrapMode:Text.Wrap}
            Text {text:panel.title;textFormat:Text.PlainText;font.pointSize:19;font.bold:true;color:"black";Layout.fillWidth:true;wrapMode:Text.Wrap;maximumLineCount:3;elide:Text.ElideRight}
            Text {text:panel.url;textFormat:Text.PlainText;font.pointSize:14;color:"black";Layout.fillWidth:true;wrapMode:Text.WrapAnywhere;maximumLineCount:3;elide:Text.ElideRight}
            Text {objectName:"webDownloadMessage";text:panel.message;textFormat:Text.PlainText;font.pointSize:19;color:"black";Layout.fillWidth:true;wrapMode:Text.Wrap}
            RowLayout {
                Layout.fillWidth:true;spacing:20
                Rectangle {
                    objectName:"webDownloadCancelButton";Layout.fillWidth:true;implicitHeight:80;radius:8;border.width:2;border.color:"black";color:"white";visible:panel.phase!=="importing"
                    Text {anchors.centerIn:parent;text:panel.phase==="offered"||panel.phase==="downloading"?"Cancel":"Back to Web";font.pointSize:17;font.bold:true;color:"black"}
                    TapHandler {onTapped:panel.cancel()}
                }
                Rectangle {
                    objectName:"webDownloadConfirmButton";Layout.fillWidth:true;implicitHeight:80;radius:8;color:"black";visible:panel.phase==="offered"||panel.phase==="done"||panel.phase==="uncertain"
                    Text {anchors.centerIn:parent;text:panel.phase==="offered"?"Save to My files":panel.phase==="done"?"Close Web":"Checked My files";font.pointSize:17;font.bold:true;color:"white"}
                    TapHandler {onTapped:panel.phase==="offered"?panel.start():panel.phase==="done"?panel.closeWeb():panel.forgetUncertain()}
                }
            }
        }
    }
    Component.onDestruction:shutdown()
}
