"""
lspci.py - Linux-compatible lspci Parser and Tree Formatter for InquiBench
Parses raw PCI scan output from the DOS guest and formats as standard lspci output,
including tree view ('lspci -t', 'lspci -tv', 'lspci -tvnn', 'lspci -nn', 'lspci -v').
"""

import re
from typing import List, Dict, Optional

# Standard PCI Vendor Database (Common Retro / 86Box hardware)
PCI_VENDORS = {
    '8086': 'Intel Corporation',
    '5333': 'S3 Graphics Ltd.',
    '1002': 'Advanced Micro Devices, Inc. [AMD/ATI]',
    '1013': 'Cirrus Logic',
    '1022': 'Advanced Micro Devices, Inc. [AMD]',
    '10ec': 'Realtek Semiconductor Co., Ltd.',
    '1274': 'Ensoniq',
    '1106': 'VIA Technologies, Inc.',
    '1039': 'Silicon Integrated Systems [SiS]',
    '10de': 'NVIDIA Corporation',
    '121a': '3Dfx Interactive, Inc.',
    '104c': 'Texas Instruments',
    '1000': 'LSI Logic / Symbios Logic',
    '9004': 'Adaptec',
    '1011': 'Digital Equipment Corporation',
    '105a': 'Promise Technology, Inc.',
    '104b': 'BusLogic',
    '1111': 'Santa Cruz Operation',
    '1234': 'Technical Corp.',
}

# Standard PCI Device Database
PCI_DEVICES = {
    # Intel Chipsets & Components
    ('8086', '1250'): '82439HX [TXC] (430HX Triton II System Controller)',
    ('8086', '7000'): '82371SB PIIX3 PCI-to-ISA Bridge [Triton II]',
    ('8086', '7010'): '82371SB PIIX3 Bus-Master IDE Controller',
    ('8086', '7020'): '82371SB PIIX3 USB Controller',
    ('8086', '1237'): '82441FX PMC [Natoma] (440FX System Controller)',
    ('8086', '7099'): '82438FX [Natoma] Data Path (DPX)',
    ('8086', '7100'): '82439TX System Controller (MTXC)',
    ('8086', '7110'): '82371AB/EB/MB PIIX4 ISA Bridge',
    ('8086', '7111'): '82371AB/EB/MB PIIX4 IDE Controller',
    ('8086', '7112'): '82371AB/EB/MB PIIX4 USB Controller',
    ('8086', '7113'): '82371AB/EB/MB PIIX4 ACPI / Power Management',
    ('8086', '7190'): '440BX/ZX/DX - 82443BX/ZX/DX Host bridge',
    ('8086', '7191'): '440BX/ZX/DX - 82443BX/ZX/DX AGP bridge',
    ('8086', '7192'): '440BX/ZX/DX - 82443BX/ZX/DX Host bridge (no AGP)',
    ('8086', '100e'): '82540EM Gigabit Ethernet Controller',
    ('8086', '1229'): '82557/8/9/0/1 Ethernet Controller [EtherExpress PRO/100]',
    
    # S3 Graphics
    ('5333', '8811'): 'Trio64 / Trio32 (86C764/765)',
    ('5333', '8812'): 'Aurora64V+ (86CM65)',
    ('5333', '8814'): 'Trio64V+ (86C765)',
    ('5333', '8901'): 'ViRGE (86C325)',
    ('5333', '8902'): 'ViRGE/DX (86C375)',
    ('5333', '8880'): 'Vision 868 (86C868)',
    ('5333', '8890'): 'Vision 968 (86C968)',
    
    # ATI / AMD
    ('1002', '4758'): 'Mach64 GX',
    ('1002', '4752'): 'Mach64 CT',
    ('1002', '4754'): 'Mach64 VT',
    ('1002', '4756'): 'Mach64 VT4',
    ('1002', '4742'): 'Rage XL AGP 2X',
    ('1002', '4749'): 'Rage Pro AGP 2X',
    
    # Cirrus Logic
    ('1013', '00a0'): 'GD 5430',
    ('1013', '00a8'): 'GD 5434-4',
    ('1013', '00ac'): 'GD 5436',
    ('1013', '00b8'): 'GD 5446',
    
    # Network / Audio / Storage
    ('1022', '2000'): '79c970 [PCnet32 LANCE] Ethernet',
    ('10ec', '8029'): 'RTL-8029(AS) Ethernet Controller',
    ('10ec', '8139'): 'RTL-8139/8139C/8139C+ Ethernet Controller',
    ('1274', '1371'): 'ES1371 / Creative Labs CT5880 AudioPCI',
    ('1274', '5000'): 'ES1370 [AudioPCI]',
    ('121a', '0001'): 'Voodoo',
    ('121a', '0002'): 'Voodoo 2',
    ('121a', '0003'): 'Voodoo Banshee',
    ('121a', '0005'): 'Voodoo 3',
    ('1000', '0001'): '53C810 32-bit PCI Fast SCSI Controller',
    ('9004', '7078'): 'AHA-2940/2940W / AIC-7870 SCSI Controller',
}

