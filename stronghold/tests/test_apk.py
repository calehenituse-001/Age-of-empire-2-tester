#!/usr/bin/env python3
"""Artifact integrity checks. Installation, rendering and gameplay require Android."""
import hashlib,io,json,pathlib,struct,sys,zipfile
from elftools.elf.elffile import ELFFile
from androguard.core.apk import APK
from loguru import logger
logger.disable('androguard')
ROOT=pathlib.Path(__file__).resolve().parents[1]
original=pathlib.Path(sys.argv[1]);signed=pathlib.Path(sys.argv[2])
assert hashlib.sha256(original.read_bytes()).hexdigest()=='92dc03003274dcac024d63a66e61fab75f9f5b26bb3bcd01c89f935bfa22d252'
with zipfile.ZipFile(original) as a,zipfile.ZipFile(signed) as b:
    assert b.testzip() is None
    excluded={'AndroidManifest.xml','lib/arm64-v8a/libstronghold.so'}
    preserved=0
    for name in a.namelist():
        if name.upper().startswith('META-INF/') or name in excluded:continue
        assert a.read(name)==b.read(name),f'Unrelated entry changed: {name}'
        preserved+=1
    allowed={'classes2.dex','lib/arm64-v8a/libstronghold_mod_runtime.so'}
    assert {n for n in b.namelist() if n not in a.namelist() and not n.upper().startswith('META-INF/')}==allowed
    manifest=json.loads((ROOT/'build/patch_manifest.json').read_text())
    raw=a.read('lib/arm64-v8a/libstronghold.so');patched=b.read('lib/arm64-v8a/libstronghold.so')
    assert hashlib.sha256(patched).hexdigest()==manifest['patched_sha256']
    elf=ELFFile(io.BytesIO(patched));old=ELFFile(io.BytesIO(raw))
    assert elf['e_machine']=='EM_AARCH64' and elf['e_type']=='ET_DYN'
    loads=[p for p in elf.iter_segments() if p['p_type']=='PT_LOAD']
    for i,p in enumerate(loads):
        assert p['p_filesz']<=p['p_memsz']
        assert p['p_offset']%p['p_align']==p['p_vaddr']%p['p_align']
        if i+1<len(loads):assert p['p_vaddr']+p['p_memsz']<=loads[i+1]['p_vaddr']
    # Restore each deliberately changed part, remove inserted padding, then require
    # byte-for-byte equality with the original library, including all other code.
    restored=bytearray(patched)
    for site in manifest['sites']:
        at=site['offset'];assert restored[at:at+4].hex()==site['patched']
        ins=struct.unpack_from('<I',restored,at)[0];delta=ins&0x3ffffff
        if delta&(1<<25):delta-=1<<26
        assert ins>>26==5 and site['va']+delta*4==site['target']
        restored[at:at+4]=bytes.fromhex(site['original'])
    at=manifest['code_offset'];del restored[at:at+manifest['inserted_size']]
    restored[:64]=raw[:64]
    ph0=old['e_phoff'];phn=old['e_phnum']*old['e_phentsize'];restored[ph0:ph0+phn]=raw[ph0:ph0+phn]
    sh0=old['e_shoff'];shn=old['e_shnum']*old['e_shentsize'];restored[sh0:sh0+shn]=raw[sh0:sh0+shn]
    assert bytes(restored)==raw,'Unexpected library mutation'
    # Check provenance of allowlisted inventory callsites directly against BL.
    def old_word(va):
        for p in old.iter_segments():
            if p['p_type']=='PT_LOAD' and p['p_vaddr']<=va<p['p_vaddr']+p['p_filesz']:
                return struct.unpack_from('<I',raw,va-p['p_vaddr']+p['p_offset'])[0]
        raise AssertionError(hex(va))
    for lr in [0x2520b70,0x2520c44,0x2520d20,0x2c5ae80,0x2c5b000,0x2c5b12c,0x2c5b1e8,0x2c5b2ac,0x2c5b374,0x2c5b68c,0x2c5b740,0x2c5b7fc,0x2c5b8d8]:
        ins=old_word(lr-4);assert ins>>26==0x25,(hex(lr),'not BL')
        delta=ins&0x3ffffff
        if delta&(1<<25):delta-=1<<26
        assert lr-4+delta*4==0x2c558b4,(hex(lr),'different target')
    bridge=ELFFile(io.BytesIO(b.read('lib/arm64-v8a/libstronghold_mod_runtime.so')))
    assert bridge['e_machine']=='EM_AARCH64'
    names={s.name for s in bridge.get_section_by_name('.dynsym').iter_symbols() if s['st_shndx']!='SHN_UNDEF'}
    for n in ['nativeAvailable','nativeApply','nativeDiagnostics']:assert 'Java_org_stronghold_port_StrongholdNativeBridge_'+n in names
apk=APK(str(signed));original_apk=APK(str(original))
assert apk.get_package()=='org.stronghold.port'
assert apk.get_min_sdk_version()=='28' and apk.get_target_sdk_version()=='28'
assert set(apk.get_permissions())==set(original_apk.get_permissions())
assert set(apk.get_activities())==set(original_apk.get_activities())
ns='{http://schemas.android.com/apk/res/android}'
providers=apk.get_android_manifest_xml().findall('.//provider')
p=next(p for p in providers if p.get(ns+'name')=='org.stronghold.port.mod.ModInitProvider')
assert p.get(ns+'exported')=='false' and p.get(ns+'process')==':extreme'
assert p.get(ns+'authorities')=='org.stronghold.port.modinit33'
assert apk.is_signed_v2() or apk.is_signed_v3(), 'APK signing block missing'
report={'apk_sha256':hashlib.sha256(signed.read_bytes()).hexdigest(),'apk_bytes':signed.stat().st_size,
        'original_apk_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),'size_increase_bytes':signed.stat().st_size-original.stat().st_size,
        'unchanged_original_entries':preserved,'original_dex_preserved':True,'original_other_libraries_preserved':True,
        'manifest_provider':'non-exported, :extreme','package':apk.get_package(),'min_sdk':28,'target_sdk':28,
        'patched_sites':len(manifest['sites']),'runtime_android_tested':False,'native_arm64_emulated':True}
(ROOT/'build/apk_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
