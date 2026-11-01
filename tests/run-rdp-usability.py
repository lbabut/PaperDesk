#!/usr/bin/env python3
"""Recoverable real-AppLoad RDP fixture; never inject global physical input."""
import argparse, hashlib, io, json, os, re, secrets, shlex, shutil, signal, socket, subprocess, tarfile, time
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--host',required=True);p.add_argument('--key',required=True);p.add_argument('--known-hosts',required=True)
p.add_argument('--run',action='store_true');p.add_argument('--deploy',action='store_true')
p.add_argument('--expected-native-sha256',required=True)
p.add_argument('--server');p.add_argument('--output',default='docs/paperrdp-usability-device-2026-11-01.json')
a=p.parse_args();os.umask(0o077);root=Path(__file__).resolve().parents[1];work=root/'work/rdp-usability';token=secrets.token_hex(8)
run=work/('probe-'+token);run.mkdir(parents=True);run.chmod(0o700)
remote_base='/home/root/.local/state/paperrdp-usability-'+token
fixture=remote_base+'/fixture';apps='/home/root/xovi/exthome/appload';qrr='/home/root/xovi/exthome/qt-resource-rebuilder/paperdesk-appload-window.qml'
main_qrr='/home/root/xovi/exthome/qt-resource-rebuilder/paperdesk-appload.qml'
ids={'ui':'paperrdp-probe-'+token,'engine':'paperrdp-engine-probe-'+token,'helper':'paperrdp-profile-probe-'+token}
ssh=['ssh','-i',a.key,'-o','UserKnownHostsFile='+a.known_hosts,'-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','root@'+a.host]
q=shlex.quote
def remote(cmd,data=None):
 c=subprocess.run(ssh+[cmd],input=data,capture_output=True,timeout=45)
 if c.returncode:raise RuntimeError('Remote operation failed: '+c.stderr.decode(errors='replace').strip())
 return c.stdout
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def interrupted(_s,_f):raise KeyboardInterrupt
signal.signal(signal.SIGTERM,interrupted)
source=root/'product/payload/apps';binary=source/'paperrdp/paperrdp';testbinary=root/'work/tests/paperrdp-e2e'
assert sha(binary)==a.expected_native_sha256,'Stale native production binary'
assert testbinary.is_file(),'Build --e2e first'
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
# The test app IDs and all profile/certificate paths are private to this run.
stage=run/'staged';stage.mkdir();u=stage/ids['ui'];(u/'production/ui').mkdir(parents=True)
ui=(source/'paperrdp-login/ui/main.qml').read_text().replace('external::paperrdp-profile','__PROBE_HELPER__').replace('external::paperrdp','external::'+ids['engine']).replace('__PROBE_HELPER__','external::'+ids['helper'])
(u/'production/ui/main.qml').write_text(ui)
harness=(root/'tests/device/rdp-usability.qml').read_text().replace('__RDP_FIXTURE_DIR__',fixture+'/profiles').replace('__RDP_COMMAND_FILE__',fixture+'/command.json').replace('__RDP_PORT__',str(port))
(u/'bench.qml').write_text(harness);shutil.copy2(source/'paperrdp-login/icon.png',u/'icon.png')
(u/'manifest.json').write_text(json.dumps({'id':ids['ui'],'name':'RDP Usability Diagnostics','entry':'/bench.qml','loadsBackend':False,'supportsScaling':True,'canHaveMultipleFrontends':False}))
(u/'probe-run-id').write_text(token)
(u/'application.qrc').write_text('<RCC><qresource prefix="/"><file>bench.qml</file><file>production/ui/main.qml</file></qresource></RCC>')
rcc='/home/lukasz/Documents/Codex/2026-09-25/m-2/work/qt-rcc-pkg/root/usr/lib/qt5/bin/rcc'
subprocess.run([rcc,'--binary','application.qrc','-o','resources.rcc'],cwd=u,check=True)
for kind,name in [('engine','paperrdp'),('helper','paperrdp-profile')]:
 d=stage/ids[kind];d.mkdir();shutil.copy2(testbinary if kind=='engine' else source/name/'profile-manager',d/('engine' if kind=='engine' else 'manager'))
 script='#!/bin/sh\numask 077\n'
 if kind=='engine':
  script+='export PAPERDESK_TEST_INPUT_FIFO='+q(fixture+'/input.fifo')+'\nexport PAPERDESK_TEST_RDP_CONFIG_DIR='+q(fixture+'/profiles')+'\nexport XDG_CONFIG_HOME='+q(fixture+'/certs')+'\n'
 else:script+='export PAPERDESK_RDP_CONFIG_DIR='+q(fixture+'/profiles')+'\nexport PATH='+q(fixture+'/bin')+':"$PATH"\n'
 script+='exec '+q(apps+'/'+ids[kind]+('/engine' if kind=='engine' else '/manager'))+' "$@"'+(' 2> '+q(fixture+'/engine.log') if kind=='engine' else '')+'\n'
 (d/'launch').write_text(script);(d/'launch').chmod(0o755)
 manifest=json.loads((source/name/'external.manifest.json').read_text());manifest['application']=apps+'/'+ids[kind]+'/launch';manifest['workingDirectory']=apps+'/'+ids[kind]
 (d/'external.manifest.json').write_text(json.dumps(manifest));(d/'probe-run-id').write_text(token)
