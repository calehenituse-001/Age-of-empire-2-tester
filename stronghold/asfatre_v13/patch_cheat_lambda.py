#!/usr/bin/env python3
"""Hook the EXISTING Asfatre Cheat button, not a separately bootstrapped overlay.

Expects baksmali-disassembled v1.3 classes.dex. Only replaces the click handler
which originally toggled the built-in CheatMenu expansion.
"""
import pathlib
import re
import sys

METHOD="lambda$new$0$org-stronghold-port-CheatMenu"
HOOK="Lorg/stronghold/port/AdvancedCheatPanel;->openForView(Landroid/view/View;)V"

def patch(root):
    path=pathlib.Path(root)/"org/stronghold/port/CheatMenu.smali"
    src=path.read_text(encoding="utf-8")
    pat=r"(?ms)^\.method[^\n]*\b"+re.escape(METHOD)+r"\(Landroid/view/View;\)V\n.*?^\.end method"
    # Check regex cautiously; method must be private synthetic and contain
    # the original update logic. Do not accept already-patched or other versions.
    matches=list(re.finditer(pat,src))
    if len(matches)!=1: raise ValueError("Exactly one original CheatMenu toggle method required")
    old=matches[0].group(0)
    if HOOK in src: raise ValueError("Already patched")
    if "refresh()V" not in old or "iput-boolean" not in old:
        raise ValueError("Original CheatMenu click implementation differs; refusing patch")
    header=old.splitlines()[0]
    new=header+"\n    .locals 0\n"+\
        "    invoke-static {p1}, "+HOOK+"\n"+\
        "    return-void\n.end method"
    path.write_text(src[:matches[0].start()]+new+src[matches[0].end():],encoding="utf-8")
    print("Patched Asfatre Cheat click to AdvancedCheatPanel.openForView")

if __name__=="__main__":
    if len(sys.argv)!=2: raise SystemExit("Usage: patch_cheat_lambda.py smali-output-directory")
    patch(sys.argv[1])
