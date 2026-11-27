// Exercise the actual QML function from an explicitly supplied runtime source.
// No copy of unrelated shared QML code, network/device access or source writes.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
if(process.argv.length!==3)throw Error('Usage: node tests/rdp-keyboard-gap-inset.cjs PATH_TO_WINDOW_QML');
const source=fs.readFileSync(process.argv[2],'utf8');
const start=source.indexOf('    function calculateRdpKeyboardInset(');
const end=source.indexOf('    function sendRdpViewport(',start);
assert(start>=0&&end>start,'Expected runtime keyboard inset function');
let cases=0;
for(const [width,height] of [[1404,1872],[1872,1404]]){
 const context=vm.createContext({rdpNativeKeyboardPanel:null,rdpChrome:{width,height,mapFromItem(_null,x,y,width,height){return{x,y,width,height};}},isFinite});
 vm.runInContext(source.slice(start,end),context);
 const calc=(visible,r)=>context.calculateRdpKeyboardInset(visible,r);
 const rect=h=>({x:0,y:height-h,width,height:h});
 const check=(v,r,want)=>{assert(Math.abs(calc(v,r)-want)<1e-6);cases++;};
 check(false,rect(500),0);
 check(true,rect(300),300);check(true,rect(500),500);
 check(true,rect(720),720);
 check(true,{x:0,y:113,width,height:height-113},height-112-240);
 check(true,{x:0,y:0,width:0,height:0},height*.38);
 check(true,{x:0,y:112,width:width*.2,height:height-112},height*.38);
 check(true,{x:NaN,y:0,width,height},height*.38);
 context.rdpNativeKeyboardPanel={virtualKeyboard:{visible:true,width,height:544,mapToItem(){return{x:0,y:height-544,width,height:544};}}};
 check(true,{x:0,y:0,width,height:544},544);
 check(false,{x:0,y:0,width,height:544},0);
 context.rdpNativeKeyboardPanel.virtualKeyboard.visible=false;
 check(true,{x:0,y:0,width,height:544},height*.38);
}
console.log(`PASS ${cases} actual-function inset checks; valid short keyboards reclaim space, invalid geometry keeps fallback`);
