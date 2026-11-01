#!/usr/bin/env python3
"""Authenticate the real reMarkable system SSH client with the production ARM backend.

Uses the same password-only Paramiko/marker fixture as the host integration
test, bound to one explicit LAN address and accepting only the chosen tablet.
The server runs no commands and exposes no files. On the tablet, only a unique
private /tmp directory is created and removed; no apps/services are changed.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import tarfile
import threading
import uuid

import paramiko


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.1.167")
    parser.add_argument("--bind", default="192.168.1.113")
    parser.add_argument("--key", required=True)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--output", default="docs/paperterminal-real-ssh-device-2026-11-01.json")
    args = parser.parse_args()
    if args.bind != "192.168.1.113":
        parser.error("This diagnostic is scoped to the explicitly authorized LAN address 192.168.1.113")
    root = Path(__file__).resolve().parents[1]
    cache = Path(os.environ.get("PAPERDESK_TOOLCACHE", "/home/lukasz/Documents/Codex/2026-09-25/m-2/work"))
    sdk = Path(os.environ.get("PAPERDESK_QT_SDK", str(cache / "papersketch-qt-sdk/root")))
    toolchain = cache / "arm-toolchain/root"
    include = sdk / "usr/include/x86_64-linux-gnu/qt6"
    token = uuid.uuid4().hex
    work = root / "work/terminal-followup/real-ssh-device" / token
    work.mkdir(parents=True, exist_ok=False)
    source = root / "product/payload/apps/paperterminal/native/paperterminal-native.cpp"
    helper = source.parent / "paperterminal-askpass"
    if helper.read_bytes()[:20][18:20] != b"\x28\x00":
        raise RuntimeError("The production password helper must be an ARM ELF executable")
    ssh = ["ssh", "-i", args.key, "-o", "UserKnownHostsFile=" + args.known_hosts,
           "-o", "StrictHostKeyChecking=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "root@" + args.host]

    def remote(command, data=None, timeout=45, check=True):
        result = subprocess.run(ssh + [command], input=data, capture_output=True, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError("Tablet diagnostic command failed: " + result.stderr.decode(errors="replace"))
        return result

    metadata = remote("uname -m; test -x /usr/bin/ssh; test -f /usr/lib/plugins/platforms/libqoffscreen.so").stdout.decode()
    def real_known_hosts_digest():
        return remote("if test -f /home/root/.ssh/known_hosts; then sha256sum /home/root/.ssh/known_hosts; else printf absent; fi").stdout.decode().split()[0]
    known_hosts_before = real_known_hosts_digest()
    client_path = remote("readlink -f /usr/bin/ssh").stdout.decode().strip()
    if not metadata.startswith("armv7l\n"):
        raise RuntimeError("This probe requires the authorized ARMv7 reMarkable tablet")
    subprocess.run([str(sdk / "usr/lib/qt6/libexec/moc"), "-I" + str(include),
                    "-DPAPERTERMINAL_TESTING", "-DPAPERTERMINAL_NO_PLUGIN", str(source),
                    "-o", str(work / "paperterminal-native.moc")], check=True)
    compiler = toolchain / "usr/bin/arm-linux-gnueabihf-g++-12"
    driver = work / "terminal-ssh-integration"
    command = [str(compiler), "--sysroot=" + str(toolchain), "-std=c++17", "-O2", "-marm", "-fPIC",
               "-Wall", "-Wextra", "-I" + str(include), "-I" + str(work)]
    command += ["-I" + str(include / module) for module in ("QtCore", "QtGui", "QtQml", "QtQuick")]
    command += [str(root / "tests/terminal-ssh-integration.cpp"), "-L" + str(root / "work/terminal-device-libs"),
                "-Wl,--allow-shlib-undefined", "-l:libQt6Quick.so.6", "-l:libQt6Qml.so.6", "-l:libQt6Gui.so.6",
                "-l:libQt6Core.so.6", "-lpthread", "-ldl", "-o", str(driver)]
    subprocess.run(command, env=dict(os.environ, LD_LIBRARY_PATH=str(toolchain / "usr/lib/x86_64-linux-gnu")), check=True)

    # This is intentionally the same authentication/shell-marker protocol as
    # run-terminal-ssh-integration.py, with exec/subsystems explicitly refused.
    synthetic_password = "PaperTerminal-local-test-42!"
    authenticated, failures, guesses_skipped = [], [], []
    stop = threading.Event()

    class Fixture(paramiko.ServerInterface):
        def __init__(self): self.shell = threading.Event()
        def get_allowed_auths(self, username): return "password"
        def check_auth_password(self, username, password):
            good = username == "paperterminal-fixture" and password == synthetic_password
            authenticated.append(good)
            return paramiko.AUTH_SUCCESSFUL if good else paramiko.AUTH_FAILED
        def check_channel_request(self, kind, chanid):
            return paramiko.OPEN_SUCCEEDED if kind == "session" else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
        def check_channel_pty_request(self, channel, term, width, height, pixelwidth, pixelheight, modes): return True
        def check_channel_window_change_request(self, channel, width, height, pixelwidth, pixelheight): return True
        def check_channel_shell_request(self, channel): self.shell.set(); return True
        def check_channel_exec_request(self, channel, command): return False
        def check_channel_subsystem_request(self, channel, name): return False

    class GuessAwareTransport(paramiko.Transport):
        def _parse_kex_init(self, message):
            # Paramiko 5.1 parses first_kex_follows but does not discard a
            # mismatched optimistic guess. Dropbear actually sends one.
            # Implement RFC 4253 section 7 for this isolated fixture only.
            proposal = self._really_parse_kex_init(paramiko.Message(message.asbytes()))
            agreed_kex = next((name for name in proposal["kex_algo_list"] if name in self.preferred_kex), None)
            server_keys = set(self.server_key_dict).intersection(self.preferred_keys)
            agreed_key = next((name for name in proposal["server_key_algo_list"] if name in server_keys), None)
            skip = proposal["kex_follows"] and (
                proposal["kex_algo_list"][0] != agreed_kex or proposal["server_key_algo_list"][0] != agreed_key)
            super()._parse_kex_init(message)
            if skip:
                packet_type, _ = self.packetizer.read_message()
                if not 30 <= packet_type <= 49:
                    raise paramiko.SSHException("Unexpected optimistic KEX packet")
                guesses_skipped.append(True)

    host_key = paramiko.RSAKey.generate(2048)
    stage = "/tmp/paperterminal-ssh-device-" + token
    report = {"scope": "Real ARM native/production password integration and tablet system SSH against isolated LAN Paramiko fixture",
              "tablet": args.host, "serverBind": args.bind, "temporaryStage": stage,
              "systemSshExecutable": client_path, "realKnownHostsSha256Before": known_hosts_before,
              "passwordMethod": "stock Dropbear canonical/noecho pre-auth" if client_path == "/usr/sbin/dropbearmulti" else "OpenSSH app-local askpass",
              "nativeSourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "productionArmHelperSha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
              "servicesOrApplicationsChanged": False, "commandsExecutedByFixture": False,
              "filesExposedByFixture": False,
              "fixtureKex": "curve25519-sha256@libssh.org; RFC4253 first_kex_follows mismatch discarded"}
    output = root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    uploaded = False
    with socket.socket() as listener:
        listener.bind((args.bind, 0)); listener.listen(3); listener.settimeout(0.25)
        port = listener.getsockname()[1]
        report["serverPort"] = port

        def serve():
            while not stop.is_set() and len(authenticated) < 2:
                try: connection, peer = listener.accept()
                except socket.timeout: continue
                if peer[0] != args.host:
                    connection.close(); continue
                transport = GuessAwareTransport(connection)
                transport.get_security_options().kex = ("curve25519-sha256@libssh.org",)
                transport.banner_timeout = 5; transport.auth_timeout = 10
                try:
                    transport.add_server_key(host_key)
                    server = Fixture(); transport.start_server(server=server)
                    channel = transport.accept(10)
                    if channel is None or not server.shell.wait(5): raise RuntimeError("Fixture channel did not open")
                    channel.sendall(b"\r\nSSH_AUTHENTICATED_FIXTURE\r\n")
                    channel.send_exit_status(0); channel.close(); transport.join(1)
                except Exception as error: failures.append(type(error).__name__)
                finally: transport.close()

        thread = threading.Thread(target=serve, daemon=True); thread.start()
        try:
            remote("mkdir -m 700 " + shlex.quote(stage)); uploaded = True
            archive = io.BytesIO()
            with tarfile.open(fileobj=archive, mode="w:gz") as bundle:
                bundle.add(driver, arcname="terminal-ssh-integration")
                bundle.add(helper, arcname="paperterminal-askpass")
            remote("tar -xzf - -C " + shlex.quote(stage), archive.getvalue())
            report["uploadedHelperSha256"] = remote("sha256sum " + shlex.quote(stage + "/paperterminal-askpass")).stdout.decode().split()[0]
            if report["uploadedHelperSha256"] != report["productionArmHelperSha256"]:
                raise RuntimeError("Uploaded password helper checksum mismatch")
            remote("mkdir -m 700 " + shlex.quote(stage + "/home") + " " + shlex.quote(stage + "/runtime"))
            command = ("cd " + shlex.quote(stage) + " && TMPDIR=" + shlex.quote(stage) + " LD_PRELOAD= QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software "
                       "QT_PLUGIN_PATH=/usr/lib/plugins XDG_RUNTIME_DIR=" + shlex.quote(stage + "/runtime") +
                       " timeout -k 3 50 ./terminal-ssh-integration " + shlex.quote(stage + "/home") + " " + str(port) + " " + shlex.quote(args.bind))
            result = remote(command, timeout=60, check=False)
            combined = result.stdout + result.stderr
            if synthetic_password.encode() in combined: raise RuntimeError("A fixture credential leaked into diagnostic output")
            (work / "driver.log").write_bytes(combined)
            report.update({"driverExitCode": result.returncode, "authenticatedConnections": len(authenticated),
                           "authenticationSucceeded": authenticated == [True, True], "fixtureErrors": failures,
                           "optimisticKexGuessesDiscarded": len(guesses_skipped),
                           "syntheticPasswordAbsentFromOutput": True,
                           "hostKeyApprovedManuallyByTest": result.returncode == 0,
                           "firstDropbearPasswordEnteredManually": result.returncode == 0 and client_path == "/usr/sbin/dropbearmulti",
                           "secondPasswordUsedWithoutManualInput": result.returncode == 0,
                           "closedToNextSavedConnection": result.returncode == 0,
                           "passed": result.returncode == 0 and authenticated == [True, True] and not failures})
        finally:
            stop.set(); thread.join(2)
            report["realKnownHostsSha256After"] = real_known_hosts_digest()
            report["realKnownHostsUnchanged"] = report["realKnownHostsSha256After"] == known_hosts_before
            if uploaded:
                report["hostKeyStoredOnlyInPrivateHome"] = remote("test -s " + shlex.quote(stage + "/home/.ssh/known_hosts"), check=False).returncode == 0 and report["realKnownHostsUnchanged"]
                cleanup = remote("rm -rf -- " + shlex.quote(stage), check=False)
                report["temporaryStageRemoved"] = cleanup.returncode == 0
            else: report["temporaryStageRemoved"] = True
            report["passed"] = report.get("passed", False) and report["realKnownHostsUnchanged"] and report.get("hostKeyStoredOnlyInPrivateHome", False)
            output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not report.get("passed") or not report["temporaryStageRemoved"]:
        raise SystemExit("ARM SSH integration failed; inspect this run's driver.log")


if __name__ == "__main__":
    main()