# Standard PCI Class Codes (Base + Subclass)
PCI_CLASSES = {
    '0001': 'VGA compatible controller',
    '0100': 'SCSI storage controller',
    '0101': 'IDE interface',
    '0102': 'Floppy disk controller',
    '0104': 'RAID bus controller',
    '0106': 'SATA controller',
    '0108': 'Non-Volatile memory controller',
    '0200': 'Ethernet controller',
    '0280': 'Network controller',
    '0300': 'VGA compatible controller',
    '0301': 'XGA compatible controller',
    '0302': '3D controller',
    '0380': 'Display controller',
    '0400': 'Multimedia video controller',
    '0401': 'Multimedia audio controller',
    '0403': 'Audio device',
    '0500': 'RAM memory',
    '0600': 'Host bridge',
    '0601': 'ISA bridge',
    '0602': 'EISA bridge',
    '0604': 'PCI bridge',
    '0605': 'PCMCIA bridge',
    '0607': 'CardBus bridge',
    '0700': 'Serial controller',
    '0701': 'Parallel controller',
    '0800': 'PIC',
    '0801': 'DMA controller',
    '0802': 'Timer',
    '0803': 'RTC',
    '0c00': 'FireWire (IEEE 1394)',
    '0c03': 'USB controller',
    '0c05': 'SMBus',
}

# --- Dynamic pci.ids database loader ---
_LOADED_PCI_IDS = False
_DYNAMIC_VENDORS = {}
_DYNAMIC_DEVICES = {}
_DYNAMIC_CLASSES = {}

