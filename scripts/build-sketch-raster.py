import pathlib,subprocess,os
root=pathlib.Path(__file__).resolve().parents[1];cache=pathlib.Path(os.environ.get("PAPERDESK_TOOLCACHE","/home/lukasz/Documents/Codex/2026-09-25/m-2/work"))
sdk=cache/"papersketch-qt-sdk/root";includes=sdk/"usr/include/x86_64-linux-gnu/qt6";work=root/"work/papersketch-native-ink"
work.mkdir(parents=True,exist_ok=True)
src=root/"product/payload/apps/papersketch/native/papersketch-raster.cpp"
moc=sdk/"usr/lib/qt6/libexec/moc"
p=subprocess.run([str(moc),"-I"+str(includes),str(src),"-o",str(work/"papersketch-raster.moc")],capture_output=True,text=True);print("MOC",p.returncode,p.stdout,p.stderr);p.check_returncode()
c=cache/"arm-toolchain/root";env=os.environ.copy();env["LD_LIBRARY_PATH"]=str(c/"usr/lib/x86_64-linux-gnu")
zlib=cache/"arm-sysroot/root"
args=[str(c/"usr/bin/arm-linux-gnueabihf-g++-12"),"--sysroot="+str(c),"-std=c++17","-O2","-fPIC","-shared","-marm","-I"+str(includes),"-I"+str(work),"-idirafter",str(zlib/"usr/include")]
profile=os.environ.get("PAPERDESK_SKETCH_CPU_PROFILE","portable")
if profile=="rm2-cortex-a7":
    # Explicit device-specific opt-in, not a generic ARM compatibility promise.
    # Never use fast-math: pigment state must match the portable build exactly.
    args.remove("-O2")
    args += ["-O3","-mcpu=cortex-a7","-mfpu=neon-vfpv4","-ffp-contract=off"]
elif profile!="portable":
    raise SystemExit("Unknown PAPERDESK_SKETCH_CPU_PROFILE: "+profile)
for name in ["QtCore","QtGui","QtQml","QtQuick"]:args+=["-I"+str(includes/name)]
args+=[str(src),"-L"+str(zlib/"lib/arm-linux-gnueabihf"),"-l:libz.so.1","-ldl","-lpthread","-lm","-o",str(src.with_suffix(".so"))]
p=subprocess.run(args,env=env,capture_output=True,text=True);print("BUILD",p.returncode,p.stdout,p.stderr[-12000:]);p.check_returncode()
