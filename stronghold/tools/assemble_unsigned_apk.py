#!/usr/bin/env python3
"""Assemble APK without repackaging resources or touching original DEX.
Input APK belongs to user; it is NEVER included in the source distribution.
Requires precompiled classes2.dex and ARM64 .so libraries from Android SDK/NDK.
"""
import hashlib, pathlib, sys, zipfile
from inject_manifest_provider import insert, validate
ROOT=pathlib.Path(__file__).resolve().parents[1]
input_apk=pathlib.Path(sys.argv[1])
output_apk=pathlib.Path(sys.argv[2])
menu_dex=ROOT/'build/dex/classes.dex'
modlib=ROOT/'build/libstronghold-menu-v33.so'
bridge=ROOT/'build/libstronghold_mod_runtime.so'
assert all(p.is_file() for p in [input_apk,menu_dex,modlib,bridge]), 'Missing compiled build input'
assert menu_dex.read_bytes()[:4]==b'dex\n'
assert modlib.read_bytes()[:4]==b'\x7fELF' and bridge.read_bytes()[:4]==b'\x7fELF'
output_apk.parent.mkdir(parents=True,exist_ok=True)
replacement={
 'AndroidManifest.xml':None,
 'lib/arm64-v8a/libstronghold.so':modlib.read_bytes(),
}
with zipfile.ZipFile(input_apk) as zin:
 assert 'classes2.dex' not in zin.namelist(), 'Existing secondary DEX requires custom merge'
 replacement['AndroidManifest.xml']=insert(zin.read('AndroidManifest.xml'))
 original_dex_hash=hashlib.sha256(zin.read('classes.dex')).hexdigest()
 with zipfile.ZipFile(output_apk,'w',allowZip64=True) as zout:
  for info in zin.infolist():
   if info.filename.upper().startswith('META-INF/'):
    continue
   payload=replacement.get(info.filename)
   if payload is None:payload=zin.read(info)
   zout.writestr(info,payload,compress_type=info.compress_type,compresslevel=6)
  zout.writestr('classes2.dex',menu_dex.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=6)
  zout.writestr('lib/arm64-v8a/libstronghold_mod_runtime.so',bridge.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=6)
with zipfile.ZipFile(output_apk) as z:
 assert z.testzip() is None
 assert hashlib.sha256(z.read('classes.dex')).hexdigest()==original_dex_hash
 assert z.read('lib/arm64-v8a/libstronghold.so')==modlib.read_bytes()
 assert z.read('classes2.dex')==menu_dex.read_bytes()
 validate(z.read('AndroidManifest.xml'))
 print('Unsigned APK structurally valid; original classes.dex unchanged')
 print('Size:',output_apk.stat().st_size,'SHA256',hashlib.sha256(output_apk.read_bytes()).hexdigest())
