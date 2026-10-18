#!/usr/bin/env python3
"""Founder-authorized Telegram-only handoff, 2026-10-18. Run as svc-hermes.
Back up runtime credentials locally on host before detaching; Discord unaffected.
Restore with --restore. Never prints credential values.
"""
from pathlib import Path
import shutil, sys, os, subprocess
home=Path.home()/'.hermes'
backup=home/'backups/telegram-handoff-2026-10-18'
env=home/'.env'
if '--restore' in sys.argv:
    saved=backup/'telegram.env'
    if not saved.exists(): raise SystemExit('No Telegram backup exists')
    text=env.read_text(); lines=[x for x in text.splitlines() if not x.strip().removeprefix('export ').startswith('TELEGRAM_')]
    env.write_text('\n'.join(lines)+'\n'+saved.read_text()); env.chmod(0o600)
    print('Telegram variables restored; restart gateway to activate.')
else:
    text=env.read_text(); lines=text.splitlines()
    telegram=[x for x in lines if x.strip().removeprefix('export ').startswith('TELEGRAM_')]
    if not telegram: raise SystemExit('Telegram already detached; nothing changed.')
    backup.mkdir(parents=True,exist_ok=True); backup.chmod(0o700)
    if (backup/'telegram.env').exists(): raise SystemExit('Backup already exists; refusing to overwrite.')
    shutil.copy2(env,backup/'original.env')
    (backup/'telegram.env').write_text('\n'.join(telegram)+'\n'); (backup/'telegram.env').chmod(0o600)
    # Request quiet shutdown so Hermes does not announce a shutdown to Telegram.
    sys.path.insert(0,str(home/'hermes-agent'))
    from gateway.drain_control import write_drain_marker
    import inspect
    print('Drain marker API:',str(inspect.signature(write_drain_marker)))
    env.write_text('\n'.join(x for x in lines if x not in telegram)+'\n'); env.chmod(0o600)
    print('Telegram variables backed up and removed; restart gateway to activate.')
