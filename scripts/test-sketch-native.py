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
# The same deterministic workload is compiled into the real evdev injector.
pattern_test = work / 'detail-pattern'
subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                str(root / 'tests/test-sketch-detail-pattern.c'), '-o', str(pattern_test)], check=True)
subprocess.run([str(pattern_test)], check=True)
# Compile the actual fast-pen path against a private framebuffer: no device I/O.
preview_test = work / 'preview-batch'
subprocess.run(['gcc', '-O2', '-Wall', '-Wextra', '-Wno-format-truncation',
                str(root / 'tests/test-sketch-native-batch.c'), '-o', str(preview_test),
                '-ldl', '-lpthread', '-lm'], check=True)
subprocess.run([str(preview_test)], check=True)
subprocess.run([str(sdk / 'lib/qt6/libexec/moc'), '-I' + str(include),
                str(root / 'product/payload/apps/papersketch/native/papersketch-raster.cpp'),
                '-o', str(work / 'papersketch-raster.moc')], check=True)
env = dict(os.environ, QT_QPA_PLATFORM='offscreen')
for name in ['release-resource', 'preview-shade', 'charcoal', 'tile-seams', 'contact-cache', 'preferences', 'input-fidelity', 'pointer-filter', 'stylus-eraser', 'rapidograph', 'rapidograph-integration', 'pdf', 'finger-transport', 'material', 'material-realism', 'pressure', 'touch', 'pen', 'display', 'material-integration', 'workflow', 'realism-integration', 'kit-state', 'publication', 'latency', 'raster']:
    source = root / ('tests/test-sketch-' + name + '.cpp')
    args = ['g++', '-std=c++17', '-O2', '-fPIC', '-pthread', '-I' + str(work), '-I' + str(include)]
    args += ['-I' + str(include / module) for module in ['QtCore', 'QtGui', 'QtQml', 'QtQuick']]
    args += [str(source)]
    if name in ['charcoal', 'tile-seams', 'release-resource', 'preferences', 'input-fidelity', 'pointer-filter', 'stylus-eraser', 'rapidograph', 'rapidograph-integration', 'pdf', 'material-integration', 'workflow', 'realism-integration', 'kit-state', 'publication', 'latency', 'raster']:
        args += ['-l:libQt6Quick.so.6', '-l:libQt6Qml.so.6', '-l:libQt6Gui.so.6', '-l:libQt6Core.so.6', '-ldl', '-lz']
    target = work / name
    subprocess.run(args + ['-o', str(target)], check=True, cwd=root)
    print('Running', name, flush=True)
    subprocess.run([str(target)], check=True, env=env, cwd=root)