production=run/'production';production.mkdir()
for name in ['paperrdp','paperrdp-login','paperrdp-profile']:shutil.copytree(source/name,production/name)
shutil.copy2(root/'product/payload/system/paperdesk-appload-window.qml',run/'new-window.qml')
main_source=(root/'product/payload/system/paperdesk-appload.qml').read_text()
assert main_source.count('application.id === "external::paperrdp"')==1
(run/'probe-appload.qml').write_text(main_source.replace('application.id === "external::paperrdp"','(application.id === "external::paperrdp" || application.id === "external::'+ids['engine']+'")'))
report={'scope':'real production QML/helper and ARM E2E engine through AppLoad, loopback RDP server over SSH reverse tunnel','physical_input_injected':False,'optical_ghosting_measured':False,'backup':remote_base,'run_id':token,'native_sha256':sha(binary),'e2e_sha256':sha(testbinary),'window_sha256':sha(run/'new-window.qml'),'states':[],'test_adapter':'Temporary AppLoad integration additionally recognizes the isolated engine ID in the existing production orientation branch; restored before normal UI restart.'}
(run/'prepared.json').write_text(json.dumps(report,indent=2)+'\n');print('Prepared RDP diagnostics:',run,flush=True)
if not a.run:raise SystemExit(0)
server=Path(a.server or work/'server-src/fixture-server').resolve();assert server.is_file()
server_log=run/'wire.log';server_process=None;tunnel=None;stopped=False;committed=False;passed=False;old_failure='';failure=None
old_app_hashes={};revision=0;state_request=0;pid=0
idle_guard=r'''set -eu
systemctl is-active --quiet xochitl
! systemctl is-active --quiet paperdesk-update.service
! pidof paperrdp >/dev/null
for f in /home/root/.config/rmssh/paperterminal-*.state; do test ! -f "$f" || test "$(cut -d' ' -f1 "$f")" = ready; done
xp=$(systemctl show -p MainPID --value xochitl)
for status in /proc/[0-9]*/status; do
 parent=$(sed -n 's/^PPid:[[:space:]]*//p' "$status" 2>/dev/null || true)
 if test "$parent" = "$xp"; then child=${status%/status}; exe=$(readlink "$child/exe" 2>/dev/null || true); case "$exe" in */ssh|*/dropbearmulti) exit 1;; esac; fi
done
'''
def wire():return server_log.read_text(errors='replace') if server_log.exists() else ''
def start_server(changed=False):
 global server_process
 log=server_log.open('ab');base=server.parent
 server_process=subprocess.Popen([str(server),'--port='+str(port),'--cert='+str(base/('changed.crt' if changed else 'server.crt')),'--key='+str(base/('changed.key' if changed else 'server.key'))],cwd=base,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);log.close()
 end=time.monotonic()+8
 while time.monotonic()<end:
  if server_process.poll() is not None:raise RuntimeError('Fixture RDP server exited')
  try:
   with socket.create_connection(('127.0.0.1',port),timeout=.2):return
  except OSError:time.sleep(.1)
 raise RuntimeError('Fixture server did not listen')
def stop_server():
 global server_process
 if server_process and server_process.poll() is None:
  server_process.terminate()
  try:server_process.wait(timeout=5)
  except subprocess.TimeoutExpired:server_process.kill();server_process.wait(timeout=5)
 server_process=None

