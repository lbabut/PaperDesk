import QtQuick 2.15
import Qt.labs.settings 1.1
import "../game.js" as Game

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"
    signal close

    property var gameState: null
    property string panel: ""
    property string notice: ""
    property int selectedWidth: 19
    property string selectedDifficulty: "tactical"
    property string selectedPlayer1: "human"
    property string selectedPlayer2: "computer"
    property bool loaded: false
    property bool closing: false
    property bool computerEnabled: true
    property int lastThinkMs: 0
    property var aiWork: null
    property var restoreWork: null
    property var undoCache: []
    readonly property bool restoring: restoreWork !== null
    readonly property bool thinking: Game.isComputer(gameState) && !gameState.paused
    readonly property bool hasComputer: !!gameState && (Game.controller(gameState, 1) === "computer" || Game.controller(gameState, 2) === "computer")
    readonly property bool computerOnly: !!gameState && Game.controller(gameState, 1) === "computer" && Game.controller(gameState, 2) === "computer"
    readonly property bool selectedHasComputer: selectedPlayer1 === "computer" || selectedPlayer2 === "computer"
    readonly property var points: gameState ? Game.score(gameState) : ({player1: 0, player2: 0, net: 0})
    // reMarkable 2: 226 pixels/inch. Fullscreen 5 mm = 226 * 5 / 25.4 px.
    readonly property real fiveMillimeters: 226 * 5 / 25.4
    readonly property real boardInset: gameState && gameState.width === 29 ? 64 : 100
    readonly property real gridStep: gameState ? Math.min((boardArea.width - boardInset) / (gameState.width - 1), (boardArea.height - boardInset) / (gameState.height - 1), gameState.width === 29 ? fiveMillimeters : 10000) : 1
    readonly property real gridLeft: gameState ? (boardArea.width - (gameState.width - 1) * gridStep) / 2 : 0
    readonly property real gridTop: gameState ? (boardArea.height - (gameState.height - 1) * gridStep) / 2 : 0

    Settings {
        id: saved
        objectName: "dotsSavedSettings"
        category: "PaperDeskDots"
        property string game: ""
        property string checkpoint: ""
    }
    Settings {
        id: testSettings
        category: "PaperDeskE2E"
        property bool dotsCapture: false
    }
    Timer {
        id: screenshotTimer
        interval: 650
        repeat: false
        onTriggered: root.logTestTargets(root)
    }

    component ActionButton: Rectangle {
        id: button
        property string label: "Action"
        property bool primary: false
        property bool available: true
        signal triggered
        width: 176
        height: 76
        radius: 8
        border.width: 2
        border.color: available ? "black" : "#888888"
        color: available && (primary || tap.pressed) ? "black" : "white"
        Text {
            anchors.centerIn: parent
            text: button.label
            font.pointSize: 16
            font.bold: true
            color: !button.available ? "#777777" : (button.primary || tap.pressed ? "white" : "black")
        }
        TapHandler {
            id: tap
            enabled: button.available
            onTapped: {
                console.log("PaperDots action", button.objectName)
                button.triggered()
            }
        }
    }

    component PlayerPicker: Item {
        id: picker
        property string title: "Player"
        property string value: "human"
        property bool expanded: false
        onExpandedChanged: { if (root.loaded && testSettings.dotsCapture) screenshotTimer.restart() }
        signal picked(string kind)
        signal opened
        width: 340
        height: 120
        z: expanded ? 10 : 1
        Text { text: picker.title; font.pixelSize: 23; font.bold: true; color: "black" }
        ActionButton {
            objectName: picker.objectName + "Button"
            width: parent.width
            anchors.bottom: parent.bottom
            label: (picker.value === "computer" ? "Computer" : "Human") + "  ▾"
            onTriggered: {
                picker.expanded = !picker.expanded
                if (picker.expanded) picker.opened()
            }
        }
        Rectangle {
            visible: picker.expanded
            y: picker.height + 6
            width: picker.width
            height: 166
            color: "white"
            border.width: 2
            border.color: "black"
            radius: 8
            Column {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 4
                ActionButton {
                    objectName: picker.objectName + "HumanOption"
                    width: parent.width
                    height: 76
                    label: "Human"
                    primary: picker.value === "human"
                    onTriggered: { picker.expanded = false; picker.picked("human") }
                }
                ActionButton {
                    objectName: picker.objectName + "ComputerOption"
                    width: parent.width
                    height: 76
                    label: "Computer"
                    primary: picker.value === "computer"
                    onTriggered: { picker.expanded = false; picker.picked("computer") }
                }
            }
        }
    }

    function playerLabel(player) {
        return "Player " + player + " (" + (Game.controller(gameState, player) === "computer" ? "Computer" : "Human") + ")"
    }

    function mayCompute() {
        return loaded && !closing && computerEnabled && panel === "" &&
                Game.isComputer(gameState) && !gameState.paused
    }

    function queueComputer() {
        if (mayCompute()) turnDelayTimer.restart()
    }

    function logTestTargets(item) {
        if (!testSettings.dotsCapture) return
        if (item.visible && item.objectName && item.objectName.indexOf("dots") === 0 &&
                item.mapToItem && (item.triggered || item.objectName === "dotsBoard")) {
            var point = item.mapToItem(null, item.width / 2, item.height / 2)
            console.log("PaperDots target", item.objectName, Math.round(point.x), Math.round(point.y))
        }
        if (item.children) for (var i = 0; i < item.children.length; ++i)
            logTestTargets(item.children[i])
    }

    function persist(flush) {
        if (loaded && gameState) {
            saved.game = Game.serialize(gameState)
            saved.checkpoint = Game.checkpoint(saved.game, gameState)
            if (flush && typeof saved.sync === "function") saved.sync()
            else saveTimer.restart()
        }
    }

    function applyMove(index) {
        var next = Game.play(gameState, index)
        if (!next) return false
        undoCache = undoCache.slice(-3).concat([gameState])
        gameState = next
        return true
    }

    function startGame() {
        if (!loaded || closing) return
        undoCache = []
        aiTimer.stop()
        turnDelayTimer.stop()
        gameState = Game.newGame(selectedWidth, selectedWidth === 15 ? 19 : (selectedWidth === 29 ? 33 : 23),
                                 selectedDifficulty, selectedPlayer1, selectedPlayer2)
        notice = ""
        panel = ""
        queueComputer()
        console.log("PaperDots new game", gameState.width, gameState.height, gameState.difficulty,
                    gameState.players[0], gameState.players[1])
    }

    function playIndex(index) {
        if (!loaded || !gameState || panel !== "" || Game.controller(gameState, gameState.turn) !== "human" ||
                gameState.paused || gameState.finished || closing) return false
        if (!applyMove(index)) { notice = "Choose an empty intersection outside a base."; return false }
        notice = ""
        console.log("PaperDots human move", index, "captured", points.player1, points.player2)
        return true
    }

    function tapBoard(x, y) {
        if (!gameState) return
        var gx = Math.round((x - gridLeft) / gridStep)
        var gy = Math.round((y - gridTop) / gridStep)
        if (gx < 0 || gy < 0 || gx >= gameState.width || gy >= gameState.height) return
        playIndex(gy * gameState.width + gx)
    }

    function computerMove() {
        if (!loaded || !Game.isComputer(gameState) || gameState.paused || panel !== "" || closing) return
        var started = Date.now()
        var index = Game.chooseMove(gameState)
        if (index >= 0) applyMove(index)
        lastThinkMs = Date.now() - started
        console.log("PaperDots computer move", index, "timeMs", lastThinkMs)
    }

    function thinkSlice() {
        if (!mayCompute()) return
        if (!aiWork) aiWork = { list: Game.candidates(gameState), cursor: 0,
                               best: -1, value: -Infinity, started: Date.now() }
        // Yield between candidates so Close, Undo and the device watchdog
        // remain responsive even on the tablet's small ARM processor.
        var deadline = Date.now() + 22
        do {
            var candidate = aiWork.list[aiWork.cursor++]
            if (!candidate) break
            var value = Game.evaluateMove(gameState, candidate)
            if (value > aiWork.value) { aiWork.best = candidate.index; aiWork.value = value }
        } while (aiWork.cursor < aiWork.list.length && Date.now() < deadline)
        if (aiWork.cursor < aiWork.list.length) { aiTimer.restart(); return }
        var chosen = aiWork.best
        lastThinkMs = Date.now() - aiWork.started
        if (chosen >= 0) applyMove(chosen)
        console.log("PaperDots computer move", chosen, "timeMs", lastThinkMs)
    }

    function undo() {
        if (!loaded || !gameState || !gameState.moves.length) return
        aiTimer.stop()
        turnDelayTimer.stop()
        var record = Game.undoRecord(gameState)
        for (var i = undoCache.length - 1; i >= 0; --i) {
            if (JSON.stringify(undoCache[i].moves) === JSON.stringify(record.moves)) {
                var previous = Game.clone(undoCache[i])
                previous.paused = record.paused
                undoCache = undoCache.slice(0, i)
                gameState = previous
                notice = ""
                console.log("PaperDots undo", record.moves.length, "cached")
                return
            }
        }
        if (gameState.moves.length > 64) {
            beginRestore(JSON.stringify(record))
            console.log("PaperDots undo", record.moves.length)
            return
        }
        gameState = Game.undoRound(gameState)
        notice = ""
        console.log("PaperDots undo", gameState.moves.length)
    }

    function togglePause() {
        if (!loaded || !gameState || !hasComputer || gameState.finished) return
        var next = Game.clone(gameState)
        next.paused = !next.paused
        gameState = next
        notice = ""
        console.log("PaperDots pause", gameState.paused, "moves", gameState.moves.length)
    }

    function unloading() {
        closing = true
        restoreTimer.stop()
        restoreWork = null
        aiTimer.stop()
        turnDelayTimer.stop()
        screenshotTimer.stop()
        saveTimer.stop()
        persist(true)
    }

    function closeApp() {
        if (closing) return
        unloading()
        console.log("PaperDots close")
        close()
    }

    onGameStateChanged: {
        aiTimer.stop()
        turnDelayTimer.stop()
        aiWork = null
        boardCanvas.requestPaint()
        persist()
        queueComputer()
        if (testSettings.dotsCapture) screenshotTimer.restart()
    }
    onPanelChanged: {
        aiTimer.stop()
        turnDelayTimer.stop()
        aiWork = null
        if (panel === "") {
            player1Picker.expanded = false
            player2Picker.expanded = false
        }
        queueComputer()
        if (testSettings.dotsCapture) screenshotTimer.restart()
    }
    onSelectedPlayer1Changed: { if (loaded && testSettings.dotsCapture) screenshotTimer.restart() }
    onSelectedPlayer2Changed: { if (loaded && testSettings.dotsCapture) screenshotTimer.restart() }
    Timer { id: aiTimer; interval: 30; repeat: false; onTriggered: root.thinkSlice() }
    Timer { id: turnDelayTimer; interval: root.computerOnly ? 650 : 30; repeat: false; onTriggered: { if (root.mayCompute()) aiTimer.restart() } }
    Timer { id: restoreTimer; interval: 16; repeat: false; onTriggered: root.restoreSlice() }
    Timer { id: saveTimer; interval: 1200; onTriggered: { if (typeof saved.sync === "function") saved.sync() } }

    function finishRestore(state, restored) {
        if (closing) return
        restoreWork = null
        gameState = state || Game.newGame(19, 23, "tactical")
        notice = ""
        selectedWidth = gameState.width
        selectedDifficulty = gameState.difficulty
        selectedPlayer1 = Game.controller(gameState, 1)
        selectedPlayer2 = Game.controller(gameState, 2)
        loaded = true
        persist()
        queueComputer()
        console.log("PaperDots ready", restored ? "restored" : "new", gameState.moves.length)
        console.log("PaperDots match", gameState.width, gameState.height, Game.controller(gameState, 1),
                    Game.controller(gameState, 2), "paused", gameState.paused, "moves", gameState.moves.length)
        if (testSettings.dotsCapture) screenshotTimer.restart()
    }

    function beginRestore(raw) {
        aiTimer.stop(); turnDelayTimer.stop(); restoreTimer.stop()
        loaded = false
        undoCache = []
        var checkpointStarted = Date.now()
        var cached = raw === saved.game ? Game.restoreCheckpoint(raw, saved.checkpoint) : null
        if (cached) {
            console.log("PaperDots checkpoint restored", cached.moves.length, "timeMs", Date.now() - checkpointStarted)
            finishRestore(cached, true); return
        }
        var data = Game.restorePlan(raw)
        if (!data) { finishRestore(null, false); return }
        var state = Game.newGame(data.width, data.height, data.difficulty, data.players[0], data.players[1])
        if (!data.moves.length) {
            state.paused = data.paused === true && (data.players[0] === "computer" || data.players[1] === "computer")
            finishRestore(state, true)
            return
        }
        gameState = state
        restoreWork = {data: data, state: state, cursor: 0, lastNotice: Date.now()}
        notice = "Restoring saved game… 0 / " + data.moves.length
        console.log("PaperDots restoring", data.moves.length)
        restoreTimer.start()
    }

    function restoreSlice() {
        if (closing || !restoreWork) return
        var work = restoreWork, started = work.cursor, deadline = Date.now() + 18
        do {
            var next = Game.play(work.state, work.data.moves[work.cursor])
            if (!next) { finishRestore(null, false); return }
            work.state = next
            ++work.cursor
        } while (work.cursor < work.data.moves.length && work.cursor - started < 4 && Date.now() < deadline)
        if (work.cursor < work.data.moves.length) {
            if (Date.now() - work.lastNotice >= 500) {
                notice = "Restoring saved game… " + work.cursor + " / " + work.data.moves.length
                work.lastNotice = Date.now()
            }
            restoreTimer.restart()
        } else {
            work.state.paused = work.data.paused === true &&
                (work.data.players[0] === "computer" || work.data.players[1] === "computer")
            finishRestore(work.state, true)
        }
    }
    Component.onCompleted: beginRestore(saved.game)
    Component.onDestruction: unloading()

    Rectangle {
        id: header
        width: parent.width
        height: 112
        color: "black"
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text { text: "PAPERDESK  /  QUIET STRATEGY"; color: "white"; font.pixelSize: 13; font.bold: true; font.letterSpacing: 2 }
            Text { text: "PaperDesk Dots"; color: "white"; font.pixelSize: 34; font.bold: true }
        }
        ActionButton {
            objectName: "dotsCloseButton"
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            label: "Close"
            onTriggered: root.closeApp()
        }
    }

    Row {
        id: actions
        anchors.top: header.bottom
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.leftMargin: 28
        spacing: 16
        ActionButton {
            objectName: "dotsNewButton"
            available: root.loaded
            label: "New game"
            onTriggered: {
                root.selectedWidth = root.gameState.width
                root.selectedDifficulty = root.gameState.difficulty
                root.selectedPlayer1 = Game.controller(root.gameState, 1)
                root.selectedPlayer2 = Game.controller(root.gameState, 2)
                root.panel = "new"
            }
        }
        ActionButton { objectName: "dotsUndoButton"; label: root.gameState && Game.controller(root.gameState, 1) !== Game.controller(root.gameState, 2) ? "Undo turn" : "Undo move"; available: root.loaded && !!root.gameState && root.gameState.moves.length > 0; onTriggered: root.undo() }
        ActionButton { objectName: "dotsPauseButton"; label: root.gameState && root.gameState.paused ? "Resume" : "Pause"; visible: root.hasComputer; available: root.loaded && !!root.gameState && !root.gameState.finished; onTriggered: root.togglePause() }
    }

    Row {
        id: scores
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.top: actions.bottom
        anchors.topMargin: 24
        spacing: 36
        Text { text: "●  PLAYER 1 · " + (root.gameState && Game.controller(root.gameState, 1) === "computer" ? "Computer" : "Human") + "   " + root.points.player1; font.pixelSize: 26; font.bold: true; color: "black" }
        Text { text: "○  PLAYER 2 · " + (root.gameState && Game.controller(root.gameState, 2) === "computer" ? "Computer" : "Human") + "   " + root.points.player2; font.pixelSize: 26; font.bold: true; color: "black" }
    }
    Text {
        id: status
        objectName: "dotsStatus"
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.top: scores.bottom
        anchors.topMargin: 16
        width: parent.width - 64
        wrapMode: Text.WordWrap
        text: {
            if (!root.gameState) return ""
            if (root.restoring) return root.notice
            var leader = root.points.net === 0 ? "Level score" : "Player " + (root.points.net > 0 ? 1 : 2) + " leads by " + Math.abs(root.points.net)
            if (root.gameState.finished) return "Board full · " + (root.points.net === 0 ? "A draw" : "Player " + (root.points.net > 0 ? 1 : 2) + " wins")
            if (root.gameState.paused) return "Paused · " + leader
            return root.notice || root.playerLabel(root.gameState.turn) + (root.thinking ? " is thinking…" : " to move") + "  ·  " + leader
        }
        font.pixelSize: 24
        font.bold: !!root.gameState && root.gameState.finished
        color: "black"
    }

    Item {
        id: boardArea
        objectName: "dotsBoard"
        anchors.top: status.bottom
        anchors.topMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        width: parent.width
        Canvas {
            id: boardCanvas
            objectName: "dotsCanvas"
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d"), state = root.gameState
                ctx.clearRect(0, 0, width, height)
                if (!state) return
                var step = root.gridStep, left = root.gridLeft, top = root.gridTop
                var w = state.width, h = state.height, i, j, x, y
                function px(index) { return left + (index % w) * step }
                function py(index) { return top + Math.floor(index / w) * step }
                ctx.lineWidth = 1
                ctx.strokeStyle = "#b7b7b7"
                ctx.beginPath()
                for (x = 0; x < w; ++x) { ctx.moveTo(left + x * step, top); ctx.lineTo(left + x * step, top + (h - 1) * step) }
                for (y = 0; y < h; ++y) { ctx.moveTo(left, top + y * step); ctx.lineTo(left + (w - 1) * step, top + y * step) }
                ctx.stroke()
                // Sparse hatching distinguishes bases without a grey wash.
                ctx.strokeStyle = "black"
                ctx.lineWidth = 1
                ctx.beginPath()
                for (i = 0; i < state.bases.length; ++i) {
                    var base = state.bases[i]
                    for (j = 0; j < base.cells.length; ++j) {
                        var fine = base.cells[j], fx = fine % base.fineWidth, fy = Math.floor(fine / base.fineWidth)
                        if ((fx + fy) % 4 !== 0) continue
                        x = left + (fx / 2 - 1) * step; y = top + (fy / 2 - 1) * step
                        ctx.moveTo(x - step * 0.09, y + step * 0.09)
                        ctx.lineTo(x + step * 0.09, y - step * 0.09)
                    }
                }
                ctx.stroke()
                ctx.lineWidth = 3
                for (i = 0; i < state.bases.length; ++i) {
                    var b = state.bases[i]
                    ctx.beginPath()
                    for (j = 0; j < b.edges.length; ++j) {
                        var a = b.edges[j][0], end = b.edges[j][1]
                        if (!Game.active(state, a, b.player) || !Game.active(state, end, b.player)) continue
                        if (b.player === 1) { ctx.moveTo(px(a), py(a)); ctx.lineTo(px(end), py(end)) }
                        else {
                            for (var part = 0; part < 8; part += 2) {
                                ctx.moveTo(px(a) + (px(end) - px(a)) * part / 8, py(a) + (py(end) - py(a)) * part / 8)
                                ctx.lineTo(px(a) + (px(end) - px(a)) * (part + 1) / 8, py(a) + (py(end) - py(a)) * (part + 1) / 8)
                            }
                        }
                    }
                    ctx.stroke()
                }
                var radius = Math.max(7, step * 0.15)
                for (i = 0; i < state.board.length; ++i) {
                    if (!state.board[i]) continue
                    x = px(i); y = py(i)
                    ctx.beginPath(); ctx.arc(x, y, radius, 0, 2 * Math.PI)
                    ctx.fillStyle = state.board[i] === 1 ? "black" : "white"
                    ctx.fill(); ctx.stroke()
                    if (state.territory[i] === 3 - state.board[i]) {
                        ctx.beginPath()
                        ctx.moveTo(x - radius - 4, y - radius - 4); ctx.lineTo(x + radius + 4, y + radius + 4)
                        ctx.moveTo(x + radius + 4, y - radius - 4); ctx.lineTo(x - radius - 4, y + radius + 4)
                        ctx.stroke()
                    }
                }
                if (state.moves.length) {
                    i = state.moves[state.moves.length - 1]
                    ctx.lineWidth = 2
                    ctx.beginPath(); ctx.arc(px(i), py(i), radius + 7, 0, 2 * Math.PI); ctx.stroke()
                }
            }
        }
        TapHandler {
            enabled: root.panel === "" && !!root.gameState && !Game.isComputer(root.gameState) && !root.gameState.paused && !root.gameState.finished
            onTapped: function(eventPoint) { root.tapBoard(eventPoint.position.x, eventPoint.position.y) }
        }
    }
    Rectangle {
        id: modal
        objectName: "dotsDialog"
        visible: root.panel !== ""
        anchors.fill: parent
        color: "white"
        z: 10
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 96
            height: newGameContent.implicitHeight + 96
            border.color: "black"
            border.width: 3
            radius: 12
            Column {
                id: newGameContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 48
                spacing: 28
                Text { text: "PAPERDESK  /  DOTS"; font.pixelSize: 16; font.bold: true; font.letterSpacing: 2; color: "black" }
                Text { text: "A fresh sheet."; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 40; font.bold: true; color: "black" }
                Text {
                    width: parent.width
                    text: "Choose your board and players. Starting a new game replaces the saved game."
                    font.pixelSize: 26; wrapMode: Text.WordWrap; color: "black"
                }
                Text { text: "BOARD"; font.pixelSize: 18; font.bold: true; color: "black" }
                Row {
                    spacing: 20
                    ActionButton { objectName: "dotsSmallBoardButton"; width: 240; label: "15 × 19 · spacious"; primary: root.selectedWidth === 15; onTriggered: root.selectedWidth = 15 }
                    ActionButton { objectName: "dotsLargeBoardButton"; width: 240; label: "19 × 23 · classic"; primary: root.selectedWidth === 19; onTriggered: root.selectedWidth = 19 }
                    ActionButton { objectName: "dotsExtraBoardButton"; width: 240; label: "29 × 33 · 5 mm"; primary: root.selectedWidth === 29; onTriggered: root.selectedWidth = 29 }
                }
                Row {
                    spacing: 28
                    z: 20
                    PlayerPicker {
                        id: player1Picker
                        objectName: "dotsPlayer1Picker"
                        title: "● Player 1"
                        value: root.selectedPlayer1
                        onPicked: function(kind) { root.selectedPlayer1 = kind }
                        onOpened: player2Picker.expanded = false
                    }
                    PlayerPicker {
                        id: player2Picker
                        objectName: "dotsPlayer2Picker"
                        title: "○ Player 2"
                        value: root.selectedPlayer2
                        onPicked: function(kind) { root.selectedPlayer2 = kind }
                        onOpened: player1Picker.expanded = false
                    }
                }
                Text { visible: root.selectedHasComputer; text: "COMPUTER LEVEL"; font.pixelSize: 18; font.bold: true; color: "black" }
                Row {
                    visible: root.selectedHasComputer; spacing: 20
                    ActionButton { objectName: "dotsRelaxedButton"; width: 240; label: "Relaxed"; primary: root.selectedDifficulty === "relaxed"; onTriggered: root.selectedDifficulty = "relaxed" }
                    ActionButton { objectName: "dotsTacticalButton"; width: 240; label: "Tactical"; primary: root.selectedDifficulty === "tactical"; onTriggered: root.selectedDifficulty = "tactical" }
                }
                Row {
                    spacing: 20
                    ActionButton { objectName: "dotsDialogCancelButton"; width: 240; label: "Keep playing"; onTriggered: root.panel = "" }
                    ActionButton { objectName: "dotsStartButton"; width: 240; label: "Start game"; primary: true; onTriggered: root.startGame() }
                }
            }
        }
    }
}
