// Exercise the production client against a real, isolated SSH protocol server.
#define PAPERTERMINAL_TESTING
#define PAPERTERMINAL_NO_PLUGIN
#include "../product/payload/apps/paperterminal/native/paperterminal-native.cpp"
#include <QtGui/QGuiApplication>
#include <QtCore/QDirIterator>
#include <cassert>
#include <functional>

static bool until(const std::function<bool()> &condition, int timeout = 8000) {
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < timeout) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
        QThread::msleep(1);
    }
    return condition();
}

int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) return 2;
    const QByteArray home = argv[1];
    qputenv("HOME", home);
    qputenv("XDG_CONFIG_HOME", home + "/config");
    QGuiApplication application(argc, argv);
    const QString host = argc == 4 ? QString::fromLocal8Bit(argv[3]) : QStringLiteral("127.0.0.1");
    const QString user = QStringLiteral("paperterminal-fixture");
    const QString port = QString::fromLocal8Bit(argv[2]);
    // Synthetic fixture only; never supplied by a user or used outside the
    // isolated loopback/LAN fixture.
    const QString password = QStringLiteral("PaperTerminal-local-test-42!");
    QString credentialId;
    {
        TerminalView writer;
        credentialId = writer.createCredentialId();
        assert(!credentialId.isEmpty());
        assert(writer.savePassword(credentialId, host, user, port, password));
        assert(writer.hasSavedPassword(credentialId, host, user, port));
        assert(!writer.hasSavedPassword(credentialId, host, user, QStringLiteral("1")));
        QDirIterator files(QString::fromLocal8Bit(home) + "/.config/paperterminal", QDir::Files, QDirIterator::Subdirectories);
        int secrets = 0;
        while (files.hasNext()) {
            struct stat info{};
            const QByteArray path = QFile::encodeName(files.next());
            assert(::stat(path.constData(), &info) == 0 && (info.st_mode & 0777) == 0600);
            ++secrets;
        }
        assert(secrets > 0);
    }
    TerminalView terminal;
    terminal.setWidth(1404); terminal.setHeight(1872);
    assert(terminal.hasSavedPassword(credentialId, host, user, port));
    assert(terminal.connectTo(host, user, port, credentialId));
    const bool hostKeyQuestion = until([&] {
        return terminal.textForTest().contains("yes/no", Qt::CaseInsensitive) ||
               terminal.textForTest().contains("fingerprint", Qt::CaseInsensitive);
    });
    assert(hostKeyQuestion);
    // The test itself explicitly approves this freshly generated test host key.
    const bool dropbear = QFileInfo(QStringLiteral("/usr/bin/ssh")).canonicalFilePath() == QStringLiteral("/usr/sbin/dropbearmulti");
    terminal.putString(dropbear ? QStringLiteral("y\r") : QStringLiteral("yes\r"));
    if (dropbear) {
        // Any manual input, including first host-key consent, cancels this
        // launch's autofill. The first password remains an explicit entry.
        assert(!terminal.passwordPendingForTest());
        assert(until([&] { return terminal.textForTest().contains("password:", Qt::CaseInsensitive); }));
        terminal.putString(password + '\r');
    }
    assert(until([&] { return !terminal.running(); }, 12000));
    assert(terminal.textForTest().contains("SSH_AUTHENTICATED_FIXTURE"));
    assert(!terminal.textForTest().contains(password));
    assert(terminal.textForTest().contains("Press Enter"));
    // Open another saved connection directly from retained exit diagnostics.
    assert(terminal.connectTo(host, user, port, credentialId));
    assert(until([&] { return !terminal.running(); }, 12000));
    assert(terminal.textForTest().contains("SSH_AUTHENTICATED_FIXTURE"));
    assert(!terminal.textForTest().contains(password));
    assert(terminal.error().isEmpty());
    assert(terminal.sessionError().isEmpty());
    assert(terminal.forgetPassword(credentialId));
    assert(!terminal.hasSavedPassword(credentialId, host, user, port));
    printf("PASS real system SSH: manual host key, persisted opt-in password, no password echo, closed-to-next Open\n");
}
