import QtQuick 2.15
import QtTest 1.3
import "../../product/payload/apps/paperdots/game.js" as Game

Item {
    id: scene
    width: 1404
    height: 1872
    property var app: null
    SignalSpy { id: closeSpy; target: scene.app; signalName: "close" }
    TestCase {
        name: "PaperDots"
        when: windowShown
        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/paperdots/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.app = component.createObject(scene, {computerEnabled: false})
            verify(scene.app !== null, component.errorString())
            waitForRendering(scene.app)
        }
        function cleanupTestCase() { scene.app.destroy() }
        function init() {
            scene.app.computerEnabled = false
            scene.app.closing = false
            scene.app.selectedWidth = 19
            scene.app.selectedDifficulty = "tactical"
            scene.app.selectedPlayer1 = "human"
            scene.app.selectedPlayer2 = "computer"
            scene.app.startGame()
            closeSpy.clear()
        }
        function tap(name) {
            var target = findChild(scene.app, name)
            verify(target !== null, name)
            verify(target.visible && target.enabled, name + " must be usable")
            mouseClick(target, target.width / 2, target.height / 2, Qt.LeftButton)
            wait(30)
        }
        function choose(player, kind) {
            tap("dotsPlayer" + player + "PickerButton")
            tap("dotsPlayer" + player + "Picker" + kind + "Option")
        }
        function test_cleanBoardHasNoFooterOrSizeLabel() {
            var board = findChild(scene.app, "dotsBoard")
            verify(board.y + board.height > scene.app.height - 30)
            var source = new XMLHttpRequest()
            source.open("GET", Qt.resolvedUrl("../../product/payload/apps/paperdots/ui/main.qml"), false)
            source.send()
            verify(source.responseText.indexOf("Progress saved automatically") < 0)
            verify(source.responseText.indexOf('id: footer') < 0)
        }
        function longSavedGame() {
            var state = Game.newGame(29, 33, "relaxed", "human", "human")
            for (var i = 0; i < 160; ++i) {
                for (var cell = 0; cell < state.board.length && !Game.legal(state, cell); ++cell) {}
                state = Game.play(state, cell)
                verify(state !== null)
            }
            return state
        }
        function test_long_restore_and_undo_yield_without_saving_partial_board() {
            var component = Qt.createComponent("../../product/payload/apps/paperdots/ui/main.qml")
            var app = component.createObject(scene, {computerEnabled: false})
            var original = longSavedGame(), raw = Game.serialize(original)
            var settings = findChild(app, "dotsSavedSettings")
            settings.game = raw
            app.beginRestore(raw)
            compare(app.loaded, false)
            compare(settings.game, raw)
            verify(!app.playIndex(900))
            compare(findChild(app, "dotsNewButton").available, false)
            tryCompare(app, "loaded", true, 10000)
            compare(Game.serialize(app.gameState), raw)
            compare(app.points.net, Game.score(original).net)
            var expectedUndo = Game.serialize(Game.undoRound(original))
            app.undo()
            compare(app.loaded, false)
            compare(settings.game, raw)
            tryCompare(app, "loaded", true, 10000)
            compare(Game.serialize(app.gameState), expectedUndo)
            app.destroy()
        }
        function test_checkpoint_reopens_long_game_immediately_and_recent_undo_is_cached() {
            var original = longSavedGame(), raw = Game.serialize(original)
            var settings = findChild(scene.app, "dotsSavedSettings")
            settings.game = raw
            settings.checkpoint = Game.checkpoint(raw, original)
            scene.app.beginRestore(raw)
            compare(scene.app.loaded, true)
            compare(Game.serialize(scene.app.gameState), raw)
            verify(!scene.app.restoring)
            var index = -1
            for (var i = 0; i < original.board.length; ++i) if (Game.legal(original, i)) { index = i; break }
            verify(index >= 0)
            scene.app.applyMove(index)
            scene.app.undo()
            compare(scene.app.loaded, true)
            compare(Game.serialize(scene.app.gameState), raw)
        }
        function test_close_during_restore_keeps_the_entire_saved_game() {
            var component = Qt.createComponent("../../product/payload/apps/paperdots/ui/main.qml")
            var app = component.createObject(scene, {computerEnabled: false})
            var raw = Game.serialize(longSavedGame())
            var settings = findChild(app, "dotsSavedSettings")
            settings.game = raw
            app.beginRestore(raw)
            var spy = Qt.createQmlObject('import QtTest 1.3; SignalSpy { signalName: "close" }', scene)
            spy.target = app
            var closeButton = findChild(app, "dotsCloseButton")
            mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2, Qt.LeftButton)
            compare(spy.count, 1)
            wait(80)
            compare(app.loaded, false)
            compare(settings.game, raw)
            spy.destroy(); app.destroy()
        }
        function test_board_tap_and_computer_reply_undo_round() {
            var board = findChild(scene.app, "dotsBoard")
            mouseClick(board, scene.app.gridLeft + 9 * scene.app.gridStep + 3,
                       scene.app.gridTop + 11 * scene.app.gridStep - 4, Qt.LeftButton)
            compare(scene.app.gameState.board[11 * 19 + 9], 1)
            scene.app.computerMove()
            compare(scene.app.gameState.moves.length, 2)
            tap("dotsUndoButton")
            compare(scene.app.gameState.moves.length, 0)
        }
        function test_computer_reply_pauses_for_new_game_panel_and_resumes() {
            scene.app.computerEnabled = true
            scene.app.playIndex(200)
            tryVerify(function() { return scene.app.gameState.moves.length === 2 }, 4000)
            verify(scene.app.playIndex(300))
            tap("dotsNewButton")
            var count = scene.app.gameState.moves.length
            wait(150)
            compare(scene.app.gameState.moves.length, count)
            tap("dotsDialogCancelButton")
            tryVerify(function() { return scene.app.gameState.turn === 1 }, 4000)
        }
        function test_new_game_picker_cancel_and_all_sizes() {
            scene.app.playIndex(200)
            tap("dotsNewButton")
            tap("dotsExtraBoardButton")
            choose(2, "Human")
            tap("dotsDialogCancelButton")
            compare(scene.app.gameState.moves.length, 1)
            compare(scene.app.gameState.width, 19)
            tap("dotsNewButton")
            tap("dotsSmallBoardButton")
            tap("dotsRelaxedButton")
            tap("dotsStartButton")
            compare(scene.app.gameState.width, 15)
            compare(scene.app.gameState.difficulty, "relaxed")
            tap("dotsNewButton")
            tap("dotsExtraBoardButton")
            tap("dotsStartButton")
            compare(scene.app.gameState.width, 29)
            compare(scene.app.gameState.height, 33)
            verify(Math.abs(scene.app.gridStep * 25.4 / 226 - 5) < 0.05,
                   "Large-board pitch should be 5 mm on fullscreen reMarkable 2")
            tap("dotsNewButton")
            tap("dotsLargeBoardButton")
            tap("dotsStartButton")
            compare(scene.app.gameState.width, 19)
        }
        function test_human_human_accepts_both_players_and_undo_is_one_move() {
            tap("dotsNewButton")
            choose(2, "Human")
            tap("dotsStartButton")
            scene.app.computerEnabled = true
            verify(scene.app.playIndex(200))
            verify(scene.app.playIndex(201))
            compare(scene.app.gameState.board[200], 1)
            compare(scene.app.gameState.board[201], 2)
            wait(150)
            compare(scene.app.gameState.moves.length, 2)
            compare(findChild(scene.app, "dotsPauseButton").visible, false)
            tap("dotsUndoButton")
            compare(scene.app.gameState.moves.length, 1)
            compare(scene.app.gameState.turn, 2)
        }
        function test_computer_human_starts_and_human_can_reply() {
            tap("dotsNewButton")
            choose(1, "Computer")
            choose(2, "Human")
            tap("dotsStartButton")
            scene.app.computerMove()
            compare(scene.app.gameState.moves.length, 1)
            compare(scene.app.gameState.turn, 2)
            verify(scene.app.playIndex(300))
            tap("dotsUndoButton")
            compare(scene.app.gameState.moves.length, 1)
            compare(scene.app.gameState.turn, 2)
        }
        function test_computer_computer_pause_resume_undo_and_no_human_input() {
            tap("dotsNewButton")
            choose(1, "Computer")
            tap("dotsRelaxedButton")
            tap("dotsStartButton")
            scene.app.computerEnabled = true
            scene.app.queueComputer()
            verify(!scene.app.playIndex(200))
            tryVerify(function() { return scene.app.gameState.moves.length >= 2 }, 6000)
            tap("dotsPauseButton")
            var count = scene.app.gameState.moves.length
            verify(scene.app.gameState.paused)
            wait(300)
            compare(scene.app.gameState.moves.length, count)
            tap("dotsUndoButton")
            compare(scene.app.gameState.moves.length, count - 1)
            verify(scene.app.gameState.paused)
            tap("dotsPauseButton")
            tryVerify(function() { return scene.app.gameState.moves.length >= count }, 4000)
            tap("dotsPauseButton")
        }
        function test_pause_and_player_choices_survive_save() {
            scene.app.selectedPlayer1 = "computer"
            scene.app.selectedPlayer2 = "computer"
            scene.app.startGame()
            scene.app.computerMove()
            scene.app.togglePause()
            scene.app.persist()
            var settings = findChild(scene.app, "dotsSavedSettings")
            var restored = Game.restore(settings.game)
            compare(Game.controller(restored, 1), "computer")
            compare(Game.controller(restored, 2), "computer")
            verify(restored.paused)
            compare(Game.serialize(restored), Game.serialize(scene.app.gameState))
        }
        function test_close_stops_computers_and_emits_once() {
            scene.app.selectedPlayer1 = "computer"
            scene.app.startGame()
            scene.app.computerEnabled = true
            scene.app.queueComputer()
            tap("dotsCloseButton")
            scene.app.closeApp()
            var count = scene.app.gameState.moves.length
            wait(150)
            compare(closeSpy.count, 1)
            compare(scene.app.gameState.moves.length, count)
        }
        function test_remaining_controls_fit_and_retired_actions_are_absent() {
            compare(findChild(scene.app, "dotsRulesButton"), null)
            compare(findChild(scene.app, "dotsFinishButton"), null)
            tap("dotsNewButton")
            var start = findChild(scene.app, "dotsStartButton")
            var corner = start.mapToItem(scene.app, start.width, start.height)
            verify(corner.y < scene.app.height)
            verify(corner.x < scene.app.width)
            tap("dotsDialogCancelButton")
            var close = findChild(scene.app, "dotsCloseButton")
            compare(close.x + close.width, scene.app.width - 24)
        }
        function test_capture_drawing_and_large_board_preview() {
            var position = Game.newGame(29, 33, "tactical", "human", "human")
            position.board[14 * 29 + 14] = 1
            position.board[15 * 29 + 15] = 1
            position.board[16 * 29 + 14] = 1
            position.board[15 * 29 + 14] = 2
            scene.app.gameState = Game.play(position, 15 * 29 + 13)
            compare(scene.app.points.player1, 1)
            wait(80)
            var preview = grabImage(scene.app)
            compare(preview.width, scene.app.width)
            compare(preview.height, scene.app.height)
            preview.save("/tmp/paperdesk-dots-preview.png")
            tap("dotsNewButton")
            preview = grabImage(scene.app)
            preview.save("/tmp/paperdesk-dots-setup-preview.png")
        }
    }
}
