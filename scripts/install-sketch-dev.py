import argparse
import io
import pathlib
import shlex
import subprocess
import tarfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--host", default="10.11.99.1")
parser.add_argument("--key", required=True)
parser.add_argument("--known-hosts", required=True)
parser.add_argument("--launch", action="store_true")
parser.add_argument("--native-raster",action="store_true",help="Install the native QImage engine with rollback")
parser.add_argument("--native-raster-path",type=pathlib.Path,help="Stage this regular file as the native raster module; requires --native-raster")
parser.add_argument("--native-ink", action="store_true", help="Install exact-build native pen preview with rollback")
parser.add_argument("--host-key-alias")
args = parser.parse_args()
raster_override = None
if args.native_raster_path is not None:
    if not args.native_raster:
        parser.error("--native-raster-path requires --native-raster")
    override_path = args.native_raster_path.expanduser()
    if not override_path.is_file():
        parser.error("--native-raster-path must name a regular file")
    try:
        raster_override = override_path.read_bytes()
    except OSError as error:
        parser.error("Cannot read --native-raster-path: " + str(error))
root = pathlib.Path(__file__).resolve().parents[1]
source = root / "product/payload/apps/papersketch"
for name in ("manifest.json", "resources.rcc", "icon.png"):
    if not (source / name).is_file():
        parser.error("Build Paper Sketch before installing: missing " + name)
if args.native_ink and not (source / "native/papersketch-ink.so").is_file():
    parser.error("Build native/papersketch-ink.so before --native-ink")
if args.native_raster and raster_override is None and not (source / "native/papersketch-raster.so").is_file():
    parser.error("Build native/papersketch-raster.so before --native-raster")
extensions=[]
if args.native_ink:extensions.append("papersketch-ink.so")
if args.native_raster:extensions.append("papersketch-raster.so")
ssh = ["ssh", "-i", args.key, "-o", "UserKnownHostsFile=" + args.known_hosts,
       "-o", "StrictHostKeyChecking=yes", "-o", "BatchMode=yes",
       "-o", "ConnectTimeout=8", "root@" + args.host]
if args.host_key_alias:
    ssh[-1:-1] = ["-o", "HostKeyAlias=" + args.host_key_alias]
def remote(command, data=None):
    result = subprocess.run(ssh + [command], input=data, capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout

remote('set -eu; test -d /home/root/xovi/exthome/appload; test "$(stat -c %t:%T /dev/input/event2)" = d:42; test -z "$(pidof paperdesk-rm-touchd || true)"; ! systemctl is-active --quiet paperdesk-update.service')
backup = remote("mktemp -d /home/root/.local/state/papersketch-install.XXXXXX").decode().strip()
assert backup.startswith("/home/root/.local/state/papersketch-install.")
b = shlex.quote(backup)
stream = io.BytesIO()
with tarfile.open(fileobj=stream, mode="w") as archive:
    archive.add(source, arcname="papersketch")
remote("mkdir -p " + b + "/stage; tar -xf - -C " + b + "/stage", stream.getvalue())
if raster_override is not None:
    # Replace only the staged payload after extraction; the local product module
    # and the rollback copy of the installed extension remain untouched.
    remote("cat > " + b + "/stage/papersketch/native/papersketch-raster.so", raster_override)
mask = remote("systemctl is-enabled remarkable-fail.service || true").decode().strip()
mask_here = mask not in ("masked", "masked-runtime")
stopped = False
installed = False
try:
    if mask_here:
        remote("systemctl mask --runtime remarkable-fail.service")
    remote("systemctl stop xochitl")
    stopped = True
    remote("set -eu; cp -p /home/root/.config/remarkable/xochitl.conf " + b + "/xochitl.conf; "
           "if test -d /home/root/xovi/exthome/appload/papersketch; then "
           "cp -a /home/root/xovi/exthome/appload/papersketch " + b + "/previous; fi; "
           "if test -d /home/root/.local/share/paperdesk/sketch; then cp -a /home/root/.local/share/paperdesk/sketch " + b + "/sketch-state; fi; "
           "mkdir -p /home/root/.local/share/paperdesk/sketch; "
           "chmod 700 /home/root/.local/share/paperdesk/sketch; "
           "cp -a " + b + "/stage/papersketch /home/root/xovi/exthome/appload/papersketch.new; "
           "if test -d /home/root/xovi/exthome/appload/papersketch; then "
           "mv /home/root/xovi/exthome/appload/papersketch " + b + "/replaced; fi; "
           "mv /home/root/xovi/exthome/appload/papersketch.new /home/root/xovi/exthome/appload/papersketch")
    installed = True
    for extension in extensions:
        remote("set -eu; test -d /home/root/xovi/extensions.d; "
               "if test -f /home/root/xovi/extensions.d/" + extension + "; then "
               "cp -p /home/root/xovi/extensions.d/" + extension + " " + b + "/previous-" + extension + "; fi; "
               "cp " + b + "/stage/papersketch/native/" + extension + " /home/root/xovi/extensions.d/" + extension + "; "
               "rm -f /tmp/papersketch-ink /tmp/papersketch-ink-status")
    if args.launch:
        remote("awk 'BEGIN { skip=0 } /^\\[PaperDeskE2E\\]$/ { skip=1; next } /^\\[/ { skip=0 } !skip { print }' "
               "/home/root/.config/remarkable/xochitl.conf > " + b + "/launch.conf; "
               "printf '\\n[PaperDeskE2E]\\nautostart=true\\napplicationId=papersketch\\n' >> " + b + "/launch.conf; "
               "cp " + b + "/launch.conf /home/root/.config/remarkable/xochitl.conf")
    remote("systemctl reset-failed xochitl; systemctl start xochitl")
    stopped = False
    time.sleep(8)
    remote("systemctl is-active --quiet xochitl")
except Exception:
    if installed:
        for extension in extensions:
            remote("systemctl stop xochitl; rm -f /home/root/xovi/extensions.d/" + extension + "; "
                   "if test -f " + b + "/previous-" + extension + "; then cp -p " + b + "/previous-" + extension + " /home/root/xovi/extensions.d/" + extension + "; fi")
        remote("systemctl stop xochitl; mv /home/root/xovi/exthome/appload/papersketch " + b + "/failed; "
               "if test -d " + b + "/previous; then cp -a " + b + "/previous /home/root/xovi/exthome/appload/papersketch; fi")
        stopped = True
    remote("if test -f " + b + "/xochitl.conf; then cp -p " + b + "/xochitl.conf /home/root/.config/remarkable/xochitl.conf; fi")
    raise
finally:
    if stopped:
        remote("systemctl reset-failed xochitl; systemctl start xochitl")
    if mask_here:
        remote("systemctl unmask --runtime remarkable-fail.service")
print("Installed Paper Sketch; rollback: " + backup)
print(remote("systemctl is-active xochitl; pidof xochitl; stat -c %t:%T /dev/input/event2").decode())
