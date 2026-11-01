// Paper Terminal: original app-local Qt terminal/PTY integration.
// SPDX-License-Identifier: MIT
#include <QtCore/QCoreApplication>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDir>
#include <QtCore/QElapsedTimer>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSaveFile>
#include <QtCore/QTemporaryDir>
#include <QtCore/QUuid>
#include <QtCore/QProcessEnvironment>
#include <QtCore/QRegularExpression>
#include <QtCore/QSocketNotifier>
#include <QtCore/QThread>
#include <QtCore/QTimer>
#include <QtGui/QFontMetricsF>
#include <QtGui/QFontInfo>
#include <QtGui/QGlyphRun>
#include <QtGui/QKeyEvent>
#include <QtGui/QPainter>
#include <QtQml/QQmlExtensionPlugin>
#include <QtQml/qqml.h>
#include <QtQuick/QQuickPaintedItem>
#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cmath>
#include <csignal>
#include <cstring>
#include <memory>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include "terminal-core.h"

namespace {
void paperTerminalLibraryAnchor() {}
void eraseSecret(QByteArray &bytes) {
    if (!bytes.isEmpty()) {
        volatile char *data = bytes.data();
        for (qsizetype index = 0; index < bytes.size(); ++index) data[index] = 0;
    }
    bytes.clear();
}
}

class TerminalView : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QFont font READ font WRITE setFont NOTIFY fontChanged)
    Q_PROPERTY(bool ansiColors READ ansiColors WRITE setAnsiColors NOTIFY ansiColorsChanged)
    Q_PROPERTY(QSizeF cellSize READ cellSize NOTIFY cellSizeChanged)
    Q_PROPERTY(QSize terminalSize READ terminalSize NOTIFY terminalSizeChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString sessionError READ sessionError NOTIFY sessionErrorChanged)
    Q_PROPERTY(QString replacementToken READ replacementToken NOTIFY replacementTokenChanged)
    Q_PROPERTY(bool menuReady READ menuReady NOTIFY menuReadyChanged)
    Q_PROPERTY(int latchedModifiers READ latchedModifiers NOTIFY modifiersChanged)
    Q_PROPERTY(int lockedModifiers READ lockedModifiers NOTIFY modifiersChanged)
public:
    explicit TerminalView(QQuickItem *parent = nullptr) : QQuickPaintedItem(parent) {
        m_font.setFamily(QStringLiteral("DejaVu Sans Mono"));
        m_font.setPointSize(26);
        setOpaquePainting(true);
        setFillColor(Qt::white);
        setAntialiasing(false);
        m_frame.setSingleShot(true);
        connect(&m_frame, &QTimer::timeout, this, &TerminalView::flushFrame);
        connect(this, &QQuickItem::visibleChanged, this, [this] {
            if (isVisible()) redraw(); else m_frame.stop();
        });
        recalculateMetrics();
    }
    ~TerminalView() override {
        m_stopRequested = true;
        m_frame.stop();
        closePty();
        closeExecPipe();
        closePasswordChannel();
        removeMenuState();
        // Destruction ends this session immediately. Reaping happens in its
        // dedicated waiter; there is never a waitpid() on the UI thread.
        if (m_child && !m_child->reaped.load()) signalChild(m_child, SIGKILL);
    }
    QFont font() const { return m_font; }
    bool ansiColors() const { return m_ansiColors; }
    QSizeF cellSize() const { return m_cellSize; }
    QSize terminalSize() const { return QSize(m_core.columns(), m_core.rows()); }
    bool running() const { return bool(m_child); }
    QString error() const { return m_error; }
    QString sessionError() const { return m_sessionError; }
    QString replacementToken() const { return m_replacementToken; }
    bool menuReady() const { return m_menuReady; }
    int latchedModifiers() const { return m_latchedModifiers; }
    int lockedModifiers() const { return m_lockedModifiers; }
    Q_INVOKABLE bool cycleModifier(int modifier) {
        if (modifier != Qt::ControlModifier && modifier != Qt::AltModifier) return false;
        if ((m_latchedModifiers | m_lockedModifiers) & modifier) {
            m_latchedModifiers &= ~modifier; m_lockedModifiers &= ~modifier;
        } else m_latchedModifiers |= modifier;
        emit modifiersChanged(); return true;
    }
    Q_INVOKABLE bool lockModifier(int modifier) {
        if (modifier != Qt::ControlModifier && modifier != Qt::AltModifier) return false;
        if ((m_lockedModifiers & modifier) && !(m_latchedModifiers & modifier)) return true;
        m_latchedModifiers &= ~modifier; m_lockedModifiers |= modifier;
        emit modifiersChanged(); return true;
    }
    Q_INVOKABLE void clearModifiers() {
        if (!(m_latchedModifiers | m_lockedModifiers)) return;
        m_latchedModifiers = m_lockedModifiers = 0;
        emit modifiersChanged();
    }

    void setFont(const QFont &font) {
        if (m_font == font) return;
        m_font = font;
        recalculateMetrics();
        emit fontChanged();
    }
    void setAnsiColors(bool enabled) {
        if (m_ansiColors == enabled) return;
        m_ansiColors = enabled;
        redraw();
        emit ansiColorsChanged();
    }
    Q_INVOKABLE void start() {
        if (m_child) return;
        m_stopRequested = false;
        m_awaitingMenu = false;
        launch({QStringLiteral("/home/root/.local/bin/rmssh-menu"), {}, false});
    }
    Q_INVOKABLE void stop() {
        clearReplacementToken();
        clearModifiers();
        m_stopRequested = true;
        setMenuReady(false);
        m_awaitingMenu = false;
        if (m_nextLaunch) eraseSecret(m_nextLaunch->password);
        m_nextLaunch.reset();
        terminateCurrent();
    }
    Q_INVOKABLE QString createCredentialId() const { return QUuid::createUuid().toString(QUuid::WithoutBraces); }
    Q_INVOKABLE bool connectTo(const QString &host, const QString &user, const QString &port, const QString &credentialId = QString()) {
        clearReplacementToken();
        clearModifiers();
        Launch next; SecretCleanup secret{next.password};
        if (!prepareDirectLaunch(host, user, port, credentialId, next)) return false;
        if (m_stopRequested || m_nextLaunch) {
            setSessionError(QStringLiteral("The terminal is changing sessions. Try again shortly.")); return false;
        }
        if (m_child && m_directSsh) {
            if (ownedLiveChild()) offerReplacement(0);
            setSessionError(QStringLiteral("A connection is active. Close it before opening another connection."), true); return false;
        }
        quint64 revision = 0;
        const MenuState state = m_child ? menuState(&revision) : MenuState::Ready;
        const bool safeStartup = !m_menuInputSent && (state == MenuState::Missing || state == MenuState::Starting);
        if (m_child && (m_menuCommandPending || (state != MenuState::Ready && state != MenuState::Closed && !safeStartup))) {
            if (!m_menuCommandPending && state == MenuState::Busy && revision > 0 && ownedLiveChild()) offerReplacement(revision);
            setSessionError(QStringLiteral("Return to the local menu before opening another connection."), true); return false;
        }
        beginDirectLaunch(std::move(next));
        return true;
    }
    Q_INVOKABLE bool connectReplacing(const QString &host, const QString &user, const QString &port,
                                     const QString &credentialId, const QString &expectedToken) {
        const bool authorized = replacementMatches(expectedToken);
        const pid_t previousPid = m_replacementPid;
        const quint64 previousGeneration = m_replacementGeneration, previousRevision = m_replacementRevision;
        const bool previousDirect = m_replacementDirect;
        // A confirmation is single-use, including failed/stale confirmations.
        clearReplacementToken();
        if (!authorized) {
            setSessionError(QStringLiteral("The current session changed. Select the connection again.")); return false;
        }
        Launch next; SecretCleanup secret{next.password};
        if (!prepareDirectLaunch(host, user, port, credentialId, next)) return false;
        if (!sameReplacementChild(previousPid, previousGeneration, previousRevision, previousDirect)) {
            setSessionError(QStringLiteral("The current session changed. Select the connection again.")); return false;
        }
        beginDirectLaunch(std::move(next));
        return true;
    }
    Q_INVOKABLE bool sendMenuCommand(const QString &choice) {
        if (choice != QStringLiteral("n") && choice != QStringLiteral("l") && choice != QStringLiteral("q")) return false;
        refreshMenuReady();
        if (!m_menuReady || m_writes.size() != m_writeOffset) {
            setSessionError(QStringLiteral("Return to the local menu before choosing this option.")); return false;
        }
        quint64 revision = 0;
        if (menuState(&revision) != MenuState::Ready || revision == 0 || revision <= m_consumedMenuRevision) {
            setMenuReady(false); return false;
        }
        // Consume this exact menu generation before writing one whitelisted
        // command. Repeated clicks/keys cannot reach its upcoming shell/prompt.
        m_consumedMenuRevision = revision;
        m_menuCommandPending = true;
        m_menuInputSent = true;
        clearModifiers();
        setMenuReady(false); setSessionError({});
        enqueue(choice.toLatin1() + '\n');
        return true;
    }
    Q_INVOKABLE bool hasSavedPassword(const QString &credentialId, const QString &host, const QString &user, const QString &port) const {
        if (!validEndpoint(host, user, port) || !validCredentialId(credentialId)) return false;
        QByteArray password;
        const bool present = readPassword(credentialId, host, user, port, &password);
        eraseSecret(password);
        return present;
    }
    Q_INVOKABLE bool savePassword(const QString &credentialId, const QString &host, const QString &user, const QString &port, const QString &password) {
        QByteArray bytes = password.toUtf8();
        if (!validCredentialId(credentialId) || !validEndpoint(host, user, port) || bytes.isEmpty() || bytes.size() > 1024 ||
            bytes.contains('\0') || bytes.contains('\r') || bytes.contains('\n')) {
            eraseSecret(bytes);
            setSessionError(QStringLiteral("Enter a password of at most 1024 bytes without line breaks.")); return false;
        }
        if (!privatePasswordDirectory(true)) {
            eraseSecret(bytes);
            setSessionError(QStringLiteral("Cannot create a private password folder.")); return false;
        }
        const QString path = passwordPath(credentialId);
        struct stat existing{};
        const QByteArray nativePath = QFile::encodeName(path);
        if (::lstat(nativePath.constData(), &existing) == 0 &&
            (!S_ISREG(existing.st_mode) || existing.st_uid != ::geteuid() || existing.st_nlink != 1)) {
            eraseSecret(bytes); setSessionError(QStringLiteral("Cannot replace an unsafe password file.")); return false;
        }
        eraseSecret(bytes);
        bytes = QJsonDocument(QJsonObject{{"version", 1}, {"credentialId", credentialId}, {"host", host}, {"user", user},
            {"port", QString::number(port.toInt())}, {"password", password}}).toJson(QJsonDocument::Compact);
        QSaveFile file(path); file.setDirectWriteFallback(false);
        const bool saved = file.open(QIODevice::WriteOnly) &&
            file.setPermissions(QFile::ReadOwner | QFile::WriteOwner) && file.write(bytes) == bytes.size() && file.commit();
        eraseSecret(bytes);
        setSessionError(saved ? QString() : QStringLiteral("The password could not be saved privately."));
        return saved;
    }
    Q_INVOKABLE bool forgetPassword(const QString &credentialId) {
        if (!validCredentialId(credentialId)) { setSessionError(QStringLiteral("Invalid password identifier.")); return false; }
        const QString path = passwordPath(credentialId);
        const QByteArray nativePath = QFile::encodeName(path);
        struct stat info{};
        const bool absent = ::lstat(nativePath.constData(), &info) < 0 && errno == ENOENT;
        const bool removed = absent || (privatePasswordDirectory(false) && ::unlink(nativePath.constData()) == 0);
        setSessionError(removed ? QString() : QStringLiteral("The saved password could not be removed."));
        return removed;
    }
