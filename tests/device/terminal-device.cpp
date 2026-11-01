// Isolated, offscreen ARM smoke test for the actual Paper Terminal QML/plugin.
// It never opens the framebuffer or changes the running tablet interface.
#include <QtCore/QCoreApplication>
#include <QtCore/QDir>
#include <QtCore/QElapsedTimer>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QResource>
#include <QtCore/QThread>
#include <QtCore/QTimer>
#include <QtGui/QGuiApplication>
#include <QtGui/QImage>
#include <QtGui/QScreen>
#include <QtGui/QFont>
#include <QtGui/QFontInfo>
#include <QtGui/QFontMetricsF>
#include <QtGui/QPainter>
#include <cmath>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickView>
#include <functional>
#include <algorithm>
#include <termios.h>
#include <poll.h>
#include <unistd.h>

class ProbeCounter : public QObject {
    Q_OBJECT
public:
    int frames = 0, heartbeats = 0;
    qint64 maximumGapMs = 0;
    QElapsedTimer sinceBeat;
public slots:
    void frame() { ++frames; }
    void beat() {
        if (sinceBeat.isValid()) maximumGapMs = std::max(maximumGapMs, sinceBeat.elapsed());
        sinceBeat.restart(); ++heartbeats;
    }
};

static bool until(const std::function<bool()> &condition, int timeout = 6000) {
    QElapsedTimer elapsed; elapsed.start();
    while (!condition() && elapsed.elapsed() < timeout) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
        QThread::msleep(1);
    }
    return condition();
}
static void spin(int milliseconds) {
    QElapsedTimer elapsed; elapsed.start();
    until([&] { return elapsed.elapsed() >= milliseconds; }, milliseconds + 500);
}
static QByteArray read(const QString &path) {
    QFile file(path); return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}
static QJsonArray dimensions(QSize size) { return {size.width(), size.height()}; }

static QByteArray expectedRawInput() {
    // Literal xterm bytes, independent of the production encoder. Start with
    // the original UTF-8/control/navigation probe, then exercise touch state.
    QByteArray expected = QByteArray::fromHex("c485031b5b447f0d");
    expected += "\033OP\033OQ\033OR\033OS\033[15~\033[17~\033[18~\033[19~"
                "\033[20~\033[21~\033[23~\033[24~";
    expected += "\003c\033xx"; // Ctrl(next)+c, c; Alt(next)+x, x.
    expected += "\033[1;7P\033[15;7~\033[24;7~";
    expected += "\003\014c"; // Locked Ctrl+C/Ctrl+L, then clear and plain c.
    expected += "\033\030"; // Explicit touch Ctrl+Alt+x, not physical AltGr.
    expected += QString::fromUtf8("ą").toUtf8(); // Physical AltGr stays text.
    return expected;
}

static int captureRawInput(const QString &home) {
    struct termios saved{}, raw{};
    if (::tcgetattr(STDIN_FILENO, &saved) != 0) return 10;
    raw = saved; ::cfmakeraw(&raw);
    if (::tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) return 11;
    QFile ready(home + "/raw-ready");
    if (!ready.open(QIODevice::WriteOnly) || ready.write("READY") != 5) return 12;
    ready.close();
    QByteArray bytes;
    const qsizetype required = expectedRawInput().size();
    while (bytes.size() < required) {
        struct pollfd descriptor{STDIN_FILENO, POLLIN, 0};
        if (::poll(&descriptor, 1, 6000) <= 0) break;
        char buffer[128];
        const ssize_t count = ::read(STDIN_FILENO, buffer,
                                    size_t(std::min(qsizetype(sizeof buffer), required - bytes.size())));
        if (count <= 0) break;
        bytes.append(buffer, int(count));
    }
    ::tcsetattr(STDIN_FILENO, TCSANOW, &saved);
    QFile output(home + "/input.hex");
    if (!output.open(QIODevice::WriteOnly)) return 13;
    output.write(bytes.toHex(' '));
    return bytes.size() == required ? 0 : 14;
}

