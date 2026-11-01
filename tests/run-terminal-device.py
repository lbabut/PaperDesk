#!/usr/bin/env python3
"""Run actual ARM/QML terminal diagnostics offscreen in an isolated tablet /tmp.

No app installation, global extension, service restart, framebuffer or input
injection is used. Only this run's temporary directory is uploaded and removed.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='10.11.99.1')
    parser.add_argument('--key', required=True)
    parser.add_argument('--known-hosts', required=True)
    parser.add_argument('--output', default='docs/paperterminal-device-2026-11-01.json')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    cache = Path(os.environ.get('PAPERDESK_TOOLCACHE', '/home/lukasz/Documents/Codex/2026-09-25/m-2/work'))
    sdk = Path(os.environ.get('PAPERDESK_QT_SDK', str(cache / 'papersketch-qt-sdk/root')))
    toolchain = cache / 'arm-toolchain/root'
    work = root / 'work/terminal-device'
    libraries = root / 'work/terminal-device-libs'
    work.mkdir(parents=True, exist_ok=True)
    libraries.mkdir(parents=True, exist_ok=True)
    ssh = ['ssh', '-i', args.key, '-o', 'UserKnownHostsFile=' + args.known_hosts,
           '-o', 'StrictHostKeyChecking=yes', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', 'root@' + args.host]

    def remote(command, data=None, timeout=45, check=True):
        result = subprocess.run(ssh + [command], input=data, capture_output=True, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError('Tablet diagnostic command failed: ' + result.stderr.decode(errors='replace'))
        return result

    metadata = remote('set -eu; uname -m; cat /etc/os-release; test -x /home/root/.local/bin/rmssh-menu; test -f /usr/lib/plugins/platforms/libqoffscreen.so').stdout.decode()
    if not metadata.startswith('armv7l\n'):
        raise RuntimeError('This probe requires an ARMv7 reMarkable 2.')
    for module in ['Core', 'Gui', 'Qml', 'Quick']:
        destination = libraries / ('libQt6' + module + '.so.6')
        destination.write_bytes(remote('cat /usr/lib/' + destination.name).stdout)
    include = sdk / 'usr/include/x86_64-linux-gnu/qt6'
    subprocess.run([str(sdk / 'usr/lib/qt6/libexec/moc'), '-I' + str(include), str(root / 'tests/device/terminal-device.cpp'),
                    '-o', str(work / 'terminal-device.moc')], check=True)
    compiler = toolchain / 'usr/bin/arm-linux-gnueabihf-g++-12'
    command = [str(compiler), '--sysroot=' + str(toolchain), '-std=c++17', '-O2', '-marm', '-fPIC',
               '-I' + str(include), '-I' + str(work)]
    command += ['-I' + str(include / module) for module in ['QtCore', 'QtGui', 'QtQml', 'QtQuick']]
    command += [str(root / 'tests/device/terminal-device.cpp'), '-L' + str(libraries),
                '-Wl,--allow-shlib-undefined', '-l:libQt6Quick.so.6', '-l:libQt6Qml.so.6',
                '-l:libQt6Gui.so.6', '-l:libQt6Core.so.6', '-lpthread', '-ldl', '-o', str(work / 'terminal-device')]
    env = dict(os.environ, LD_LIBRARY_PATH=str(toolchain / 'usr/lib/x86_64-linux-gnu'))
    subprocess.run(command, env=env, check=True)
    source = root / 'product/payload/apps/paperterminal'
    plugin = source / 'native/libpaperterminal_native.so'
    plugin_digest = hashlib.sha256(plugin.read_bytes()).hexdigest()
    token = uuid.uuid4().hex
    stage = '/tmp/paperterminal-device-' + token
    fixture = work / token
    shutil.copytree(source, fixture / 'app')
    qmldir = fixture / 'app/native/qmldir'
    qmldir.write_text(qmldir.read_text().replace('/home/root/xovi/exthome/appload/paperterminal/native', stage + '/app/native'))
    rcc = Path(os.environ.get('PAPERDESK_RCC', str(cache / 'qt-rcc-pkg/root/usr/lib/qt5/bin/rcc')))
    subprocess.run([str(rcc), '--binary', 'application.qrc', '-o', 'resources.rcc'], cwd=fixture / 'app', check=True)
    mock = fixture / 'imports/net/asivery/ApploadUtils'
    shutil.copytree(root / 'tests/qml/imports/net/asivery/ApploadUtils', mock)
    shutil.copy2(work / 'terminal-device', fixture / 'terminal-device')
    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode='w:gz') as bundle:
        for path in sorted(fixture.rglob('*')):
            if path.is_file(): bundle.add(path, arcname=path.relative_to(fixture).as_posix())
    output = root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {'scope': 'Offscreen ARM CPU/render/PTY probe. Physical e-ink latency and AppLoad hardware behavior are outside this probe.',
              'tabletMetadata': metadata, 'pluginSha256': plugin_digest,
              'menuScope': 'Compatibility with the pre-existing installed rmssh-menu, executed with isolated HOME. This probe does not validate the packaged menu changes; those require the separate AppLoad hardware test.',
              'installedMenuSha256': remote('sha256sum /home/root/.local/bin/rmssh-menu').stdout.decode().split()[0],
              'packagedMenuSha256': hashlib.sha256((root / 'product/payload/system/rmssh-menu').read_bytes()).hexdigest(),
              'qmlSha256': hashlib.sha256((source / 'ui/main.qml').read_bytes()).hexdigest(),
              'nativeSourceSha256': hashlib.sha256((source / 'native/paperterminal-native.cpp').read_bytes()).hexdigest(),
              'temporaryStage': stage}
    try:
        remote('mkdir -m 700 ' + shlex.quote(stage))
        remote('tar -xzf - -C ' + shlex.quote(stage), archive.getvalue())
        report['uploadedPluginSha256'] = remote('sha256sum ' + shlex.quote(stage + '/app/native/libpaperterminal_native.so')).stdout.decode().split()[0]
        if report['uploadedPluginSha256'] != plugin_digest:
            raise RuntimeError('Uploaded native plugin checksum mismatch.')
        command = ('set -eu; cd ' + shlex.quote(stage) + '; mkdir -m 700 home runtime home/config home/data home/cache; '
                   'HOME=' + shlex.quote(stage + '/home') + ' XDG_CONFIG_HOME=' + shlex.quote(stage + '/home/config') +
                   ' XDG_DATA_HOME=' + shlex.quote(stage + '/home/data') + ' XDG_CACHE_HOME=' + shlex.quote(stage + '/home/cache') +
                   ' XDG_RUNTIME_DIR=' + shlex.quote(stage + '/runtime') + ' LD_PRELOAD= QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software '
                   'QT_PLUGIN_PATH=/usr/lib/plugins QML_IMPORT_PATH=' + shlex.quote(stage + '/imports:/usr/lib/qml') +
                   ' QML2_IMPORT_PATH=' + shlex.quote(stage + '/imports:/usr/lib/qml') +
                   ' timeout -k 3 60 ./terminal-device ' + shlex.quote(stage) + ' ' + shlex.quote(stage + '/report.json'))
        result = remote(command, timeout=70, check=False)
        (work / 'device.log').write_bytes(result.stdout + result.stderr)
        report['exitCode'] = result.returncode
        raw = remote('cat ' + shlex.quote(stage + '/report.json'), check=False).stdout
        if raw: report['probe'] = json.loads(raw)
        image = remote('cat ' + shlex.quote(stage + '/terminal-offscreen.png'), check=False)
        if image.returncode == 0:
            screenshot = work / 'terminal-offscreen.png'; screenshot.write_bytes(image.stdout)
            report['offscreenScreenshot'] = str(screenshot.relative_to(root))
    finally:
        cleanup = remote('rm -rf -- ' + shlex.quote(stage), check=False)
        report['temporaryStageRemoved'] = cleanup.returncode == 0
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(output)
    print(json.dumps(report.get('probe', {}), ensure_ascii=False, indent=2))
    if report.get('exitCode') != 0 or not report.get('probe', {}).get('passed'):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
