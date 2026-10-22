const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../product/payload/apps/literm/ui/main.qml'), 'utf8');
const method = source.slice(source.indexOf('    function openSavedSession('), source.indexOf('    function cancelSessionOpening('));
function runtime(state, status=0) {
    const writes = [], requests = [];
    function XHR() { requests.push(this); }
    XHR.DONE = 4;
    XHR.prototype.open = function(method,url) { this.url=url; };
    XHR.prototype.send = function() {};
    const root = {sessionOpening:false, disposed:false, sessionStateRequest:null,
        sessionsPanel:{valid(){return true},visible:true,message:''},
        terminal:{putString(value){writes.push(value)}},
        sessionOpenTimeout:{restart(){},stop(){}},
        showSystemKeyboard(){},XMLHttpRequest:XHR,console:{log(){}},writes,requests};
    root.root=root;vm.createContext(root);vm.runInContext(method,root);
    root.openSavedSession('server.example','tester','22');
    root.respond = function() {
        const r = requests[0];r.readyState=4;r.status=status;r.responseText=state;r.onreadystatechange();
    };
    return root;
}
for(const state of ['busy 123','ready','ready x','','not-ready 123','ready 123\nextra']) {
    const root = runtime(state);root.respond();
    assert.deepEqual(root.writes,[],'Never type a launcher command into a busy or unknown terminal');
    assert.equal(root.sessionsPanel.visible,true);
}
const ready = runtime('ready 123\n');ready.respond();
assert.deepEqual(ready.writes,['c server.example tester 22\n']);
assert.equal(ready.sessionsPanel.visible,false);
const closed = runtime('closed 123');closed.respond();
assert.deepEqual(closed.writes,['\nc server.example tester 22\n']);
const missing = runtime('ready 123',404);missing.respond();assert.deepEqual(missing.writes,[]);
const disposed = runtime('ready 123');disposed.disposed=true;disposed.respond();assert.deepEqual(disposed.writes,[]);
const double = runtime('ready 123');double.openSavedSession('other','tester','22');
assert.equal(double.requests.length,1);double.respond();assert.equal(double.writes.length,1);
console.log('SSH session protocol: ready/closed only, active-session guard, stale response and double-open rejection OK');
