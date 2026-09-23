#!/usr/bin/env python3
import os
import subprocess
import sys


script = os.path.realpath(os.path.join(
    os.path.dirname(__file__), "..", "plugins", "lt", "scripts", "reconcile-hosts.py"
))
raise SystemExit(subprocess.call([sys.executable, script] + sys.argv[1:]))