def journal():
 logs=remote('journalctl -u xochitl _PID='+str(pid)+' --no-pager').decode(errors='replace');(run/'xochitl-journal.log').write_text(logs);return logs
def payload(line,marker):return json.JSONDecoder().raw_decode(line.split(marker,1)[1])[0]

def until(check,seconds=20):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=check()
  if value:return value
  time.sleep(.25)
 raise RuntimeError('Diagnostic condition timed out')

def wait_state(action,rev=None,seconds=20):
 def check():
  for line in journal().splitlines()[::-1]:
   if 'PAPERDESK_RDP_PROBE_RESULT ' in line:
    result=payload(line,'PAPERDESK_RDP_PROBE_RESULT ');report['qml_result']=result
    if not result.get('passed'):raise RuntimeError('AppLoad diagnostic failed: '+str(result.get('error')))
    if action=='finish':return result
   if 'PAPERDESK_RDP_PROBE_STATE ' in line:
    value=payload(line,'PAPERDESK_RDP_PROBE_STATE ')
    if value['action']==action and (rev is None or value['revision']==rev):
     assert value['passed'],value;report['states'].append(value);print('RDP phase:',action,flush=True);return value
 return until(check,seconds)

def command(action,**kw):
 global revision
 revision+=1;data=json.dumps(dict(revision=revision,action=action,**kw)).encode()
 remote('cat > '+q(fixture+'/command.new')+'; mv '+q(fixture+'/command.new')+' '+q(fixture+'/command.json'),data)
 return wait_state(action,revision)

def fifo(lines):remote('timeout 4 sh -c '+q('cat > '+q(fixture+'/input.fifo')),lines.encode())
def native_state():
 global state_request
 state_request+=1;fifo('state '+str(state_request)+'\n')
 def check():
  logs=remote('cat '+q(fixture+'/engine.log')).decode(errors='replace');(run/'engine.log').write_text(logs)
  for line in logs.splitlines()[::-1]:
   if 'PAPERDESK_RDP_NATIVE_STATE ' in line:
    value=payload(line,'PAPERDESK_RDP_NATIVE_STATE ')
    if value['request']==state_request:return value
 return until(check,5)
def await_mode(mode):return until(lambda:(value if (value:=native_state())['mode']==mode else None),15)
def capture(label):
 python='/home/lukasz/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3';script=root.with_name('PaperDesk-terminal')/'work/capture-terminal-screen.py'
 c=subprocess.run([python,str(script),'--host','root@'+a.host,'--identity',a.key,'--known-hosts',a.known_hosts,'--output',str(run/(label+'.png'))],capture_output=True,text=True,timeout=45)
 assert c.returncode==0,c.stderr

def pack():
 files=list(stage.rglob('*'))+list(production.rglob('*'))+[run/'new-window.qml',run/'probe-appload.qml']
 sums=[]
 for path in files:
  if not path.is_file():continue
  rel=('test-apps/'+str(path.relative_to(stage))) if path.is_relative_to(stage) else ('production/'+str(path.relative_to(production))) if path.is_relative_to(production) else path.name
  sums.append(sha(path)+'  '+rel+'\n')
 (run/'SHA256SUMS').write_text(''.join(sums))
 data=io.BytesIO()
 with tarfile.open(fileobj=data,mode='w:gz') as archive:
  archive.add(stage,arcname='test-apps');archive.add(production,arcname='production');archive.add(run/'new-window.qml',arcname='new-window.qml');archive.add(run/'probe-appload.qml',arcname='probe-appload.qml');archive.add(run/'SHA256SUMS',arcname='SHA256SUMS')
 return data.getvalue()
def rollback_apps():
 errors=[]
 for name in ['paperrdp','paperrdp-login','paperrdp-profile']:
  old=remote_base+'/previous-apps/'+name;target=apps+'/'+name
  try:remote('set -eu; mkdir -p '+q(remote_base+'/failed-apps')+'; if test -d '+q(old)+'; then if test -e '+q(target)+'; then mv '+q(target)+' '+q(remote_base+'/failed-apps/'+name)+'; fi; mv '+q(old)+' '+q(target)+'; fi')
  except BaseException as e:errors.append(name+': '+str(e))
 try:remote('if test -f '+q(remote_base+'/old-window.qml')+'; then cp -p '+q(remote_base+'/old-window.qml')+' '+q(qrr)+'; fi')
 except BaseException as e:errors.append('window: '+str(e))
 if errors:raise RuntimeError('; '.join(errors))
