// PaperDesk Dots. Pure rules and bounded tactical search; no QML dependencies.
// A twice-resolution lattice keeps diagonal connections closed while a margin
// outside the board prevents its edges from being used as capture walls.
function newGame(width, height, difficulty, player1, player2) {
    var count = width * height
    var state = { version: 2, width: width, height: height, board: [], territory: [],
                  bases: [], moves: [], turn: 1, finished: false, paused: false,
                  players: [player1 === "computer" ? "computer" : "human",
                            player2 === "human" ? "human" : "computer"],
                  difficulty: difficulty === "relaxed" ? "relaxed" : "tactical" }
    for (var i = 0; i < count; ++i) { state.board.push(0); state.territory.push(0) }
    return state
}

function controller(state, player) {
    return state.players ? state.players[player - 1] : (player === 1 ? "human" : "computer")
}

function isComputer(state) {
    return !!state && !state.finished && controller(state, state.turn) === "computer"
}

function clone(state) {
    return { version: 2, width: state.width, height: state.height,
             board: state.board.slice(), territory: state.territory.slice(),
             bases: state.bases.slice(), moves: state.moves.slice(),
             turn: state.turn, finished: state.finished, paused: !!state.paused,
             players: [controller(state, 1), controller(state, 2)], difficulty: state.difficulty }
}

function legal(state, index) {
    return !state.finished && index >= 0 && index < state.board.length &&
            index === Math.floor(index) && !state.board[index] && !state.territory[index]
}

function active(state, index, player) {
    return state.board[index] === player && state.territory[index] !== 3 - player
}

function score(state) {
    var captured = [0, 0, 0]
    for (var i = 0; i < state.board.length; ++i)
        if (state.board[i] && state.territory[i] === 3 - state.board[i])
            ++captured[state.territory[i]]
    return { player1: captured[1], player2: captured[2],
             net: captured[1] - captured[2] }
}

function capture(state, player, keepDrawing) {
    var w = state.width, h = state.height
    var fw = 2 * w + 3, fh = 2 * h + 3, length = fw * fh
    var walls = new Uint8Array(length), labels = new Int32Array(length)
    var queue = new Int32Array(length), edges = [], i, x, y, j, p, q, activeCount = 0
    var directions = [[1, 0], [0, 1], [1, 1], [-1, 1]]
    for (i = 0; i < state.board.length; ++i) {
        if (!active(state, i, player)) continue
        ++activeCount
        x = i % w; y = Math.floor(i / w)
        p = (2 * y + 2) * fw + 2 * x + 2
        walls[p] = 1
        for (j = 0; j < directions.length; ++j) {
            var dx = directions[j][0], dy = directions[j][1]
            if (x + dx < 0 || x + dx >= w || y + dy >= h) continue
            q = (y + dy) * w + x + dx
            if (!active(state, q, player)) continue
            var midpoint = p + dy * fw + dx
            walls[midpoint] = 1
            if (keepDrawing) edges.push({ a: i, b: q, middle: midpoint })
        }
    }
    if (activeCount < 4) return
    // Each component of the complement is a face. Only closed faces containing
    // a new enemy dot become bases. Empty loops remain playable.
    var component = 0, regions = [], outsideRegions = {}, offsets = [-1, 1, -fw, fw]
    for (i = 0; i < length; ++i) {
        if (walls[i] || labels[i]) continue
        ++component
        var head = 0, tail = 1, outside = false, regionCells = []
        queue[0] = i
        labels[i] = component
        while (head < tail) {
            p = queue[head++]
            x = p % fw
            if (x === 0 || x === fw - 1 || p < fw || p >= length - fw) outside = true
            if (keepDrawing && component > 1) regionCells.push(p)
            for (j = 0; j < 4; ++j) {
                if ((j === 0 && x === 0) || (j === 1 && x === fw - 1) ||
                    (j === 2 && p < fw) || (j === 3 && p >= length - fw)) continue
                q = p + offsets[j]
                if (!walls[q] && !labels[q]) { labels[q] = component; queue[tail++] = q }
            }
        }
        outsideRegions[component] = outside
        if (keepDrawing) regions.push({ id: component, cells: regionCells })
    }
    var capturedRegions = {}, cells = [], territoryChanged = false
    for (i = 0; i < state.board.length; ++i) {
        if (state.board[i] !== 3 - player || state.territory[i] === player) continue
        p = (2 * Math.floor(i / w) + 2) * fw + 2 * (i % w) + 2
        if (labels[p] && !outsideRegions[labels[p]]) capturedRegions[labels[p]] = true
    }
    for (i = 0; i < regions.length; ++i) {
        if (capturedRegions[regions[i].id]) cells = cells.concat(regions[i].cells)
    }
    for (i = 0; i < state.board.length; ++i) {
        p = (2 * Math.floor(i / w) + 2) * fw + 2 * (i % w) + 2
        if (capturedRegions[labels[p]]) {
            state.territory[i] = player
            territoryChanged = true
        }
    }
    if (!keepDrawing || !territoryChanged) return
    var border = []
    for (i = 0; i < edges.length; ++i) {
        p = edges[i].middle
        // A boundary edge touches an enclosed face on at least one side.
        for (y = -1; y <= 1; ++y) {
            var touches = false
            for (x = -1; x <= 1; ++x)
                if (capturedRegions[labels[p + y * fw + x]]) touches = true
            if (touches) { border.push([edges[i].a, edges[i].b]); break }
        }
    }
    state.bases.push({ player: player, cells: cells, edges: border, fineWidth: fw })
}

