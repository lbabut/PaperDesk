#!/usr/bin/env python3
"""PaperDesk desktop installer for Linux and Windows."""
import hashlib
import io
import os
from pathlib import Path
import sys
import tarfile
import threading
import tkinter as tk
from tkinter import messagebox, ttk

APPS = ("paperdesk", "literm", "paperweb", "paperrdp-login",
        "paperrdp", "paperrss", "papercare", "shims")
TARGET = "/home/root/xovi/exthome/appload"
STATE = "/home/root/.local/share/paperdesk"
ROOT = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
PRODUCT = ROOT / "product"


def verify_package():
    for line in (PRODUCT / "SHA256SUMS").read_text().splitlines():
        expected, relative = line.split(maxsplit=1)
        path = (PRODUCT / relative).resolve()
        if not path.is_relative_to(PRODUCT.resolve()) or not path.is_file():
            raise ValueError("Invalid package path: " + relative)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError("Package verification failed: " + relative)


def make_archive():
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w:gz") as archive:
        for path in sorted(PRODUCT.rglob("*")):
            if path.is_file() and path.name != "paperdesk.local.conf":
                archive.add(path, arcname=path.relative_to(PRODUCT).as_posix())
    data.seek(0)
    return data


def execute(client, command):
    _, stdout, stderr = client.exec_command(command, timeout=120)
    output = stdout.read().decode("utf-8", "replace")
    error = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if code:
        raise RuntimeError((output + "\n" + error).strip() or f"Remote exit code {code}")
    return output


class Installer:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("PaperDesk Apps — installer")
        self.root.minsize(520, 360)
        self.host = tk.StringVar(value="10.11.99.1")
        self.code = tk.StringVar()
        self.status = tk.StringVar(value="Connect the reMarkable 2 over USB.")
        self.client = None
        self.existing = []
        panel = ttk.Frame(self.root, padding=20)
        panel.pack(fill="both", expand=True)
        ttk.Label(panel, text="Install PaperDesk on reMarkable 2",
                  font=("", 16, "bold")).pack(anchor="w", pady=(0, 14))
        ttk.Label(panel, text="Tablet address").pack(anchor="w")
        ttk.Entry(panel, textvariable=self.host).pack(fill="x", pady=(0, 8))
        ttk.Label(panel, text="USB management code").pack(anchor="w")
        ttk.Entry(panel, textvariable=self.code, show="•").pack(fill="x", pady=(0, 12))
        row = ttk.Frame(panel)
        row.pack(fill="x")
        self.scan = ttk.Button(row, text="Check tablet", command=self.check)
        self.scan.pack(side="left")
        self.install = ttk.Button(row, text="Install", command=self.install_now,
                                  state="disabled")
        self.install.pack(side="left", padx=12)
        ttk.Label(panel, textvariable=self.status, wraplength=470,
                  justify="left").pack(anchor="w", pady=(18, 8))
        self.details = tk.Text(panel, height=8, wrap="word", state="disabled")
        self.details.pack(fill="both", expand=True)

    def show(self, message):
        self.details.configure(state="normal")
        self.details.insert("end", message + "\n")
        self.details.see("end")
        self.details.configure(state="disabled")

    def post(self, func, *args):
        self.root.after(0, func, *args)

    def ask(self, title, question):
        answered = threading.Event()
        result = []
        def dialog():
            result.append(messagebox.askyesno(title, question, parent=self.root))
            answered.set()
        self.post(dialog)
        answered.wait()
        return result[0]

    def busy(self, value):
        self.scan.configure(state="disabled" if value else "normal")
        self.install.configure(state="disabled" if value or not self.client else "normal")

    def background(self, work):
        self.busy(True)
        def run():
            try:
                work()
            except Exception as exc:
                self.post(self.status.set, "Error: " + str(exc))
                self.post(self.show, str(exc))
            finally:
                self.post(self.busy, False)
        threading.Thread(target=run, daemon=True).start()

    def check(self):
        host, password = self.host.get().strip(), self.code.get()
        if not host or not password:
            messagebox.showerror("Missing details", "Enter the tablet address and USB code.")
            return
        self.client = None
        self.install.configure(state="disabled")
        self.background(lambda: self.connect(host, password))

    def connect(self, host, password):
        import paramiko
        self.post(self.status.set, "Connecting and checking installed apps…")
        client = paramiko.SSHClient()
        known_hosts = Path.home() / ".ssh" / "known_hosts"
        if known_hosts.is_file():
            client.load_host_keys(str(known_hosts))
        installer = self
        class ConfirmHost(paramiko.MissingHostKeyPolicy):
            def missing_host_key(self, ssh_client, hostname, key):
                fingerprint = hashlib.sha256(key.asbytes()).hexdigest()
                if not installer.ask("Trust tablet?",
                                     f"First connection to {hostname}.\n"
                                     f"SSH key SHA-256: {fingerprint}\n\nTrust this device?"):
                    raise RuntimeError("Device identity was not accepted")
                known_hosts.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                ssh_client.get_host_keys().add(hostname, key.get_name(), key)
                ssh_client.save_host_keys(str(known_hosts))
        client.set_missing_host_key_policy(ConfirmHost())
        client.connect(hostname=host, username="root", password=password,
                       look_for_keys=False, allow_agent=False, timeout=12)
        command = (
            "test -d /home/root/xovi && "
            f"test -d {TARGET} && "
            "test -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so && "
            f"printf 'VERSION='; cat {STATE}/current-version 2>/dev/null || true; "
            f"for app in {' '.join(APPS)}; do "
            f"if test -e {TARGET}/$app; then printf 'APP=%s\\n' \"$app\"; fi; done"
        )
        output = execute(client, command)
        version = next((s[8:] for s in output.splitlines() if s.startswith("VERSION=")), "")
        existing = [s[4:] for s in output.splitlines() if s.startswith("APP=")]
        if not output.startswith("VERSION="):
            client.close()
            raise RuntimeError("XOVI, AppLoad or resource rebuilder is missing.")
        self.client, self.existing = client, existing
        self.post(self.show, "Installed PaperDesk: " + (version or "none"))
        self.post(self.show, "Existing app IDs: " + (", ".join(existing) or "none"))
        self.post(self.status.set, "Tablet checked. Review the existing apps, then select Install.")

    def install_now(self):
        if not self.client:
            return
        if self.existing and not messagebox.askyesno(
                "Existing apps",
                "These app IDs already exist:\n" + ", ".join(self.existing) +
                "\n\nPaperDesk will back them up and replace only these IDs. "
                "Other applications remain untouched. Continue?", parent=self.root):
            return
        self.background(self.transfer)

    def transfer(self):
        self.post(self.status.set, "Verifying and copying PaperDesk…")
        verify_package()
        archive = make_archive()
        client = self.client
        directory = execute(client, "mktemp -d /home/root/paperdesk-install.XXXXXX").strip()
        if not directory.startswith("/home/root/paperdesk-install."):
            raise RuntimeError("Unexpected temporary directory")
        try:
            with client.open_sftp() as sftp:
                sftp.putfo(archive, directory + "/package.tar.gz")
            output = execute(client, f"tar -xzf {directory}/package.tar.gz -C {directory} && "
                             f"chmod 755 {directory}/install.sh && {directory}/install.sh")
            self.post(self.show, output.strip())
            self.post(self.status.set, "Installed. Restarting XOVI…")
            execute(client, "/home/root/xovi/start")
            self.post(self.status.set, "PaperDesk is installed.")
        finally:
            try:
                execute(client, f"rm -rf -- {directory}")
            finally:
                client.close()
                self.client = None

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    Installer().run()
