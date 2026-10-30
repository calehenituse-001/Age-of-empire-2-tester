"""No proprietary game data required. Fixtures exercise actual simulation classes."""
import os, subprocess, tempfile, shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1]
engine=os.environ.get('GODOT_BIN','godot')
log=[]
(root/'artifacts').mkdir(exist_ok=True)
try:
    with tempfile.TemporaryDirectory(prefix='aoe-validation-') as tmp:
        env=os.environ.copy(); env['AOE_LAUNCHER_ROOT']=tmp+'/runtime'; env['AOE_TEST_MODS']=tmp+'/mods'
        shutil.copytree(root/'samples/ModernEraExpansion',Path(tmp)/'mods/npc.modern-era')
        for args in [['--editor','--import'],['res://tests/launcher_tests.tscn'],['--quit-after','10']]:
            result=subprocess.run([engine,'--headless','--path',str(root/'godot_game'),*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
            log.append(result.stdout)
            if result.returncode or 'SCRIPT ERROR' in result.stdout or '\nERROR:' in result.stdout or 'FAIL ' in result.stdout:
                raise RuntimeError(result.stdout)
            if 'launcher_tests.tscn' in ' '.join(args):
                assert 'LAUNCHER_TESTS' in result.stdout
                print(result.stdout)
            if '--quit-after' in args:
                assert 'BOOT_READY_MISSING_DATA' in result.stdout
        print('Godot parser, simulation tests and missing-data boot passed.')
except subprocess.TimeoutExpired as error:
    log.append(str(error.stdout)); raise
finally:
    (root/'artifacts/godot-validation.log').write_text('\n'.join(log))
