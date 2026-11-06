#!/usr/bin/env python3
"""Check shell syntax without mutating source files."""
from pathlib import Path
import subprocess

for directory in ('scripts','roles','projects'):
    for path in sorted(Path(directory).rglob('*.sh')):
        subprocess.run(['bash','-n',str(path)],check=True)
print('Shell syntax OK')
