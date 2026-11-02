import argparse
import configparser
import hashlib
import io
import json
import pathlib
import re
import shlex
import shutil
import subprocess
import struct
import tarfile
import time

p=argparse.ArgumentParser()
p.add_argument("--host",required=True)
p.add_argument("--host-key-alias")
p.add_argument("--key",required=True)
p.add_argument("--known-hosts",required=True)
p.add_argument("--baseline-qml")
p.add_argument("--smoke",action="store_true")
p.add_argument("--input-probe",action="store_true")
p.add_argument("--shading-probe",action="store_true")
p.add_argument("--latency-probe",action="store_true")
p.add_argument("--latency-fresh-only",action="store_true",help="limit the latency probe to fresh-page HB and charcoal")
p.add_argument("--controls-probe",action="store_true")
p.add_argument("--workflow-probe",action="store_true")
p.add_argument("--pdf-probe",action="store_true")
p.add_argument("--realism-probe",action="store_true")
p.add_argument("--output",default="docs/papersketch-native-2026-10-31.json")
a=p.parse_args()
if a.latency_fresh_only and not a.latency_probe:
    p.error("--latency-fresh-only requires --latency-probe")
if a.latency_probe and any((a.smoke,a.input_probe,a.shading_probe,a.controls_probe,a.workflow_probe,a.realism_probe,a.pdf_probe)):
    p.error("--latency-probe must run separately from other probes")
uses_input=a.pdf_probe or a.input_probe or a.shading_probe or a.latency_probe or a.controls_probe or a.workflow_probe or a.realism_probe
root=pathlib.Path(__file__).resolve().parents[1]
work=root/"work/papersketch-native"
app=work/"papersketch-native-bench"
app.mkdir(parents=True,exist_ok=True)
source=root/"product/payload/apps/papersketch"
production=(source/"ui/main.qml").read_text()
baseline=(root/a.baseline_qml).read_text() if a.baseline_qml else production
needle='category: "PaperDeskSketch"'
assert needle in baseline
candidate=production
if not a.baseline_qml:
    old='displayMethod: root.busy || root.painting ? DisplayMethodArea.Fast :\\n                       (typeof DisplayMethodArea.Content==="number" ? DisplayMethodArea.Content : DisplayMethodArea.Fast)'
    if old in candidate:
        start=candidate.index("                DisplayMethodArea {",candidate.index("id:liveInk"))
        end=candidate.index("\n                }",start)+len("\n                }")
        candidate=candidate[:start]+candidate[end:]
        candidate=candidate.replace(old,"displayMethod: DisplayMethodArea.Fast")
namespace_suffix=str(time.time_ns())
for name,text in [("baseline",baseline),("constant-fast",candidate)]:
    folder=app/name
    (folder/"ui").mkdir(parents=True,exist_ok=True)
    (folder/"ui/main.qml").write_text(text.replace(needle,'category: "PaperDeskSketchNativeBench'+name+namespace_suffix+'"'))
    shutil.copy2(source/"engine.js",folder/"engine.js")
    for qml_name in ("native-tile.qml","ToolIcon.qml"):
        shutil.copy2(source/"ui"/qml_name,folder/"ui"/qml_name)
harness=(root/("tests/device/papersketch-latency.qml" if a.latency_probe else "tests/device/papersketch-realism.qml" if a.realism_probe else "tests/device/papersketch-workflow.qml" if a.workflow_probe else "tests/device/papersketch-controls.qml" if a.controls_probe else "tests/device/papersketch-shading.qml" if a.shading_probe else "tests/device/papersketch-input.qml" if a.input_probe else "tests/device/papersketch-native.qml")).read_text()
if a.latency_fresh_only:
    marker="property bool freshOnly:false"
    assert harness.count(marker)==1,"Latency harness fresh-only option is missing"
    harness=harness.replace(marker,"property bool freshOnly:true")
