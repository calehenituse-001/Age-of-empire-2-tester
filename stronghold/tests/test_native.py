#!/usr/bin/env python3
"""Executes the REAL patched ARM64 instructions under Unicorn with synthetic state.
This is not Android gameplay, real player identity validation, or an AI isolation claim.
"""
import io,json,pathlib,random,struct,unittest
from elftools.elf.elffile import ELFFile
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM
from unicorn import arm64_const as reg
ROOT=pathlib.Path(__file__).resolve().parents[1]
M=json.loads((ROOT/'build/patch_manifest.json').read_text())
RAW=(ROOT/'build/libstronghold-menu-v33.so').read_bytes()
GUEST=0x2000000000;STRIDE=0x39f4;STOCK=0x122c330
REGS=[getattr(reg,'UC_ARM64_REG_X'+str(i)) for i in range(31)]

class Machine:
    def __init__(self,base):
        self.base=base;self.u=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
        elf=ELFFile(io.BytesIO(RAW));loads=[p for p in elf.iter_segments() if p['p_type']=='PT_LOAD']
        end=max(p['p_vaddr']+p['p_memsz'] for p in loads)
        self.u.mem_map(base,(end+4095)&~4095)
        for p in loads:self.u.mem_write(base+p['p_vaddr'],p.data())
        self.u.mem_map(GUEST,0x4000000)
        self.stack=0x6000010000;self.u.mem_map(self.stack-0x10000,0x20000)
        self.control=base+M['control_va'];self.reset()
    def write(self,ptr,v):self.u.mem_write(ptr,struct.pack('<I',v&0xffffffff))
    def read(self,ptr):return struct.unpack('<I',self.u.mem_read(ptr,4))[0]
    def guest(self,ptr,v):self.write(GUEST|ptr,v)
    def reset(self):
        self.u.mem_write(self.control,bytes(352));self.write(self.control+4,1000)
        self.identity()
    def identity(self,local=3,mode=99,viewer=6):
        self.guest(0x248ca00,mode);self.guest(0x2bb8ee8,3)
        self.guest(0x25f8748,local);self.guest(0x25f874c,viewer)
        for i in range(1,9):self.guest(0x248ca90+4*i,1 if i==local else 100+i);self.guest(0x248cafc+4*i,0 if i==local else 1)
    def frame(self):
        rng=random.Random(33);r=[rng.randrange(1<<50) for _ in range(31)]
        for k,v in zip(REGS,r):self.u.reg_write(k,v)
        self.u.reg_write(reg.UC_ARM64_REG_SP,self.stack)
        self.u.reg_write(reg.UC_ARM64_REG_NZCV,0xa0000000)
        for i in range(32):self.u.reg_write(getattr(reg,'UC_ARM64_REG_Q'+str(i)),(1<<120)+i)
        return r
    def run_site(self,index,changes,early_inventory=False):
        r=self.frame()
        for i,v in changes.items():r[i]=v;self.u.reg_write(REGS[i],v)
        start=self.base+M['sites'][index]['va']
        end=self.base+(0x2c56120 if early_inventory else M['sites'][index]['va']+4)
        self.u.emu_start(start,end,count=20000)
        assert self.u.reg_read(reg.UC_ARM64_REG_PC)==end,'Hook did not return to expected instruction'
        after=[self.u.reg_read(k) for k in REGS]
        assert self.u.reg_read(reg.UC_ARM64_REG_SP)==self.stack,'Native SP damaged'
        assert self.u.reg_read(reg.UC_ARM64_REG_NZCV)==0xa0000000,'NZCV damaged'
        for i in range(32):assert self.u.reg_read(getattr(reg,'UC_ARM64_REG_Q'+str(i)))==(1<<120)+i,'SIMD damaged'
        return r,after
    def reason(self,site):return self.read(self.control+160+site*4)

class HookTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.machines=[Machine(0),Machine(0x7000000000)]
    def test_gold_each_site_owner_aslr_registers(self):
        regs=[(15,17),(16,17),(14,15),(16,17),(14,13),(10,9),(16,17)]
        for m in self.machines:
            for site,(ptr,val) in enumerate(regs):
                for owner,enabled,expected in [(3,True,1000),(2,True,900),(3,False,900)]:
                    with self.subTest(base=m.base,site=site,owner=owner,enabled=enabled):
                        m.reset();m.write(m.control,(1<<15) if enabled else 0)
                        address=GUEST|(STOCK+owner*STRIDE+15*4);m.write(address,1000)
                        before,after=m.run_site(site,{ptr:address,val:900})
                        self.assertEqual(m.read(address),expected)
                        before[val]=expected;self.assertEqual(before,after)
    def test_gold_income_and_identity_fail_closed(self):
        for m in self.machines:
            for kind in ['income','mode0','multiplayer','badslot','wrongid','duplicate','AI','other_game','badpointer']:
                with self.subTest(base=m.base,kind=kind):
                    m.reset();m.write(m.control,1<<15);address=GUEST|(STOCK+3*STRIDE+60)
                    m.write(address,1000);value=1100 if kind=='income' else 900
                    if kind=='mode0':m.guest(0x248ca00,0)
                    if kind=='multiplayer':m.guest(0x248ca00,2)
                    if kind=='badslot':m.guest(0x25f8748,9)
                    if kind=='wrongid':m.guest(0x248ca90+12,8)
                    if kind=='duplicate':m.guest(0x248ca90+4,1)
                    if kind=='AI':m.guest(0x248cafc+12,2)
                    if kind=='other_game':m.guest(0x2bb8ee8,6)
                    if kind=='badpointer':address+=4;m.write(address,1000)
                    before,after=m.run_site(0,{15:address,17:value})
                    self.assertEqual(m.read(address),value);self.assertEqual(before,after)
                    self.assertNotEqual(m.reason(0),0)
    def test_inventory_dispatch_sources_flags_stock(self):
        for m in self.machines:
            for item,caller,owner,qty,flag,stock,expected in [
                (2,0x2c5ae80,3,5,0,8,True),(4,0x2c5b000,3,1,0,8,True),
                (6,0x2c5b12c,3,1,0,8,True),(7,0x2c5b1e8,3,1,0,8,True),
                (17,0x2520b70,3,1,0,8,True),(24,0x2520c44,3,1,0,8,True),
                (15,0x12340,3,1,0,8,True),(17,0x2520b70,2,1,0,8,False),
                (17,0x12340,3,1,0,8,False),(2,0x2520b70,3,1,0,8,False),
                (2,0x2c5ae80,3,5,0,0,False),(2,0x2c5ae80,3,9,0,8,False),
                (2,0x2c5ae80,3,-1,0,8,False),(2,0x2c5ae80,3,1,1,8,False),
                (10,0x2c5ae80,3,1,0,8,False)]:
                with self.subTest(base=m.base,item=item,owner=owner,qty=qty,caller=caller,flag=flag):
                    m.reset();m.write(m.control,(1<<2)|(1<<4)|(1<<6)|(1<<7)|(1<<15)|(255<<17))
                    esp=0x800000
                    for off,v in [(4,owner),(8,item),(12,qty),(16,flag)]:m.guest(esp+off,v)
                    address=GUEST|(STOCK+owner*STRIDE+item*4);m.write(address,stock)
                    before,after=m.run_site(7,{8:item,16:esp,30:m.base+caller},expected)
                    before[8]=0 if expected else item;self.assertEqual(before,after)
                    self.assertEqual(m.read(address),stock)
                    self.assertEqual(m.reason(7)==0,expected)
    def test_inventory_original_epilogue_virtual_stack(self):
        for m in self.machines:
            with self.subTest(base=m.base):
                m.reset();m.write(m.control,1<<17);m.frame()
                esp=0x800000;caller=m.base+0x2520b70
                saved=[m.u.reg_read(REGS[i]) for i in range(19,30)]
                m.u.reg_write(reg.UC_ARM64_REG_X30,caller)
                for offset,v in [(0,12345),(4,3),(8,17),(12,1),(16,0)]:m.guest(esp+offset,v)
                for off,v in [(0xdc0,11),(0xdc4,22),(0xdc8,33),(0xdcc,44),(0xdd0,esp),(0xdd4,55),(0xdd8,66),(0xddc,77)]:m.write(m.base+0x3baa000+off,v)
                stock=GUEST|(STOCK+3*STRIDE+17*4);m.write(stock,5)
                m.u.emu_start(m.base+0x2c558b4,caller,count=20000)
                self.assertEqual(m.u.reg_read(reg.UC_ARM64_REG_PC),caller)
                self.assertEqual(m.u.reg_read(reg.UC_ARM64_REG_SP),m.stack)
                self.assertEqual([m.u.reg_read(REGS[i]) for i in range(19,30)],saved)
                self.assertEqual(m.read(m.base+0x3baadd0),esp+20)
                self.assertEqual(m.read(stock),5)
                self.assertEqual(m.read(m.base+0x3baadc4),22)
                self.assertEqual(m.read(m.base+0x3baadd8),66)
                self.assertEqual(m.read(m.base+0x3baaddc),77)
    def test_peasant_rate_limits_decimal_and_owner(self):
        for m in self.machines:
            for milli,instant,owner,rate,expected in [(1000,0,3,10,10),(3000,0,3,10,30),(25000,0,3,10,250),(100000,0,3,10,1000),(100000,0,3,100,4000),(1250,0,3,10,12),(3000,1,3,10,4000),(3000,1,2,10,10),(100000,1,3,0,0),(100000,1,3,-10,-10)]:
                with self.subTest(base=m.base,milli=milli,instant=instant,owner=owner,rate=rate):
                    m.reset();m.write(m.control+4,milli);m.write(m.control+8,instant)
                    ptr=0x122bed0+owner*STRIDE;address=GUEST|ptr
                    before,after=m.run_site(8,{9:ptr,11:owner,15:rate&0xffffffff,17:address})
                    self.assertEqual(m.read(address),expected&0xffffffff)
                    before[15]=expected&0xffffffff;self.assertEqual(before,after)
            m.reset();m.write(m.control+4,1250);ptr=0x122bed0+3*STRIDE
            result=[]
            for _ in range(4):m.run_site(8,{9:ptr,11:3,15:1,17:GUEST|ptr});result.append(m.read(GUEST|ptr))
            self.assertEqual(result,[1,1,1,2])

if __name__=='__main__':unittest.main(verbosity=2)