def load_pci_ids_file(filepath: Optional[str] = None):
    """Loads pci.ids if present to expand coverage to 2,500+ vendors and 20,000+ devices."""
    global _LOADED_PCI_IDS, _DYNAMIC_VENDORS, _DYNAMIC_DEVICES, _DYNAMIC_CLASSES
    if _LOADED_PCI_IDS and filepath is None:
        return

    import os
    candidates = []
    if filepath:
        candidates.append(filepath)
    else:
        base_dir = os.path.dirname(os.path.abspath(__file__))
        candidates.append(os.path.join(base_dir, 'pci.ids'))
        candidates.append(os.path.join(base_dir, '..', 'pci.ids'))
        candidates.append('pci.ids')
        candidates.append(os.path.join('host', 'pci.ids'))

    target_file = None
    for cand in candidates:
        if os.path.isfile(cand):
            target_file = cand
            break

    if not target_file:
        return

    current_vendor = None
    current_class = None

    try:
        with open(target_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if not line or line.startswith('#'):
                    continue
                if line.startswith('\t\t'):
                    continue
                elif line.startswith('\t'):
                    if current_vendor and len(line) >= 6:
                        dev_id = line[1:5].strip().lower()
                        dev_name = line[5:].strip()
                        _DYNAMIC_DEVICES[(current_vendor, dev_id)] = dev_name
                    elif current_class and len(line) >= 4:
                        sub_id = line[1:3].strip().lower()
                        sub_name = line[3:].strip()
                        _DYNAMIC_CLASSES[current_class + sub_id] = sub_name
                elif line.startswith('C '):
                    current_vendor = None
                    current_class = line[2:4].strip().lower()
                elif line[0] in '0123456789abcdefABCDEF' and len(line) >= 6 and line[4] == ' ':
                    current_vendor = line[:4].strip().lower()
                    _DYNAMIC_VENDORS[current_vendor] = line[4:].strip()
                    current_class = None
        _LOADED_PCI_IDS = True
    except Exception:
        pass


def update_pci_ids(dest_path: Optional[str] = None) -> str:
    """Downloads the latest official pci.ids database."""
    import os
    import urllib.request
    url = "https://raw.githubusercontent.com/pciutils/pciutils/master/pci.ids"
    if not dest_path:
        base_dir = os.path.dirname(os.path.abspath(__file__))
        dest_path = os.path.join(base_dir, 'pci.ids')
    urllib.request.urlretrieve(url, dest_path)
    # Reload database
    global _LOADED_PCI_IDS
    _LOADED_PCI_IDS = False
    load_pci_ids_file(dest_path)
    return dest_path


class PCIDevice:
    def __init__(self, bus: int, dev: int, func: int, vendor: str, device: str,
                 class_code: str, rev: str, desc: str = "", irq: Optional[int] = None):
        self.bus = bus
        self.dev = dev
        self.func = func
        self.vendor = vendor.lower()
        self.device = device.lower()
        self.class_code = class_code.lower()
        self.rev = rev.lower()
        self.desc_raw = desc
        self.irq = irq
        self.bars = []  # List of dict: {'idx': int, 'type': 'io'|'mem', 'addr': str, 'flags': str}

    @property
    def slot_str(self) -> str:
        return f"{self.dev:02x}.{self.func}"

    @property
    def bdf_str(self) -> str:
        return f"{self.bus:02x}:{self.dev:02x}.{self.func}"

    @property
    def class_name(self) -> str:
        load_pci_ids_file()
        if self.class_code in _DYNAMIC_CLASSES:
            return _DYNAMIC_CLASSES[self.class_code]
        return PCI_CLASSES.get(self.class_code, 'Unknown device class')

    @property
    def vendor_name(self) -> str:
        load_pci_ids_file()
        if self.vendor in _DYNAMIC_VENDORS:
            return _DYNAMIC_VENDORS[self.vendor]
        return PCI_VENDORS.get(self.vendor, f"Vendor {self.vendor}")

    @property
    def device_name(self) -> str:
        load_pci_ids_file()
        if (self.vendor, self.device) in _DYNAMIC_DEVICES:
            return _DYNAMIC_DEVICES[(self.vendor, self.device)]
        dev_entry = PCI_DEVICES.get((self.vendor, self.device))
        if dev_entry:
            return dev_entry
        if self.desc_raw:
            # Strip prefix vendor if already present
            d = self.desc_raw
            if d.lower().startswith('intel '):
                d = d[6:]
            return d
        return f"Device {self.device}"


def parse_pciscan_output(text: str) -> List[PCIDevice]:
    """Parses output lines from D:\\PCISCAN.COM."""
    devices: List[PCIDevice] = []
    current_dev: Optional[PCIDevice] = None

    dev_pat = re.compile(
        r'\[([0-9a-fA-F]{2}):([0-9a-fA-F]{2})\.([0-7])\]\s+'
        r'([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\s+'
        r'\[([0-9a-fA-F]{4})\]\s+'
        r'\(rev\s+([0-9a-fA-F]{2})\)'
        r'(?:\s*-\s*(.*?))?'
        r'(?:\s*\[IRQ:\s*(\d+)\])?$'
    )
    bar_pat = re.compile(r'BAR(\d):\s*([0-9a-fA-F]{8})\s*\((.*?)\)')

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        m_dev = dev_pat.match(line)
        if m_dev:
            bus_hex, dev_hex, func_str, ven, dev, cls, rev, desc, irq_str = m_dev.groups()
            irq_val = int(irq_str) if irq_str else None
            current_dev = PCIDevice(
                bus=int(bus_hex, 16),
                dev=int(dev_hex, 16),
                func=int(func_str, 10),
                vendor=ven,
                device=dev,
                class_code=cls,
                rev=rev,
                desc=desc or "",
                irq=irq_val
            )
            devices.append(current_dev)
            continue

        m_bar = bar_pat.search(line)
        if m_bar and current_dev:
            bar_idx, bar_val, bar_desc = m_bar.groups()
            raw_int = int(bar_val, 16)
            if raw_int & 1:  # I/O port
                io_addr = f"{raw_int & ~3:04x}"
                current_dev.bars.append({
                    'idx': int(bar_idx),
                    'type': 'io',
                    'addr': io_addr,
                    'flags': ''
                })
            else:  # Memory mapped
                mem_addr = f"{raw_int & ~0xF:08x}"
                current_dev.bars.append({
                    'idx': int(bar_idx),
                    'type': 'mem',
                    'addr': mem_addr,
                    'flags': '32-bit, non-prefetchable'
                })

    return devices


def format_lspci(devices: List[PCIDevice], tree: bool = False, verbose: int = 0, numeric: int = 0) -> str:
    """
    Formats the list of PCI devices matching standard Linux lspci output.
    
    Arguments:
        tree: If True, renders as a hierarchical bus tree (-t).
        verbose: Verbosity level (0=standard, 1=-v, 2=-vv).
        numeric: 0=names, 1=numeric only (-n), 2=numeric + names (-nn).
    """
    if not devices:
        return "No PCI devices detected."

    if not tree:
        # Standard flat lspci list
        lines = []
        for d in devices:
            # Build device description according to numeric mode
            if numeric == 1:
                # -n: 00:00.0 Class 0600: 8086:1250 (rev 00)
                main_line = f"{d.bdf_str} Class {d.class_code}: {d.vendor}:{d.device} (rev {d.rev})"
            elif numeric >= 2:
                # -nn: 00:00.0 Host bridge [0600]: Intel Corporation 82439HX [TXC] [8086:1250] (rev 00)
                main_line = (f"{d.bdf_str} {d.class_name} [{d.class_code}]: "
                             f"{d.vendor_name} {d.device_name} [{d.vendor}:{d.device}] (rev {d.rev})")
            else:
                # standard: 00:00.0 Host bridge: Intel Corporation 82439HX [TXC] (rev 00)
                main_line = (f"{d.bdf_str} {d.class_name}: "
                             f"{d.vendor_name} {d.device_name} (rev {d.rev})")
            lines.append(main_line)

            if verbose > 0:
                lines.append(f"\tSubsystem: {d.vendor_name} {d.device_name}")
                lines.append("\tFlags: bus master, medium devsel")
                if d.irq is not None and d.irq > 0:
                    lines.append(f"\tInterrupt: pin A routed to IRQ {d.irq}")
                for b in d.bars:
                    if b['type'] == 'io':
                        lines.append(f"\tRegion {b['idx']}: I/O ports at {b['addr']}")
                    else:
                        flags_str = f" ({b['flags']})" if b.get('flags') else ""
                        lines.append(f"\tRegion {b['idx']}: Memory at {b['addr']}{flags_str}")
                lines.append("")

        return "\n".join(lines).strip()

    # --- Tree rendering (lspci -t, lspci -tv, lspci -tvnn) ---
    lines = []
    buses = sorted(list(set(d.bus for d in devices)))
    
    for bus_idx in buses:
        bus_devs = [d for d in devices if d.bus == bus_idx]
        bus_header = f"-[{bus_idx:04x}:{bus_idx:02x}]-"
        indent = " " * len(bus_header)

        for i, d in enumerate(bus_devs):
            is_last = (i == len(bus_devs) - 1)
            branch = "\\-" if is_last else "+-"
            prefix = (bus_header + branch) if i == 0 else (indent + branch)
            
            # Format node text based on flags
            if verbose == 0 and numeric == 0:
                # lspci -t: just slot names
                node_text = f"{d.slot_str}"
            elif verbose == 0 and numeric == 1:
                # lspci -tn: slot + numeric ID
                node_text = f"{d.slot_str}  {d.vendor}:{d.device}"
            elif numeric >= 2 or (verbose > 0 and numeric == 0):
                # lspci -tvnn or lspci -tv: full class [class] + vendor device [vendor:device] (rev xx)
                if numeric >= 2:
                    node_text = (f"{d.slot_str}  {d.class_name} [{d.class_code}]: "
                                 f"{d.vendor_name} {d.device_name} [{d.vendor}:{d.device}] (rev {d.rev})")
                else:
                    node_text = (f"{d.slot_str}  {d.class_name}: "
                                 f"{d.vendor_name} {d.device_name} (rev {d.rev})")
            elif numeric == 1 and verbose > 0:
                node_text = (f"{d.slot_str}  [{d.class_code}]: "
                             f"[{d.vendor}:{d.device}] (rev {d.rev})")
            else:
                node_text = f"{d.slot_str}  {d.vendor_name} {d.device_name}"

            lines.append(f"{prefix}{node_text}")

            # Verbose tree details (-v / -vv)
            if verbose > 0:
                sub_indent = indent + ("        " if is_last else "|       ")
                if d.irq is not None and d.irq > 0:
                    lines.append(f"{sub_indent}[IRQ {d.irq}]")
                for b in d.bars:
                    if b['type'] == 'io':
                        lines.append(f"{sub_indent}[BAR{b['idx']}] I/O ports at 0x{b['addr']}")
                    else:
                        flags_str = f" ({b['flags']})" if b.get('flags') else ""
                        lines.append(f"{sub_indent}[BAR{b['idx']}] Memory at 0x{b['addr']}{flags_str}")

    return "\n".join(lines)


if __name__ == '__main__':
    import sys
    import argparse
    parser = argparse.ArgumentParser(description="InquiBench Offline lspci Formatter")
    parser.add_argument('file', nargs='?', help='Input report file from PCISCAN.COM or HWPROBE.COM')
    parser.add_argument('-t', action='store_true', help='Show tree diagram of PCI bus')
    parser.add_argument('-v', action='count', default=0, help='Be verbose')
    parser.add_argument('-n', action='count', default=0, help='Show numeric IDs (-n) or numeric + names (-nn)')
    parser.add_argument('-tvnn', action='store_true', help='Tree view with verbose details and numeric+name IDs')
    parser.add_argument('--update-ids', action='store_true', help='Download latest official pci.ids database')

    args = parser.parse_args()

    if args.update_ids:
        print("[*] Updating pci.ids database...")
        path = update_pci_ids()
        print(f"[+] Updated: {path}")

    if args.file:
        with open(args.file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        is_tree = args.t or args.tvnn
        verb = max(args.v, 1 if args.tvnn else 0)
        num = max(args.n, 2 if args.tvnn else 0)
        devs = parse_pciscan_output(content)
        print(format_lspci(devs, tree=is_tree, verbose=verb, numeric=num))
    elif not args.update_ids:
        parser.print_help()
