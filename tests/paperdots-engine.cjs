const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../product/payload/apps/paperdots/game.js'), 'utf8');
const game = new Function(source + '\nreturn {newGame, play, legal, score, capture, active, chooseMove, undoRound, restore, serialize, controller, isComputer, checkpoint, restoreCheckpoint, cacheHash};')();
let passed = 0;
function test(name, run) { run(); ++passed; console.log('PASS ' + name); }
function at(s, x, y) { return y * s.width + x; }
function put(s, player, dots) { dots.forEach(([x, y]) => { s.board[at(s, x, y)] = player; }); return s; }
function diamond() {
    const s = game.newGame(7, 7, 'tactical');
    put(s, 1, [[3, 2], [4, 3], [3, 4]]);
    put(s, 2, [[3, 3]]);
    return s;
}
test('diagonal ring captures, closes and retains dots', () => {
    const initial = diamond(), s = game.play(initial, at(initial, 2, 3));
    assert.equal(game.score(s).player1, 1);
    assert.equal(s.board[at(s, 3, 3)], 2);
    assert.equal(s.territory[at(s, 3, 3)], 1);
    assert.equal(game.legal(s, at(s, 3, 3)), false);
    assert.equal(s.bases.length, 1);
    assert.equal(s.bases[0].edges.length, 4);
    assert.equal(initial.board[at(initial, 2, 3)], 0, 'simulation cannot mutate input');
});
test('empty ring stays playable; entering it is captured', () => {
    const s = game.newGame(7, 7, 'tactical');
    put(s, 1, [[3, 2], [4, 3], [3, 4], [2, 3]]);
    game.capture(s, 1, true);
    assert.equal(s.bases.length, 0);
    assert.equal(game.legal(s, at(s, 3, 3)), true);
    s.turn = 2;
    const next = game.play(s, at(s, 3, 3));
    assert.equal(game.score(next).player1, 1);
});
test('board edge never completes an open base', () => {
    const s = game.newGame(7, 7, 'tactical');
    put(s, 1, [[0, 1], [1, 1], [2, 1], [2, 2], [2, 3], [1, 3], [0, 3]]);
    put(s, 2, [[0, 2], [1, 2]]);
    game.capture(s, 1, true);
    assert.equal(game.score(s).player1, 0);
    assert.equal(s.bases.length, 0);
});
test('captured dots cannot form an interlocking base', () => {
    const s = diamond();
    s.territory[at(s, 3, 2)] = 2;
    const next = game.play(s, at(s, 2, 3));
    assert.equal(game.score(next).player1, 0);
});
test('capturing a base releases friendly dots and transfers score', () => {
    const s = game.newGame(7, 7, 'tactical');
    put(s, 2, [[3, 2], [4, 3], [3, 4], [2, 3]]);
    put(s, 1, [[3, 3]]);
    game.capture(s, 2, true);
    assert.equal(game.score(s).player2, 1);
    for (let x = 1; x <= 5; ++x) put(s, 1, [[x, 1], [x, 5]]);
    for (let y = 2; y <= 4; ++y) put(s, 1, [[5, y]]);
    put(s, 1, [[1, 2], [1, 4]]);
    const next = game.play(s, at(s, 1, 3));
    assert.equal(game.score(next).player1, 4);
    assert.equal(game.score(next).player2, 0);
    assert.equal(game.active(next, at(next, 3, 3), 1), true);
});
test('base blocks empty interior intersections without adding empty bases', () => {
    const s = game.newGame(9, 9, 'tactical');
    for (let x = 2; x <= 6; ++x) put(s, 1, [[x, 2], [x, 6]]);
    for (let y = 3; y <= 5; ++y) put(s, 1, [[2, y], [6, y]]);
    put(s, 2, [[4, 4]]);
    game.capture(s, 1, true);
    assert.equal(game.legal(s, at(s, 3, 4)), false);
    const count = s.bases.length;
    game.capture(s, 1, true);
    assert.equal(s.bases.length, count);
    assert.equal(game.score(s).player1, 1, 'capture cannot be counted twice');
});
test('AI chooses an immediate capture', () => {
    const s = diamond();
    s.board = s.board.map(v => v ? 3 - v : 0);
    s.turn = 2;
    assert.equal(game.chooseMove(s), at(s, 2, 3));
});
test('AI blocks a one-move enemy capture', () => {
    const s = diamond();
    s.turn = 2;
    assert.equal(game.chooseMove(s), at(s, 2, 3));
});
test('round undo, pending reply undo and save restore', () => {
    let s = game.newGame(15, 19, 'tactical');
    s = game.play(s, at(s, 7, 9));
    assert.equal(game.undoRound(s).moves.length, 0);
    s = game.play(s, game.chooseMove(s));
    assert.equal(game.undoRound(s).moves.length, 0);
    const restored = game.restore(game.serialize(s));
    assert.equal(game.serialize(restored), game.serialize(s));
    s.paused = true;
    assert.equal(game.restore(game.serialize(s)).paused, true);
});
test('invalid persisted games and illegal moves fail safely', () => {
    const s = game.newGame(15, 19, 'relaxed');
    assert.equal(game.restore('{broken'), null);
    assert.equal(game.restore(JSON.stringify({ version: 1, width: 3000, height: 3000, moves: [] })), null);
    assert.equal(game.restore(JSON.stringify({ version: 1, width: 15, height: 19, moves: [10, 10] })), null);
    for (const index of [-1, 285, 0.5, null, '0', NaN]) assert.equal(game.play(s, index), null);
});
test('full board ends naturally and no computer move is requested', () => {
    let s = game.newGame(2, 2, 'tactical');
    [0, 1, 2, 3].forEach(i => { s = game.play(s, i); });
    assert.equal(s.finished, true);
    assert.equal(game.chooseMove(s), -1);
});
test('bounded AI self-play, reproducible save and legal moves', () => {
    let s = game.newGame(19, 23, 'tactical');
    const started = Date.now();
    for (let round = 0; round < 90 && !s.finished; ++round) {
        const index = game.chooseMove(s);
        assert.equal(game.legal(s, index), true);
        s = game.play(s, index);
    }
    const restored = game.restore(game.serialize(s));
    assert.equal(game.serialize(restored), game.serialize(s));
    assert.equal(JSON.stringify(restored.territory), JSON.stringify(s.territory));
    assert.equal(JSON.stringify(game.score(restored)), JSON.stringify(game.score(s)));
    assert.ok(Date.now() - started < 20000, 'search must stay bounded');
    console.log('90-ply tactical self-play: ' + (Date.now() - started) + ' ms');
});
test('all four player assignments survive save and replay', () => {
    for (const p1 of ['human', 'computer']) for (const p2 of ['human', 'computer']) {
        let s = game.newGame(29, 33, 'relaxed', p1, p2);
        assert.equal(game.controller(s, 1), p1);
        assert.equal(game.controller(s, 2), p2);
        assert.equal(game.isComputer(s), p1 === 'computer');
        s = game.play(s, 400);
        assert.equal(game.isComputer(s), p2 === 'computer');
        const restored = game.restore(game.serialize(s));
        assert.equal(game.serialize(restored), game.serialize(s));
    }
});
test('human-human and computer-computer undo one move, simulations stay paused', () => {
    for (const kind of ['human', 'computer']) {
        let s = game.newGame(19, 23, 'relaxed', kind, kind);
        s = game.play(game.play(s, 200), 201);
        const undone = game.undoRound(s);
        assert.equal(undone.moves.length, 1);
        assert.equal(undone.turn, 2);
        assert.equal(undone.paused, kind === 'computer');
        assert.equal(game.controller(undone, 1), kind);
        assert.equal(game.restore(game.serialize(undone)).paused, kind === 'computer');
    }
});
test('computer-first opening can be undone without being instantly repeated', () => {
    let s = game.newGame(19, 23, 'tactical', 'computer', 'human');
    s = game.play(s, game.chooseMove(s));
    let undone = game.undoRound(s);
    assert.equal(undone.moves.length, 0);
    assert.equal(undone.paused, true);
    s = game.play(s, 300);
    undone = game.undoRound(s);
    assert.equal(undone.moves.length, 1);
    assert.equal(undone.turn, 2);
    assert.equal(undone.paused, false);
});
test('version 1 saved games retain moves and the default players', () => {
    const old = {version: 1, width: 19, height: 23, difficulty: 'tactical', moves: [200, 201], finished: true};
    const restored = game.restore(JSON.stringify(old));
    assert.equal(restored.moves.length, 2);
    assert.equal(game.controller(restored, 1), 'human');
    assert.equal(game.controller(restored, 2), 'computer');
    assert.equal(restored.finished, false);
    assert.equal(JSON.parse(game.serialize(restored)).version, 2);
    assert.equal(game.restore(JSON.stringify({...old, version: 2, players: ['human', 'robot']})), null);
});
test('large board self-play stays legal for either computer colour', () => {
    let s = game.newGame(29, 33, 'relaxed', 'computer', 'computer');
    const started = Date.now();
    for (let ply = 0; ply < 50 && !s.finished; ++ply) {
        const index = game.chooseMove(s);
        assert.equal(game.legal(s, index), true);
        s = game.play(s, index);
    }
    assert.equal(game.serialize(game.restore(game.serialize(s))), game.serialize(s));
    assert.ok(Date.now() - started < 20000);
});
test('checkpoint restores exact board, bases and scores without replay', () => {
    let state = game.newGame(29, 33, 'relaxed', 'human', 'human');
    for(let i=0;i<150;++i) state = game.play(state, i);
    const raw=game.serialize(state), cached=game.checkpoint(raw,state);
    assert.deepEqual(game.restoreCheckpoint(raw,cached),state);
    assert.equal(game.restoreCheckpoint(raw,cached.slice(0,-2)),null);
    assert.equal(game.restoreCheckpoint(raw.replace('relaxed','tactical'),cached),null);
    function corrupt(change) {
        const data=JSON.parse(cached), snapshot=JSON.parse(data.snapshot);
        change(snapshot);data.snapshot=JSON.stringify(snapshot);
        data.hash=game.cacheHash(raw+'|'+data.snapshot);
        assert.equal(game.restoreCheckpoint(raw,JSON.stringify(data)),null);
    }
    corrupt(s=>s.board[0]=2);
    corrupt(s=>s.territory[0]=4);
    corrupt(s=>s.turn=2);
    corrupt(s=>s.bases=[{player:1,fineWidth:61,cells:[999999],edges:[]}]);
    corrupt(s=>s.bases=[{player:1,fineWidth:61,cells:[1],edges:[[-1,8]]}]);
    assert.equal(game.restoreCheckpoint(raw,'x'.repeat(1000001)),null);
});
console.log(passed + ' engine scenarios passed');
