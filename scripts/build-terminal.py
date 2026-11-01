#!/usr/bin/env python3
"""Build Paper Terminal's app-local QML plugin without installing a global backend.

The ARM build deliberately leaves Qt symbols for xochitl to resolve, matching
the target's own Qt. Host builds link the installed matching Qt runtime and
always stay under work/, never replacing the shipped ARM plugin.
"""
import argparse
import os
import pathlib
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", action="store_true", help="build host QML plugin under work/terminal-native-host")
    parser.add_argument("--test", action="store_true", help="build and run the real PTY/render host tests")
    parser.add_argument("--no-plugin-build", action="store_true", help="with --test, rebuild only test executables/helper; leave all QML plugin binaries untouched")
    args = parser.parse_args()
    if args.no_plugin_build and not args.test:
        parser.error("--no-plugin-build requires --test")
    if args.test and not args.no_plugin_build:
        # The RCC import test must use a matching, freshly built host plugin.
        # Keep --test self-contained on a clean checkout.
        subprocess.run([sys.executable, str(pathlib.Path(__file__).resolve()), "--host"], check=True)
    root = pathlib.Path(__file__).resolve().parents[1]
    cache = pathlib.Path(os.environ.get("PAPERDESK_TOOLCACHE", "/home/lukasz/Documents/Codex/2026-09-25/m-2/work"))
    sdk = pathlib.Path(os.environ.get("PAPERDESK_QT_SDK", str(cache / "papersketch-qt-sdk/root")))
    include = sdk / "usr/include/x86_64-linux-gnu/qt6"
    moc = sdk / "usr/lib/qt6/libexec/moc"
    source = root / "product/payload/apps/paperterminal/native/paperterminal-native.cpp"
    helper_source = source.parent / "paperterminal-askpass.cpp"
    host = args.host or args.test
    work = root / ("work/terminal-native-tests" if args.test else "work/terminal-native-host" if host else "work/terminal-native-arm")
    work.mkdir(parents=True, exist_ok=True)
    moc_args = [str(moc), "-I" + str(include)]
    if args.test:
        moc_args += ["-DPAPERTERMINAL_NO_PLUGIN", "-DPAPERTERMINAL_TESTING"]
    subprocess.run(moc_args + [str(source), "-o", str(work / "paperterminal-native.moc")], check=True)
    env = os.environ.copy()
    common = ["-std=c++17", "-O2", "-fPIC", "-Wall", "-Wextra", "-Wpedantic", "-I" + str(include), "-I" + str(work)]
    for module in ["QtCore", "QtGui", "QtQml", "QtQuick"]:
        common += ["-I" + str(include / module)]
    if host:
        compiler = os.environ.get("CXX", "g++")
        output = work / ("terminal-native-test" if args.test else "libpaperterminal_native.so")
        source_to_build = root / "tests/terminal-native.cpp" if args.test else source
        command = [compiler] + common + ([] if args.test else ["-shared"]) + [str(source_to_build)]
        # Runtime-only Debian packages do not provide development .so links.
        command += ["-l:libQt6Quick.so.6", "-l:libQt6Qml.so.6", "-l:libQt6Gui.so.6", "-l:libQt6Core.so.6", "-lpthread", "-ldl", "-o", str(output)]
        helper_command = [compiler, "-std=c++17", "-O2", "-fPIE", "-pie", "-Wall", "-Wextra", "-Wpedantic", str(helper_source), "-o", str(work / "paperterminal-askpass")]
    else:
        toolchain = cache / "arm-toolchain/root"
        compiler = toolchain / "usr/bin/arm-linux-gnueabihf-g++-12"
        env["LD_LIBRARY_PATH"] = str(toolchain / "usr/lib/x86_64-linux-gnu")
        output = source.parent / "libpaperterminal_native.so"
        command = [str(compiler), "--sysroot=" + str(toolchain)] + common + ["-shared", "-marm", str(source), "-ldl", "-lpthread", "-lm", "-Wl,-z,noexecstack", "-o", str(output)]
        helper_command = [str(compiler), "--sysroot=" + str(toolchain), "-std=c++17", "-O2", "-marm", "-fPIE", "-pie", "-Wall", "-Wextra", "-Wpedantic", str(helper_source), "-Wl,-z,noexecstack", "-o", str(source.parent / "paperterminal-askpass")]
    subprocess.run(helper_command, env=env, check=True)
    subprocess.run(command, env=env, check=True)
    if host and not args.test:
        shutil.copy2(source.parent / "qmldir", work / "qmldir")
    print(output)
    if args.test:
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["QT_QUICK_BACKEND"] = "software"
        env["QT_LOGGING_RULES"] = "qt.qpa.*=false"
        subprocess.run([str(output)], env=env, check=True, cwd=root)


if __name__ == "__main__":
    main()