int main(int argc, char **argv) {
    if (argc == 3 && QByteArray(argv[1]) == "--capture-input")
        return captureRawInput(QString::fromLocal8Bit(argv[2]));
    QGuiApplication application(argc, argv);
    QCoreApplication::setOrganizationName("PaperDeskIsolatedDeviceProbe");
    QCoreApplication::setApplicationName("PaperTerminalOffscreenProbe");
    if (argc != 3) return 2;
    const QString stage = QString::fromLocal8Bit(argv[1]);
    const QString home = QDir::homePath();
    QJsonObject report{{"scope", "actual ARM plugin and full QML resource, offscreen only"},
                       {"qtVersion", qVersion()}, {"home", home},
                       {"physicalEinkLatencyMeasured", false}};
    bool passed = true;
    auto check = [&](const char *name, bool value) { report[name] = value; passed = passed && value; };
    check("homeIsIsolated", home == stage + "/home");
    check("resourceRegistered", QResource::registerResource(stage + "/app/resources.rcc"));
    QQuickView view;
    view.engine()->addImportPath(stage + "/imports");
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(1404, 1872);
    view.setSource(QUrl("qrc:/ui/main.qml"));
    check("fullQmlLoaded", view.status() == QQuickView::Ready);
    if (view.status() != QQuickView::Ready) {
        QJsonArray errors; for (const auto &error : view.errors()) errors.append(error.toString());
        report["qmlErrors"] = errors;
    }
    view.show();
    QObject *root = view.rootObject();
    QObject *terminal = root ? root->findChild<QObject *>("terminalRenderer") : nullptr;
    check("actualNativeRenderer", terminal && QByteArray(terminal->metaObject()->className()) == "TerminalView");
    ProbeCounter counter; QTimer heartbeat;
    QObject::connect(&heartbeat, &QTimer::timeout, &counter, &ProbeCounter::beat);
    heartbeat.start(10);
    if (terminal) {
        QObject::connect(terminal, SIGNAL(displayBufferChanged()), &counter, SLOT(frame()));
        check("ptyStarted", until([&] { return terminal->property("running").toBool(); }));
        auto send = [&](const QString &text) {
            return QMetaObject::invokeMethod(terminal, "putString", Q_ARG(QString, text));
        };
        spin(400);
        if (terminal->property("menuReady").toBool()) {
            bool selected = false;
            check("localShellSelectedThroughHomeApi", QMetaObject::invokeMethod(terminal, "sendMenuCommand",
                  Q_RETURN_ARG(bool, selected), Q_ARG(QString, QStringLiteral("l"))) && selected);
        } else send("l\r"); // Compatibility with the old two-field menu.
        spin(400);
        send("test -t 0 && test -t 1 && printf PTY_OK > \"$HOME/pty-proof\"; stty size > \"$HOME/size-before\"\r");
        check("interactivePtyAndShell", until([&] { return read(home + "/pty-proof") == "PTY_OK"; }));
        check("menuReadyInIsolatedHome", read(home + "/pty-proof") == "PTY_OK");
        const QSize originalSize = terminal->property("terminalSize").toSize();
        report["terminalColumnsRowsBefore"] = dimensions(originalSize);
        check("ptyDimensionsBefore", until([&] {
            return read(home + "/size-before").simplified() == QByteArray::number(originalSize.height()) + ' ' + QByteArray::number(originalSize.width());
        }));
        view.resize(1200, 1500); spin(200);
        const QSize resized = terminal->property("terminalSize").toSize();
        report["terminalColumnsRowsAfter"] = dimensions(resized);
        send("stty size > \"$HOME/size-after\"\r");
        check("ptyResizeDelivered", resized != originalSize && until([&] {
            return read(home + "/size-after").simplified() == QByteArray::number(resized.height()) + ' ' + QByteArray::number(resized.width());
        }));
        const QSizeF originalCell = terminal->property("cellSize").toSizeF();
        root->setProperty("terminalFontSize", root->property("terminalFontSize").toDouble() + 4);
        spin(250);
        const QSizeF largerCell = terminal->property("cellSize").toSizeF();
        check("qmlFontSizeChangesNativeCells", largerCell.width() > originalCell.width() && largerCell.height() > originalCell.height());
        send(stage + "/terminal-device --capture-input \"$HOME\"\r");
        check("rawInputReady", until([&] { return QFile::exists(home + "/raw-ready"); }));
        auto key = [&](int key, int modifiers, const QString &text = QString()) {
            return QMetaObject::invokeMethod(terminal, "vkbKeyPress", Q_ARG(int, key), Q_ARG(int, modifiers), Q_ARG(QString, text));
        };
        auto modifierAction = [&](const char *method, int modifier) {
            bool accepted = false;
            return QMetaObject::invokeMethod(terminal, method, Q_RETURN_ARG(bool, accepted), Q_ARG(int, modifier)) && accepted;
        };
        auto clearModifiers = [&] { return QMetaObject::invokeMethod(terminal, "clearModifiers"); };
        auto modifiersAre = [&](int latched, int locked) {
            return terminal->property("latchedModifiers").isValid() && terminal->property("lockedModifiers").isValid() &&
                terminal->property("latchedModifiers").toInt() == latched && terminal->property("lockedModifiers").toInt() == locked;
        };
        bool modifierStatesPassed = clearModifiers() && modifiersAre(0, 0);
        key(Qt::Key_A, Qt::NoModifier, QString::fromUtf8("ą"));
        key(Qt::Key_C, Qt::ControlModifier); key(Qt::Key_Left, Qt::NoModifier);
        key(Qt::Key_Backspace, Qt::NoModifier); key(Qt::Key_Return, Qt::NoModifier);
        for (int function = Qt::Key_F1; function <= Qt::Key_F12; ++function)
            key(function, Qt::NoModifier);
        modifierStatesPassed &= modifierAction("cycleModifier", Qt::ControlModifier) && modifiersAre(Qt::ControlModifier, 0);
        send("c"); modifierStatesPassed &= modifiersAre(0, 0); send("c");
        modifierStatesPassed &= modifierAction("cycleModifier", Qt::AltModifier) && modifiersAre(Qt::AltModifier, 0);
        send("x"); modifierStatesPassed &= modifiersAre(0, 0); send("x");
        for (int function : {Qt::Key_F1, Qt::Key_F5, Qt::Key_F12}) {
            modifierStatesPassed &= modifierAction("cycleModifier", Qt::ControlModifier);
            modifierStatesPassed &= modifierAction("cycleModifier", Qt::AltModifier);
            modifierStatesPassed &= modifiersAre(Qt::ControlModifier | Qt::AltModifier, 0);
            key(function, Qt::NoModifier);
            modifierStatesPassed &= modifiersAre(0, 0);
        }
        modifierStatesPassed &= modifierAction("lockModifier", Qt::ControlModifier) && modifiersAre(0, Qt::ControlModifier);
        send("c"); modifierStatesPassed &= modifiersAre(0, Qt::ControlModifier);
        send("l"); modifierStatesPassed &= modifiersAre(0, Qt::ControlModifier);
        modifierStatesPassed &= clearModifiers() && modifiersAre(0, 0); send("c");
        modifierStatesPassed &= modifierAction("cycleModifier", Qt::ControlModifier);
        modifierStatesPassed &= modifierAction("cycleModifier", Qt::AltModifier);
        send("x"); modifierStatesPassed &= modifiersAre(0, 0);
        key(Qt::Key_A, Qt::ControlModifier | Qt::AltModifier, QString::fromUtf8("ą"));
        check("touchModifierStateTransitions", modifierStatesPassed);
        check("rawInputCaptureCompleted", until([&] { return QFile::exists(home + "/input.hex"); }, 8000));
        const QByteArray actualInput = QByteArray::fromHex(read(home + "/input.hex"));
        const QByteArray expectedInput = expectedRawInput();
        report["rawInputHex"] = QString::fromLatin1(read(home + "/input.hex").simplified());
        report["expectedRawInputHex"] = QString::fromLatin1(expectedInput.toHex(' '));
        report["rawInputBytes"] = actualInput.size();
        check("unicodeControlArrowBackspaceEnter", actualInput.left(8) == expectedInput.left(8));
        check("allFunctionKeysAndTouchModifiersExact", actualInput == expectedInput);
        spin(150); counter.maximumGapMs = 0; counter.heartbeats = 0;
        const int framesBefore = counter.frames;
        QElapsedTimer flood; flood.start();
        send("i=0; while [ \"$i\" -lt 4000 ]; do printf 'Paper Terminal ARM output row %05d abcdefghijklmnopqrstuvwxyz\\n' \"$i\"; i=$((i+1)); done; printf DONE > \"$HOME/flood.done\"\r");
        check("outputFloodCompleted", until([&] { return read(home + "/flood.done") == "DONE"; }, 20000));
        spin(600);
        report["floodRows"] = 4000; report["floodElapsedMs"] = double(flood.elapsed());
        report["floodFrames"] = counter.frames - framesBefore;
        report["floodHeartbeats"] = counter.heartbeats;
        report["floodMaximumEventLoopGapMs"] = double(counter.maximumGapMs);
        check("outputRemainedResponsive", counter.heartbeats > 5 && counter.maximumGapMs < 1000);
        spin(300); const int framesBeforeIdle = counter.frames; spin(600);
        report["idleFramesIn600Ms"] = counter.frames - framesBeforeIdle;
        check("staticIdleWithoutRepaints", counter.frames == framesBeforeIdle);
        // Reusing an image after a font change must clear the partial bottom
        // row, even when the window's image dimensions did not change.
        root->setProperty("terminalFontSize", root->property("terminalFontSize").toDouble() + 3);
        spin(250);
        auto *item = qobject_cast<QQuickItem *>(terminal);
        const QImage fontResizeImage = view.grabWindow();
        const QSize fontResizeGrid = terminal->property("terminalSize").toSize();
        const QSizeF fontResizeCell = terminal->property("cellSize").toSizeF();
        int tailInk = 0, tailSamples = 0;
        if (item && !fontResizeImage.isNull()) {
            const QPointF origin = item->mapToScene(QPointF(0, 0));
            const qreal scaleX = qreal(fontResizeImage.width()) / view.width();
            const qreal scaleY = qreal(fontResizeImage.height()) / view.height();
            const int firstY = int((origin.y() + fontResizeGrid.height() * fontResizeCell.height()) * scaleY) + 1;
            const int endY = int((origin.y() + item->height()) * scaleY) - 1;
            for (int y = firstY; y < endY; ++y) {
                for (int x = int(origin.x() * scaleX) + 1; x < int((origin.x() + item->width()) * scaleX) - 1; ++x) {
                    if (x >= 0 && y >= 0 && x < fontResizeImage.width() && y < fontResizeImage.height()) {
                        ++tailSamples; if (qGray(fontResizeImage.pixel(x, y)) < 250) ++tailInk;
                    }
                }
            }
        }
        report["fontResizeBottomTailPixels"] = tailSamples;
        report["fontResizeBottomTailInkPixels"] = tailInk;
        check("fontResizeClearsBottomTail", tailSamples > 0 && tailInk == 0);
        view.resize(1404, 1872); spin(200);
        const int edgeColumns = terminal->property("terminalSize").toSize().width();
        QString edgeBody;
        while (edgeBody.size() < edgeColumns - 2) edgeBody += "AiWm0B";
        edgeBody.truncate(std::max(0, edgeColumns - 2));
        const QString edgeLine = "[" + edgeBody + "]";
        report["rightEdgeMarkerColumns"] = edgeColumns;
        send("printf '\\033[2J\\033[H\\033[?25lPAPER TERMINAL - ARM OFFSCREEN PROBE\\n\\n" + edgeLine +
             "\\n\\nNative plugin loaded from the full RCC.\\nPTY, UTF-8, control keys and resize exercised.\\n4000 output lines; timing is in the JSON.\\n\\nOffscreen only: no physical e-ink measurement.\\n'\r");
        spin(400);
        const QImage screenshot = view.grabWindow();
        const QFont font = terminal->property("font").value<QFont>();
        const QFontInfo info(font);
        const QFontMetricsF screenMetrics(font), imageMetrics(font, &screenshot);
        QImage defaultImage(2, 2, QImage::Format_RGB32);
        const QFontMetricsF defaultImageMetrics(font, &defaultImage);
        const QString sample = "Native QML plugin loaded from the full RCC resource.";
        const QSizeF finalCell = terminal->property("cellSize").toSizeF();
        const QSize finalGrid = terminal->property("terminalSize").toSize();
        auto paintMetrics = [&](bool normalizePixels, QFont::HintingPreference hinting) {
            QFont paintFont = font;
            paintFont.setStyleHint(QFont::Monospace);
            paintFont.setFixedPitch(true);
            paintFont.setHintingPreference(hinting);
            if (normalizePixels) paintFont.setPixelSize(QFontInfo(paintFont).pixelSize());
            const QFontMetricsF natural(paintFont);
            const qreal advance = natural.horizontalAdvance(QLatin1Char('M'));
            const qreal cell = std::ceil(advance);
            paintFont.setLetterSpacing(QFont::AbsoluteSpacing, cell - advance);
            QImage canvas(2200, 150, QImage::Format_RGB32); canvas.fill(Qt::white);
            QPainter painter(&canvas); painter.setFont(paintFont);
            painter.setRenderHint(QPainter::TextAntialiasing, false);
            const QFontMetricsF adjusted(paintFont), onImage(paintFont, &canvas);
            const QFontMetrics painterInteger = painter.fontMetrics();
            painter.setPen(Qt::black); painter.drawText(QPointF(0, 100), QString(64, QLatin1Char('M')));
            painter.end();
            int rightmostInk = -1;
            for (int y = 0; y < canvas.height(); ++y)
                for (int x = 0; x < canvas.width(); ++x)
                    if (qGray(canvas.pixel(x, y)) < 128) rightmostInk = std::max(rightmostInk, x);
            return QJsonObject{
                {"pixelNormalized", normalizePixels}, {"hintingPreference", int(hinting)},
                {"pointSize", paintFont.pointSizeF()},
                {"pixelSize", paintFont.pixelSize()}, {"resolvedPixelSize", QFontInfo(paintFont).pixelSize()},
                {"naturalMAdvance", advance}, {"roundedCellWidth", cell},
                {"absoluteLetterSpacing", paintFont.letterSpacing()},
                {"screenMAdvance", adjusted.horizontalAdvance(QLatin1Char('M'))},
                {"screenSampleAdvance", adjusted.horizontalAdvance(sample)},
                {"imageMAdvance", onImage.horizontalAdvance(QLatin1Char('M'))},
                {"imageSampleAdvance", onImage.horizontalAdvance(sample)},
                {"painterIntegerMAdvance", painterInteger.horizontalAdvance(QLatin1Char('M'))},
                {"painterIntegerSampleAdvance", painterInteger.horizontalAdvance(sample)},
                {"expected64MGridWidth", cell * 64}, {"painted64MRightmostInk", rightmostInk}
            };
        };
        report["fullHintingFontReference"] = paintMetrics(false, QFont::PreferFullHinting);
        report["pixelNormalizedFullHintingReference"] = paintMetrics(true, QFont::PreferFullHinting);
        report["pixelNormalizedVerticalHintingMetrics"] = paintMetrics(true, QFont::PreferVerticalHinting);
        report["fontMetricsNote"] = "Qt shaping metrics below are reference measurements. The final native backend positions ASCII glyphs explicitly at grid cells, so shaped-string advance can differ from the terminal grid without causing clipping.";
        report["finalFontMetrics"] = QJsonObject{
            {"requestedFamily", font.family()}, {"resolvedFamily", info.family()},
            {"pointSize", font.pointSizeF()}, {"pixelSize", font.pixelSize()},
            {"resolvedPointSize", info.pointSizeF()}, {"resolvedPixelSize", info.pixelSize()},
            {"terminalCellWidth", finalCell.width()}, {"terminalCellHeight", finalCell.height()},
            {"terminalColumns", finalGrid.width()}, {"terminalRows", finalGrid.height()},
            {"terminalItemWidth", terminal->property("width").toDouble()},
            {"terminalItemHeight", terminal->property("height").toDouble()},
            {"screenLogicalDpiX", view.screen()->logicalDotsPerInchX()},
            {"screenLogicalDpiY", view.screen()->logicalDotsPerInchY()},
            {"screenshotLogicalDpiX", screenshot.logicalDpiX()},
            {"screenshotLogicalDpiY", screenshot.logicalDpiY()},
            {"defaultImageLogicalDpiX", defaultImage.logicalDpiX()},
            {"defaultImageLogicalDpiY", defaultImage.logicalDpiY()},
            {"screenMAdvance", screenMetrics.horizontalAdvance(QLatin1Char('M'))},
            {"screenshotMAdvance", imageMetrics.horizontalAdvance(QLatin1Char('M'))},
            {"defaultImageMAdvance", defaultImageMetrics.horizontalAdvance(QLatin1Char('M'))},
            {"sample", sample}, {"sampleCharacters", sample.size()},
            {"screenSampleAdvance", screenMetrics.horizontalAdvance(sample)},
            {"screenshotSampleAdvance", imageMetrics.horizontalAdvance(sample)},
            {"defaultImageSampleAdvance", defaultImageMetrics.horizontalAdvance(sample)}
        };
        check("offscreenScreenshotSaved", !screenshot.isNull() && screenshot.save(stage + "/terminal-offscreen.png"));
        report["nativeError"] = terminal->property("error").toString();
        check("nativeErrorEmpty", terminal->property("error").toString().isEmpty());
        QMetaObject::invokeMethod(root, "unloading");
        check("ptyStoppedAndReaped", until([&] { return !terminal->property("running").toBool(); }));
    }
    const QByteArray maps = read("/proc/self/maps");
    check("noLiTermLoaded", !maps.contains("/literm.so"));
    check("noXoviLoaded", !maps.contains("/xovi.so"));
    check("nativePluginLoaded", maps.contains((stage + "/app/native/libpaperterminal_native.so").toUtf8()));
    report["passed"] = passed;
    QFile output(QString::fromLocal8Bit(argv[2]));
    if (!output.open(QIODevice::WriteOnly)) return 3;
    output.write(QJsonDocument(report).toJson(QJsonDocument::Indented));
    return passed ? 0 : 1;
}

#include "terminal-device.moc"