function play(state, index, keepDrawing) {
    if (!legal(state, index)) return null
    var next = clone(state), player = next.turn
    next.board[index] = player
    next.moves.push(index)
    // The mover's capture takes precedence. Then resolve a dot placed inside
    // an opponent's previously empty loop, without granting an extra turn.
    capture(next, player, keepDrawing !== false)
    capture(next, 3 - player, keepDrawing !== false)
    next.turn = 3 - player
    var hasMove = false
    for (var i = 0; i < next.board.length; ++i)
        if (!next.board[i] && !next.territory[i]) { hasMove = true; break }
    next.finished = !hasMove
    return next
}

function replay(width, height, moves, difficulty, player1, player2) {
    var state = newGame(width, height, difficulty, player1, player2)
    for (var i = 0; i < moves.length; ++i) {
        state = play(state, moves[i])
        if (!state) return null
    }
    return state
}

function serialize(state) {
    return JSON.stringify({ version: 2, width: state.width, height: state.height,
                           moves: state.moves, difficulty: state.difficulty,
                           players: [controller(state, 1), controller(state, 2)],
                           paused: !!state.paused })
}

// A derived cache, never a replacement for the portable move log. Old saves
// and damaged caches fall back to replay. No functions/code are deserialized.
function cacheHash(text) {
    var hash = 2166136261
    for (var i = 0; i < text.length; ++i) { hash ^= text.charCodeAt(i); hash = Math.imul(hash, 16777619) }
    return (hash >>> 0).toString(16)
}
function checkpoint(raw, state) {
    var snapshot = JSON.stringify(clone(state))
    if (snapshot.length > 500000) return ""
    return JSON.stringify({version: 1, record: raw, snapshot: snapshot, hash: cacheHash(raw + "|" + snapshot)})
}
function restoreCheckpoint(raw, cached) {
    if (typeof raw !== "string" || typeof cached !== "string" || cached.length > 1000000) return null
    try {
        var data = restorePlan(raw), cache = JSON.parse(cached)
        if (!data || !cache || cache.version !== 1 || cache.record !== raw || typeof cache.snapshot !== "string" ||
            cache.hash !== cacheHash(raw + "|" + cache.snapshot)) return null
        var state = JSON.parse(cache.snapshot), count = data.width * data.height
        if (!state || state.width !== data.width || state.height !== data.height ||
            !Array.isArray(state.board) || state.board.length !== count ||
            !Array.isArray(state.territory) || state.territory.length !== count ||
            !Array.isArray(state.bases) || state.bases.length > count ||
            JSON.stringify(state.moves) !== JSON.stringify(data.moves) ||
            JSON.stringify(state.players) !== JSON.stringify(data.players) ||
            state.difficulty !== (data.difficulty === "relaxed" ? "relaxed" : "tactical") ||
            state.turn !== 1 + (data.moves.length % 2) || typeof state.finished !== "boolean" ||
            state.paused !== (data.paused === true)) return null
        var board = [], seen = {}, hasMove = false, i, j
        for (i = 0; i < count; ++i) board.push(0)
        for (i = 0; i < data.moves.length; ++i) {
            var index = data.moves[i]
            if (!Number.isInteger(index) || index < 0 || index >= count || seen[index]) return null
            seen[index] = true; board[index] = 1 + (i % 2)
        }
        for (i = 0; i < count; ++i) {
            if (state.board[i] !== board[i] || [0, 1, 2].indexOf(state.territory[i]) < 0) return null
            if (!board[i] && !state.territory[i]) hasMove = true
        }
        if (state.finished === hasMove) return null
        var fw = 2 * data.width + 3, fineCount = fw * (2 * data.height + 3)
        for (i = 0; i < state.bases.length; ++i) {
            var base = state.bases[i]
            if (!base || (base.player !== 1 && base.player !== 2) || base.fineWidth !== fw ||
                !Array.isArray(base.cells) || base.cells.length > fineCount ||
                !Array.isArray(base.edges) || base.edges.length > count * 4) return null
            for (j = 0; j < base.cells.length; ++j)
                if (!Number.isInteger(base.cells[j]) || base.cells[j] < 0 || base.cells[j] >= fineCount) return null
            for (j = 0; j < base.edges.length; ++j) {
                var edge = base.edges[j]
                if (!Array.isArray(edge) || edge.length !== 2 || !Number.isInteger(edge[0]) ||
                    !Number.isInteger(edge[1]) || edge[0] < 0 || edge[0] >= count || edge[1] < 0 || edge[1] >= count) return null
            }
        }
        return clone(state)
    } catch (error) { return null }
}

