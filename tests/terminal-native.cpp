// Real host PTY, renderer, lifecycle and resource-import regression tests.
#define PAPERTERMINAL_TESTING
#define PAPERTERMINAL_NO_PLUGIN
#include "../product/payload/apps/paperterminal/native/paperterminal-native.cpp"
#include <QtCore/QProcess>
#include <QtCore/QResource>
#include <QtCore/QTemporaryDir>
#include <QtGui/QGuiApplication>
#include <QtQml/QQmlComponent>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickWindow>
#include <cassert>
#include <functional>

static bool until(const std::function<bool()> &condition, int timeout = 4000) {
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < timeout) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 5); QThread::msleep(1);
    }
    return condition();
}
static void spin(int milliseconds) { QElapsedTimer timer; timer.start(); until([&] { return timer.elapsed() >= milliseconds; }, milliseconds + 200); }
static void writeFile(const QString &path, const QByteArray &data) {
    QFile file(path); assert(file.open(QIODevice::WriteOnly)); assert(file.write(data) == data.size());
}
static void viewport(TerminalView &terminal) { terminal.setWidth(800); terminal.setHeight(480); }

int main(int argc, char **argv) {
    QGuiApplication application(argc, argv);
    const QString root = QDir::currentPath();
    QTemporaryDir temporaryHome; assert(temporaryHome.isValid());
    qputenv("HOME", temporaryHome.path().toUtf8());

    // Load the exact app-local native import from an RCC, as AppLoad does.
    // Only the fixture's plugin directory changes to the host output path.
    {
        QTemporaryDir fixture; assert(fixture.isValid());
        QDir().mkpath(fixture.path() + "/native"); QDir().mkpath(fixture.path() + "/ui");
        const QString pluginDirectory = root + "/work/terminal-native-host";
        assert(QFile::exists(pluginDirectory + "/libpaperterminal_native.so"));
        writeFile(fixture.path() + "/native/qmldir", "module PaperTerminal.Native\nplugin paperterminal_native " + pluginDirectory.toUtf8() + "\nclassname PaperTerminalPlugin\n");
        writeFile(fixture.path() + "/ui/main.qml", "import QtQuick\nimport \"../native\" as Native\nNative.TerminalView { width: 640; height: 400; font.pointSize: 20 }\n");
        writeFile(fixture.path() + "/application.qrc", "<RCC><qresource prefix=\"/paperterminal\"><file>ui/main.qml</file><file>native/qmldir</file></qresource></RCC>");
        const QString rcc = qEnvironmentVariable("PAPERDESK_TOOLCACHE", "/home/lukasz/Documents/Codex/2026-09-25/m-2/work") + "/qt-rcc-pkg/root/usr/lib/qt5/bin/rcc";
        QProcess resourceCompiler; resourceCompiler.setWorkingDirectory(fixture.path());
        resourceCompiler.start(rcc, {"--binary", "application.qrc", "-o", "resources.rcc"});
        assert(resourceCompiler.waitForFinished(5000)); assert(resourceCompiler.exitCode() == 0);
        QQmlEngine engine;
        const QString resource = fixture.path() + "/resources.rcc";
        for (const QString &prefix : {QStringLiteral("/appload-first-random-prefix"), QStringLiteral("/appload-next-random-prefix")}) {
            assert(QResource::registerResource(resource, prefix));
            {
                QQmlComponent component(&engine, QUrl("qrc:" + prefix + "/paperterminal/ui/main.qml"));
                assert(until([&] { return !component.isLoading(); }));
                if (component.isError()) qWarning() << component.errors();
                assert(component.isReady()); std::unique_ptr<QObject> object(component.create());
                assert(object); assert(object->property("terminalSize").toSize().width() > 10);
                object.reset();
            }
            assert(QResource::unregisterResource(resource, prefix));
        }
        printf("PASS local plugin unload/reload across RCC prefixes in one QML engine\n");
    }

    // A fallback monospace font can retain fractional layout advances even
    // when full hinting rounds single-glyph metrics. Every ASCII glyph must
    // still occupy exactly its declared terminal cell, through the last one.
    for (const QString &family : {QStringLiteral("Noto Sans Mono"), QStringLiteral("DejaVu Sans")}) {
        TerminalView terminal; terminal.setWidth(1332); terminal.setHeight(160);
        QFont font(family); font.setPointSize(33); terminal.setFont(font);
        const QByteArray sample = QByteArray("Native QML plugin loaded from the full RCC resource.").left(terminal.terminalSize().width());
        terminal.feedForTest("\033[?25l" + sample);
        assert(until([&] { return !terminal.framePendingForTest(); }));
        const int cellWidth = int(terminal.cellSize().width()), cellHeight = int(terminal.cellSize().height());
        QFont referenceFont = font; referenceFont.setStyleHint(QFont::Monospace); referenceFont.setFixedPitch(true);
        referenceFont.setHintingPreference(QFont::PreferFullHinting);
        referenceFont.setPixelSize(QFontInfo(referenceFont).pixelSize());
        QFontMetricsF referenceMetrics(referenceFont);
        referenceFont.setLetterSpacing(QFont::AbsoluteSpacing, cellWidth - referenceMetrics.horizontalAdvance('M'));
        QImage reference(1332, cellHeight, QImage::Format_RGB32); reference.fill(Qt::white);
        { QPainter painter(&reference); painter.setRenderHint(QPainter::TextAntialiasing, false); painter.setFont(referenceFont);
          for (int column = 0; column < sample.size(); ++column)
              painter.drawText(QPointF(column * cellWidth, std::ceil(referenceMetrics.ascent())), QString(QChar::fromLatin1(sample[column]))); }
        int misplaced = 0;
        for (int y = 0; y < cellHeight; ++y)
            for (int x = 0; x < 1332; ++x)
                misplaced += terminal.imageForTest().pixel(x, y) != reference.pixel(x, y);
        if (misplaced) qWarning() << "ASCII terminal grid mismatches:" << misplaced;
        assert(misplaced == 0);
    }

    // Crisp text, explicit background selections, inverse, coalesced frames,
    // unchanged curses output and hidden sessions all use the real renderer.
    {
        QQuickWindow window; window.setGeometry(0, 0, 800, 480); window.show();
        TerminalView terminal; terminal.setParentItem(window.contentItem()); viewport(terminal); int frames = 0;
        QObject::connect(&terminal, &TerminalView::displayBufferChanged, [&] { ++frames; });
        terminal.feedForTest("\033[2J\033[H\033[?25lA\033[44mB\033[0m\033[7mC\033[0m\033[2;1H\033[4m   \033[0m\033[H");
        assert(until([&] { return !terminal.framePendingForTest(); }));
        const int cell = int(terminal.cellSize().width());
        assert(qRed(terminal.imageForTest().pixel(1, 1)) == 255);
        assert(qRed(terminal.imageForTest().pixel(cell + 1, 1)) == 0);
        assert(qRed(terminal.imageForTest().pixel(cell * 2 + 1, 1)) == 0);
        int ink = 0;
        for (int y = 0; y < int(terminal.cellSize().height()); ++y)
            for (int x = 0; x < cell; ++x) ink += qRed(terminal.imageForTest().pixel(x, y)) < 128;
        assert(ink > 5);
        int underlineInk = 0;
        for (int y = int(terminal.cellSize().height()); y < int(terminal.cellSize().height()) * 2; ++y)
            for (int x = 0; x < cell * 3; ++x) underlineInk += qRed(terminal.imageForTest().pixel(x, y)) < 128;
        assert(underlineInk > 5);
        assert(terminal.imageForTest().save(root + "/work/terminal-native-host/terminal-render.png"));
        // Font metrics and the backing image must use identical pixel glyphs
        // even on tablets whose image DPI differs from the screen DPI.
        terminal.feedForTest("\033[" + QByteArray::number(terminal.terminalSize().width()) + "G#");
        assert(until([&] { return !terminal.framePendingForTest(); }));
        const QImage reference = terminal.imageForTest();
        QImage &differentDpi = const_cast<QImage &>(terminal.imageForTest());
        differentDpi.setDotsPerMeterX(7874); differentDpi.setDotsPerMeterY(7874); // 200 DPI.
        terminal.redraw(); assert(until([&] { return !terminal.framePendingForTest(); }));
        int differentPixels = 0;
        for (int y = 0; y < reference.height(); ++y)
            for (int x = 0; x < reference.width(); ++x)
                differentPixels += reference.pixel(x, y) != terminal.imageForTest().pixel(x, y);
        if (differentPixels) qWarning() << "Font DPI changed raster pixels:" << differentPixels;
        assert(differentPixels == 0);
        differentDpi.setDotsPerMeterX(reference.dotsPerMeterX());
        differentDpi.setDotsPerMeterY(reference.dotsPerMeterY());
        // Restore the same final row for the unchanged curses-frame check.
        terminal.feedForTest("\033[" + QByteArray::number(terminal.terminalSize().width()) + "G ");
        assert(until([&] { return !terminal.framePendingForTest(); }));
        const int before = frames;
        for (int i = 0; i < 100; ++i) terminal.feedForTest("\033[HA\033[44mB\033[0m\033[7mC\033[0m");
        spin(200); assert(frames == before); assert(!terminal.framePendingForTest());
        terminal.setVisible(false); terminal.feedForTest("\033[HNEW"); spin(200); assert(frames == before);
        terminal.setVisible(true);
        const bool shown = until([&] { return frames >= before + 1; });
        if (!shown) qWarning() << "visibility frames" << before << frames << terminal.isVisible() << terminal.framePendingForTest();
        assert(shown);
        spin(250); assert(frames == before + 1); assert(!terminal.framePendingForTest());
        // Enlarging a font can remove rows without resizing the image. Old
        // glyphs must not survive in the newly unused bottom margin.
        QFont larger = terminal.font();
        int minimumGrid = 480, selectedSize = 27;
        for (int size = 27; size <= 70; ++size) {
            QFont candidate = terminal.font(); candidate.setPointSize(size);
            const int lineHeight = int(std::ceil(QFontMetricsF(candidate).height() * 1.08));
            const int grid = (480 / lineHeight) * lineHeight;
            if (grid < minimumGrid) { minimumGrid = grid; selectedSize = size; }
        }
        terminal.feedForTest("\033[" + QByteArray::number(terminal.terminalSize().height()) + ";1HMMMMMMMM");
        assert(until([&] { return !terminal.framePendingForTest(); }));
        int oldMarginInk = 0;
        for (int y = minimumGrid; y < 480; ++y)
            for (int x = 0; x < 200; ++x) oldMarginInk += qRed(terminal.imageForTest().pixel(x, y)) < 128;
        assert(oldMarginInk > 5);
        larger.setPointSize(selectedSize); terminal.setFont(larger);
        assert(until([&] { return !terminal.framePendingForTest(); }));
        const int marginTop = terminal.terminalSize().height() * int(terminal.cellSize().height());
        for (int y = marginTop; y < 480; ++y)
            for (int x = 0; x < 800; ++x) assert(qRed(terminal.imageForTest().pixel(x, y)) == 255);
    }

    // A real raw PTY checks Type Folio Unicode text, Ctrl keys, arrows,
    // Backspace, Enter and the dimensions delivered to the child.
    {
        TerminalView terminal; viewport(terminal);
        const QString python = QStringLiteral(
            "import os,tty,termios,fcntl,struct,signal\n"
            "tty.setraw(0)\n"
            "def size():\n"
            " s=struct.unpack('HHHH',fcntl.ioctl(0,termios.TIOCGWINSZ,b'\\0'*8)); return '%dx%d'%(s[1],s[0])\n"
            "signal.signal(signal.SIGWINCH,lambda *_:os.write(1,('RESIZE:'+size()+'>').encode()))\n"
            "os.write(1,('READY:'+size()+'>').encode())\n"
            "data=b''\n"
            "while not data.endswith(b'\\r'): data+=os.read(0,256)\n"
            "os.write(1,b'\\r\\nHEX:'+data.hex().encode()+b'\\r\\n')\n");
        terminal.startForTest("/usr/bin/python3", {"-u", "-c", python});
        const QString ready = QString("READY:%1x%2>").arg(terminal.terminalSize().width()).arg(terminal.terminalSize().height());
        assert(until([&] { return terminal.textForTest().contains(ready); }));
        const QSizeF previousCell = terminal.cellSize();
        QFont larger = terminal.font(); larger.setPointSize(30); terminal.setFont(larger);
        assert(terminal.cellSize() != previousCell);
        const QString resized = QString("RESIZE:%1x%2>").arg(terminal.terminalSize().width()).arg(terminal.terminalSize().height());
        assert(until([&] { return terminal.textForTest().contains(resized); }));
        terminal.vkbKeyPress(Qt::Key_A, Qt::NoModifier, QString::fromUtf8("ą"));
        terminal.vkbKeyPress(Qt::Key_C, Qt::ControlModifier);
        terminal.vkbKeyPress(Qt::Key_Left, Qt::NoModifier);
        terminal.vkbKeyPress(Qt::Key_Backspace, Qt::NoModifier);
        terminal.vkbKeyPress(Qt::Key_Return, Qt::NoModifier);
        assert(until([&] { return !terminal.running(); }));
        assert(terminal.textForTest().contains("HEX:c485031b5b447f0d"));
        assert(terminal.error().isEmpty());
    }

    // Exercise every F-key and modifier combination through a real raw PTY.
    // A capture file avoids losing a long hex report to bounded scrollback.
    {
        QTemporaryDir fixture; assert(fixture.isValid());
        const QString capture = fixture.path() + "/keys.bin";
        TerminalView terminal; viewport(terminal);
        QStringList rejections;
        QObject::connect(&terminal, &TerminalView::inputRejected, [&](const QString &reason) { rejections += reason; });
        terminal.startForTest("/usr/bin/python3", {"-u", "-c",
            "import os,tty,sys\ntty.setraw(0)\nos.write(1,b'KEY_CAPTURE_READY\\r\\n')\ndata=b''\n"
            "while not data.endswith(b'\\x1dEND_KEYS\\x1d'): data+=os.read(0,4096)\n"
            "open(sys.argv[1],'wb').write(data[:-10])\nos.write(1,b'KEY_CAPTURE_DONE\\r\\n')", capture}, true);
        assert(until([&] { return terminal.textForTest().contains("KEY_CAPTURE_READY"); }));
        QByteArray expected;
        const QList<QByteArray> plain{"\033OP", "\033OQ", "\033OR", "\033OS", "\033[15~", "\033[17~", "\033[18~", "\033[19~", "\033[20~", "\033[21~", "\033[23~", "\033[24~"};
        const QList<QByteArray> control{"\033[1;5P", "\033[1;5Q", "\033[1;5R", "\033[1;5S", "\033[15;5~", "\033[17;5~", "\033[18;5~", "\033[19;5~", "\033[20;5~", "\033[21;5~", "\033[23;5~", "\033[24;5~"};
        const QList<QByteArray> alt{"\033[1;3P", "\033[1;3Q", "\033[1;3R", "\033[1;3S", "\033[15;3~", "\033[17;3~", "\033[18;3~", "\033[19;3~", "\033[20;3~", "\033[21;3~", "\033[23;3~", "\033[24;3~"};
        const QList<QByteArray> both{"\033[1;7P", "\033[1;7Q", "\033[1;7R", "\033[1;7S", "\033[15;7~", "\033[17;7~", "\033[18;7~", "\033[19;7~", "\033[20;7~", "\033[21;7~", "\033[23;7~", "\033[24;7~"};
        for (int modifier : {int(Qt::NoModifier), int(Qt::ControlModifier), int(Qt::AltModifier), int(Qt::ControlModifier | Qt::AltModifier)}) {
            const auto &table = modifier == 0 ? plain : modifier == Qt::ControlModifier ? control : modifier == Qt::AltModifier ? alt : both;
            for (int key = 0; key < 12; ++key) {
                terminal.vkbKeyPress(Qt::Key_F1 + key, modifier); expected += table[key];
            }
        }
        // Explicit touch Ctrl+Alt shares the function-key encoder and is not
        // confused with a physical AltGr event that includes printable text.
        for (int key = 0; key < 12; ++key) {
            assert(terminal.cycleModifier(Qt::ControlModifier)); assert(terminal.cycleModifier(Qt::AltModifier));
            terminal.vkbKeyPress(Qt::Key_F1 + key, Qt::NoModifier); expected += both[key];
            assert(terminal.latchedModifiers() == 0 && terminal.lockedModifiers() == 0);
        }
        assert(!terminal.cycleModifier(Qt::ShiftModifier));
        assert(!terminal.lockModifier(Qt::ControlModifier | Qt::AltModifier));
        terminal.cycleModifier(Qt::ControlModifier);
        terminal.vkbKeyPress(Qt::Key_Control, Qt::ControlModifier);
        terminal.putString("");
        assert(terminal.latchedModifiers() == Qt::ControlModifier);
        terminal.putString(QString::fromUtf8("ą")); // Undefined Ctrl/Unicode chord sends no bytes.
        assert(rejections.size() == 1 && terminal.latchedModifiers() == Qt::ControlModifier);
        terminal.vkbKeyPress(Qt::Key_C, Qt::NoModifier, "c"); expected += '\003';
        assert(terminal.latchedModifiers() == 0);
        terminal.putString("c"); expected += 'c';
        terminal.cycleModifier(Qt::AltModifier); terminal.putString("x"); expected += "\033x";
        terminal.putString("x"); expected += 'x';
        terminal.lockModifier(Qt::AltModifier); terminal.vkbKeyPress(Qt::Key_Escape, Qt::NoModifier); expected += "\033\033";
        terminal.cycleModifier(Qt::AltModifier); terminal.vkbKeyPress(Qt::Key_Escape, Qt::NoModifier); expected += '\033';
        terminal.cycleModifier(Qt::ControlModifier); terminal.cycleModifier(Qt::AltModifier);
        terminal.vkbKeyPress(Qt::Key_C, Qt::NoModifier, "c"); expected += "\033\003";
        terminal.lockModifier(Qt::ControlModifier);
        terminal.putString("a"); terminal.vkbKeyPress(Qt::Key_B, Qt::NoModifier, "b"); expected += "\001\002";
        assert(terminal.lockedModifiers() == Qt::ControlModifier && terminal.latchedModifiers() == 0);
        terminal.cycleModifier(Qt::ControlModifier); terminal.putString("b"); expected += 'b';
        terminal.lockModifier(Qt::ControlModifier); terminal.cycleModifier(Qt::AltModifier);
        terminal.vkbKeyPress(Qt::Key_F1, Qt::NoModifier); expected += both[0];
        assert(terminal.lockedModifiers() == Qt::ControlModifier && terminal.latchedModifiers() == 0);
        terminal.vkbKeyPress(Qt::Key_F5, Qt::NoModifier); expected += control[4];
        terminal.clearModifiers(); terminal.vkbKeyPress(Qt::Key_F12, Qt::NoModifier); expected += plain[11];
        terminal.cycleModifier(Qt::AltModifier); terminal.putString(QString::fromUtf8("😀")); expected += QByteArray("\033") + QString::fromUtf8("😀").toUtf8();
        assert(terminal.latchedModifiers() == 0);
        terminal.vkbKeyPress(Qt::Key_A, Qt::ControlModifier | Qt::AltModifier, QString::fromUtf8("ą")); expected += QString::fromUtf8("ą").toUtf8();
        terminal.vkbKeyPress(Qt::Key_Q, Qt::GroupSwitchModifier, "@"); expected += '@';
        terminal.cycleModifier(Qt::ControlModifier); terminal.lockModifier(Qt::AltModifier);
        terminal.putString("synthetic-secret-paste");
        assert(terminal.latchedModifiers() == 0 && terminal.lockedModifiers() == 0 && rejections.size() == 2);
        terminal.lockModifier(Qt::AltModifier); terminal.vkbKeyPress(Qt::Key_X, Qt::NoModifier, "multi-character commit");
        assert(terminal.lockedModifiers() == 0 && rejections.size() == 3);
        terminal.cycleModifier(Qt::ControlModifier); terminal.putString(QString::fromUtf8("é"));
        assert(terminal.latchedModifiers() == 0 && rejections.size() == 4);
        for (const auto &reason : rejections) assert(!reason.contains("synthetic-secret") && !reason.contains("multi-character"));
        terminal.putString("ordinary paste\n"); expected += "ordinary paste\n";
        terminal.vkbKeyPress(Qt::Key_F1, Qt::ShiftModifier | Qt::ControlModifier | Qt::AltModifier); expected += "\033[1;8P";
        terminal.vkbKeyPress(Qt::Key_F12, Qt::ShiftModifier | Qt::ControlModifier | Qt::AltModifier); expected += "\033[24;8~";
        terminal.putString(QString::fromLatin1("\035END_KEYS\035"));
        terminal.lockModifier(Qt::AltModifier);
        assert(until([&] { return !terminal.running(); }));
        assert(terminal.latchedModifiers() == 0 && terminal.lockedModifiers() == 0);
        QFile recorded(capture); assert(recorded.open(QIODevice::ReadOnly));
        const QByteArray actual = recorded.readAll();
        if (actual != expected) qWarning() << "Key capture differs:" << actual.toHex() << expected.toHex();
        assert(actual == expected);
        assert(!terminal.textForTest().contains("synthetic-secret-paste"));
    }
    // Failed/offline sends do not consume next; lifecycle boundaries do clear
    // both next and locked without persisting them into another connection.
    {
        TerminalView terminal; viewport(terminal);
        terminal.cycleModifier(Qt::ControlModifier);
        terminal.vkbKeyPress(Qt::Key_C, Qt::NoModifier, "c");
        assert(terminal.latchedModifiers() == Qt::ControlModifier);
        terminal.lockModifier(Qt::AltModifier); terminal.stop();
        assert(terminal.latchedModifiers() == 0 && terminal.lockedModifiers() == 0);
        terminal.cycleModifier(Qt::ControlModifier); terminal.lockModifier(Qt::AltModifier);
        assert(!terminal.connectTo("-invalid", "test", "22"));
        assert(terminal.latchedModifiers() == 0 && terminal.lockedModifiers() == 0);
        terminal.lockModifier(Qt::ControlModifier);
        terminal.startForTest("/bin/sh", {"-c", "sleep .08; exec /bin/sh \"$1\"", "fixture", root + "/product/payload/system/rmssh-menu"});
        assert(terminal.lockedModifiers() == 0);
        terminal.lockModifier(Qt::ControlModifier); terminal.cycleModifier(Qt::AltModifier);
        assert(until([&] { return terminal.menuReady(); }));
        assert(terminal.latchedModifiers() == 0 && terminal.lockedModifiers() == 0);
        terminal.lockModifier(Qt::ControlModifier); terminal.sendMenuCommand("q");
        assert(terminal.lockedModifiers() == 0);
        assert(until([&] { return !terminal.running(); }));
    }
    printf("PASS real PTY F1-F12, Ctrl/Alt next+lock, physical AltGr, Unicode, paste rejection and lifecycle resets\n");

    // Never emit mouse escape sequences unless the remote enabled tracking.
    {
        TerminalView terminal; viewport(terminal);
        assert(!terminal.sendMouse(1, 1, 0));
        terminal.feedForTest("\033[?1000h\033[?1006h");
        assert(terminal.sendMouse(1, 1, 0));
        assert(!terminal.sendMouse(0, 1, 0));
        terminal.feedForTest("\033[?1000l");
        assert(!terminal.sendMouse(1, 1, 0));
    }

    // Exec failure information must survive even if waitpid wins the race
    // against the status-pipe notifier. No failure should close the app.
    for (int attempt = 0; attempt < 12; ++attempt) {
        TerminalView terminal; viewport(terminal); int quits = 0;
        QObject::connect(&terminal, &TerminalView::terminalQuit, [&] { ++quits; });
        terminal.startForTest("/paperterminal-test/no-such-program");
        assert(until([&] { return !terminal.running(); }));
        assert(!terminal.error().isEmpty()); assert(quits == 0);
    }

    // Graceful stop is asynchronous, the escalation kills an uncooperative
    // session, and its dedicated waiter reaps it without leaving a zombie.
    {
        TerminalView terminal; viewport(terminal);
        terminal.startForTest("/bin/sh", {"-c", "trap '' HUP; printf READY; sleep 30"});
        assert(until([&] { return terminal.textForTest().contains("READY"); }));
        const pid_t child = terminal.pidForTest();
        QElapsedTimer stop; stop.start(); terminal.stop(); assert(stop.elapsed() < 40);
        assert(until([&] { return !terminal.running(); }));
        assert(::kill(child, 0) == -1 && errno == ESRCH);
        int status; assert(::waitpid(child, &status, WNOHANG) == -1 && errno == ECHILD);
    }

    // Bounded nonblocking input and safe destruction of an active PTY.
    {
        auto terminal = std::make_unique<TerminalView>(); viewport(*terminal);
        terminal->startForTest("/bin/sh", {"-c", "trap '' HUP; stty -echo; printf READY; sleep 30"});
        assert(until([&] { return terminal->textForTest().contains("READY"); }));
        terminal->putString(QString(70000, QLatin1Char('x')));
        assert(!terminal->error().isEmpty()); assert(terminal->queuedForTest() <= 65536);
        const pid_t child = terminal->pidForTest(); terminal.reset();
        assert(until([&] { return ::kill(child, 0) == -1 && errno == ESRCH; }));
        int status; assert(::waitpid(child, &status, WNOHANG) == -1 && errno == ECHILD);
    }

    // Home consumes full input packets without typing profile numbers into
    // the launcher. A selected menu generation stays consumed until a newer
    // state is observed through PTY output; no idle state polling is needed.
    {
        TerminalView terminal; viewport(terminal);
        QStringList inputs; int readinessChanges = 0;
        QObject::connect(&terminal, &TerminalView::menuInput, [&](const QString &text) { inputs += text; });
        QObject::connect(&terminal, &TerminalView::menuReadyChanged, [&] { ++readinessChanges; });
        terminal.startForTest("/bin/sh", {root + "/product/payload/system/rmssh-menu"});
        assert(until([&] { return terminal.menuReady(); }));
        terminal.putString("12\rclipboard suffix\r");
        terminal.vkbKeyPress(Qt::Key_1, Qt::NoModifier, "1");
        terminal.vkbKeyPress(Qt::Key_Backspace, Qt::NoModifier);
        terminal.vkbKeyPress(Qt::Key_Return, Qt::NoModifier);
        terminal.vkbKeyPress(Qt::Key_Delete, Qt::NoModifier);
        terminal.vkbKeyPress(Qt::Key_Escape, Qt::NoModifier);
        assert(inputs == QStringList({"12\rclipboard suffix\r", "1", "\177", "\r", "\033[3~", "\033"}));
        assert(terminal.queuedForTest() == 0);
        assert(!terminal.sendMenuCommand("1")); assert(!terminal.sendMenuCommand("l\nq"));
        assert(terminal.menuReady());
        assert(terminal.sendMenuCommand("n")); assert(!terminal.menuReady());
        assert(!terminal.sendMenuCommand("l"));
        terminal.putString("late packet\r");
        terminal.vkbKeyPress(Qt::Key_L, Qt::NoModifier, "l");
        assert(!terminal.menuReady());
        assert(until([&] { return terminal.textForTest().remove('\n').contains("Host or IP address:"); }));
        assert(!terminal.menuReady());
        terminal.putString("\r"); // An empty host returns to a fresh menu.
        assert(until([&] { return terminal.menuReady(); }));
        const QString lateFile = temporaryHome.path() + "/late-menu-command-must-not-run";
        assert(terminal.sendMenuCommand("l")); assert(!terminal.menuReady());
        terminal.putString("touch " + lateFile + "\r");
        assert(!terminal.sendMenuCommand("n"));
        assert(until([&] { return terminal.textForTest().remove('\n').contains("Local shell. Type exit"); }));
        assert(!terminal.menuReady());
        terminal.putString("exit\r");
        assert(until([&] { return terminal.menuReady(); }));
        assert(!QFile::exists(lateFile));
        assert(readinessChanges >= 5);
        assert(terminal.sendMenuCommand("q")); assert(!terminal.menuReady());
        assert(until([&] { return !terminal.running(); }));
        assert(!terminal.menuReady());
    }
    {
        TerminalView terminal; viewport(terminal);
        terminal.startForTest("/usr/bin/python3", {"-u", "-c",
            "import os,time,select,termios\n"
            "mode=termios.tcgetattr(0); mode[3]&=~termios.ECHO; termios.tcsetattr(0,termios.TCSANOW,mode)\n"
            "path=os.environ['PAPERTERMINAL_STATE_FILE']\n"
            "def state(name,revision):\n fd=os.open(path,os.O_CREAT|os.O_WRONLY|os.O_TRUNC,0o600); os.write(fd,f'{name} {os.getpid()} {revision}\\n'.encode()); os.close(fd)\n"
            "state('ready',5); print('CHOICE',flush=True); input()\n"
            "state('busy',6); time.sleep(.2)\n"
            "assert not select.select([0],[],[],0)[0]\n"
            "print('NO_GHOST_INPUT',flush=True); state('ready',7); print('CHOICE',flush=True); input()"});
        assert(until([&] { return terminal.menuReady(); }));
        assert(terminal.sendMenuCommand("n"));
        for (int attempt = 0; attempt < 5; ++attempt) {
            assert(!terminal.sendMenuCommand("l")); assert(!terminal.menuReady());
            terminal.putString("1\r");
        }
        assert(!terminal.connectTo("127.0.0.1", "test", "1"));
        assert(until([&] { QFile state(terminal.stateFileForTest()); return state.open(QIODevice::ReadOnly) && state.readAll().startsWith("busy "); }));
        terminal.readForTest(); // A stale notifier/EAGAIN is not new output.
        terminal.putString("late packet must stay in Home\r");
        assert(until([&] { return terminal.menuReady(); }));
        assert(terminal.textForTest().contains("NO_GHOST_INPUT"));
        terminal.stop(); assert(!terminal.menuReady());
        assert(until([&] { return !terminal.running(); }));
    }
    // A profile's connectTo closes Home synchronously. Late Home packets and
    // commands cannot become stdin for the newly launched SSH client.
    {
        QTemporaryDir fixture; assert(fixture.isValid());
        const QString fakeSsh = fixture.path() + "/ssh";
        writeFile(fakeSsh, "#!/usr/bin/python3\nimport os,select,tty,time\ntty.setraw(0)\nprint('SSH_READY',flush=True)\ntime.sleep(.2)\nassert not select.select([0],[],[],0)[0]\nprint('NO_LATE_MENU_INPUT',flush=True)\n");
        QFile::setPermissions(fakeSsh, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        TerminalView terminal; viewport(terminal); terminal.sshForTest(fakeSsh);
        terminal.startForTest("/bin/sh", {root + "/product/payload/system/rmssh-menu"});
        assert(until([&] { return terminal.menuReady(); }));
        assert(terminal.connectTo("127.0.0.1", "test", "1")); assert(!terminal.menuReady());
        terminal.putString("1\rignored menu suffix\r");
        assert(until([&] { return terminal.textForTest().contains("SSH_READY"); }));
        assert(!terminal.sendMenuCommand("l"));
        assert(until([&] { return !terminal.running(); }));
        assert(terminal.textForTest().remove('\n').contains("NO_LATE_MENU_INPUT"));
        assert(!terminal.menuReady());
    }
    printf("PASS Home menu generations, full-packet keyboard interception and late-choice isolation\n");

    // A normal Open never interrupts an active local shell or SSH client.
    // Only explicit confirmation for the same process/generation can switch,
    // after validating the complete second profile before closing anything.
    {
        QTemporaryDir fixture; assert(fixture.isValid());
        const QString fakeSsh = fixture.path() + "/ssh", argumentsFile = fixture.path() + "/args";
        const QByteArray fixtureDirectory = fixture.path().toUtf8();
        writeFile(fakeSsh, "#!/usr/bin/python3\nimport os,sys,tty\ntty.setraw(0)\n"
            "open('" + fixtureDirectory + "/args','w').write('\\n'.join(sys.argv[1:]))\n"
            "os.write(1,b'REPLACEMENT_SSH_READY\\r\\n')\n"
            "while True:\n data=os.read(0,4096)\n if not data: break\n open('" + fixtureDirectory + "/input-'+str(os.getpid()),'ab').write(data)\n");
        QFile::setPermissions(fakeSsh, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        struct Profile { QString host, user, port; };
        const std::vector<Profile> profiles{{"first.fixture.invalid", "first-user", "22021"}, {"second.fixture.invalid", "second-user", "22022"}};
        const auto &second = profiles[1];
        TerminalView terminal; viewport(terminal); terminal.sshForTest(fakeSsh);
        terminal.startForTest("/bin/sh", {root + "/product/payload/system/rmssh-menu"});
        assert(until([&] { return terminal.menuReady(); }));
        assert(terminal.sendMenuCommand("l"));
        assert(until([&] { return terminal.textForTest().remove('\n').contains("Local shell. Type exit"); }));
        const pid_t localMenu = terminal.pidForTest();
        assert(!terminal.connectTo(second.host, second.user, second.port));
        const QString localToken = terminal.replacementToken();
        assert(!localToken.isEmpty()); assert(terminal.pidForTest() == localMenu);
        // Cancel has no native call: the local shell stays usable and no SSH
        // process nor connection command is sent behind the confirmation.
        spin(80);
        assert(terminal.replacementToken() == localToken && terminal.pidForTest() == localMenu);
        assert(!QFile::exists(argumentsFile)); assert(terminal.queuedForTest() == 0);
        assert(terminal.connectReplacing(second.host, second.user, second.port, "", localToken));
        assert(terminal.replacementToken().isEmpty());
        assert(until([&] { return terminal.pidForTest() != localMenu && terminal.textForTest().contains("REPLACEMENT_SSH_READY"); }));
        QFile arguments(argumentsFile); assert(arguments.open(QIODevice::ReadOnly));
        QByteArray argv = arguments.readAll(); arguments.close();
        assert(argv.endsWith("--\nsecond.fixture.invalid"));
        assert(argv.contains("-p\n22022\n-l\nsecond-user\n")); assert(!argv.contains("first.fixture.invalid"));
        const pid_t secondSsh = terminal.pidForTest();
        assert(!terminal.connectReplacing(second.host, second.user, second.port, "", localToken));
        assert(terminal.pidForTest() == secondSsh && terminal.replacementToken().isEmpty());
        // Validation failures consume confirmations without interrupting the
        // current SSH child. Invalid profiles do not even offer a dialog.
        assert(!terminal.connectTo(profiles[0].host, profiles[0].user, profiles[0].port));
        QString token = terminal.replacementToken(); assert(!token.isEmpty());
        assert(!terminal.connectReplacing("-invalid", second.user, second.port, "", token));
        assert(terminal.pidForTest() == secondSsh && terminal.replacementToken().isEmpty());
        assert(!terminal.connectTo(second.host, second.user, second.port, "bad-id"));
        assert(terminal.replacementToken().isEmpty() && terminal.pidForTest() == secondSsh);
        const QString missingId = terminal.createCredentialId();
        assert(!terminal.connectTo(second.host, second.user, second.port, missingId));
        assert(terminal.replacementToken().isEmpty() && terminal.pidForTest() == secondSsh);
        assert(!terminal.connectTo(second.host, second.user, second.port)); token = terminal.replacementToken();
        assert(!token.isEmpty());
        assert(!terminal.connectReplacing(second.host, second.user, second.port, missingId, token));
        assert(terminal.replacementToken().isEmpty() && terminal.pidForTest() == secondSsh);
        // A newer ordinary Open invalidates the earlier prompt even if the
        // same direct SSH process and PTY remain active.
        assert(!terminal.connectTo(second.host, second.user, second.port)); const QString older = terminal.replacementToken();
        assert(!terminal.connectTo(profiles[0].host, profiles[0].user, profiles[0].port));
        assert(!terminal.replacementToken().isEmpty() && terminal.replacementToken() != older);
        assert(!terminal.connectReplacing(second.host, second.user, second.port, "", older));
        assert(terminal.pidForTest() == secondSsh && terminal.replacementToken().isEmpty());
        assert(!terminal.connectTo(profiles[0].host, profiles[0].user, profiles[0].port)); token = terminal.replacementToken();
        assert(terminal.connectReplacing(profiles[0].host, profiles[0].user, profiles[0].port, "", token));
        assert(terminal.replacementToken().isEmpty());
        assert(until([&] { return terminal.pidForTest() != secondSsh && terminal.textForTest().contains("REPLACEMENT_SSH_READY"); }));
        assert(arguments.open(QIODevice::ReadOnly)); argv = arguments.readAll(); arguments.close();
        assert(argv.endsWith("--\nfirst.fixture.invalid")); assert(argv.contains("-p\n22021\n-l\nfirst-user\n"));
        assert(QDir(fixture.path()).entryList({"input-*"}, QDir::Files).isEmpty());
        assert(!terminal.connectTo(second.host, second.user, second.port)); assert(!terminal.replacementToken().isEmpty());
        terminal.stop(); assert(terminal.replacementToken().isEmpty());
        assert(until([&] { return !terminal.running(); }));
    }
    // A menu can run another local shell with exactly the same PID and PTY.
    // A token for busy revision3 cannot authorize replacement of revision5.
    {
        QTemporaryDir fixture; assert(fixture.isValid());
        const QString fakeSsh = fixture.path() + "/ssh";
        writeFile(fakeSsh, "#!/bin/sh\nprintf UNEXPECTED_REPLACEMENT\n");
        QFile::setPermissions(fakeSsh, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        TerminalView terminal; viewport(terminal); terminal.sshForTest(fakeSsh);
        terminal.startForTest("/usr/bin/python3", {"-u", "-c",
            "import os,time,sys\npath=os.environ['PAPERTERMINAL_STATE_FILE']\n"
            "def state(revision):\n fd=os.open(path,os.O_CREAT|os.O_WRONLY|os.O_TRUNC,0o600); os.write(fd,f'busy {os.getpid()} {revision}\\n'.encode()); os.close(fd)\n"
            "state(3); print('BUSY_THREE',flush=True); input()\nstate(5); print('BUSY_FIVE',flush=True); time.sleep(20)"});
        assert(until([&] { return terminal.textForTest().contains("BUSY_THREE"); }));
        const pid_t pid = terminal.pidForTest();
        assert(!terminal.connectTo("second.fixture.invalid", "fixture-user", "22022"));
        const QString token = terminal.replacementToken(); assert(!token.isEmpty());
        terminal.putString("next\r");
        assert(until([&] { return terminal.textForTest().contains("BUSY_FIVE"); }));
        assert(terminal.pidForTest() == pid);
        assert(!terminal.connectReplacing("second.fixture.invalid", "fixture-user", "22022", "", token));
        assert(terminal.pidForTest() == pid && terminal.replacementToken().isEmpty());
        assert(!terminal.textForTest().contains("UNEXPECTED_REPLACEMENT"));
        terminal.stop(); assert(until([&] { return !terminal.running(); }));
    }
    printf("PASS confirmed second-profile replacement, local/direct cancellation, validation, stale PID/generation/revision tokens and no PTY command injection\n");

    // Profile values are never typed into the PTY. A stale/busy/wrong-PID
    // state refuses connection. A current owner-only state permits direct
    // argv-based SSH to a deliberately closed local port, retaining errors.
    {
        TerminalView terminal; viewport(terminal);
        terminal.startForTest("/bin/sh", {"-c", "umask 077; mkdir -p \"$HOME/.config/rmssh\"; printf 'ready %s\\n' \"$$\" > \"$PAPERTERMINAL_STATE_FILE\"; trap 'exit 0' HUP; printf READY; while :; do sleep 1; done"});
        assert(until([&] { return terminal.textForTest().contains("READY"); }));
        assert(!terminal.connectTo("-oProxyCommand=bad", "root", "22"));
        assert(!terminal.connectTo("localhost\n", "root", "22"));
        const QString state = terminal.stateFileForTest();
        writeFile(state, "ready 1\n"); QFile::setPermissions(state, QFile::ReadOwner | QFile::WriteOwner);
        assert(!terminal.connectTo("127.0.0.1", "test", "1"));
        writeFile(state, "busy " + QByteArray::number(terminal.pidForTest()) + '\n');
        assert(!terminal.connectTo("::1", "test", "1"));
        writeFile(state, "ready " + QByteArray::number(terminal.pidForTest()) + '\n');
        QFile::setPermissions(state, QFile::ReadOwner | QFile::WriteOwner | QFile::ReadOther);
        assert(!terminal.connectTo("127.0.0.1", "test", "1"));
        QFile::setPermissions(state, QFile::ReadOwner | QFile::WriteOwner);
        assert(terminal.connectTo("127.0.0.1", "test", "1"));
        const bool closed = until([&] { return !terminal.running() && terminal.textForTest().remove('\n').contains("Press Enter"); }, 6000);
        if (!closed) qWarning() << "SSH close state" << terminal.running() << terminal.error() << terminal.textForTest();
        assert(closed);
        assert(terminal.textForTest().contains("refused", Qt::CaseInsensitive));
        assert(terminal.textForTest().contains("code 255"));
        terminal.vkbKeyPress(Qt::Key_X, Qt::NoModifier, "x"); spin(120); assert(!terminal.running());
        // Open another saved session directly from the closed-SSH screen;
        // requiring an invisible Enter in the old local menu was the bug.
        assert(terminal.connectTo("127.0.0.1", "test", "1"));
        assert(until([&] { return !terminal.running() && terminal.textForTest().remove('\n').contains("Press Enter"); }, 6000));
        assert(!QFile::exists(state));
    }

    // A user can open a saved session immediately, before the local launcher
    // has written ready. No user input means it cannot be an active shell.
    {
        qputenv("PAPERDESK_RMSSH_START_DELAY", "0.4");
        TerminalView terminal; viewport(terminal);
        terminal.startForTest("/bin/sh", {root + "/product/payload/system/rmssh-menu"});
        const QString state = terminal.stateFileForTest();
        assert(terminal.connectTo("127.0.0.1", "test", "1"));
        assert(until([&] { return !terminal.running() && terminal.textForTest().remove('\n').contains("Press Enter"); }, 6000));
        assert(!QFile::exists(state));
        qunsetenv("PAPERDESK_RMSSH_START_DELAY");
    }

    // Credentials are opt-in per profile, independent even for duplicate
    // endpoints, private, atomically bound to their endpoint, and never read
    // back into QML. Refusals do not become persistent runtime error overlays.
    {
        auto terminal = std::make_unique<TerminalView>(); viewport(*terminal);
        terminal->startForTest("/bin/sh", {root + "/product/payload/system/rmssh-menu"});
        const QString state = terminal->stateFileForTest();
        assert(until([&] { return QFile::exists(state); }));
        const pid_t child = terminal->pidForTest(); terminal.reset();
        assert(until([&] { return ::kill(child, 0) == -1 && errno == ESRCH; }));
        assert(!QFile::exists(state));
        assert(!QFile::exists(state + '.' + QString::number(child)));
    }
    {
        TerminalView terminal; viewport(terminal);
        const QString id = terminal.createCredentialId(), other = terminal.createCredentialId();
        const QString secret = QString::fromUtf8("synthetic-test-secret-ą");
        assert(terminal.forgetPassword(id)); assert(terminal.forgetPassword(id));
        assert(terminal.savePassword(id, "127.0.0.1", "test", "1", secret));
        assert(terminal.hasSavedPassword(id, "127.0.0.1", "test", "1"));
        assert(!terminal.hasSavedPassword(other, "127.0.0.1", "test", "1"));
        assert(!terminal.hasSavedPassword(id, "other-host", "test", "1"));
        const QString file = terminal.passwordFileForTest(id);
        struct stat permissions{}; assert(::stat(QFile::encodeName(file).constData(), &permissions) == 0);
        assert((permissions.st_mode & 0777) == 0600);
        assert(::stat(QFile::encodeName(QFileInfo(file).absolutePath()).constData(), &permissions) == 0);
        assert((permissions.st_mode & 0777) == 0700);
        assert(terminal.savePassword(other, "127.0.0.1", "test", "1", "independent-test-secret"));
        assert(terminal.forgetPassword(other));
        assert(terminal.hasSavedPassword(id, "127.0.0.1", "test", "1"));
        assert(!terminal.connectTo("other-host", "test", "1", id));
        assert(!terminal.sessionError().isEmpty()); assert(terminal.error().isEmpty());
        assert(::chmod(QFile::encodeName(file).constData(), 0644) == 0);
        assert(!terminal.hasSavedPassword(id, "127.0.0.1", "test", "1"));
        assert(terminal.savePassword(id, "127.0.0.1", "test", "1", secret));

        QTemporaryDir fixture; assert(fixture.isValid());
        const QString fakeSsh = fixture.path() + "/ssh";
        const QString manual = "manual-synthetic-second-password";
        const QByteArray secretHash = QCryptographicHash::hash(secret.toUtf8(), QCryptographicHash::Sha256).toHex();
        const QByteArray manualHash = QCryptographicHash::hash(manual.toUtf8(), QCryptographicHash::Sha256).toHex();
        const QByteArray fakeSource = "#!/usr/bin/python3\nimport os,subprocess,hashlib,sys\n"
            "helper=os.environ['SSH_ASKPASS']\n"
            "env=dict(os.environ,SSH_ASKPASS_PROMPT='confirm')\n"
            "answer=subprocess.check_output([helper,'HOST_KEY_CONFIRM (yes/no)? '],env=env).strip()\n"
            "assert answer==b'yes'\n"
            "answer=subprocess.check_output([helper,\"test@127.0.0.1's password: \"],env=os.environ).rstrip(b'\\n')\n"
            "assert hashlib.sha256(answer).hexdigest()=='" + secretHash + "'\n"
            "assert answer not in b'\\0'.join(x.encode() for x in sys.argv)\n"
            "assert answer not in b'\\0'.join((k+'='+v).encode() for k,v in os.environ.items())\n"
            "print('STORED_PASSWORD_CHANNEL_OK',flush=True)\n"
            "answer=subprocess.check_output([helper,'Second password: '],env=os.environ).rstrip(b'\\n')\n"
            "assert hashlib.sha256(answer).hexdigest()=='" + manualHash + "'\n"
            "print('MANUAL_PASSWORD_NOECHO_OK',flush=True)\n";
        writeFile(fakeSsh, fakeSource); QFile::setPermissions(fakeSsh, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        terminal.sshForTest(fakeSsh);
        assert(terminal.connectTo("127.0.0.1", "test", "1", id));
        assert(until([&] { return terminal.textForTest().contains("HOST_KEY_CONFIRM"); }));
        assert(!terminal.textForTest().contains("STORED_PASSWORD_CHANNEL_OK"));
        terminal.putString("yes\r");
        assert(until([&] { return terminal.textForTest().contains("Second password:"); }));
        terminal.putString(manual + '\r');
        assert(until([&] { return !terminal.running(); }));
        const QString screen = terminal.textForTest().remove('\n');
        assert(screen.contains("STORED_PASSWORD_CHANNEL_OK")); assert(screen.contains("MANUAL_PASSWORD_NOECHO_OK"));
        assert(!screen.contains(secret)); assert(!screen.contains(manual));
        assert(terminal.forgetPassword(id));
    }

    // Stock Dropbear has no askpass support. Its getpass is canonical/noecho;
    // the forced remote PTY is raw before remote output. Never auto-fill in
    // echo/raw modes, after manual input, twice, or for truncated prompts.
    for (const QByteArray &scenario : {QByteArray("auto"), QByteArray("echo"), QByteArray("raw"), QByteArray("manual"), QByteArray("wrong"), QByteArray("long")}) {
        TerminalView terminal; viewport(terminal);
        const QString id = terminal.createCredentialId();
        const QString user = scenario == "long" ? QString(70, 'u') : QStringLiteral("test");
        const QString secret = QStringLiteral("synthetic-dropbear-secret");
        const QString manual = QStringLiteral("manual-dropbear-attempt");
        assert(terminal.savePassword(id, "127.0.0.1", user, "1", secret));
        const QByteArray secretHash = QCryptographicHash::hash(secret.toUtf8(), QCryptographicHash::Sha256).toHex();
        const QByteArray manualHash = QCryptographicHash::hash(manual.toUtf8(), QCryptographicHash::Sha256).toHex();
        QTemporaryDir fixture; assert(fixture.isValid());
        const QString fakeSsh = fixture.path() + "/dropbear";
        const QByteArray fakeSource = "#!/usr/bin/python3\nimport os,sys,termios,tty,select,hashlib,time\n"
            "mode='" + scenario + "'\n"
            "assert 'DROPBEAR_PASSWORD' not in os.environ\n"
            "assert not any(x.startswith('UserKnownHostsFile=') for x in sys.argv)\n"
            "prompt=(sys.argv[sys.argv.index('-l')+1]+\"@127.0.0.1's password: \").encode()\n"
            "base=termios.tcgetattr(0)\n"
            "def noecho():\n t=termios.tcgetattr(0); t[3]|=termios.ICANON; t[3]&=~termios.ECHO; termios.tcsetattr(0,termios.TCSAFLUSH,t)\n"
            "if mode=='echo':\n os.write(1,prompt); time.sleep(.15); assert not select.select([0],[],[],0)[0]; print('ECHO_GUARD',flush=True); assert sys.stdin.readline().strip()=='yes'; noecho(); os.write(1,b'\\r\\n'+prompt)\n"
            "elif mode=='manual':\n print('MANUAL_READY',flush=True); assert sys.stdin.readline().strip()=='yes'; noecho(); os.write(1,prompt)\n"
            "elif mode=='raw':\n tty.setraw(0); os.write(1,prompt)\n"
            "else:\n noecho(); os.write(1,(b'other'+prompt if mode=='wrong' else prompt[:79]))\n"
            "if mode=='auto':\n"
            " answer=sys.stdin.buffer.readline().rstrip(b'\\n'); assert hashlib.sha256(answer).hexdigest()=='" + secretHash + "'\n"
            " assert answer not in b'\\0'.join(x.encode() for x in sys.argv); assert answer not in b'\\0'.join((k+'='+v).encode() for k,v in os.environ.items())\n"
            " os.write(1,b'\\r\\n'+prompt); print('SECOND_MANUAL',flush=True); answer=sys.stdin.buffer.readline().rstrip(b'\\n'); assert hashlib.sha256(answer).hexdigest()=='" + manualHash + "'\n"
            "else:\n time.sleep(.2); assert not select.select([0],[],[],0)[0]\n"
            "termios.tcsetattr(0,termios.TCSANOW,base); print('DROPBEAR_GUARD_OK',flush=True)\n";
        writeFile(fakeSsh, fakeSource); QFile::setPermissions(fakeSsh, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        terminal.sshForTest(fakeSsh, true);
        qputenv("DROPBEAR_PASSWORD", "must-not-be-inherited");
        assert(terminal.connectTo("127.0.0.1", user, "1", id));
        qunsetenv("DROPBEAR_PASSWORD");
        if (scenario == "echo" || scenario == "manual") {
            assert(until([&] { return terminal.textForTest().remove('\n').contains(scenario == "echo" ? "ECHO_GUARD" : "MANUAL_READY"); }));
            assert(terminal.passwordPendingForTest());
            if (scenario == "echo") terminal.putString("yes\r");
            else { terminal.vkbKeyPress(Qt::Key_Y, Qt::NoModifier, "y"); terminal.putString("es\r"); }
            assert(!terminal.passwordPendingForTest());
        } else if (scenario == "raw") {
            assert(until([&] { return terminal.textForTest().contains("password:"); }));
            assert(terminal.running()); assert(!terminal.passwordPendingForTest());
        } else if (scenario == "long") {
            assert(!terminal.passwordPendingForTest());
        } else if (scenario == "auto") {
            assert(until([&] { return terminal.textForTest().remove('\n').contains("SECOND_MANUAL"); }));
            assert(!terminal.passwordPendingForTest());
            terminal.putString(manual + '\r');
        }
        assert(until([&] { return !terminal.running(); }));
        assert(terminal.textForTest().remove('\n').contains("DROPBEAR_GUARD_OK"));
        assert(!terminal.textForTest().contains(secret)); assert(!terminal.textForTest().contains(manual));
        assert(!terminal.passwordPendingForTest());
        assert(terminal.forgetPassword(id));
    }
    printf("PASS Dropbear canonical/noecho, echo hostkey, raw spoof, manual cancellation, single attempt and truncated prompt guards\n");

    // Continuous output remains sliced while a GUI heartbeat runs; after
    // exit, the final diagnostic must still be visible (no tail truncation).
    {
        TerminalView terminal; viewport(terminal);
        int ticks = 0; qint64 longest = 0; QElapsedTimer gap; gap.start();
        QTimer heartbeat; heartbeat.setInterval(5);
        QObject::connect(&heartbeat, &QTimer::timeout, [&] { longest = std::max(longest, gap.restart()); ++ticks; });
        heartbeat.start();
        terminal.startForTest("/usr/bin/python3", {"-u", "-c", "import os; os.write(1,b'line 1234567890\\r\\n'*15000+b'END-OF-OUTPUT\\r\\n')"});
        assert(until([&] { return !terminal.running(); }, 12000));
        heartbeat.stop(); assert(ticks > 2); assert(longest < 120);
        assert(terminal.textForTest().contains("END-OF-OUTPUT"));
        printf("PTY flood heartbeat: %d ticks, longest %lld ms\n", ticks, static_cast<long long>(longest));
    }
    printf("PASS Paper Terminal: RCC local plugin, renderer, e-ink coalescing, real PTY/Unicode, safe argv SSH, bounded IO, async shutdown and reaping\n");
}