if a.pdf_probe:harness=(root/"tests/device/papersketch-pdf.qml").read_text()
if a.smoke:harness=harness.replace("property bool smokeOnly:false","property bool smokeOnly:true")
if a.baseline_qml:harness=harness.replace('"constant-fast"','"tiled-fast"')
elif candidate==baseline:harness=harness.replace('["baseline","constant-fast"]','["production-1","production-2"]')
(app/"bench.qml").write_text(harness)
shutil.copy2(source/"icon.png",app/"icon.png")
(app/"manifest.json").write_text(json.dumps({"name":"Paper Sketch Native Diagnostics","id":"papersketch-native-bench","entry":"/bench.qml","icon":"icon.png","loadsBackend":False,"supportsScaling":True,"canHaveMultipleFrontends":False}))
paths=["bench.qml"]+[name+"/"+relative for name in ("baseline","constant-fast") for relative in ("ui/main.qml","ui/native-tile.qml","ui/ToolIcon.qml","engine.js")]
(app/"application.qrc").write_text('<RCC><qresource prefix="/">'+''.join('<file>'+x+'</file>' for x in paths)+'</qresource></RCC>')
rcc=pathlib.Path("/home/lukasz/Documents/Codex/2026-09-25/m-2/work/qt-rcc-pkg/root/usr/lib/qt5/bin/rcc")
subprocess.run([str(rcc),"--binary","application.qrc","-o","resources.rcc"],cwd=app,check=True)
ssh=["ssh","-i",a.key,"-o","UserKnownHostsFile="+a.known_hosts,"-o","StrictHostKeyChecking=yes","-o","BatchMode=yes","-o","ConnectTimeout=8"]
if a.host_key_alias:ssh+=["-o","HostKeyAlias="+a.host_key_alias]
ssh+=["root@"+a.host]
def remote(command,data=None):
    result=subprocess.run(ssh+[command],input=data,capture_output=True,timeout=45)
    if result.returncode:raise RuntimeError(result.stderr.decode(errors="replace"))
    return result.stdout
def config_for_launch(raw,app_id):
    rows=[]
    skip=False
    for line in raw.decode().splitlines():
        if line.strip()=="[PaperDeskE2E]":
            skip=True
            continue
        if line.startswith("["):
            skip=False
        if not skip:
            rows.append(line)
    return ("\n".join(rows).rstrip()+"\n\n[PaperDeskE2E]\nautostart=true\napplicationId="+app_id+"\n").encode()
def document_hash(raw):
    c=configparser.ConfigParser(interpolation=None,strict=False)
    c.read_string(raw.decode())
    value=c.get("PaperDeskSketch","document",fallback="")
    return hashlib.sha256(value.encode()).hexdigest()
