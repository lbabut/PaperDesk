#!/usr/bin/env python3
"""Compile/run native host regressions with the same headers as the ARM build."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
cache = Path(os.environ.get('PAPERDESK_TOOLCACHE', '/home/lukasz/Documents/Codex/2026-09-25/m-2/work'))
sdk = cache / 'papersketch-qt-sdk/root/usr'
include = sdk / 'include/x86_64-linux-gnu/qt6'
work = root / 'work/native-tests'
work.mkdir(parents=True, exist_ok=True)
subprocess.run([str(sdk / 'lib/qt6/libexec/moc'), '-I' + str(include),
                str(root / 'product/payload/apps/papersketch/native/papersketch-raster.cpp'),
                '-o', str(work / 'papersketch-raster.moc')], check=True)
env = dict(os.environ, QT_QPA_PLATFORM='offscreen')
for name in ['material', 'material-realism', 'pressure', 'touch', 'pen', 'display', 'material-integration', 'workflow', 'realism-integration', 'kit-state', 'publication', 'raster']:
    source = root / ('tests/test-sketch-' + name + '.cpp')
    args = ['g++', '-std=c++17', '-O2', '-fPIC', '-pthread', '-I' + str(work), '-I' + str(include)]
    args += ['-I' + str(include / module) for module in ['QtCore', 'QtGui', 'QtQml', 'QtQuick']]
    args += [str(source)]
    if name in ['material-integration', 'workflow', 'realism-integration', 'kit-state', 'publication', 'raster']:
        args += ['-l:libQt6Quick.so.6', '-l:libQt6Qml.so.6', '-l:libQt6Gui.so.6', '-l:libQt6Core.so.6', '-ldl', '-lz']
    target = work / name
    subprocess.run(args + ['-o', str(target)], check=True, cwd=root)
    print('Running', name, flush=True)
    subprocess.run([str(target)], check=True, env=env, cwd=root)
