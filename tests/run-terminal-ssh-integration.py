#!/usr/bin/env python3
"""Real OpenSSH authentication against an ephemeral loopback-only SSH fixture.

Requires Paramiko in the chosen Python environment. Uses only synthetic
credentials, a disposable HOME/host key, and never changes host SSH settings.
Run after `python3 scripts/build-terminal.py --test` builds the host helper.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading

import paramiko


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="docs/paperterminal-real-ssh-2026-11-01.json")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    cache = Path(os.environ.get("PAPERDESK_TOOLCACHE", "/home/lukasz/Documents/Codex/2026-09-25/m-2/work"))
    sdk = cache / "papersketch-qt-sdk/root"
    includes = sdk / "usr/include/x86_64-linux-gnu/qt6"
    work = root / "work/terminal-followup/real-ssh"
    work.mkdir(parents=True, exist_ok=True)
    driver = work / "terminal-ssh-integration"
    command = [os.environ.get("CXX", "g++"), "-std=c++17", "-O2", "-fPIC", "-Wall", "-Wextra",
               "-I" + str(includes), "-I" + str(root / "work/terminal-native-tests")]
    command += ["-I" + str(includes / module) for module in ("QtCore", "QtGui", "QtQml", "QtQuick")]
    command += [str(root / "tests/terminal-ssh-integration.cpp"), "-l:libQt6Quick.so.6", "-l:libQt6Qml.so.6",
                "-l:libQt6Gui.so.6", "-l:libQt6Core.so.6", "-lpthread", "-ldl", "-o", str(driver)]
    subprocess.run(command, check=True)
    helper = root / "work/terminal-native-host/paperterminal-askpass"
    shutil.copy2(helper, work / helper.name)
    synthetic_password = "PaperTerminal-local-test-42!"
    authenticated = []
    failures = []
    stop = threading.Event()

    class Fixture(paramiko.ServerInterface):
        def __init__(self):
            self.shell = threading.Event()

        def get_allowed_auths(self, username):
            return "password"

        def check_auth_password(self, username, password):
            good = username == "paperterminal-fixture" and password == synthetic_password
            authenticated.append(good)
            return paramiko.AUTH_SUCCESSFUL if good else paramiko.AUTH_FAILED

        def check_channel_request(self, kind, chanid):
            return paramiko.OPEN_SUCCEEDED if kind == "session" else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

        def check_channel_pty_request(self, channel, term, width, height, pixelwidth, pixelheight, modes):
            return True

        def check_channel_window_change_request(self, channel, width, height, pixelwidth, pixelheight):
            return True

        def check_channel_shell_request(self, channel):
            self.shell.set()
            return True

    host_key = paramiko.RSAKey.generate(2048)
    with socket.socket() as listener, tempfile.TemporaryDirectory(prefix="paperterminal-real-ssh-") as home:
        listener.bind(("127.0.0.1", 0))
        listener.listen(3)
        listener.settimeout(0.25)

        def serve():
            while not stop.is_set() and len(authenticated) < 2:
                try:
                    connection, _ = listener.accept()
                except socket.timeout:
                    continue
                transport = paramiko.Transport(connection)
                transport.banner_timeout = 5
                transport.auth_timeout = 10
                try:
                    transport.add_server_key(host_key)
                    server = Fixture()
                    transport.start_server(server=server)
                    channel = transport.accept(10)
                    if channel is None or not server.shell.wait(5):
                        raise RuntimeError("Fixture shell did not open")
                    channel.sendall(b"\r\nSSH_AUTHENTICATED_FIXTURE\r\n")
                    channel.send_exit_status(0)
                    channel.close()
                    # Wait on protocol closure, with a bound, before teardown.
                    transport.join(1)
                except Exception as error:
                    failures.append(type(error).__name__)
                finally:
                    transport.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", HOME=home)
        try:
            result = subprocess.run([str(driver), home, str(listener.getsockname()[1])],
                                    env=env, capture_output=True, text=True, timeout=45)
        finally:
            stop.set()
            thread.join(2)
        assert synthetic_password not in result.stdout + result.stderr, "A fixture password leaked into test output"
        (work / "driver.log").write_text(result.stdout + result.stderr)
        permissions = [oct(path.stat().st_mode & 0o777) for path in (Path(home) / ".config/paperterminal").rglob("*") if path.is_file()]
        report = {"scope": "Real system OpenSSH client and production native implementation against ephemeral loopback Paramiko fixture",
                  "passed": result.returncode == 0 and authenticated == [True, True] and not failures,
                  "authenticated_connections": len(authenticated), "authentication_succeeded": all(authenticated),
                  "driver_exit_code": result.returncode, "fixture_errors": failures,
                  "synthetic_password_absent_from_output": True,
                  "host_key_approved_manually_by_test": result.returncode == 0,
                  "closed_to_next_saved_connection": result.returncode == 0,
                  "host_helper_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
                  "remaining_credential_file_modes": permissions}
        output = root / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        if not report["passed"]:
            raise SystemExit("Real SSH integration failed; inspect work/terminal-followup/real-ssh/driver.log")


if __name__ == "__main__":
    main()
