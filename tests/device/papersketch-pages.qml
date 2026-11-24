import QtQuick 2.15
Rectangle {
    id:bench; anchors.fill:parent; color:"white"; signal close
    property int phase:0
    property int checked:0
    property var digests:[]
    property var result:({real_device:true,created:0,reloaded:0,passed:false})
    function require(ok,message){if(!ok)throw Error(message);}
    function done(error){
        if(error)result.error=String(error);
        result.passed=!error && result.created===14 && result.reloaded===14 && result.appended && result.deleted;
        ticker.stop();phase=99;
        console.log("PAPERSKETCH_NATIVE_RESULT "+JSON.stringify({execution:"isolated native 14-page save, reload, append and delete; no physical input",pages_probe:result,cases:[]}));
    }
    function step(){
        if(phase===2){subject.active=true;phase=3;return;}
        var a=subject.item;if(!a || !a.ready || a.replaying || a.painting)return;
        try{
            require(!a.saveBlocked,"Save blocked");
            if(phase===0){a.confirmation="book";a.confirmAction();phase=1;return;}
            if(phase===1){
                require(a.pageIndex===result.created,"New page did not advance");
                a.tool=1;a.brushSize=5;a.strength=.8;
                var x=180+result.created*12;
                a.beginStroke(Qt.point(x,300),"pen",1,.7);
                a.extendStroke(Qt.point(x+25,330),"pen",.8);a.finishStroke();
                require(a.saveBook(),"Page save failed");
                digests.push(a.nativeRaster.opticalDigest());result.created++;
                if(result.created<14){a.newPage();return;}
                require(a.pageCount===14,"Expected 14 pages before reopen");
                subject.active=false;phase=2;return;
            }
            if(phase===3){
                require(a.pageCount===14,"Reopen lost pages");
                a.selectPage(checked);phase=4;return;
            }
            if(phase===4){
                require(a.pageIndex===checked && a.page.cacheSlot===checked,"Page identity changed");
                require(a.nativeRaster.opticalDigest()===digests[checked],"Drawing changed after reopen");
                checked++;result.reloaded=checked;
                if(checked<14){phase=3;return;}
                a.newPage();require(a.pageCount===15 && a.page.cacheSlot===14,"Append after reopen failed");
                require(a.saveBook(),"Appended page save failed");result.appended=true;
                a.selectPage(5);phase=5;return;
            }
            if(phase===5){
                a.confirmation="delete";a.confirmAction();
                require(a.pageCount===14 && a.page.cacheSlot===6,"Delete changed surviving identity");
                require(a.nativeRaster.opticalDigest()===digests[6],"Delete changed surviving image");
                require(a.saveBook(),"Deletion save failed");result.deleted=true;done("");
            }
        }catch(error){done(error);}
    }
    Loader{id:subject;anchors.fill:parent;source:"baseline/ui/main.qml"}
    Timer{id:ticker;interval:80;repeat:true;running:true;onTriggered:bench.step()}
}