private:
    static bool validCredentialId(const QString &id) {
        static const QRegularExpression pattern(QStringLiteral("\\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z"));
        return pattern.match(id).hasMatch();
    }
    static bool validEndpoint(const QString &host, const QString &user, const QString &port, int *parsedPort = nullptr) {
        static const QRegularExpression hostPattern(QStringLiteral("\\A[A-Za-z0-9._:%][A-Za-z0-9._:%-]{0,254}\\z"));
        static const QRegularExpression userPattern(QStringLiteral("\\A[A-Za-z0-9_.@][A-Za-z0-9_.@-]{0,127}\\z"));
        static const QRegularExpression portPattern(QStringLiteral("\\A[0-9]{1,5}\\z"));
        bool portOk = false;
        const int number = port.toInt(&portOk);
        if (!hostPattern.match(host).hasMatch() || !userPattern.match(user).hasMatch() ||
            !portPattern.match(port).hasMatch() || !portOk || number < 1 || number > 65535) {
            return false;
        }
        if (parsedPort) *parsedPort = number;
        return true;
    }
public:
    Q_INVOKABLE void redraw() {
        m_fullDirty = true;
        scheduleFrame();
    }
    Q_INVOKABLE void putString(const QString &text) {
        if (!text.isEmpty()) cancelDropbearPassword();
        if (m_awaitingMenu) {
            if (text.contains('\r') || text.contains('\n')) start();
            return;
        }
        if (text.isEmpty()) return;
        if (m_latchedModifiers | m_lockedModifiers) {
            uint codepoint = 0;
            if (!singleCodepoint(text, &codepoint)) {
                rejectModifiedText(); return;
            }
            int key = int(codepoint);
            if (codepoint >= 'a' && codepoint <= 'z') key -= 'a' - 'A';
            else if (codepoint == '\r' || codepoint == '\n') key = Qt::Key_Return;
            else if (codepoint == '\t') key = Qt::Key_Tab;
            else if (codepoint == '\b' || codepoint == 127) key = Qt::Key_Backspace;
            else if (codepoint == 27) key = Qt::Key_Escape;
            // Unicode text has no implicit ASCII Ctrl key mapping. Alt alone
            // still prefixes its complete UTF-8 codepoint with one Escape.
            if (codepoint > 127) key = Qt::Key_unknown;
            vkbKeyPress(key, Qt::NoModifier, text);
            return;
        }
        const QByteArray bytes = text.toUtf8();
        if (interceptMenuInput(bytes)) return;
        if (m_child && !m_directSsh) m_menuInputSent = true;
        enqueue(bytes);
    }
    Q_INVOKABLE void scrollLines(int lines) {
        if (!lines) return;
        m_core.scroll(lines);
        collectDamage();
    }
    Q_INVOKABLE void mousePress(qreal, qreal y) { m_dragging = std::isfinite(y); m_dragY = y; }
    Q_INVOKABLE void mouseMove(qreal, qreal y) {
        if (!m_dragging || !std::isfinite(y)) return;
        const int lines = int((y - m_dragY) / m_cellSize.height());
        if (lines) { scrollLines(lines); m_dragY += lines * m_cellSize.height(); }
    }
    Q_INVOKABLE void mouseRelease(qreal x, qreal y) { mouseMove(x, y); m_dragging = false; }
    Q_INVOKABLE bool sendMouse(int column, int row, int button) {
        cancelDropbearPassword();
        refreshMenuReady();
        if (m_menuReady || m_menuCommandPending) return false;
        if (!m_core.mouseTracking() || m_core.scrollOffset() || column < 1 || row < 1 ||
            column > m_core.columns() || row > m_core.rows() || (button != 0 && button != 2)) return false;
        if (m_core.sgrMouse()) {
            const QByteArray location = QByteArray::number(column) + ';' + QByteArray::number(row);
            enqueue("\033[<" + QByteArray::number(button) + ';' + location + 'M' +
                    "\033[<" + QByteArray::number(button) + ';' + location + 'm');
        } else {
            if (column > 223 || row > 223) return false;
            QByteArray report("\033[M");
            report += char(32 + button); report += char(32 + column); report += char(32 + row);
            report += "\033[M"; report += char(35); report += char(32 + column); report += char(32 + row);
            enqueue(report);
        }
        return true;
    }
    Q_INVOKABLE void vkbKeyPress(int key, int modifiers, const QString &text = QString()) {
        cancelDropbearPassword();
        if (m_awaitingMenu) {
            if (key == Qt::Key_Return || key == Qt::Key_Enter) start();
            return;
        }
        if ((modifiers & Qt::ShiftModifier) && (key == Qt::Key_PageUp || key == Qt::Key_PageDown)) {
            scrollLines((key == Qt::Key_PageUp ? 1 : -1) * std::max(1, m_core.rows() - 1));
            return;
        }
        if (key == Qt::Key_Control || key == Qt::Key_Alt || key == Qt::Key_Shift || key == Qt::Key_Meta || key == Qt::Key_AltGr) return;
        const int physicalModifiers = modifiers;
        const int touchModifiers = m_latchedModifiers | m_lockedModifiers;
        if (touchModifiers && !text.isEmpty() && !singleCodepoint(text)) {
            rejectModifiedText(); return;
        }
        modifiers |= touchModifiers;
        QByteArray bytes;
        const bool control = modifiers & Qt::ControlModifier;
        const bool alt = modifiers & Qt::AltModifier;
        // AltGr belongs to the physical event. Explicit touch Ctrl+Alt must
        // encode a chord even when the IME supplies ordinary text for it.
        const bool altGr = (physicalModifiers & Qt::GroupSwitchModifier) ||
            ((physicalModifiers & Qt::ControlModifier) && (physicalModifiers & Qt::AltModifier) && !text.isEmpty());
        const int modifier = 1 + bool(modifiers & Qt::ShiftModifier) + 2 * alt + 4 * control + 8 * bool(modifiers & Qt::MetaModifier);
        auto csiKey = [&](char final) {
            if (modifier > 1) return QByteArray("\033[1;") + QByteArray::number(modifier) + final;
            return QByteArray(m_core.applicationCursor() ? "\033O" : "\033[") + final;
        };
        auto tildeKey = [&](int code) {
            return QByteArray("\033[") + QByteArray::number(code) +
                (modifier > 1 ? QByteArray(";") + QByteArray::number(modifier) : QByteArray()) + '~';
        };
        bool encodedModifiers = false;
        switch (key) {
        case Qt::Key_Up: bytes = csiKey('A'); encodedModifiers = true; break;
        case Qt::Key_Down: bytes = csiKey('B'); encodedModifiers = true; break;
        case Qt::Key_Right: bytes = csiKey('C'); encodedModifiers = true; break;
        case Qt::Key_Left: bytes = csiKey('D'); encodedModifiers = true; break;
        case Qt::Key_Home: bytes = csiKey('H'); encodedModifiers = true; break;
        case Qt::Key_End: bytes = csiKey('F'); encodedModifiers = true; break;
        case Qt::Key_Insert: bytes = tildeKey(2); encodedModifiers = true; break;
        case Qt::Key_Delete: bytes = tildeKey(3); encodedModifiers = true; break;
        case Qt::Key_PageUp: bytes = tildeKey(5); encodedModifiers = true; break;
        case Qt::Key_PageDown: bytes = tildeKey(6); encodedModifiers = true; break;
        case Qt::Key_Return: case Qt::Key_Enter: bytes = "\r"; break;
        case Qt::Key_Backspace: bytes = QByteArray(1, '\177'); break;
        case Qt::Key_Backtab: bytes = "\033[Z"; break;
        case Qt::Key_Tab: bytes = modifiers & Qt::ShiftModifier ? "\033[Z" : "\t"; break;
        case Qt::Key_Escape: bytes = QByteArray(1, '\033'); break;
        default:
            if (key >= Qt::Key_F1 && key <= Qt::Key_F4) {
                const char final = 'P' + key - Qt::Key_F1;
                bytes = modifier > 1 ? QByteArray("\033[1;") + QByteArray::number(modifier) + final : QByteArray("\033O") + final;
                encodedModifiers = true;
            } else if (key >= Qt::Key_F5 && key <= Qt::Key_F12) {
                static const int codes[] = {15, 17, 18, 19, 20, 21, 23, 24};
                bytes = tildeKey(codes[key - Qt::Key_F5]); encodedModifiers = true;
            } else if (control && !altGr) {
                if (key >= Qt::Key_A && key <= Qt::Key_Z) bytes = QByteArray(1, char(key - Qt::Key_A + 1));
                else if (key == Qt::Key_Space || key == Qt::Key_At) bytes = QByteArray(1, '\0');
                else if (key >= Qt::Key_BracketLeft && key <= Qt::Key_Underscore) bytes = QByteArray(1, char(key - Qt::Key_BracketLeft + 27));
                else if (key == Qt::Key_Question) bytes = QByteArray(1, '\177');
            } else if (!text.isEmpty()) bytes = text.toUtf8();
            else if (key >= Qt::Key_Space && key <= Qt::Key_AsciiTilde) {
                char character = char(key);
                if (key >= Qt::Key_A && key <= Qt::Key_Z && !(modifiers & Qt::ShiftModifier)) character += 'a' - 'A';
                bytes = QByteArray(1, character);
            }
        }
        if (bytes.isEmpty()) {
            if (touchModifiers && control && !altGr)
                emit inputRejected(QStringLiteral("No Ctrl shortcut for this character"));
            return;
        }
        if (alt && !altGr && !encodedModifiers) bytes.prepend('\033');
        if (interceptMenuInput(bytes)) return;
        if (m_child && !m_directSsh) m_menuInputSent = true;
        if (m_core.scrollOffset()) { m_core.scroll(-m_core.scrollOffset()); collectDamage(); }
        if (enqueue(bytes) && m_latchedModifiers) {
            m_latchedModifiers = 0; emit modifiersChanged();
        }
    }

    void paint(QPainter *painter) override { painter->drawImage(QPoint(0, 0), m_image); }