remote('set -eu; test "$(stat -c %t:%T /dev/input/event2)" = d:42; test -z "$(pidof paperdesk-rm-touchd || true)"; ! systemctl is-active --quiet paperdesk-update.service; test ! -e /home/root/xovi/exthome/appload/papersketch-native-bench')
backup=remote("mktemp -d /home/root/.local/state/papersketch-native.XXXXXX").decode().strip()
assert backup.startswith("/home/root/.local/state/papersketch-native.")
b=shlex.quote(backup)
mask=remote("systemctl is-enabled remarkable-fail.service || true").decode().strip()
mask_here=mask not in ("masked","masked-runtime")
original=None
injected=set()
report={"candidate_qml_sha256":hashlib.sha256(candidate.encode()).hexdigest(),"source_qml_sha256":hashlib.sha256(baseline.encode()).hexdigest(),"source_engine_sha256":hashlib.sha256((source/"engine.js").read_bytes()).hexdigest(),"source_icon_sha256":hashlib.sha256((source/"ui/ToolIcon.qml").read_bytes()).hexdigest(),"backup":backup,"cache_namespace":"PaperDeskSketchNativeBenchbaseline"+namespace_suffix}
try:
    if uses_input:
        cache=pathlib.Path("/home/lukasz/Documents/Codex/2026-09-25/m-2/work/arm-toolchain/root")
        env=dict(__import__("os").environ,LD_LIBRARY_PATH=str(cache/"usr/lib/x86_64-linux-gnu"))
        driver=work/"input-driver-arm"
        subprocess.run([str(cache/"usr/bin/arm-linux-gnueabihf-gcc-12"),"--sysroot="+str(cache),"-O2",str(root/"tests/device/papersketch-input-driver.c"),"-o",str(driver)],env=env,check=True)
        remote("cat > /tmp/papersketch-input-driver; chmod 700 /tmp/papersketch-input-driver",driver.read_bytes())
    if mask_here:remote("systemctl mask --runtime remarkable-fail.service")
    remote("systemctl stop xochitl")
    original=remote("cat /home/root/.config/remarkable/xochitl.conf")
    remote("cp -p /home/root/.config/remarkable/xochitl.conf "+b+"/xochitl.conf")
    report["artwork_before_sha256"]=document_hash(original)
    data=io.BytesIO()
    with tarfile.open(fileobj=data,mode="w") as t:t.add(app,arcname=app.name)
    remote("tar -xf - -C /home/root/xovi/exthome/appload",data.getvalue())
    launch_awk=r'BEGIN {skip=0} /^\[PaperDeskE2E\]$/ {skip=1;next} /^\[/ {skip=0} !skip {print}'
    remote("awk "+shlex.quote(launch_awk)+" "+b+"/xochitl.conf > "+b+"/launch.conf; printf '%s\\n' '' '[PaperDeskE2E]' 'autostart=true' 'applicationId=papersketch-native-bench' >> "+b+"/launch.conf; cp -p "+b+"/launch.conf /home/root/.config/remarkable/xochitl.conf")
    remote("systemctl reset-failed xochitl; systemctl start xochitl")
    pid=remote("pidof xochitl").decode().split()[0]
    started=time.monotonic()
    aux=remote("cat /proc/"+pid+"/auxv")
    ticks=dict(struct.iter_unpack("<II",aux)).get(17,100)
    cpu_start=None
    def cpu_ticks():
        fields=remote("cat /proc/"+pid+"/stat").decode().rsplit(") ",1)[1].split()
        return int(fields[11])+int(fields[12])
    result=None
    for attempt in range(65):
        logs=remote("journalctl -u xochitl _PID="+pid+" --no-pager").decode()
        if uses_input:
            for line in logs.splitlines():
                if "PAPERSKETCH_INPUT_READY " not in line:continue
                payload=line.split("PAPERSKETCH_INPUT_READY ",1)[1];payload=payload[:payload.rfind("}")+1]
                request=json.loads(payload);mode=request["mode"]
                request_id=request.get("id",mode)
                if request_id in injected:continue
                assert mode in ("finger","pen")
                points=request["start"]+request["end"]
                if mode=="finger":points=[points[0],1871-points[1],points[2],1871-points[3]]
                if mode=="pen":
                    points=[20966-points[1]*20966/1872,points[0]*15725/1404,20966-points[3]*20966/1872,points[2]*15725/1404]
                coords=[str(round(v)) for v in points]
                pattern=[request["pattern"]] if request.get("pattern") else []
                try:event_report=json.loads(remote(shlex.join(["/tmp/papersketch-input-driver",mode]+coords+pattern)))
                except RuntimeError as error:
                    if "Input is busy" in str(error) or "Touch contact is active" in str(error):
                        if attempt%8==0:print("Waiting for existing "+mode+" contact to end",flush=True)
                        continue
                    raise
                event_report["id"]=request_id
                report.setdefault("evdev_injections",[]).append(event_report);injected.add(request_id)
        if "PAPERSKETCH_NATIVE_CASE" in logs and cpu_start is None:
            cpu_start=(time.monotonic(),cpu_ticks())
        if "PAPERSKETCH_NATIVE_RESULT " in logs:
            line=next(x for x in logs.splitlines() if "PAPERSKETCH_NATIVE_RESULT " in x)
            payload=line.split("PAPERSKETCH_NATIVE_RESULT ",1)[1]
            payload=payload[:payload.rfind("}")+1]
            result=json.loads(payload)
            (work/"tablet-journal.log").write_text(logs)
            break
        if attempt%8==0:print("Native benchmark running",round(time.monotonic()-started,1),"s",flush=True)
        time.sleep(2)
    if result is None:
        (work/"tablet-journal.log").write_text(logs)
        raise RuntimeError("Native benchmark timed out; inspect work/papersketch-native/tablet-journal.log")
    if cpu_start is not None:
        cpu_wall=time.monotonic()-cpu_start[0]
        report["process_cpu_sample"]={"wall_seconds":round(cpu_wall,3),"cpu_seconds":round((cpu_ticks()-cpu_start[1])/ticks,3),"reference":"one CPU core; sampling starts after the first benchmark case is observed"}
    if uses_input:
        for event in report.get("evdev_injections",[]):
            if event["mode"]=="pen" and "input_probe" in result:
                result["input_probe"]["pen"]["post_release_to_tile_ms"]=result["input_probe"]["pen"]["tile_seen_ms"]-event["release_ms"]
        if "input_probe" in result:result["input_probe"]["polling_granularity_ms"]=16
        if "shading_probe" in result:
            for case in result["shading_probe"]["cases"]:
                event=next(e for e in report["evdev_injections"] if e["id"]==case["id"])
                case["tile_visible_before_release"]=case["tile_seen_ms"]<event["release_ms"]
                case["injected_duration_ms"]=event["release_ms"]-event["contact_ms"]
    if a.realism_probe or a.latency_probe:
        probe_name="latency_probe" if a.latency_probe else "realism_probe"
        runtime_errors=[line for line in logs.splitlines() if ("bench.qml:" in line or "baseline/ui/main.qml:" in line) and any(error in line for error in ("TypeError:","ReferenceError:","SyntaxError:"))]
        result[probe_name]["runtime_errors"]=runtime_errors
        result[probe_name]["passed"]=result[probe_name]["passed"] and not runtime_errors
    if a.latency_probe:
        probe=result["latency_probe"]
        events={event["id"]:event for event in report.get("evdev_injections",[])}
        for case in probe["cases"]:
            event=events.get(case["id"])
            if event is None:
                case["evdev_injection_missing"]=True
                probe["passed"]=False
                continue
            contact=event["contact_ms"]
            case["evdev_contact_ms"]=contact;case["evdev_release_ms"]=event["release_ms"]
            case["tile_visible_before_release"]=bool(case.get("tile_seen_ms")) and case["tile_seen_ms"]<event["release_ms"]
            case["injected_duration_ms"]=event["release_ms"]-contact
            for output,timestamp in (
                ("evdev_contact_to_qt_input_observed_ms","first_input_observed_ms"),
                ("evdev_contact_to_damage_ms","first_damage_published_ms"),
                ("evdev_contact_to_raster_upper_ms","raster_seen_ms"),
                ("evdev_contact_to_tile_upper_ms","tile_seen_ms"),
                ("evdev_contact_to_submitted_frame_upper_ms","first_frame_after_tile_ms"),
            ):
                case[output]=case[timestamp]-contact if case.get(timestamp) else None
            stats=case.get("native_latency_stats")
            if stats:
                for key in ("first_advance_ms","first_publish_ms","first_tile_paint_ms"):
                    case["evdev_contact_to_native_"+key.removesuffix("_ms")+"_ms"]=stats[key]-contact if stats.get(key) else None
        probe["timing_origin"]="tablet CLOCK_REALTIME contact_ms versus QML Date.now/native epoch timestamps"
        probe["physical_panel_latency_measured"]=False
        result["cases"]=probe["cases"]
    report["results"]=result
    report["runtime_seconds"]=round(time.monotonic()-started,2)
    print(json.dumps(result,indent=2),flush=True)
