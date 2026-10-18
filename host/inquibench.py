#!/usr/bin/env python3
"""
InquiBench - Retro Hardware Interrogator & Benchmark Suite
"NOBODY expects the Silicon Inquisition!"
"""

import sys
from host_bridge import DOSSerialBridge, main as bridge_main

BANNER = r"""
  ___                   _ ____                  _     
 |_ _|_ __   __ _ _   _(_) __ )  ___ _ __   ___| |__  
  | || '_ \ / _` | | | | |  _ \ / _ \ '_ \ / __| '_ \ 
  | || | | | (_| | |_| | | |_) |  __/ | | | (__| | | |
 |___|_| |_|\__, |\__,_|_|____/ \___|_| |_|\___|_| |_|
               |_|  Nobody expects the Silicon Inquisition!
"""

if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    print(BANNER)
    bridge_main()
