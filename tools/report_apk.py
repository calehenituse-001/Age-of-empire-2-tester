"""Inspect real APK, rather than reporting a size estimate or an unbuilt project."""
from pathlib import Path
import hashlib,json,os,subprocess,sys,zipfile
apk=Path(sys.argv[1]).resolve()
sdk=Path(os.environ['ANDROID_HOME']);build=sdk/'build-tools/36.0.0'
def run(tool,*args):return subprocess.check_output([str(build/tool),*args],text=True,stderr=subprocess.STDOUT)
signature=run('apksigner','verify','--verbose',str(apk))
badging=run('aapt','dump','badging',str(apk))
permissions=run('aapt','dump','permissions',str(apk))
assert "package: name='id.npc.aoe2launcher'" in badging
assert "launchable-activity: name='id.npc.aoe2launcher.LauncherActivity'" in badging
for permission in ['MANAGE_EXTERNAL_STORAGE','READ_EXTERNAL_STORAGE','WRITE_EXTERNAL_STORAGE','SYSTEM_ALERT_WINDOW','BIND_ACCESSIBILITY_SERVICE']:
    assert permission not in permissions,permission
with zipfile.ZipFile(apk) as z:
    names=z.namelist(); assert 'assets/game.pck' in names
    abis=sorted({n.split('/')[1] for n in names if n.startswith('lib/') and n.endswith('.so')})
    assert abis==['arm64-v8a'],abis
    assert not any(n.lower().endswith(('.drs','.dat','.dll')) for n in names)
size=apk.stat().st_size
report=dict(apk=apk.name,bytes=size,decimalMB=round(size/1e6,2),sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),signed=True,abis=abis,minSdk=26,targetSdk=35,gameDataBundled=False,under30MB=size<30_000_000,physicalXiaomiValidation='pending; own HD game files required',badging=badging,permissions=permissions,signature=signature)
out=Path('artifacts');out.mkdir(exist_ok=True);(out/'build-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['badging','signature','permissions']},indent=2))
