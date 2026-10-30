#!/usr/bin/env python3
"""Asfatre v1.3 version-locked ELF transformer; preserves the vendor extra segment."""
import hashlib, io, json, os, pathlib, struct, subprocess, sys
from elftools.elf.elffile import ELFFile
ROOT=pathlib.Path(__file__).resolve().parents[1]
SHA='9f23ca8ef417c93d319e3f04a34d5eb0535b8c3222810f839c17d889a4c593a2'
SITES=[
 ('regular_recruit',0x2520aec,'f10100b9','str w17, [x15]'),
 ('arab_recruit',0x2521510,'110200b9','str w17, [x16]'),
 ('market_purchase',0x2c77090,'cf0100b9','str w15, [x14]'),
 ('trade_purchase',0x2c2c7c8,'110200b9','str w17, [x16]'),
 ('siege_action',0x29d1d90,'cd0100b9','str w13, [x14]'),
 ('gold_transfer',0x297f2a8,'490100b9','str w9, [x10]'),
 ('ally_gold',0x29bcf80,'110200b9','str w17, [x16]'),
 ('inventory_debit',0x2c55970,'883d0034','cbz w8, original_zero'),
 ('peasant_rate',0x20888a0,'2f0200b9','str w15, [x17]'),
]
def branch(src,dest):
    delta=dest-src
    assert delta%4==0 and -(1<<27)<=delta<(1<<27)
    return struct.pack('<I',0x14000000|((delta//4)&0x3ffffff))
def patch(source,destination):
    raw=source.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==SHA,'Wrong library: refusing to patch'
    elf=ELFFile(io.BytesIO(raw))
    assert elf.elfclass==64 and elf.little_endian and elf['e_machine']=='EM_AARCH64' and elf['e_type']=='ET_DYN'
    loads=[(i,p) for i,p in enumerate(elf.iter_segments()) if p['p_type']=='PT_LOAD']
    rx_index,rx=next((i,p) for i,p in loads if p['p_flags']==5)
    writable=[(i,p) for i,p in loads if p['p_flags']==6]
    assert writable, 'Expected original game writable LOAD segment'
    bss_index,bss=writable[-1]
    extra=[p for _,p in loads if p['p_flags']==5 and p['p_vaddr']>bss['p_vaddr']]
    assert len(extra)==1 and extra[0]['p_vaddr']==0x3c84000, 'Unexpected Asfatre extension layout'
    insertion=rx['p_offset']+rx['p_filesz'];code_va=rx['p_vaddr']+rx['p_memsz']
    control_va=(bss['p_vaddr']+bss['p_memsz']+15)&~15
    assert insertion==0x3044090 and code_va==0x3048090 and control_va==0x3c82050
    assert control_va+4096<=extra[0]['p_vaddr'], 'Patched control block overlaps Asfatre code'
    assert code_va+0x3000<=min(p['p_vaddr'] for _,p in loads if p['p_vaddr']>code_va)
    def offset(va):
        for _,p in loads:
            if p['p_vaddr']<=va<p['p_vaddr']+p['p_filesz']:return va-p['p_vaddr']+p['p_offset']
        raise ValueError(hex(va))
    for _,va,expected,_ in SITES:assert raw[offset(va):offset(va)+4].hex()==expected
    out=ROOT/'build';out.mkdir(exist_ok=True)
    asm=['.text','.p2align 2']
    for site,(name,_,_,instruction) in enumerate(SITES):
        asm += ['.global hook_'+name,'hook_'+name+':','sub sp, sp, #256']
        asm += [f'stp x{i}, x{i+1}, [sp, #{i*8}]' for i in range(0,30,2)]
        asm += ['str x30, [sp, #240]','mrs x9, nzcv','str x9, [sp, #248]',
                'mov x0, sp',f'mov w1, #{site}','bl mod_dispatch','ldr x9, [sp, #248]','msr nzcv, x9']
        asm += [f'ldp x{i}, x{i+1}, [sp, #{i*8}]' for i in range(0,30,2)]
        asm += ['ldr x30, [sp, #240]','add sp, sp, #256']
        asm += ['cbnz w8, 1f','b original_zero','1:'] if site==7 else [instruction]
        asm += ['b return_'+name]
    (out/'hooks.S').write_text('\n'.join(asm)+'\n')
    linker=f'SECTIONS {{ . = {code_va}; .text : {{ *(.text*) *(.rodata*) }} /DISCARD/ : {{ *(.comment) *(.note*) *(.eh_frame*) }} }}\n'
    linker+=f'mod_control = {control_va}; image_base = 0; original_zero = 0x2c56120;\n'
    linker+='\n'.join(f'return_{name} = {va+4};' for name,va,_,_ in SITES)+'\n'
    (out/'payload.ld').write_text(linker)
    ndk=pathlib.Path(os.environ['NDK_BIN']);cc=str(ndk/'aarch64-linux-android28-clang')
    common=[cc,'-c','-Os','-fno-pic','-ffreestanding','-mgeneral-regs-only','-mno-outline-atomics',
            '-fno-stack-protector','-fno-unwind-tables','-fno-asynchronous-unwind-tables','-Wall','-Wextra','-Werror']
    subprocess.run(common+[str(out/'hooks.S'),'-o',str(out/'hooks.o')],check=True)
    subprocess.run(common+['-I',str(ROOT/'native'),str(ROOT/'native/payload.c'),'-o',str(out/'payload.o')],check=True)
    subprocess.run([str(ndk/'ld.lld'),'-T',str(out/'payload.ld'),'-e','mod_dispatch',str(out/'hooks.o'),str(out/'payload.o'),'-o',str(out/'payload.elf')],check=True)
    compiled=ELFFile(io.BytesIO((out/'payload.elf').read_bytes()))
    section=compiled.get_section_by_name('.text');code=section.data()
    assert section['sh_addr']==code_va and len(code)<=0x3000
    symbols={s.name:s['st_value'] for s in compiled.get_section_by_name('.symtab').iter_symbols()}
    assert not [s.name for s in compiled.get_section_by_name('.symtab').iter_symbols() if s.name and s['st_shndx']=='SHN_UNDEF']
    assert not [s.name for s in compiled.iter_sections() if s['sh_type'] in ('SHT_RELA','SHT_REL') and s['sh_size']]
    patched=bytearray(raw[:insertion]+bytes(0x4000)+raw[insertion:])
    # All load addresses and dynamic virtual pointers remain unchanged.
    for i,p in enumerate(elf.iter_segments()):
        at=elf['e_phoff']+i*elf['e_phentsize']
        if p['p_offset']>=insertion:struct.pack_into('<Q',patched,at+8,p['p_offset']+0x4000)
        if i==rx_index:
            struct.pack_into('<QQ',patched,at+32,p['p_filesz']+0x3000,p['p_memsz']+0x3000)
        if i==bss_index:struct.pack_into('<Q',patched,at+40,control_va+4096-p['p_vaddr'])
    shoff=elf['e_shoff'];new_shoff=shoff+(0x4000 if shoff>=insertion else 0)
    struct.pack_into('<Q',patched,40,new_shoff)
    for i,s in enumerate(elf.iter_sections()):
        if s['sh_offset']>=insertion:struct.pack_into('<Q',patched,new_shoff+i*elf['e_shentsize']+24,s['sh_offset']+0x4000)
    patched[insertion:insertion+len(code)]=code
    entries=[]
    for site,(name,va,expected,insn) in enumerate(SITES):
        at=offset(va);target=symbols['hook_'+name];replacement=branch(va,target)
        patched[at:at+4]=replacement
        entries.append(dict(site=site,name=name,va=va,offset=at,original=expected,patched=replacement.hex(),target=target,instruction=insn))
    destination.write_bytes(patched)
    manifest=dict(source_version='Asfatre v1.3-stable',original_sha256=SHA,patched_sha256=hashlib.sha256(patched).hexdigest(),
                  code_va=code_va,code_offset=insertion,code_size=len(code),inserted_size=0x4000,
                  control_va=control_va,signature_va=symbols['hook_signature'],sites=entries)
    (out/'patch_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (ROOT/'native/generated.h').write_text('// Generated by patch_extreme.py; offsets are relative to ELF load bias.\n'
         f'#define CONTROL_VA 0x{control_va:x}u\n#define SIGNATURE_VA 0x{symbols["hook_signature"]:x}u\n')
    print(json.dumps(manifest,indent=2))
if __name__=='__main__':patch(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]))