finally:
    if uses_input:remote("rm -f /tmp/papersketch-input-driver")
    if original is not None:
        remote("systemctl stop xochitl")
        remote("cp -p "+b+"/xochitl.conf /home/root/.config/remarkable/xochitl.conf")
        remote("if test -d /home/root/xovi/exthome/appload/papersketch-native-bench; then mv /home/root/xovi/exthome/appload/papersketch-native-bench "+b+"/benchmark-app; fi")
        remote("systemctl reset-failed xochitl; systemctl start xochitl")
    if mask_here:remote("systemctl unmask --runtime remarkable-fail.service")
    if original is not None:
        after=remote("cat /home/root/.config/remarkable/xochitl.conf")
        report["artwork_after_sha256"]=document_hash(after)
        report["artwork_preserved"]=report["artwork_before_sha256"]==report["artwork_after_sha256"]
    out=root/a.output
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,indent=2)+"\n")
    print("Report:",out,flush=True)
assert report["artwork_preserved"],"Artwork settings changed; original backup retained"

if a.smoke and not a.baseline_qml:
    assert all(probe["passed"] for probe in report["results"]["pixel_probes"]), "Native raster pixel probe failed"

if a.input_probe:
    assert report["results"]["input_probe"]["passed"], "Physical input path probe failed"
