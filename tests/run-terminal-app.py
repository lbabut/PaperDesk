#!/usr/bin/env python3
"""Run production terminal QML/PTY inside AppLoad, with recoverable device state.

Default mode prepares the probe locally. --run performs the targeted Xochitl
restart; use only after confirming the tablet is outside an edited document.
No input devices, networking configuration or global extensions are changed.
"""
import argparse
import hashlib
import io
import json
import pathlib
import re
import secrets
import signal
import shlex
import shutil
import subprocess
import tarfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="10.11.99.1")
    parser.add_argument("--key", required=True)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--rcc", default="/home/lukasz/Documents/Codex/2026-09-25/m-2/work/qt-rcc-pkg/root/usr/lib/qt5/bin/rcc")
    parser.add_argument("--output", default="docs/paperterminal-app-device-2026-11-01.json")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--expected-native-sha256", help="Refuse to run a stale or changing ARM plugin")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    source = root / "product/payload/apps/paperterminal"
    token = secrets.token_hex(8)
    application_id = "paperterminal-probe"
    remote_app = "/home/root/xovi/exthome/appload/" + application_id
    remote_tmp = "/tmp/paperterminal-app-" + token
    backup = "/home/root/.local/state/paperterminal-app-" + token
    work = root / "work/terminal-app-probe" / token
    app = work / application_id
    (app / "production/ui").mkdir(parents=True)
    (app / "production/native").mkdir()
    (app / "native").mkdir()
    ui_files = sorted((source / "ui").glob("*.qml"))
    for path in ui_files:
        shutil.copy2(path, app / "production/ui" / path.name)
    library_bytes = (source / "native/libpaperterminal_native.so").read_bytes()
    library_hash = hashlib.sha256(library_bytes).hexdigest()
    if args.expected_native_sha256 and library_hash != args.expected_native_sha256:
        raise RuntimeError("The ARM plugin does not match the requested frozen build")
    (app / "native/libpaperterminal_native.so").write_bytes(library_bytes)
    (app / "native/libpaperterminal_native.so").chmod(0o755)
    helper_bytes = (source / "native/paperterminal-askpass").read_bytes()
    (app / "native/paperterminal-askpass").write_bytes(helper_bytes)
    (app / "native/paperterminal-askpass").chmod(0o755)
    wrapper_bytes = (root / "product/payload/system/rmssh-menu").read_bytes()
    descriptor = (source / "native/qmldir").read_text()
    descriptor = descriptor.replace("/home/root/xovi/exthome/appload/paperterminal/native", remote_app + "/native")
    (app / "production/native/qmldir").write_text(descriptor)
    harness = (root / "tests/device/terminal-app.qml").read_text().replace("__SCREENSHOT_DIR__", remote_tmp)
    (app / "bench.qml").write_text(harness)
    shutil.copy2(source / "icon.png", app / "icon.png")
    (app / "probe-run-id").write_text(token + "\n")
    (app / "manifest.json").write_text(json.dumps({"id": application_id, "name": "Paper Terminal Diagnostics", "entry": "/bench.qml", "loadsBackend": False, "supportsScaling": True, "canHaveMultipleFrontends": False}))
    resources = ["bench.qml"] + ["production/ui/" + path.name for path in ui_files] + ["production/native/qmldir"]
    (app / "application.qrc").write_text('<RCC><qresource prefix="/">' + ''.join('<file>' + path + '</file>' for path in resources) + '</qresource></RCC>')
    subprocess.run([args.rcc, "--binary", "application.qrc", "-o", "resources.rcc"], cwd=app, check=True)
    print("Prepared diagnostic AppLoad app:", app, flush=True)
    if not args.run:
        return
    # Python's default SIGINT unwinds finally blocks. Give SIGTERM the same
    # behavior so an interrupted run still restores the tablet's configuration.
    def interrupt(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)

    ssh = ["ssh", "-i", args.key, "-o", "UserKnownHostsFile=" + args.known_hosts,
           "-o", "StrictHostKeyChecking=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "root@" + args.host]

    def remote(command, data=None, timeout=45):
        completed = subprocess.run(ssh + [command], input=data, capture_output=True, timeout=timeout)
        if completed.returncode:
            raise RuntimeError("Remote action failed: " + completed.stderr.decode(errors="replace").strip())
        return completed.stdout

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def state():
        raw = remote("systemctl is-active xochitl; systemctl is-enabled remarkable-fail.service 2>/dev/null || true; systemctl is-active remarkable-fail.service 2>/dev/null || true").decode().splitlines()
        return {"xochitl": raw[0], "failure_enabled": raw[1], "failure_active": raw[2]}

    remote("set -eu\n test ! -e " + shlex.quote(remote_app) + "\n test -f /home/root/.local/bin/rmssh-menu\n test ! -L /home/root/.local/bin/rmssh-menu\n test ! -L /home/root/.ssh/known_hosts\n systemctl is-active --quiet xochitl\n ! systemctl is-active --quiet paperdesk-update.service")
    original_state = state()
    mask_here = original_state["failure_enabled"] not in ("masked", "masked-runtime")
    qbackup = shlex.quote(backup)
    qapp = shlex.quote(remote_app)
    qtmp = shlex.quote(remote_tmp)
    report = {"scope": "Actual AppLoad/Xochitl production QML and native PTY with real DisplayMethodArea.Fast; no physical input injection or optical ghosting measurement.",
              "capture_note": "QQuickItem.grabToImage is unsupported by the vendor e-paper scene graph and is deliberately avoided. The vendor screenshot signal did not produce images, so capture is omitted. Workflow assertions use native running state, geometry and frame signals.",
              "backup": backup, "original_service_state": original_state,
              "source_sha256": {"qml": sha((app / "production/ui/main.qml").read_bytes()), "sessions": sha((app / "production/ui/Sessions.qml").read_bytes()),
                                 "ui_files": {path.name: sha((app / "production/ui" / path.name).read_bytes()) for path in ui_files},
                                 "native_arm_library": library_hash, "askpass_helper": sha(helper_bytes), "rmssh_menu": sha(wrapper_bytes), "harness": sha((app / "bench.qml").read_bytes())},
              "saved_sessions_fixture_scope": "PaperDeskSSH is empty only in the temporary probe configuration; the full original configuration is backed up and restored before the normal app restarts."}
    may_have_stopped = False
    failure = None
    try:
        remote("set -eu\n mkdir -p /home/root/.local/state\n mkdir -m 700 " + qbackup + "\n mkdir -m 700 " + qtmp)
        if mask_here:
            remote("systemctl mask --runtime remarkable-fail.service")
        may_have_stopped = True
        remote("set -eu\n systemctl stop xochitl\n cp -p /home/root/.config/remarkable/xochitl.conf " + qbackup + "/xochitl.conf\n cp -p /home/root/.local/bin/rmssh-menu " + qbackup + "/rmssh-menu\n"
               "if test -d /home/root/.config/rmssh; then cp -a /home/root/.config/rmssh " + qbackup + "/rmssh; touch " + qbackup + "/rmssh.existed; fi\n touch " + qbackup + "/rmssh.snapshot\n"
               "if test -d /home/root/.config/paperterminal; then cp -a /home/root/.config/paperterminal " + qbackup + "/paperterminal; touch " + qbackup + "/paperterminal.existed; fi\n touch " + qbackup + "/paperterminal.snapshot\n"
               "if test -d /home/root/.ssh; then stat -c %a /home/root/.ssh > " + qbackup + "/ssh.mode; else touch " + qbackup + "/ssh.absent; fi\n"
               "if test -f /home/root/.ssh/known_hosts; then cp -p /home/root/.ssh/known_hosts " + qbackup + "/known_hosts; else touch " + qbackup + "/known_hosts.absent; fi\n")
        original_config = remote("cat " + qbackup + "/xochitl.conf")
        report["xochitl_config_before_sha256"] = sha(original_config)
        report["rmssh_config_before_sha256"] = remote("if test -d " + qbackup + "/rmssh; then tar -cf - -C " + qbackup + " rmssh | sha256sum | cut -d' ' -f1; else echo absent; fi").decode().strip()
        rows, skip = [], False
        for line in original_config.decode().splitlines():
            if line.strip() in ("[PaperDeskE2E]", "[PaperTerminal]", "[PaperDeskSSH]"):
                skip = True
                continue
            if line.startswith("["):
                skip = False
            if not skip:
                rows.append(line)
        launch_config = ("\n".join(rows).rstrip() + "\n\n[PaperDeskE2E]\nautostart=true\napplicationId=" + application_id + "\ntraceTouches=false\nsshSessionCrud=false\n[PaperTerminal]\nsavedFontSize=26\nsavedAnsiColors=false\n[PaperDeskSSH]\nsessionsJson=[]\n").encode()
        remote("cat > /home/root/.config/remarkable/xochitl.conf", launch_config)
        remote("cat > /home/root/.local/bin/rmssh-menu; chmod 755 /home/root/.local/bin/rmssh-menu", wrapper_bytes)
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w") as bundle:
            bundle.add(app, arcname=application_id)
        remote("tar -xf - -C /home/root/xovi/exthome/appload", archive.getvalue())
        installed_hash = remote("sha256sum " + qapp + "/native/libpaperterminal_native.so").decode().split()[0]
        if installed_hash != library_hash:
            raise RuntimeError("The diagnostic plugin upload failed its SHA-256 check")
        remote("systemctl reset-failed xochitl; systemctl start xochitl")
        pid = remote("systemctl show -p MainPID --value xochitl").decode().strip()
        if not re.fullmatch(r"[1-9][0-9]*", pid):
            raise RuntimeError("Xochitl did not acquire a process ID")
        report["xochitl_pid"] = int(pid)
        began = time.monotonic()
        result = None
        while time.monotonic() - began < 120:
            logs = remote("journalctl -u xochitl _PID=" + pid + " --no-pager").decode(errors="replace")
            (work / "xochitl-journal.log").write_text(logs)
            for line in logs.splitlines():
                if "PAPERTERMINAL_APP_RESULT " in line:
                    payload = line.split("PAPERTERMINAL_APP_RESULT ", 1)[1]
                    result = json.loads(payload[:payload.rfind("}") + 1])
            if result is not None:
                break
            current_pid = remote("systemctl show -p MainPID --value xochitl").decode().strip()
            if current_pid != pid:
                raise RuntimeError("Xochitl restarted during the probe")
            time.sleep(1)
        if result is None:
            raise RuntimeError("Probe timed out; inspect " + str(work / "xochitl-journal.log"))
        report["results"] = result
        report["captures"] = {"available": False, "reason": "vendor e-paper capture unsupported"}
        report["runtime_seconds"] = round(time.monotonic() - began, 3)
        print(json.dumps(result, indent=2), flush=True)
    except Exception as error:
        failure = error
        report["execution_error"] = str(error)
    finally:
        if may_have_stopped:
            try:
                remote("set -eu\n systemctl stop xochitl\n"
                       "if test -f " + qbackup + "/xochitl.conf; then cp -p " + qbackup + "/xochitl.conf /home/root/.config/remarkable/xochitl.conf; fi\n"
                       "if test -f " + qbackup + "/rmssh-menu; then cp -p " + qbackup + "/rmssh-menu /home/root/.local/bin/rmssh-menu; fi\n"
                       "if test -f " + qbackup + "/rmssh.snapshot; then rm -rf /home/root/.config/rmssh; if test -f " + qbackup + "/rmssh.existed; then cp -a " + qbackup + "/rmssh /home/root/.config/rmssh; fi; fi\n"
                       "if test -f " + qbackup + "/paperterminal.snapshot; then rm -rf /home/root/.config/paperterminal; if test -f " + qbackup + "/paperterminal.existed; then cp -a " + qbackup + "/paperterminal /home/root/.config/paperterminal; fi; fi\n"
                       "if test -f " + qbackup + "/known_hosts; then cp -p " + qbackup + "/known_hosts /home/root/.ssh/known_hosts; elif test -f " + qbackup + "/known_hosts.absent; then rm -f /home/root/.ssh/known_hosts; fi\n"
                       "if test -f " + qbackup + "/ssh.mode; then chmod $(cat " + qbackup + "/ssh.mode) /home/root/.ssh; elif test -f " + qbackup + "/ssh.absent; then rmdir /home/root/.ssh; fi\n"
                       "if test -f " + qapp + "/probe-run-id && test \"$(cat " + qapp + "/probe-run-id)\" = " + shlex.quote(token) + "; then rm -rf " + qapp + "; fi\n"
                       "sha256sum /home/root/.config/remarkable/xochitl.conf | cut -d' ' -f1 > " + qbackup + "/restored-config.sha256\n"
                       "if test -d /home/root/.config/rmssh; then tar -cf - -C /home/root/.config rmssh | sha256sum | cut -d' ' -f1 > " + qbackup + "/restored-rmssh.sha256; else echo absent > " + qbackup + "/restored-rmssh.sha256; fi\n"
                       "systemctl reset-failed xochitl\n systemctl start xochitl\n")
                if mask_here:
                    remote("systemctl unmask --runtime remarkable-fail.service")
                time.sleep(5)
                report["restored_service_state"] = state()
                report["xochitl_config_restored"] = remote("cat " + qbackup + "/restored-config.sha256").decode().strip() == report.get("xochitl_config_before_sha256")
                report["xochitl_config_after_start_sha256"] = remote("sha256sum /home/root/.config/remarkable/xochitl.conf").decode().split()[0]
                report["xochitl_config_unchanged_after_start"] = report["xochitl_config_after_start_sha256"] == report.get("xochitl_config_before_sha256")
                report["saved_connection_settings_restored"] = report["xochitl_config_unchanged_after_start"]
                report["rmssh_config_restored"] = remote("cat " + qbackup + "/restored-rmssh.sha256").decode().strip() == report.get("rmssh_config_before_sha256")
                report["password_config_restored"] = remote("if test -f " + qbackup + "/paperterminal.existed; then diff -qr " + qbackup + "/paperterminal /home/root/.config/paperterminal >/dev/null && echo yes; else test ! -e /home/root/.config/paperterminal && echo yes; fi").decode().strip() == "yes"
                report["service_state_restored"] = report["restored_service_state"] == original_state
                report["diagnostic_app_removed"] = remote("test ! -e " + qapp + " && echo yes").decode().strip() == "yes"
                remote("rm -f " + qtmp + "/menu.png " + qtmp + "/diagnostic.png " + qtmp + "/diagnostic_later.png " + qtmp + "/returned_menu.png; rmdir " + qtmp)
            except Exception as error:
                report["restore_error"] = str(error)
                failure = RuntimeError("Device restore needs attention; backups retained at " + backup)
        elif mask_here:
            remote("systemctl unmask --runtime remarkable-fail.service")
        report["passed"] = bool(report.get("results", {}).get("passed")) and all(report.get(key, False) for key in ("xochitl_config_restored", "xochitl_config_unchanged_after_start", "rmssh_config_restored", "password_config_restored", "service_state_restored", "diagnostic_app_removed"))
        output = root / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + "\n")
        (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print("Report:", output, flush=True)
    if failure:
        raise failure
    if not report["passed"]:
        raise RuntimeError("Production AppLoad probe failed; inspect " + str(output))


if __name__ == "__main__":
    main()