function restorePlan(raw) {
    try {
        var data = JSON.parse(raw)
        if (!data || (data.version !== 1 && data.version !== 2) || !Array.isArray(data.moves) ||
                !((data.width === 15 && data.height === 19) ||
                  (data.width === 19 && data.height === 23) ||
                  (data.width === 29 && data.height === 33)) ||
                data.moves.length > data.width * data.height) return null
        var players = data.version === 1 ? ["human", "computer"] : data.players
        if (!Array.isArray(players) || players.length !== 2) return null
        for (var i = 0; i < 2; ++i)
            if (players[i] !== "human" && players[i] !== "computer") return null
        data.players = players
        return data
    } catch (error) { return null }
}

function restore(raw) {
    var data = restorePlan(raw)
    if (!data) return null
    var state = replay(data.width, data.height, data.moves, data.difficulty, data.players[0], data.players[1])
    if (state) state.paused = data.paused === true &&
            (data.players[0] === "computer" || data.players[1] === "computer")
    return state
}

function undoRecord(state) {
    var mixed = controller(state, 1) !== controller(state, 2)
    var lastPlayer = 3 - state.turn
    var take = mixed && controller(state, lastPlayer) === "computer" && state.moves.length >= 2 ? 2 : 1
    var moves = state.moves.slice(0, Math.max(0, state.moves.length - take))
    return {version: 2, width: state.width, height: state.height, moves: moves,
            difficulty: state.difficulty, players: [controller(state, 1), controller(state, 2)],
            paused: !!state.paused || controller(state, 1 + moves.length % 2) === "computer"}
}

function undoRound(state) {
    if (!state.moves.length) return state
    var data = undoRecord(state)
    var next = replay(state.width, state.height, data.moves,
                      state.difficulty, data.players[0], data.players[1])
    // A simulation must stay paused after Undo, otherwise it immediately
    // replaces the move. Likewise, do not redo an undone computer opening.
    next.paused = data.paused
    return next
}

function neighbors(state, index, player) {
    var x = index % state.width, y = Math.floor(index / state.width), count = 0
    for (var dy = -1; dy <= 1; ++dy) for (var dx = -1; dx <= 1; ++dx) {
        if ((!dx && !dy) || x + dx < 0 || y + dy < 0 ||
                x + dx >= state.width || y + dy >= state.height) continue
        if (active(state, (y + dy) * state.width + x + dx, player)) ++count
    }
    return count
}

function candidates(state) {
    var result = [], cx = (state.width - 1) / 2, cy = (state.height - 1) / 2
    for (var i = 0; i < state.board.length; ++i) {
        if (!legal(state, i)) continue
        var own = neighbors(state, i, state.turn), enemy = neighbors(state, i, 3 - state.turn)
        var distance = Math.abs(i % state.width - cx) + Math.abs(Math.floor(i / state.width) - cy)
        // A little opening variety, with deterministic tie breaking thereafter.
        result.push({ index: i, rank: own * 3 + enemy * 4 + (own && enemy ? 5 : 0) - distance * 0.08 })
    }
    result.sort(function(a, b) { return b.rank - a.rank || a.index - b.index })
    return result.slice(0, state.difficulty === "relaxed" ? 18 : 40)
}

function evaluateMove(state, candidate) {
    var player = state.turn, index = candidate.index
    var initial = score(state), sign = player === 1 ? 1 : -1
    var next = clone(state)
    next.board[index] = player
    // A new cycle needs at least two neighbours at the added vertex.
    if (neighbors(state, index, player) >= 2) capture(next, player, false)
    var ownScore = score(next), gain = sign * (ownScore.net - initial.net)
        // Test the same intersection as the opponent: blocking a one-move
        // enclosure is valuable, but an immediate capture has priority.
        var opponent = clone(state)
        opponent.turn = 3 - player
        opponent.board[index] = 3 - player
        if (neighbors(state, index, 3 - player) >= 2) capture(opponent, 3 - player, false)
        var threat = score(opponent)
        var danger = -sign * (threat.net - initial.net)
        var value = gain * 1000 + Math.max(0, danger) * 480 + candidate.rank
        // Existing empty enemy loops are rare but entering them is suicidal.
        capture(next, 3 - player, false)
        if (next.territory[index] === 3 - player) value -= 2000
        if (state.difficulty === "relaxed") value += Math.sin(index * 12.9898 + state.moves.length) * 9
    return value
}

function chooseMove(state) {
    if (state.finished) return -1
    var list = candidates(state), best = -1, bestValue = -Infinity
    for (var i = 0; i < list.length; ++i) {
        var index = list[i].index, value = evaluateMove(state, list[i])
        if (value > bestValue) { bestValue = value; best = index }
    }
    return best
}