def fallback_recovery():
 errors=[]
 steps=[('stop',lambda:remote('systemctl stop xochitl')),('apps',rollback_apps)]
 for name in ids.values():
  steps.append(('remove '+name,lambda n=name:remote('if test -f '+q(apps+'/'+n+'/probe-run-id')+' && test "$(cat '+q(apps+'/'+n+'/probe-run-id')+')" = '+q(token)+'; then rm -rf '+q(apps+'/'+n)+'; fi')))
 steps+=[('config',lambda:remote('if test -f '+q(remote_base+'/xochitl.conf')+'; then cp -p '+q(remote_base+'/xochitl.conf')+' /home/root/.config/remarkable/xochitl.conf; fi')),('main',lambda:remote('if test -f '+q(remote_base+'/old-appload.qml')+'; then cp -p '+q(remote_base+'/old-appload.qml')+' '+q(main_qrr)+'; fi')),('start',lambda:remote('systemctl reset-failed xochitl; systemctl start xochitl'))]
 for label,operation in steps:
  try:operation()
  except BaseException as e:errors.append(label+': '+str(e))
 return errors
try:
 remote(idle_guard);remote('test "$(sed -n \'s/^IMG_VERSION=//p\' /etc/os-release | tr -d \'"\')" = 3.29.0.153')
 assert remote('sha256sum '+q(main_qrr)).decode().split()[0]==sha(root/'product/payload/system/paperdesk-appload.qml'),'Device AppLoad integration differs from tested source'
 for name in ids.values():remote('test ! -e '+q(apps+'/'+name))
 old_failure=remote('systemctl is-enabled remarkable-fail.service 2>/dev/null || true').decode().strip()
 remote('umask 077; mkdir -m 700 '+q(remote_base)+'; mkdir -m 700 '+q(fixture)+' '+q(fixture+'/profiles')+' '+q(fixture+'/certs')+' '+q(fixture+'/bin')+'; mkfifo -m 600 '+q(fixture+'/input.fifo'))
 remote('tar -xzf - -C '+q(remote_base),pack())
 remote('set -eu; cd '+q(remote_base)+'; sha256sum -c SHA256SUMS >/dev/null; chown -R 0:0 test-apps production; chmod -R go-w test-apps production')
 stub='#!/bin/sh\nif test "${2:-}" = '+q(fixture+'/profiles/profiles')+' && test -f '+q(fixture+'/force-write-error')+'; then exit 1; fi\nexec /bin/mv "$@"\n'
 remote('cat > '+q(fixture+'/bin/mv')+'; chmod 700 '+q(fixture+'/bin/mv'),stub.encode())
 for name in ['paperrdp','paperrdp-login','paperrdp-profile']:
  old_app_hashes[name]=remote('find '+q(apps+'/'+name)+' -type f -exec sha256sum {} \\;').decode()
 report['profiles_before']=remote('if test -d /home/root/.config/paperrdp; then tar -cf - -C /home/root/.config paperrdp | sha256sum; else echo absent; fi').decode().strip()
 start_server();tunnel=subprocess.Popen(ssh[:-1]+['-o','ExitOnForwardFailure=yes','-N','-R',f'127.0.0.1:{port}:127.0.0.1:{port}',ssh[-1]],stdout=subprocess.DEVNULL,stderr=(run/'tunnel.log').open('wb'))
 time.sleep(.5);assert tunnel.poll() is None,'Reverse tunnel failed'
 if old_failure not in ('masked','masked-runtime'):remote('systemctl mask --runtime remarkable-fail.service')
 remote(idle_guard);stopped=True
 remote('set -eu; systemctl stop xochitl; cp -p /home/root/.config/remarkable/xochitl.conf '+q(remote_base+'/xochitl.conf')+'; cp -p '+q(qrr)+' '+q(remote_base+'/old-window.qml')+'; cp -p '+q(main_qrr)+' '+q(remote_base+'/old-appload.qml'))
 original=remote('cat '+q(remote_base+'/xochitl.conf'));report['config_before_sha256']=hashlib.sha256(original).hexdigest()
 rows=[];skip=False
 for line in original.decode().splitlines():
  if line.strip()=='[PaperDeskE2E]':skip=True;continue
  if line.startswith('['):skip=False
  if not skip:rows.append(line)
 config=('\n'.join(rows)+'\n\n[PaperDeskE2E]\nautostart=true\napplicationId='+ids['ui']+'\ntraceTouches=false\nrdpProfileCrud=false\n').encode()
 remote('cat > /home/root/.config/remarkable/xochitl.conf',config)
 remote('set -eu; cp '+q(remote_base+'/new-window.qml')+' '+q(qrr)+'; cp '+q(remote_base+'/probe-appload.qml')+' '+q(main_qrr)+'; cp -a '+q(remote_base+'/test-apps/.')+' '+q(apps)+'/; chmod 755 '+q(apps+'/'+ids['engine']+'/engine')+' '+q(apps+'/'+ids['helper']+'/manager')+'; systemctl reset-failed xochitl; systemctl start xochitl')
 pid=int(remote('systemctl show -p MainPID --value xochitl').strip());report['probe_xochitl_pid']=pid
 wait_state('crud_ready',seconds=90)
 remote('mkdir '+q(fixture+'/profiles/.profile-manager.lock'));command('save_locked');remote('rmdir '+q(fixture+'/profiles/.profile-manager.lock'));command('refresh',expectedCount=0)
 remote('touch '+q(fixture+'/force-write-error'));command('save_write_error');remote('rm '+q(fixture+'/force-write-error'));command('refresh',expectedCount=0)
 stale='v2\t3132372e302e302e31\t636f6e63757272656e74\t\t'+str(port)+'\t\t75\t8\tportrait\n'
 remote('cat > '+q(fixture+'/profiles/profiles')+'; chmod 600 '+q(fixture+'/profiles/profiles'),stale.encode());command('save_stale');command('refresh',expectedCount=1)
 report['wire']={}
 for direction in ['portrait','landscape']:
  connections=wire().count('WIRE_CONNECTED');command('connect',orientation=direction);until(lambda:wire().count('WIRE_CONNECTED')>connections,20);await_mode(2)
  shown=command('keyboard')['details'];state=native_state();engine_pid=int(state['pid']);assert state['viewportHeight']==shown['viewportHeight']
  capture(direction+'-keyboard');key_start=len(wire());command('navigation');command('send_navigation');command('functions');capture(direction+'-functions');command('send_functions')
  def keys_received():
   packets=re.findall(r'WIRE_KEY flags=(\d+) code=(\d+)',wire()[key_start:]);down={(int(c),bool(int(f)&256)) for f,c in packets if not int(f)&32768}
   return all((code,True) in down for code in [0x47,0x48,0x4f,0x49,0x4b,0x50,0x4d,0x51,0x53]) and all((code,False) in down for code in list(range(0x3b,0x45))+[0x57,0x58,0x0f,0x1c,0x2a,0x1d,0x2e,0x2f])
  until(keys_received,8)
  command('hide_keyboard');state=native_state();assert state['viewportHeight']==(1760 if direction=='portrait' else 1292)
  width=1404 if direction=='portrait' else 1872;x1=width//2-150;x2=width//2+150;y=750
  wheels=len([1 for flags in re.findall(r'WIRE_MOUSE flags=(\d+)',wire()) if int(flags)&512])
  fifo(f'down 1 {x1} {y}\ndown 2 {x2} {y}\nmove 1 {x1} {y-72}\nmove 2 {x2} {y-72}\n');time.sleep(.15);fifo(f'up 1 {x1} {y-72}\nup 2 {x2} {y-72}\n')
  until(lambda:len([1 for flags in re.findall(r'WIRE_MOUSE flags=(\d+)',wire()) if int(flags)&512])>wheels,5)
  state=native_state();assert abs(state['zoom']-1)<.01
  count=wire().count('WIRE_CONNECTED');stop_server();await_mode(3);start_server();command('retry');until(lambda:wire().count('WIRE_CONNECTED')>count,20);await_mode(2)
  report['wire'][direction]={'navigation_extended_flags':True,'f1_f12':True,'shift_tab_and_ctrl_chords':True,'two_finger_wheel':True,'retry_after_real_disconnect':True}
  if direction=='landscape':
   stop_server();await_mode(3);start_server(True);command('retry');state=until(lambda:(v if (v:=native_state())['mode']==3 and v['certificateChanged'] else None),20)
   accepted=wire().count('WIRE_PEER_ACCEPTED');command('retry');time.sleep(1);assert wire().count('WIRE_PEER_ACCEPTED')==accepted
   report['wire']['changed_certificate_blocked']=True
  command('close');until(lambda:remote('if test -e /proc/'+str(engine_pid)+'; then echo busy; else echo ready; fi').strip()==b'ready',8)
 command('finish');assert report.get('qml_result',{}).get('passed');passed=True