if a.shading_probe:
    assert report["results"]["shading_probe"]["passed"] and all(c["tile_visible_before_release"] for c in report["results"]["shading_probe"]["cases"]), "Long fast shading probe failed"

if a.controls_probe:
    assert report["results"]["controls_probe"]["passed"],"Real-device slider probe failed"

if a.workflow_probe:
    assert report["results"]["workflow_probe"]["passed"],"Named export and stable page deletion workflow failed"

if a.realism_probe:
    assert not report["results"]["realism_probe"].get("runtime_errors"),"Realism harness or production UI emitted a runtime error"
    assert report["results"]["realism_probe"]["passed"],"Real-device material controls, calibration, tilt or physical-state persistence failed"
    required={"materials-open","paper-rough","tip-sharpen","finger-clean","eraser-kneaded","materials-done","kneaded-pressure","kneaded-drag","fixture-save","calibration-open-materials","calibration-open","calibration-light","calibration-next-light","calibration-normal","calibration-next-normal","calibration-firm","calibration-save","upright","tilt","finger-contact"}
    events=report.get("evdev_injections",[])
    assert required.issubset({event["id"] for event in events}),"Realism probe skipped a required physical UI/input action"
    assert all(event.get("writes_ok") for event in events),"Realism input driver reported incomplete event writes"

if a.latency_probe:
    probe=report["results"]["latency_probe"]
    assert not probe.get("runtime_errors"),"Latency harness or production UI emitted a runtime error"
    required={"latency-fresh-hb","latency-fresh-charcoal"}
    if not a.latency_fresh_only:required|={"latency-layered-hb","latency-layered-charcoal"}
    assert probe.get("scope")==("fresh-only" if a.latency_fresh_only else "fresh-and-layered"),"Latency report scope differs from requested cases"
    events=report.get("evdev_injections",[])
    assert required.issubset({event["id"] for event in events}),"Latency probe skipped a required physical input action"
    assert required=={case["id"] for case in probe["cases"]},"Latency probe did not report exactly the requested cases"
    assert all(event.get("writes_ok") for event in events),"Latency input driver reported incomplete event writes"
    assert probe["passed"],"Latency diagnostic incomplete; inspect its error and case reports"

if a.pdf_probe:
    assert report["results"]["pdf_probe"]["passed"] and any(e.get("id")=="pdf-add" and e.get("writes_ok") for e in report.get("evdev_injections",[])),"PDF native library import failed"
