// Generate an isolated legacy move-only save; never read a user's save file.
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,'../product/payload/apps/paperdots/game.js'),'utf8');
const game = new Function(source+'\nreturn {newGame,play,legal,serialize};')();
let state = game.newGame(29,33,'relaxed','human','human');
while(state.moves.length < 431) {
    const index = state.board.findIndex((_,i)=>game.legal(state,i));
    if(index < 0) throw new Error('Fixture finished before 431 legal moves');
    state = game.play(state,index);
}
process.stdout.write(game.serialize(state));