except BaseException as error:
 failure=error;report['error']=str(error)
finally:
 try:
  if stopped:
   remote('systemctl stop xochitl')
   if passed and failure is None and a.deploy:
    remote('mkdir -m 700 '+q(remote_base+'/previous-apps'))
    for name in ['paperrdp','paperrdp-login','paperrdp-profile']:
     current=remote('find '+q(apps+'/'+name)+' -type f -exec sha256sum {} \\;').decode()
     assert sorted(current.splitlines())==sorted(old_app_hashes[name].splitlines()),'Concurrent app update'
     remote('set -eu; mv '+q(apps+'/'+name)+' '+q(remote_base+'/previous-apps/'+name)+'; mv '+q(remote_base+'/production/'+name)+' '+q(apps+'/'+name))
    committed=True
   else:rollback_apps()
   remote('set -eu; cp -p '+q(remote_base+'/xochitl.conf')+' /home/root/.config/remarkable/xochitl.conf; cp -p '+q(remote_base+'/old-appload.qml')+' '+q(main_qrr))
   for name in ids.values():remote('if test -f '+q(apps+'/'+name+'/probe-run-id')+' && test "$(cat '+q(apps+'/'+name+'/probe-run-id')+')" = '+q(token)+'; then rm -rf '+q(apps+'/'+name)+'; fi')
   remote('systemctl reset-failed xochitl; systemctl start xochitl')
   time.sleep(5);report['restored_xochitl_active']=remote('systemctl is-active xochitl').strip()==b'active'
   report['config_restored']=remote('sha256sum /home/root/.config/remarkable/xochitl.conf').decode().split()[0]==report.get('config_before_sha256')
   report['profiles_unchanged']=remote('if test -d /home/root/.config/paperrdp; then tar -cf - -C /home/root/.config paperrdp | sha256sum; else echo absent; fi').decode().strip()==report.get('profiles_before')
   report['test_apps_removed']=all(remote('test ! -e '+q(apps+'/'+name)+' && echo yes').strip()==b'yes' for name in ids.values())
   if committed:
    installed=remote('sha256sum '+q(apps+'/paperrdp/paperrdp')+' '+q(apps+'/paperrdp-login/resources.rcc')+' '+q(apps+'/paperrdp-profile/profile-manager')+' '+q(qrr)).decode().splitlines()
    expected=[sha(binary),sha(source/'paperrdp-login/resources.rcc'),sha(source/'paperrdp-profile/profile-manager'),sha(run/'new-window.qml')]
    assert [x.split()[0] for x in installed]==expected,'Installed files differ from tested build'
    report['installed_hashes']=dict(zip(['native','login_rcc','profile_helper','window'],expected))
   assert all(report.get(k) for k in ['restored_xochitl_active','config_restored','profiles_unchanged','test_apps_removed']),'Post-test state verification failed'
 except BaseException as error:
  report['restore_error']=str(error);failure=error;committed=False
  if stopped:
   report['recovery_errors']=fallback_recovery();report['fallback_recovery_started']=True
 try:
  if old_failure and old_failure not in ('masked','masked-runtime'):remote('systemctl unmask --runtime remarkable-fail.service')
  if old_failure:report['failure_service_restored']=remote('systemctl is-enabled remarkable-fail.service 2>/dev/null || true').decode().strip()==old_failure
 except BaseException as error:report['failure_service_restore_error']=str(error);failure=error
 if tunnel:
  tunnel.terminate()
  try:tunnel.wait(timeout=5)
  except subprocess.TimeoutExpired:tunnel.kill();tunnel.wait(timeout=5)
 stop_server();report['deployed']=committed;report['passed']=passed and failure is None and all(report.get(k) for k in ['restored_xochitl_active','config_restored','profiles_unchanged','failure_service_restored','test_apps_removed'])
 (root/a.output).write_text(json.dumps(report,indent=2)+'\n');(run/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'deployed':committed,'report':str(root/a.output)}),flush=True)

if failure:raise failure
assert report['passed'],'RDP device probe failed'
