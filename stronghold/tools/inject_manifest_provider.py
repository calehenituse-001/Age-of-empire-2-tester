#!/usr/bin/env python3
"""Inject a non-exported ContentProvider into THIS specific APK's binary XML.
No apktool / resource rebuilding. Raises on unexpected layouts. AXML structural test included.
"""
import pathlib,struct,sys
T_STRING=0x03; T_BOOL=0x12; NO=0xffffffff
PROVIDER='org.stronghold.port.mod.ModInitProvider'
AUTH='org.stronghold.port.modinit33'

def chunk(raw,pos):
 t,h,s=struct.unpack_from('<HHI',raw,pos)
 assert h>=8 and s>=h and pos+s<=len(raw),(pos,t,h,s)
 return t,h,s

def parse_pool(raw,pos):
 typ,h,sz=chunk(raw,pos)
 assert typ==1 and h==28
 count,styles,flags,stringsstart,stylesstart=struct.unpack_from('<IIIII',raw,pos+8)
 assert styles==0 and flags==0, 'Only UTF16, no styles supported'
 out=[]
 for i in range(count):
  at=pos+stringsstart+struct.unpack_from('<I',raw,pos+28+i*4)[0]
  n=struct.unpack_from('<H',raw,at)[0]
  assert n<0x7fff
  end=at+2+n*2
  assert raw[end:end+2]==b'\0\0'
  out.append(raw[at+2:end].decode('utf-16-le'))
 return out,sz

def encode_pool(strings):
 offsets=[];buf=bytearray()
 for s in strings:
  enc=s.encode('utf-16-le');n=len(enc)//2
  assert n<0x7fff
  offsets.append(len(buf))
  buf+=struct.pack('<H',n)+enc+b'\0\0'
 while len(buf)%4:buf+=b'\0'
 size=28+4*len(offsets)+len(buf)
 return struct.pack('<HHI5I',1,28,size,len(strings),0,0,28+4*len(offsets),0)+b''.join(struct.pack('<I',x) for x in offsets)+buf

def start_tag(name,attrs,strings):
 i=strings.index(name)
 # ResXMLTree_node header (line, comment), ResXMLTree_attrExt (ns,name,attr_start,attr_size,attr_count,id,class,style)
 ext=struct.pack('<IIHHHHHH',NO,i,20,20,len(attrs),0,0,0)
 a=b''
 for ns,key,raw,dt,val in attrs:
  a+=struct.pack('<IIIHBBI',ns,strings.index(key),raw,8,0,dt,val)
 size=16+len(ext)+len(a)
 return struct.pack('<HHIII',0x102,16,size,0,NO)+ext+a

def end_tag(name,strings):
 return struct.pack('<HHIIII',0x103,16,24,0,NO,NO)+struct.pack('<I',strings.index(name))

def validate(raw):
 assert struct.unpack_from('<HHI',raw,0)==(3,8,len(raw))
 pos=8;depth=0;providers=0
 strings,_=parse_pool(raw,pos)
 while pos<len(raw):
  typ,h,sz=chunk(raw,pos)
  if typ==0x102:
   name=struct.unpack_from('<I',raw,pos+20)[0]
   if strings[name]=='provider':providers+=1
   depth+=1
  elif typ==0x103:depth-=1;assert depth>=0
  pos+=sz
 assert pos==len(raw) and depth==0 and providers>=1
 return True

def insert(raw):
 assert raw[:4]==b'\x03\x00\x08\x00'
 old_strings,poolsize=parse_pool(raw,8)
 assert PROVIDER not in old_strings
 strings=old_strings+['authorities','provider',PROVIDER,AUTH]
 resourcepos=8+poolsize
 typ,h,sz=chunk(raw,resourcepos)
 assert typ==0x180 and h==8
 old_res=[struct.unpack_from('<I',raw,resourcepos+8+4*i)[0] for i in range((sz-8)//4)]
 assert old_res[3]==0x1010003 and old_res[6]==0x1010010
 while len(old_res)<len(strings):old_res.append(0)
 old_res[strings.index('authorities')]=0x01010018
 new_resource=struct.pack('<HHI',0x180,8,8+4*len(old_res))+b''.join(struct.pack('<I',x) for x in old_res)
 new_pool=encode_pool(strings)
 ns=old_strings.index('http://schemas.android.com/apk/res/android')
 provider=start_tag('provider',[
  (ns,'name',strings.index(PROVIDER),T_STRING,strings.index(PROVIDER)),
  (ns,'authorities',strings.index(AUTH),T_STRING,strings.index(AUTH)),
  (ns,'exported',NO,T_BOOL,0),
  (ns,'process',strings.index(':extreme'),T_STRING,strings.index(':extreme'))],strings)+end_tag('provider',strings)
 pos=resourcepos+sz; insertion=None;stack=[]
 while pos<len(raw):
  typ,h,size=chunk(raw,pos)
  if typ==0x102:
   nm=struct.unpack_from('<I',raw,pos+20)[0]
   stack.append(old_strings[nm])
  elif typ==0x103:
   nm=old_strings[struct.unpack_from('<I',raw,pos+20)[0]]
   assert stack[-1]==nm,(stack[-1],nm)
   if nm=='application' and len(stack)==2:
    assert insertion is None
    insertion=pos
   stack.pop()
  pos+=size
 assert insertion is not None,'application tag not found'
 tail=raw[resourcepos+sz:insertion]+provider+raw[insertion:]
 result=bytearray(raw[:8]+new_pool+new_resource+tail)
 struct.pack_into('<I',result,4,len(result))
 validate(result)
 return bytes(result)

if __name__=='__main__':
 inp=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);out.write_bytes(insert(inp.read_bytes()))
 print('Manifest modified and verified',out, out.stat().st_size)
