import argparse
import hashlib
import json
import pathlib
import re
import shlex
import struct
import subprocess

p = argparse.ArgumentParser()
p.add_argument("--host", required=True)
p.add_argument("--key", required=True)
p.add_argument("--known-hosts", required=True)
p.add_argument("--host-key-alias")
p.add_argument("--report", default="docs/papersketch-workflow-device-2026-11-01.json")
p.add_argument("--output", default="docs/papersketch-workflow-files-2026-11-01.json")
a = p.parse_args()
ssh = ["ssh", "-i", a.key, "-o", "UserKnownHostsFile=" + a.known_hosts, "-o", "StrictHostKeyChecking=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8"]
if a.host_key_alias:
    ssh += ["-o", "HostKeyAlias=" + a.host_key_alias]
ssh += ["root@" + a.host]
def remote(command):
    r = subprocess.run(ssh + [command], capture_output=True, timeout=30)
    r.check_returncode()
    return r.stdout
report = json.loads(pathlib.Path(a.report).read_text())
probe = report["results"]["workflow_probe"]
assert probe["passed"]
path = probe["export_path"]
assert re.fullmatch(r"/home/root/Documents/PaperSketch-test-[0-9]+\.png", path)
png = remote("cat " + shlex.quote(path))
width, height = struct.unpack(">II", png[16:24])
assert (width, height) == (1200, 1600)
r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "pipe:0", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "bgra", "pipe:1"], input=png, capture_output=True, timeout=30)
r.check_returncode()
raw = r.stdout
assert len(raw) == width * height * 4
assert hashlib.sha256(raw).hexdigest() == probe["export_optical_digest"]
gray = raw[0::4]
assert min(gray) < 255 and any(0 < v < 255 for v in gray)
namespace = report["cache_namespace"]
assert namespace.startswith("PaperDeskSketchNativeBenchbaseline")
prefix = "/home/root/.local/share/paperdesk/sketch/cache-" + hashlib.sha256(namespace.encode()).hexdigest()[:12] + "-"
checks = {}
for i in [0, 1, 2]:
    checks[str(i)] = remote("if test -f " + shlex.quote(prefix + str(i) + ".bin.material") + "; then echo yes; else echo no; fi").decode().strip() == "yes"
assert checks == {"0": False, "1": False, "2": True}
remote("rm -f -- " + shlex.quote(path))
result = {"execution": "real tablet PNG decoded by ffmpeg and private fixture cache inspection", "png_dimensions": [width, height], "grayscale_extrema": [min(gray), max(gray)], "pixel_digest_matches_exported_ram": True, "private_fixture_page_cache_exists": checks, "deleted_cache_removed_after_save": True, "test_export_removed": True, "passed": True}
pathlib.Path(a.output).write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
