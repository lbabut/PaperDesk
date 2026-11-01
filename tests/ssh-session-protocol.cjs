const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../product/payload/apps/paperterminal/ui/main.qml'), 'utf8');
const method = source.slice(source.indexOf('    function openSavedSession('), source.indexOf('    function calculateKeyboardInset('));
function runtime(accepted, valid=true, credentialId='',replacementToken='') {
    const connections = [];
    const root = {disposed:false,
        sessionsPanel:{valid(){return valid},visible:true,message:'',showMessage(message){this.message=message},
            beginReplacement(...args){this.replacementArgs=args}},
        terminalHome:{message:''},
        terminal:{replacementToken,running:true,sessionError:'Busy local launcher',error:'Retained runtime diagnostic',clearModifiers(){},connectTo(...args){connections.push(args);return accepted},
            connectReplacing(...args){this.replacementArgs=args;return this.replacementAccepted}},
        Qt:{inputMethod:{hide(){}},callLater(callback){callback()}},
        showSystemKeyboard(){this.keyboardShown=true},console:{log(){}},connections};
    root.root=root;vm.createContext(root);vm.runInContext(method,root);
    root.openSavedSession('server.example','tester','22',credentialId);
    return root;
}
const ready=runtime(true);
assert.deepEqual(ready.connections,[['server.example','tester','22','']]);
assert.equal(ready.sessionsPanel.visible,false);
assert.equal(ready.keyboardShown,true);
const busy=runtime(false);
assert.equal(busy.sessionsPanel.visible,true);
assert.equal(busy.sessionsPanel.message,'Busy local launcher');
assert.equal(busy.terminalHome.message,'Busy local launcher');
assert.equal(busy.terminal.error,'Retained runtime diagnostic');
assert.equal(busy.sessionsPanel.replacementArgs,undefined);
const replace=runtime(false,true,'profile-id','lease-42');
assert.deepEqual(replace.sessionsPanel.replacementArgs,['server.example','tester','22','profile-id','lease-42']);
replace.terminal.replacementAccepted=true;
replace.openReplacingSession('second.example','second','2202','second-profile','lease-42');
assert.deepEqual(replace.terminal.replacementArgs,['second.example','second','2202','second-profile','lease-42']);
assert.equal(replace.sessionsPanel.visible,false);
const stale=runtime(false,true,'profile-id','lease-old');
stale.terminal.replacementAccepted=false;stale.terminal.sessionError='Active session changed';
stale.openReplacingSession('second.example','second','2202','second-profile','lease-old');
assert.equal(stale.sessionsPanel.visible,true);
assert.equal(stale.sessionsPanel.message,'Active session changed');
const homeRace=runtime(false);homeRace.sessionsPanel.visible=false;
homeRace.openSavedSession('second.example','second','2202','');
assert.equal(homeRace.sessionsPanel.visible,true);
const invalid=runtime(true,false);
assert.equal(invalid.connections.length,0);
assert.equal(invalid.sessionsPanel.visible,true);
const remembered=runtime(true,true,'00000000-0000-4000-8000-000000000001');
assert.deepEqual(remembered.connections,[['server.example','tester','22','00000000-0000-4000-8000-000000000001']]);
assert.ok(!method.includes('putString('));
assert.ok(!method.includes('XMLHttpRequest'));
const shortcutMethod=source.slice(source.indexOf('    function sendShortcut('),source.indexOf('    function setAnsiColors('));
for (const visible of [false,true]) {
    let inputFocus=0,terminalFocus=0,keyboardShows=0;
    const sent=[];
    const context={console:{log(){}},Qt:{inputMethod:{visible,show(){keyboardShows++}}},
        terminal:{vkbKeyPress(...args){sent.push(args)},forceActiveFocus(){terminalFocus++}},
        systemInput:{forceActiveFocus(){inputFocus++}},showSystemKeyboard(){throw new Error('Shortcut must preserve keyboard visibility')}};
    vm.createContext(context);vm.runInContext(shortcutMethod,context);
    context.sendShortcut(0x01000034,0);
    assert.deepEqual(sent,[[0x01000034,0]]);
    assert.equal(keyboardShows,0);
    assert.equal(context.Qt.inputMethod.visible,visible);
    assert.equal(inputFocus,visible?1:0);
    assert.equal(terminalFocus,visible?0:1);
}
console.log('Terminal saved sessions: native argument-vector connect, active-session refusal and validation OK');

// Exercise the exact Home number parser against an immediate mode switch.
// The entire paste belongs to Home, including its suffix after the first Enter.
const homeSource = fs.readFileSync(path.join(__dirname, '../product/payload/apps/paperterminal/ui/Home.qml'), 'utf8');
const homeMethods = homeSource.slice(homeSource.indexOf('    function resetInput('), homeSource.indexOf('    onVisibleChanged:'));
function homeRuntime(count=32) {
    const home={visible:true,count,numberInput:'',invalidInput:false,message:'',opened:[],
        openRequested(index){home.opened.push(index);home.visible=false}};
    home.home=home;vm.createContext(home);vm.runInContext(homeMethods,home);return home;
}
const pasted=homeRuntime();pasted.handleInput('1\rmalicious remote suffix\r');
assert.deepEqual(pasted.opened,[0]);assert.equal(pasted.numberInput,'');
assert.equal(pasted.requestOpen(1),false);assert.deepEqual(pasted.opened,[0]);
const edited=homeRuntime();edited.handleInput('12');edited.handleInput('\x7f\r');assert.deepEqual(edited.opened,[0]);
const last=homeRuntime();last.handleInput('32\r');assert.deepEqual(last.opened,[31]);
for(const input of ['0\r','33\r','9999\r','l\r','1;command\r','\x1b[3~','\x1b[12~']) {
    const home=homeRuntime();home.handleInput(input);assert.deepEqual(home.opened,[],input);
}
const hidden=homeRuntime();hidden.visible=false;hidden.handleInput('1\r');assert.deepEqual(hidden.opened,[]);
const empty=homeRuntime(0);empty.handleInput('1\r');assert.deepEqual(empty.opened,[]);assert.ok(empty.message.includes('No saved'));
console.log('Terminal Home: numbered profiles, whole-packet consumption, late clicks, escape parameters and bounds OK');