#ifdef PAPERTERMINAL_TESTING
    void startForTest(const QString &program, const QStringList &arguments = {}, bool direct = false) {
        m_stopRequested = false; m_awaitingMenu = false; launch({program, arguments, direct});
    }
    QString textForTest() const {
        QString out;
        for (int row = 0; row < m_core.rows(); ++row) {
            for (const auto &cell : m_core.line(row)) if (cell.codepoint) out += QString::fromUcs4(&cell.codepoint, 1);
            out += '\n';
        }
        return out;
    }
    const QImage &imageForTest() const { return m_image; }
    void feedForTest(const QByteArray &bytes) { m_core.feed(bytes.constData(), size_t(bytes.size())); collectDamage(); }
    bool framePendingForTest() const { return m_frame.isActive(); }
    pid_t pidForTest() const { return m_child ? m_child->pid : -1; }
    qsizetype queuedForTest() const { return m_writes.size() - m_writeOffset; }
    QString stateFileForTest() const { return m_menuStatePath; }
    QString passwordFileForTest(const QString &id) const { return passwordPath(id); }
    void sshForTest(const QString &path, bool dropbear = false) { m_testSsh = path; m_testDropbear = dropbear; }
    bool passwordPendingForTest() const { return !m_dropbearPassword.isEmpty(); }
    void readForTest() { readMaster(); }
#endif

signals:
    void fontChanged();
    void ansiColorsChanged();
    void cellSizeChanged();
    void terminalSizeChanged();
    void runningChanged();
    void errorChanged();
    void sessionErrorChanged();
    void replacementTokenChanged();
    void menuReadyChanged();
    void menuInput(const QString &text);
    void modifiersChanged();
    void inputRejected(const QString &reason);
    void displayBufferChanged();
    void terminalQuit();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override {
        QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
        if (newGeometry.size() != oldGeometry.size()) resizeTerminal();
    }
    void keyPressEvent(QKeyEvent *event) override {
        vkbKeyPress(event->key(), int(event->modifiers()), event->text());
        event->accept();
    }

private:
    struct SecretCleanup { QByteArray &bytes; ~SecretCleanup() { eraseSecret(bytes); } };
    struct Launch { QString program; QStringList arguments; bool direct = false; QByteArray password{}; QString message{}; bool dropbear = false; QByteArray passwordPrompt{}; };
    enum class MenuState { Missing, Starting, Ready, Closed, Busy, Unsafe };
    struct Child { pid_t pid = -1; std::atomic<bool> reaped{false}; int status = -1; };
    static constexpr int FrameIntervalMs = 90;
    static constexpr qsizetype WriteLimit = 64 * 1024;
    PaperTerminal::TerminalCore m_core;
    QFont m_font, m_paintFont;
    QRawFont m_normalRawFont, m_boldRawFont;
    QSizeF m_cellSize{16, 32};
    qreal m_baseline = 24;
    bool m_ansiColors = false, m_fullDirty = true, m_dragging = false;
    bool m_directSsh = false, m_stopRequested = false, m_awaitingMenu = false, m_childExitSeen = false;
    bool m_inputClosed = true;
    bool m_menuInputSent = false, m_menuReady = false, m_menuCommandPending = false;
    quint64 m_consumedMenuRevision = 0;
    int m_latchedModifiers = 0, m_lockedModifiers = 0;
    qreal m_dragY = 0;
    QString m_error;
    QString m_sessionError, m_menuStatePath;
    QString m_replacementToken;
    pid_t m_replacementPid = -1;
    quint64 m_replacementGeneration = 0, m_replacementRevision = 0;
    bool m_replacementDirect = false;
    int m_passwordSocket = -1;
    QSocketNotifier *m_passwordAcceptor = nullptr;
    std::unique_ptr<QTemporaryDir> m_passwordDirectory;
    QByteArray m_sessionPassword;
    QByteArray m_dropbearPassword, m_dropbearPrompt, m_dropbearLine;
    bool m_dropbearLineOverflow = false;
