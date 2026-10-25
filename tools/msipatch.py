import olefile, struct, sys
SRC, DST = sys.argv[1], sys.argv[2]
def _c(x):
    if x<10: return chr(48+x)
    if x<36: return chr(55+x)
    if x<62: return chr(61+x)
    return "._"[x-62]
def dec(n):
    out=""
    for ch in n:
        c=ord(ch)
        if 0x3800<=c<0x4800: c-=0x3800; out+=_c(c&0x3f)+_c(c>>6)
        elif 0x4800<=c<0x4840: out+=_c(c-0x4800)
        elif c==0x4840: out+="!"
        else: out+=ch
    return out
o=olefile.OleFileIO(SRC)
names={dec(e[0]):e for e in o.listdir(streams=True) if len(e)==1}
pool=o.openstream(names["!_StringPool"]).read(); data=o.openstream(names["!_StringData"]).read()
cp,flags=struct.unpack_from("<HH",pool,0)
big = bool(flags & 0x8000); refsz = 3 if big else 2
print("codepage",cp,"flags",hex(flags),"string ref size",refsz)
strings=[None]; off=0; i=4
while i<len(pool):
    ln,rc=struct.unpack_from("<HH",pool,i); i+=4
    if ln==0 and rc!=0:  # long string: next pair holds 32-bit length
        ln=struct.unpack_from("<I",pool,i)[0]; i+=4
    strings.append(data[off:off+ln].decode("cp%d"%cp if cp else "utf-8","replace")); off+=ln
print("strings:",len(strings))
sid={s:k for k,s in enumerate(strings) if s is not None}
def rd(buf,pos): return int.from_bytes(buf[pos:pos+refsz],"little")
# columns of InstallExecuteSequence: Action(s72 key), Condition(S255), Sequence(I2)
ies=bytearray(o.openstream(names["!InstallExecuteSequence"]).read())
# column-major: col sizes = refsz, refsz, 2
nrows=len(ies)//(refsz+refsz+2); print("IES rows",nrows, "stream bytes", len(ies))
act_off=0; cond_off=nrows*refsz; seq_off=2*nrows*refsz
rows=[]
for r in range(nrows):
    a=strings[rd(ies,act_off+r*refsz)]; c=rd(ies,cond_off+r*refsz); s=struct.unpack_from("<H",ies,seq_off+2*r)[0]^0x8000
    rows.append((a,strings[c] if c else "",s))
for a,c,s in rows:
    if a in ("CheckWindowsAppSDKRuntime","SetIsWebView2RuntimeRequired","PreventDowngrading"): print("  ",a,"|",c,"|",s)
false_cond = sid["PREVENTDOWNGRADING"]; print("false-condition string id:", false_cond, "(set only when a newer version is installed)")
patched=0
for r in range(nrows):
    if strings[rd(ies,act_off+r*refsz)] in ("CheckWindowsAppSDKRuntime","SetIsWebView2RuntimeRequired"):
        ies[cond_off+r*refsz:cond_off+(r+1)*refsz]=false_cond.to_bytes(refsz,"little"); patched+=1
print("patched rows:",patched)
# write back: same size stream -> olefile write_stream
import shutil; shutil.copyfile(SRC,DST)
w=olefile.OleFileIO(DST, write_mode=True); w.write_stream(names["!InstallExecuteSequence"], bytes(ies)); w.close()
print("wrote",DST)