#ifdef PAPERTERMINAL_TESTING
    QString m_testSsh;
    bool m_testDropbear = false;
#endif
    QTimer m_frame;
    QElapsedTimer m_lastFrame;
    QImage m_image;
    std::vector<bool> m_dirtyRows;
    std::vector<uint64_t> m_rowHashes;
    int m_master = -1, m_execPipe = -1;
    QSocketNotifier *m_reader = nullptr, *m_writer = nullptr, *m_execReader = nullptr;
    QByteArray m_writes;
    qsizetype m_writeOffset = 0;
    QByteArray m_readPending;
    qsizetype m_readOffset = 0;
    quint64 m_generation = 0;
    std::shared_ptr<Child> m_child;
    std::unique_ptr<Launch> m_nextLaunch;

    bool prepareDirectLaunch(const QString &host, const QString &user, const QString &port,
                             const QString &credentialId, Launch &next) {
        int number = 0;
        if (!validEndpoint(host, user, port, &number)) {
            setSessionError(QStringLiteral("Enter a valid host, user and port (1–65535)."));
            return false;
        }
        // Fast Open can precede the menu's filesystem setup. Keep host-key
        // consent and persistence working on a completely fresh HOME too.
        const QByteArray sshDirectory = QFile::encodeName(QDir::homePath() + QStringLiteral("/.ssh"));
        struct stat sshInfo{};
        if ((::mkdir(sshDirectory.constData(), 0700) != 0 && errno != EEXIST) ||
            ::stat(sshDirectory.constData(), &sshInfo) != 0 || !S_ISDIR(sshInfo.st_mode) || sshInfo.st_uid != ::geteuid()) {
            setSessionError(QStringLiteral("Cannot create the SSH host-key folder.")); return false;
        }
        const QByteArray knownHosts = sshDirectory + "/known_hosts";
        const int hostKeys = ::open(knownHosts.constData(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (hostKeys >= 0) ::close(hostKeys);
        else if (errno != EEXIST) { setSessionError(QStringLiteral("Cannot create the SSH host-key file.")); return false; }
        QByteArray password;
        SecretCleanup secret{password};
        if (!credentialId.isEmpty() && !validCredentialId(credentialId)) {
            setSessionError(QStringLiteral("This connection has an invalid saved-password identifier.")); return false;
        }
        if (!credentialId.isEmpty() && !readPassword(credentialId, host, user, port, &password)) {
            setSessionError(QStringLiteral("The saved password file is not private or could not be read. Save it again or turn off Remember password."));
            return false;
        }
        bool dropbear = QFileInfo(QStringLiteral("/usr/bin/ssh")).canonicalFilePath() == QStringLiteral("/usr/sbin/dropbearmulti");
#ifdef PAPERTERMINAL_TESTING
        if (!m_testSsh.isEmpty()) dropbear = m_testDropbear;
#endif
        if (!dropbear && !password.isEmpty() && !QFileInfo(askpassHelper()).isExecutable()) {
            eraseSecret(password);
            setSessionError(QStringLiteral("The saved-password helper is missing. Reinstall Paper Terminal or turn off Remember password."));
            return false;
        }
        next = Launch{QStringLiteral("/usr/bin/ssh"),
            {QStringLiteral("-tt"), QStringLiteral("-o"), QStringLiteral("StrictHostKeyChecking=ask"),
             QStringLiteral("-o"), QStringLiteral("ServerAliveInterval=30"), QStringLiteral("-p"),
             QString::number(number), QStringLiteral("-l"), user, QStringLiteral("--"), host}, true, std::move(password)};
        if (!dropbear) {
            const qsizetype position = next.arguments.size() - 2;
            next.arguments.insert(position, QStringLiteral("-o"));
            next.arguments.insert(position + 1, QStringLiteral("UserKnownHostsFile=") + QDir::homePath() + QStringLiteral("/.ssh/known_hosts"));
        }
        next.dropbear = dropbear;
        next.passwordPrompt = user.toUtf8() + '@' + host.toUtf8() + "'s password: ";
        next.message = QStringLiteral("Connecting to %1@%2:%3...\r\n").arg(user, host, QString::number(number));
#ifdef PAPERTERMINAL_TESTING
        if (!m_testSsh.isEmpty()) next.program = m_testSsh;
#endif
        return true;
    }
    void beginDirectLaunch(Launch next) {
        clearReplacementToken(); clearModifiers(); setSessionError({});
        setMenuReady(false);
        m_awaitingMenu = false;
        if (m_child) {
            m_nextLaunch = std::make_unique<Launch>(std::move(next));
            terminateCurrent();
        } else launch(std::move(next));
    }
    bool ownedLiveChild() const {
        return m_child && m_child->pid > 0 && !m_child->reaped.load() && m_master >= 0 &&
            !m_inputClosed && !m_stopRequested && !m_nextLaunch;
    }
    bool sameReplacementChild(pid_t pid, quint64 generation, quint64 revision, bool direct) const {
        if (!ownedLiveChild() || m_child->pid != pid || m_generation != generation || m_directSsh != direct) return false;
        if (direct) return true;
        quint64 currentRevision = 0;
        return !m_menuCommandPending && revision > 0 && menuState(&currentRevision) == MenuState::Busy && currentRevision == revision;
    }
    bool replacementMatches(const QString &expected) const {
        return !expected.isEmpty() && expected == m_replacementToken &&
            sameReplacementChild(m_replacementPid, m_replacementGeneration, m_replacementRevision, m_replacementDirect);
    }
    void offerReplacement(quint64 revision) {
        m_replacementPid = m_child->pid; m_replacementGeneration = m_generation;
        m_replacementRevision = revision; m_replacementDirect = m_directSsh;
        m_replacementToken = QStringLiteral("%1:%2:%3:%4").arg(m_replacementPid).arg(m_replacementGeneration).arg(revision)
            .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
        emit replacementTokenChanged();
    }
    void clearReplacementToken() {
        if (m_replacementToken.isEmpty()) return;
        m_replacementToken.clear(); m_replacementPid = -1;
        m_replacementGeneration = m_replacementRevision = 0; m_replacementDirect = false;
        emit replacementTokenChanged();
    }
    static bool singleCodepoint(const QString &text, uint *codepoint = nullptr) {
        uint value = 0;
        if (text.size() == 1 && !text[0].isSurrogate()) value = text[0].unicode();
        else if (text.size() == 2 && text[0].isHighSurrogate() && text[1].isLowSurrogate())
            value = QChar::surrogateToUcs4(text[0], text[1]);
        else return false;
        if (codepoint) *codepoint = value;
        return true;
    }
    void rejectModifiedText() {
        clearModifiers();
        emit inputRejected(QStringLiteral("Paste blocked; Ctrl / Alt cleared"));
    }
    void setError(const QString &error) {
        if (!error.isEmpty()) clearReplacementToken();
        if (m_error == error) return;
        m_error = error; emit errorChanged();
    }
    void setSessionError(const QString &error, bool preserveReplacement = false) {
        if (!preserveReplacement) clearReplacementToken();
        if (m_sessionError == error) return;
        m_sessionError = error; emit sessionErrorChanged();
    }
    void setMenuReady(bool ready) {
        if (m_menuReady == ready) return;
        if (ready) { clearReplacementToken(); clearModifiers(); }
        m_menuReady = ready; emit menuReadyChanged();
    }
    void refreshMenuReady(bool outputObserved = false) {
        if (!m_child || m_directSsh || m_child->reaped.load() || m_stopRequested || m_nextLaunch || m_master < 0 || m_inputClosed) {
            setMenuReady(false); return;
        }
        quint64 revision = 0;
        const MenuState state = menuState(&revision);
        if (outputObserved && m_menuCommandPending && revision > m_consumedMenuRevision) m_menuCommandPending = false;
        setMenuReady(!m_menuCommandPending && state == MenuState::Ready && revision > m_consumedMenuRevision);
    }
    bool interceptMenuInput(const QByteArray &bytes) {
        if (bytes.isEmpty()) return true;
        const bool wasReady = m_menuReady;
        refreshMenuReady();
        if (m_menuReady) { emit menuInput(QString::fromUtf8(bytes)); return true; }
        // A packet queued for a disappearing Home must never become text in
        // the local shell/connection prompt selected by its previous packet.
        return wasReady || m_menuCommandPending || bool(m_nextLaunch);
    }
    static void signalChild(const std::shared_ptr<Child> &child, int signal) {
        if (!child || child->reaped.load()) return;
        // Each child is a new session leader, so our process is never in this group.
        if (::kill(-child->pid, signal) < 0 && errno == ESRCH) ::kill(child->pid, signal);
    }
    void recalculateMetrics() {
        m_paintFont = m_font;
        m_paintFont.setStyleHint(QFont::Monospace);
        m_paintFont.setFixedPitch(true);
        m_paintFont.setHintingPreference(QFont::PreferFullHinting);
        // Point sizes resolve against a screen; QPainter on QImage may use a
        // different DPI. Freeze that resolved size in pixels for both metrics
        // and painting so glyphs cannot grow beyond the terminal's cell grid.
        const int pixels = QFontInfo(m_paintFont).pixelSize();
        if (pixels > 0) m_paintFont.setPixelSize(pixels);
        const QFontMetricsF metrics(m_paintFont);
        const qreal naturalWidth = metrics.horizontalAdvance(QLatin1Char('M'));
        const QSizeF next(std::max(1.0, std::ceil(naturalWidth)), std::max(1.0, std::ceil(metrics.height() * 1.08)));
        m_paintFont.setLetterSpacing(QFont::AbsoluteSpacing, next.width() - naturalWidth);
        QFont normal = m_paintFont; normal.setBold(false);
        QFont bold = m_paintFont; bold.setBold(true);
        m_normalRawFont = QRawFont::fromFont(normal);
        m_boldRawFont = QRawFont::fromFont(bold);
        m_baseline = std::ceil(metrics.ascent());
        if (m_cellSize != next) { m_cellSize = next; emit cellSizeChanged(); }
        resizeTerminal();
    }
    void resizeTerminal() {
        const int columns = std::clamp(int(std::max(0.0, width()) / m_cellSize.width()), 2, 240);
        const int rows = std::clamp(int(std::max(0.0, height()) / m_cellSize.height()), 2, 160);
        if (columns != m_core.columns() || rows != m_core.rows()) {
            m_core.resize(columns, rows);
            if (m_master >= 0) {
                struct winsize size{}; size.ws_col = ushort(columns); size.ws_row = ushort(rows);
                size.ws_xpixel = ushort(std::clamp(int(width()), 0, 65535));
                size.ws_ypixel = ushort(std::clamp(int(height()), 0, 65535));
                ::ioctl(m_master, TIOCSWINSZ, &size);
            }
            emit terminalSizeChanged();
        }
        m_dirtyRows.assign(size_t(rows), true); m_fullDirty = true;
        scheduleFrame();
    }
    void collectDamage() {
        if (m_dirtyRows.size() != size_t(m_core.rows())) m_dirtyRows.assign(size_t(m_core.rows()), true);
        bool changed = false;
        for (int row : m_core.takeDirtyRows()) {
            if (row >= 0 && row < m_core.rows()) { m_dirtyRows[size_t(row)] = true; changed = true; }
        }
        const std::string replies = m_core.takeResponses();
        if (!replies.empty()) enqueue(QByteArray(replies.data(), qsizetype(replies.size())));
        if (changed) scheduleFrame();
    }
    void scheduleFrame() {
        if (m_frame.isActive() || !isVisible()) return;
        const int remaining = m_lastFrame.isValid() ? std::max(0, FrameIntervalMs - int(m_lastFrame.elapsed())) : 0;
        m_frame.start(remaining);
    }
    QColor displayColor(uint32_t rgb, bool background) const {
        if (m_ansiColors) {
            const int gray = qGray(QRgb(rgb | 0xff000000));
            // Four stable e-ink tones keep ANSI output legible without color.
            return QColor(gray < 64 ? 0 : gray < 128 ? 85 : gray < 192 ? 170 : 255,
                          gray < 64 ? 0 : gray < 128 ? 85 : gray < 192 ? 170 : 255,
                          gray < 64 ? 0 : gray < 128 ? 85 : gray < 192 ? 170 : 255);
        }
        return background && rgb == 0xffffff ? Qt::white : Qt::black;
    }
    void renderRow(QPainter &painter, int row) {
        const auto &cells = m_core.line(row);
        const qreal top = row * m_cellSize.height();
        painter.fillRect(QRectF(0, top, m_image.width(), m_cellSize.height()), Qt::white);
        // Paint all backgrounds before glyphs, so wide characters survive the
        // continuation column. Inverse and a static cursor preserve contrast.
        const bool cursorRow = m_core.cursorVisible() && m_core.cursorRow() == row;
        int cursorColumn = m_core.cursorColumn();
        if (cursorColumn > 0 && cursorColumn < int(cells.size()) && !cells[size_t(cursorColumn)].codepoint) --cursorColumn;
        const bool wideCursor = cursorColumn + 1 < int(cells.size()) && !cells[size_t(cursorColumn + 1)].codepoint;
        auto colors = [&](int column) {
            const auto &cell = cells[size_t(column)];
            QColor foreground = displayColor(cell.foreground, false);
            QColor background = displayColor(cell.background, true);
            if (foreground == background) foreground = background.lightness() < 128 ? Qt::white : Qt::black;
            if (cell.inverse) std::swap(foreground, background);
            if (cursorRow && (cursorColumn == column || (wideCursor && cursorColumn + 1 == column))) std::swap(foreground, background);
            if (foreground == background) foreground = background.lightness() < 128 ? Qt::white : Qt::black;
            return std::make_pair(foreground, background);
        };
        for (int column = 0; column < int(cells.size()); ++column) {
            const auto pair = colors(column);
            if (pair.second != Qt::white)
                painter.fillRect(QRectF(column * m_cellSize.width(), top, m_cellSize.width(), m_cellSize.height()), pair.second);
        }
        for (int column = 0; column < int(cells.size());) {
            const auto &cell = cells[size_t(column)];
            if (!cell.codepoint) { ++column; continue; }
            const auto pair = colors(column);
            QFont style = m_paintFont; style.setBold(cell.bold); style.setUnderline(cell.underline);
            painter.setFont(style); painter.setPen(pair.first);
            QString text;
            const int first = column;
            const bool ascii = cell.codepoint >= 32 && cell.codepoint <= 126;
            do {
                const auto &next = cells[size_t(column)];
                if (column != first && (!ascii || next.codepoint < 32 || next.codepoint > 126 ||
                    next.bold != cell.bold || next.underline != cell.underline || colors(column) != pair)) break;
                text += QString::fromUcs4(&next.codepoint, 1);
                ++column;
            } while (column < int(cells.size()));
            const QPointF origin(first * m_cellSize.width(), top + m_baseline);
            const QRawFont &rawFont = cell.bold ? m_boldRawFont : m_normalRawFont;
            if (ascii && rawFont.isValid()) {
                const QList<quint32> glyphs = rawFont.glyphIndexesForString(text);
                if (glyphs.size() == text.size() && !glyphs.contains(quint32(0))) {
                    // Even a monospace fallback can have varying hinted ASCII
                    // advances. Explicit positions avoid cumulative drift and
                    // clipped right-edge text while retaining one paint call
                    // for each run of matching attributes.
                    QList<QPointF> positions; positions.reserve(text.size());
                    for (qsizetype index = 0; index < text.size(); ++index)
                        positions.append(QPointF(index * m_cellSize.width(), 0));
                    QGlyphRun run; run.setRawFont(rawFont); run.setGlyphIndexes(glyphs);
                    run.setPositions(positions); run.setUnderline(cell.underline);
                    painter.drawGlyphRun(origin, run);
                    continue;
                }
            }
            // Unicode keeps Qt's font fallback. A missing raw font also uses
            // explicit cell origins, never an accumulating variable-width run.
            if (ascii) {
                for (qsizetype index = 0; index < text.size(); ++index)
                    painter.drawText(origin + QPointF(index * m_cellSize.width(), 0), text.mid(index, 1));
            } else painter.drawText(origin, text);
        }
    }
    void flushFrame() {
        // A malformed host layout must not allocate an unbounded backing image.
        const int imageWidth = std::clamp(int(std::ceil(width())), 1, 4096);
        const int imageHeight = std::clamp(int(std::ceil(height())), 1, std::min(4096, 4194304 / imageWidth));
        if (m_image.size() != QSize(imageWidth, imageHeight)) {
            m_image = QImage(imageWidth, imageHeight, QImage::Format_RGB32);
            m_image.fill(Qt::white); m_fullDirty = true;
        }
        // A larger font can leave fewer rows in the same backing image.
        // Clear the newly unused bottom/right margins during a full redraw.
        if (m_fullDirty) m_image.fill(Qt::white);
        QPainter painter(&m_image);
        painter.setRenderHint(QPainter::TextAntialiasing, false);
        QRect damage;
        if (m_rowHashes.size() != size_t(m_core.rows())) {
            m_rowHashes.assign(size_t(m_core.rows()), 0); m_fullDirty = true;
        }
        for (int row = 0; row < m_core.rows(); ++row) {
            if (!m_fullDirty && (size_t(row) >= m_dirtyRows.size() || !m_dirtyRows[size_t(row)])) continue;
            // Curses often redraws unchanged cells. Hash the final visible row
            // before painting so those writes do not refresh the e-ink panel.
            uint64_t hash = 14695981039346656037ULL;
            auto mix = [&](uint32_t value) { hash ^= value; hash *= 1099511628211ULL; };
            for (const auto &cell : m_core.line(row)) {
                mix(uint32_t(cell.codepoint)); mix(cell.foreground); mix(cell.background);
                mix(uint32_t(cell.bold) | uint32_t(cell.underline) << 1 | uint32_t(cell.inverse) << 2);
            }
            mix(m_core.cursorVisible() && m_core.cursorRow() == row ? uint32_t(m_core.cursorColumn() + 1) : 0);
            if (!m_fullDirty && m_rowHashes[size_t(row)] == hash) continue;
            m_rowHashes[size_t(row)] = hash;
            renderRow(painter, row);
            damage = damage.united(QRect(0, int(row * m_cellSize.height()), imageWidth, int(m_cellSize.height())));
        }
        if (m_fullDirty) damage = m_image.rect();
        painter.end();
        m_fullDirty = false; std::fill(m_dirtyRows.begin(), m_dirtyRows.end(), false);
        m_lastFrame.restart();
        if (!damage.isEmpty()) { update(damage); emit displayBufferChanged(); }
    }
    static QString passwordPath(const QString &credentialId) {
        return QDir::homePath() + QStringLiteral("/.config/paperterminal/passwords/") + credentialId;
    }
    static bool privatePasswordDirectory(bool create) {
        const QString home = QDir::homePath();
        const QStringList directories{home + "/.config", home + "/.config/paperterminal", home + "/.config/paperterminal/passwords"};
        for (int index = 0; index < directories.size(); ++index) {
            const QByteArray path = QFile::encodeName(directories[index]);
            if (create && ::mkdir(path.constData(), 0700) != 0 && errno != EEXIST) return false;
            struct stat info{};
            if (::lstat(path.constData(), &info) != 0 || !S_ISDIR(info.st_mode) || info.st_uid != ::geteuid()) return false;
            if (index > 0) {
                if (create && ::chmod(path.constData(), 0700) != 0) return false;
                if ((info.st_mode & 077) != 0 && !create) return false;
            }
        }
        return true;
    }
    static bool readPassword(const QString &credentialId, const QString &host, const QString &user, const QString &port, QByteArray *password) {
        if (!privatePasswordDirectory(false)) return false;
        const QByteArray nativePath = QFile::encodeName(passwordPath(credentialId));
        const int descriptor = ::open(nativePath.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
        if (descriptor < 0) return false;
        struct stat info{}; char data[8193]{};
        const bool safe = ::fstat(descriptor, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == ::geteuid() &&
            (info.st_mode & 0777) == 0600 && info.st_nlink == 1 && info.st_size > 0 && info.st_size <= 8192;
        ssize_t count = -1;
        if (safe) do { count = ::read(descriptor, data, sizeof data); } while (count < 0 && errno == EINTR);
        ::close(descriptor);
        if (!safe || count != info.st_size) return false;
        QByteArray recordBytes(data, int(count));
        volatile char *wipe = data;
        for (size_t index = 0; index < sizeof data; ++index) wipe[index] = 0;
        const QJsonObject record = QJsonDocument::fromJson(recordBytes).object(); eraseSecret(recordBytes);
        if (record.value("version").toInt() != 1 || record.value("credentialId").toString() != credentialId ||
            record.value("host").toString() != host || record.value("user").toString() != user ||
            record.value("port").toString() != QString::number(port.toInt()) || !record.value("password").isString()) return false;
        *password = record.value("password").toString().toUtf8();
        if (password->isEmpty() || password->size() > 1024 || password->contains('\0') || password->contains('\r') || password->contains('\n')) { eraseSecret(*password); return false; }
        return true;
    }
    static QString askpassHelper() {
        Dl_info info{};
        if (::dladdr(reinterpret_cast<void *>(&paperTerminalLibraryAnchor), &info) == 0 || !info.dli_fname) return {};
        return QFileInfo(QFile::decodeName(info.dli_fname)).absolutePath() + QStringLiteral("/paperterminal-askpass");
    }
    void cancelDropbearPassword() {
        eraseSecret(m_dropbearPassword);
        m_dropbearPrompt.clear(); m_dropbearLine.clear(); m_dropbearLineOverflow = false;
    }
    void observeDropbearOutput(const char *bytes, qsizetype count) {
        if (m_dropbearPassword.isEmpty()) return;
        struct termios mode{};
        // Dropbear's local getpass is canonical/noecho. Its forced-PTY
        // session enters raw before any remote channel output is serviced.
        // Once raw or any user input is seen, this launch can never auto-fill.
        if (::tcgetattr(m_master, &mode) != 0 || !(mode.c_lflag & ICANON)) {
            cancelDropbearPassword(); return;
        }
        for (qsizetype index = 0; index < count; ++index) {
            const char byte = bytes[index];
            if (byte == '\r' || byte == '\n') { m_dropbearLine.clear(); m_dropbearLineOverflow = false; }
            else if (m_dropbearLine.size() < 79) m_dropbearLine += byte;
            else m_dropbearLineOverflow = true;
        }
        if (m_dropbearLineOverflow || m_dropbearLine != m_dropbearPrompt || (mode.c_lflag & ECHO)) return;
        // Verify again immediately before a single bounded write. Never put
        // a secret behind user/terminal-response data in the async queue.
        if (!m_child || m_child->reaped.load() || m_writes.size() != m_writeOffset ||
            ::tcgetpgrp(m_master) != m_child->pid || ::tcgetattr(m_master, &mode) != 0 ||
            !(mode.c_lflag & ICANON) || (mode.c_lflag & ECHO)) {
            cancelDropbearPassword(); return;
        }
        bool stockProcess = QFileInfo(QStringLiteral("/proc/%1/exe").arg(m_child->pid)).canonicalFilePath() == QStringLiteral("/usr/sbin/dropbearmulti");
#ifdef PAPERTERMINAL_TESTING
        if (!m_testSsh.isEmpty() && m_testDropbear) stockProcess = true;
#endif
        if (!stockProcess) { cancelDropbearPassword(); return; }
        QByteArray answer; answer.swap(m_dropbearPassword); answer += '\n';
        cancelDropbearPassword();
        ssize_t written;
        do { written = ::write(m_master, answer.constData(), size_t(answer.size())); } while (written < 0 && errno == EINTR);
        const bool partial = written > 0 && written != answer.size();
        eraseSecret(answer);
        // A partial canonical line must never remain for a later remote shell.
        if (partial) { setError(QStringLiteral("Password input was interrupted. Open the connection again.")); terminateCurrent(); }
    }
    void closePasswordChannel() {
        cancelDropbearPassword();
        if (m_passwordAcceptor) { m_passwordAcceptor->setEnabled(false); delete m_passwordAcceptor; m_passwordAcceptor = nullptr; }
        if (m_passwordSocket >= 0) { ::close(m_passwordSocket); m_passwordSocket = -1; }
        m_passwordDirectory.reset();
        eraseSecret(m_sessionPassword);
    }
    bool openPasswordChannel(QByteArray password) {
        closePasswordChannel();
        m_passwordDirectory = std::make_unique<QTemporaryDir>(QDir::tempPath() + QStringLiteral("/paperterminal-askpass-XXXXXX"));
        if (!m_passwordDirectory->isValid()) { eraseSecret(password); closePasswordChannel(); return false; }
        const QByteArray path = QFile::encodeName(m_passwordDirectory->path() + "/channel");
        struct sockaddr_un address{}; address.sun_family = AF_UNIX;
        if (path.size() >= qsizetype(sizeof address.sun_path)) { eraseSecret(password); closePasswordChannel(); return false; }
        std::memcpy(address.sun_path, path.constData(), size_t(path.size() + 1));
        m_passwordSocket = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
        if (m_passwordSocket < 0 || ::bind(m_passwordSocket, reinterpret_cast<sockaddr *>(&address), sizeof address) != 0 ||
            ::chmod(path.constData(), 0600) != 0 || ::listen(m_passwordSocket, 2) != 0) {
            eraseSecret(password); closePasswordChannel(); return false;
        }
        m_sessionPassword.swap(password);
        m_passwordAcceptor = new QSocketNotifier(m_passwordSocket, QSocketNotifier::Read, this);
        connect(m_passwordAcceptor, &QSocketNotifier::activated, this, [this] {
            const int client = ::accept4(m_passwordSocket, nullptr, nullptr, SOCK_CLOEXEC | SOCK_NONBLOCK);
            if (client < 0) return;
            struct ucred peer{}; socklen_t length = sizeof peer;
            if (::getsockopt(client, SOL_SOCKET, SO_PEERCRED, &peer, &length) != 0 || peer.uid != ::geteuid()) {
                ::close(client); return;
            }
            const uint32_t size = uint32_t(m_sessionPassword.size());
            QByteArray payload;
            payload.append(char(size >> 24)); payload.append(char(size >> 16));
            payload.append(char(size >> 8)); payload.append(char(size)); payload += m_sessionPassword;
            // At most 1028 bytes, on a fresh private local connection. A
            // partial send is treated as failure by the framed helper reader.
            (void)::send(client, payload.constData(), size_t(payload.size()), MSG_NOSIGNAL);
            ::close(client); eraseSecret(payload); closePasswordChannel();
        });
        return true;
    }
    void removeMenuState() {
        if (m_menuStatePath.isEmpty()) return;
        QFile::remove(m_menuStatePath);
        if (m_child) QFile::remove(m_menuStatePath + '.' + QString::number(m_child->pid));
        m_menuStatePath.clear();
    }
    MenuState menuState(quint64 *revision = nullptr) const {
        if (revision) *revision = 0;
        if (!m_child) return MenuState::Missing;
        const QByteArray path = QFile::encodeName(m_menuStatePath);
        const int fd = ::open(path.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
        if (fd < 0) return errno == ENOENT ? MenuState::Missing : MenuState::Unsafe;
        struct stat info{}; char buffer[129]{};
        const bool safe = ::fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == ::geteuid() &&
                          (info.st_mode & 077) == 0 && info.st_nlink == 1 && info.st_size > 0 && info.st_size <= 128;
        const ssize_t count = safe ? ::read(fd, buffer, 128) : -1;
        ::close(fd);
        if (count <= 0) return MenuState::Unsafe;
        const QList<QByteArray> words = QByteArray(buffer, int(count)).simplified().split(' ');
        bool pidOk = false;
        if ((words.size() != 2 && words.size() != 3) || words[1].toLongLong(&pidOk) != m_child->pid || !pidOk) return MenuState::Unsafe;
        if (words.size() == 3) {
            bool revisionOk = false;
            const quint64 value = words[2].toULongLong(&revisionOk);
            if (!revisionOk || value == 0) return MenuState::Unsafe;
            if (revision) *revision = value;
        }
        if (words[0] == "ready") return MenuState::Ready;
        if (words[0] == "closed") return MenuState::Closed;
        if (words[0] == "starting") return MenuState::Starting;
        if (words[0] == "busy") return MenuState::Busy;
        return MenuState::Unsafe;
    }
    void terminateCurrent() {
        closePty(); closeExecPipe();
        closePasswordChannel();
        const auto child = m_child;
        signalChild(child, SIGHUP);
        if (child) QTimer::singleShot(300, QCoreApplication::instance(), [child] { signalChild(child, SIGKILL); });
        if (child && m_childExitSeen) finishChild(child);
    }
    void closeExecPipe() {
        if (m_execReader) { m_execReader->setEnabled(false); delete m_execReader; m_execReader = nullptr; }
        if (m_execPipe >= 0) { ::close(m_execPipe); m_execPipe = -1; }
    }
    void readExecStatus() {
        if (m_execPipe < 0) return;
        int failure = 0; ssize_t count;
        do { count = ::read(m_execPipe, &failure, sizeof failure); } while (count < 0 && errno == EINTR);
        if (count == sizeof failure)
            setError(QStringLiteral("Cannot start terminal program: ") + QString::fromLocal8Bit(std::strerror(failure)));
        if (count >= 0 || errno != EAGAIN) closeExecPipe();
    }
    void closePty() {
        clearReplacementToken();
        setMenuReady(false);
        cancelDropbearPassword();
        ++m_generation;
        if (m_reader) { m_reader->setEnabled(false); delete m_reader; m_reader = nullptr; }
        if (m_writer) { m_writer->setEnabled(false); delete m_writer; m_writer = nullptr; }
        if (m_master >= 0) { ::close(m_master); m_master = -1; }
        m_writes.clear(); m_writeOffset = 0;
        m_readPending.clear(); m_readOffset = 0;
        m_inputClosed = true;
    }
    bool enqueue(const QByteArray &bytes) {
        if (m_master < 0 || m_inputClosed || bytes.isEmpty()) return false;
        if (bytes.size() > WriteLimit - (m_writes.size() - m_writeOffset)) {
            setError(QStringLiteral("Terminal input is busy. Send a smaller amount of text.")); return false;
        }
        if (m_writeOffset) { m_writes.remove(0, m_writeOffset); m_writeOffset = 0; }
        m_writes += bytes;
        writeMaster();
        return !m_inputClosed;
    }
    void writeMaster() {
        if (m_master < 0) return;
        while (m_writeOffset < m_writes.size()) {
            const ssize_t written = ::write(m_master, m_writes.constData() + m_writeOffset, size_t(m_writes.size() - m_writeOffset));
            if (written > 0) { m_writeOffset += written; continue; }
            if (written < 0 && errno == EINTR) continue;
            if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) { m_writer->setEnabled(true); return; }
            // The slave may close while its final output is still buffered.
            // Stop input on write failure but preserve the read side so a
            // late terminal query cannot discard trailing SSH diagnostics.
            m_writer->setEnabled(false); m_writes.clear(); m_writeOffset = 0;
            m_inputClosed = true; return;
        }
        m_writes.clear(); m_writeOffset = 0; m_writer->setEnabled(false);
    }
    void readMaster() {
        if (m_master < 0) return;
        m_reader->setEnabled(false);
        QElapsedTimer budget; budget.start();
        qsizetype received = 0;
        bool exhausted = false, newOutputObserved = false;
        char bytes[256];
        const qsizetype limit = 32 * 1024;
        while (received < limit) {
            if (m_readOffset >= m_readPending.size()) {
                const ssize_t count = ::read(m_master, bytes, sizeof bytes);
                if (count > 0) {
                    newOutputObserved = true;
                    observeDropbearOutput(bytes, count);
                    if (m_master < 0) break;
                    m_readPending = QByteArray(bytes, int(count)); m_readOffset = 0;
                } else {
                    if (count < 0 && errno == EINTR) continue;
                    if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
                    closePty(); break; // EOF or PTY EIO after the slave closes.
                }
            }
            // Reading in modest blocks avoids syscall churn; feeding only
            // 16 bytes between budget checks bounds expensive repeated ANSI
            // full-screen operations on the tablet's slower ARM CPU.
            const qsizetype count = std::min(qsizetype(16), m_readPending.size() - m_readOffset);
            m_core.feed(m_readPending.constData() + m_readOffset, size_t(count));
            m_readOffset += count; received += count;
            if (budget.elapsed() >= 4) { exhausted = true; break; }
        }
        collectDamage();
        refreshMenuReady(newOutputObserved);
        if (m_master < 0) {
            if (m_childExitSeen && m_child) finishChild(m_child);
            return;
        }
        exhausted = exhausted || received >= limit;
        if (exhausted) {
            const quint64 generation = m_generation;
            QTimer::singleShot(5, this, [this, generation] { if (generation == m_generation && m_reader) readMaster(); });
        } else m_reader->setEnabled(true);
    }
    void finishChild(std::shared_ptr<Child> child) {
        if (m_child != child) return;
        clearReplacementToken();
        clearModifiers();
        closePty(); closeExecPipe();
        closePasswordChannel(); removeMenuState();
        const bool direct = m_directSsh;
        m_child.reset(); m_childExitSeen = false; emit runningChanged();
        if (m_nextLaunch && !m_stopRequested) {
            Launch next = std::move(*m_nextLaunch); m_nextLaunch.reset(); launch(std::move(next));
        } else if (direct && !m_stopRequested) {
            QString message = QStringLiteral("\r\nConnection closed");
            if (child->status >= 0 && WIFEXITED(child->status))
                message += QStringLiteral(" (code %1)").arg(WEXITSTATUS(child->status));
            message += QStringLiteral(". Press Enter to return to the menu.\r\n");
            const QByteArray bytes = message.toUtf8();
            m_core.feed(bytes.constData(), size_t(bytes.size()));
            m_awaitingMenu = true; collectDamage();
        } else if (!m_stopRequested && m_error.isEmpty()) emit terminalQuit();
    }
    void launch(Launch request) {
        clearReplacementToken();
        clearModifiers();
        if (m_child) { eraseSecret(request.password); return; }
        closePasswordChannel(); removeMenuState();
        setError({});
        const auto fail = [this](const QString &message) {
            closePasswordChannel(); removeMenuState(); setError(message);
        };
        const QByteArray program = QFile::encodeName(request.program);
        QList<QByteArray> arguments{program};
        for (const QString &argument : request.arguments) arguments.append(argument.toUtf8());
        QList<QByteArray> environment;
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.remove(QStringLiteral("LD_PRELOAD"));
        env.remove(QStringLiteral("DROPBEAR_PASSWORD"));
        env.remove(QStringLiteral("PAPERTERMINAL_ASKPASS_SOCKET"));
        env.remove(QStringLiteral("PAPERTERMINAL_STATE_FILE"));
        if (!request.direct) {
            m_menuStatePath = QDir::homePath() + QStringLiteral("/.config/rmssh/paperterminal-") +
                QUuid::createUuid().toString(QUuid::WithoutBraces) + QStringLiteral(".state");
            env.insert(QStringLiteral("PAPERTERMINAL_STATE_FILE"), m_menuStatePath);
        }
        if (request.dropbear && !request.password.isEmpty()) {
            // Stock 2025.89 has an 80-byte snprintf prompt. Never match an
            // ambiguous truncated endpoint; such connections stay manual.
            if (request.passwordPrompt.size() <= 79) {
                m_dropbearPassword.swap(request.password);
                m_dropbearPrompt = request.passwordPrompt;
            } else eraseSecret(request.password);
        } else if (!request.password.isEmpty()) {
            if (!openPasswordChannel(std::move(request.password))) {
                fail(QStringLiteral("Cannot create a private saved-password channel.")); return;
            }
            env.insert(QStringLiteral("SSH_ASKPASS"), askpassHelper());
            env.insert(QStringLiteral("SSH_ASKPASS_REQUIRE"), QStringLiteral("force"));
            env.remove(QStringLiteral("SSH_ASKPASS_PROMPT"));
            env.insert(QStringLiteral("PAPERTERMINAL_ASKPASS_SOCKET"), m_passwordDirectory->path() + "/channel");
        }
        env.insert(QStringLiteral("TERM"), QStringLiteral("xterm-256color"));
        env.insert(QStringLiteral("COLORTERM"), QStringLiteral(""));
        for (const QString &key : env.keys()) environment.append((key + '=' + env.value(key)).toUtf8());
        std::vector<char *> argv, envp;
        for (QByteArray &argument : arguments) argv.push_back(argument.data());
        argv.push_back(nullptr);
        for (QByteArray &entry : environment) envp.push_back(entry.data());
        envp.push_back(nullptr);
        const int master = ::posix_openpt(O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
        if (master < 0) { fail(QStringLiteral("Cannot open the terminal pseudo-device.")); return; }
        char slavePath[256];
        if (::grantpt(master) != 0 || ::unlockpt(master) != 0 || ::ptsname_r(master, slavePath, sizeof slavePath) != 0) {
            ::close(master); fail(QStringLiteral("Cannot initialize the terminal pseudo-device.")); return;
        }
        const int slave = ::open(slavePath, O_RDWR | O_NOCTTY | O_CLOEXEC);
        int errors[2] = {-1, -1};
        if (slave < 0 || ::pipe2(errors, O_CLOEXEC | O_NONBLOCK) != 0) {
            if (slave >= 0) ::close(slave);
            ::close(master);
            fail(QStringLiteral("Cannot create the terminal session.")); return;
        }
        struct winsize size{}; size.ws_col = ushort(m_core.columns()); size.ws_row = ushort(m_core.rows());
        ::ioctl(slave, TIOCSWINSZ, &size);
        // Build all Qt/string state before fork. The child uses only low-level
        // syscalls until execve(), avoiding allocator locks in xochitl.
        const int maxFd = std::clamp(int(::sysconf(_SC_OPEN_MAX)), 1024, 65536);
        sigset_t emptyMask; ::sigemptyset(&emptyMask);
        struct sigaction defaultSignal{}; defaultSignal.sa_handler = SIG_DFL; ::sigemptyset(&defaultSignal.sa_mask);
        const pid_t pid = ::fork();
        if (pid == 0) {
            ::close(errors[0]); ::close(master);
            int failure = 0;
            if (::setsid() < 0 || ::ioctl(slave, TIOCSCTTY, 0) < 0 ||
                ::dup2(slave, STDIN_FILENO) < 0 || ::dup2(slave, STDOUT_FILENO) < 0 || ::dup2(slave, STDERR_FILENO) < 0) failure = errno;
            ::sigprocmask(SIG_SETMASK, &emptyMask, nullptr);
            for (int number : {SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGPIPE, SIGCHLD}) ::sigaction(number, &defaultSignal, nullptr);
            // Keep the exec-status descriptor; all other inherited application
            // descriptors are closed, including those without FD_CLOEXEC.
            for (int descriptor = 3; descriptor < maxFd; ++descriptor) if (descriptor != errors[1]) ::close(descriptor);
            if (!failure) ::execve(program.constData(), argv.data(), envp.data());
            if (!failure) failure = errno;
            (void)::write(errors[1], &failure, sizeof failure);
            ::_exit(127);
        }
        ::close(slave); ::close(errors[1]);
        if (pid < 0) {
            ::close(master); ::close(errors[0]); fail(QStringLiteral("Cannot start the terminal process.")); return;
        }
        m_core.reset(); m_fullDirty = true;
        if (!request.message.isEmpty()) {
            const QByteArray message = request.message.toUtf8();
            m_core.feed(message.constData(), size_t(message.size()));
        }
        m_childExitSeen = false;
        m_directSsh = request.direct;
        m_menuInputSent = false; m_menuCommandPending = false; m_consumedMenuRevision = 0;
        setMenuReady(false);
        m_inputClosed = false;
        m_master = master; m_execPipe = errors[0];
        m_reader = new QSocketNotifier(master, QSocketNotifier::Read, this);
        m_writer = new QSocketNotifier(master, QSocketNotifier::Write, this); m_writer->setEnabled(false);
        connect(m_reader, &QSocketNotifier::activated, this, [this] { readMaster(); });
        connect(m_writer, &QSocketNotifier::activated, this, [this] { writeMaster(); });
        m_execReader = new QSocketNotifier(m_execPipe, QSocketNotifier::Read, this);
        connect(m_execReader, &QSocketNotifier::activated, this, &TerminalView::readExecStatus);
        const auto child = std::make_shared<Child>(); child->pid = pid; m_child = child;
        const QByteArray statePath = QFile::encodeName(m_menuStatePath);
        auto *waiter = QThread::create([child, statePath] {
            int status = 0; pid_t result;
            do { result = ::waitpid(child->pid, &status, 0); } while (result < 0 && errno == EINTR);
            if (result == child->pid) child->status = status;
            // Destruction can precede the child's last atomic state write.
            // Clean up after waitpid as well, without blocking the UI thread.
            if (!statePath.isEmpty()) {
                ::unlink(statePath.constData());
                const QByteArray temporary = statePath + '.' + QByteArray::number(child->pid);
                ::unlink(temporary.constData());
            }
            child->reaped.store(true);
        });
        connect(waiter, &QThread::finished, this, [this, child] {
            if (m_child != child) return;
            m_childExitSeen = true;
            readExecStatus();
            // Drain the remaining PTY output using the same 4 ms slices as a
            // live session. Preserve trailing SSH errors without a final UI
            // stall or an unbounded read when a child exits during a flood.
            if (m_master >= 0) readMaster();
            if (m_child == child && m_master < 0) finishChild(child);
        });
        connect(waiter, &QThread::finished, waiter, &QObject::deleteLater);
        waiter->start();
        scheduleFrame(); emit runningChanged();
    }
};

#ifndef PAPERTERMINAL_NO_PLUGIN
class PaperTerminalPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<TerminalView>(uri, 1, 0, "TerminalView"); }
};
#endif

#include "paperterminal-native.moc"
