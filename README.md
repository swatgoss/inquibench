# InquiBench

Remote hardware topology interrogation (IRQs, DMAs, PCI bus, memory mapping) and automated benchmark suite for retro operating systems (**MS-DOS 6.22 / FreeDOS 1.4 / DOS 7.1 / Windows 98**) driven by an Artificial Intelligence agent (Gemini) through an RS-232 serial link (UART 16550A).

> *"NOBODY expects the Silicon Inquisition!*  
> *Our chief weapons are:*  
> *- IRQ surprise!*  
> *- Ruthless DMA interrogation!*  
> *- Fear of PCI bus conflicts!*  
> *- And an almost fanatical devotion to synthetic benchmarks!"*

> [!IMPORTANT]
> **Development Status Notice:** This software has been **developed and tested strictly within the 86Box virtual machine environment**. Physical hardware support (e.g. on real retro PCs such as the HP t5720) is an intended future target (Phase 2) and has **NOT yet been tested or verified on physical hardware**. Do not assume it will work out-of-the-box on real machines without upcoming bench validation.

```
┌────────────────────────────────────────────────────────┐
│  HOST (AI Agent)                                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │ AI Agent (Gemini - Tool Calling & Automation)    │  │
│  └──────────────────────┬───────────────────────────┘  │
│                         ▼                              │
│  ┌──────────────────────────────────────────────────┐  │
│  │ InquiBench Host Bridge (host/host_bridge.py)     │  │
│  │ - Windows Named Pipe & Physical COM (pyserial)   │  │
│  │ - Binary packet framing (0x55 0xAA), ACK/NAK     │  │
│  └──────────────────────┬───────────────────────────┘  │
└─────────────────────────┼──────────────────────────────┘
                          │
         SERIAL LINK (RS-232 / UART 16550A @ 115200 bps, 8N1)
         - Phase 1 (Virtual)  : Windows Named Pipe [TESTED & VERIFIED]
         - Phase 2 (Physical) : Serial COM / Null-Modem [FUTURE / UNTESTED]
                          │
┌─────────────────────────┼──────────────────────────────┐
│  RETRO GUEST (MS-DOS 6.22 / FreeDOS / Win98)           │
│  ┌──────────────────────▼───────────────────────────┐  │
│  │ INQUIBEN.COM (Native 16-bit x86 Assembly, 1.1 KB)│  │
│  │ - UART 16550A driver COM1 (0x3F8, IRQ 4)         │  │
│  │ - Remote DOS command execution (EXEC COMMAND.COM)│  │
│  │ - Direct text VRAM screen dump (0xB800)          │  │
│  │ - BIOS keyboard injection (INT 16h / Buffer 0x40)│  │
│  │ - Bi-directional file transfer                   │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

---

## Features

- **Hardware Topology & Bus Auditing:** Remotely interrogates IRQ routing, DMA channels, PCI bus configuration, and memory mapping to accurately catalog vintage silicon.
- **Automated Benchmarking & Torture Testing:** Unattended execution of synthetic benchmarks, calculation stress-tests, and memory bandwidth measurement.
- **Broad Retro OS Compatibility:** 100% standard BIOS and DOS interrupt calls (`INT 10h`, `INT 16h`, `INT 21h`), targeting **MS-DOS 6.22**, **FreeDOS 1.4**, **PC-DOS**, **DR-DOS**, and **DOS 7.1 / Windows 98**.
- **High-speed 115,200 bps (8N1):** Leverages 16550A hardware FIFOs for fast, reliable data transmission.
- **Ultra-low memory footprint:** The guest daemon binary (`INQUIBEN.COM`) is only **1.1 KB**, leaving over 520 KB of conventional DOS memory free for child processes and heavy benchmarks.
- **Remote Command Execution:** Seamlessly executes internal and external DOS commands (`DIR`, `MEM`, `CHKDSK`, hardware diagnostic tools, batch scripts) with automatic stdout capture and streaming.
- **AI Vision via VRAM Screen Dump:** Direct readout of 4,000 bytes from text video memory (`0xB800:0000`), allowing the AI agent to "see" the exact DOS screen without console redirection.
- **Keyboard Injection:** Injects keystrokes directly into the BIOS circular keyboard buffer (`0x0040:0x001A`) or via `INT 16h`.
- **Bi-directional File Transfer:** Uploads and downloads benchmark tools and logs directly over the serial line without swapping disks.
- **Portability-Oriented Architecture:** Host bridge is structured to support both virtual named pipes and standard COM ports, designed to facilitate future bench testing on real retro hardware.

---

## Repository Structure

```text
├── guest/                     # Guest retro software (DOS / FreeDOS)
│   ├── inquiben.asm           # Source code in 16-bit x86 assembly
│   └── inquiben.com           # Standalone 8.3 DOS binary (1.1 KB)
├── host/                      # Host tools & communication bridge
│   ├── inquibench.py          # Main InquiBench CLI tool
│   ├── host_bridge.py         # Serial communication bridge (Pipe / COM)
│   └── test_agent.py          # End-to-end automated test suite
├── tools/                     # Offline utilities
│   └── fat16.py               # Direct FAT16 raw disk image injector/reader
├── DOS-Testbed/                # 86Box VM template configuration
│   └── 86box.cfg              # Working 86Box v6.0 machine configuration
├── HARDWARE.md                # Detailed hardware specifications (Host, 86Box, HP t5720)
└── README.md                  # Project overview and documentation
```

---

## Protocol Specification

All packets exchanged follow this binary structure:

| Field | Size | Description |
|---|---|---|
| **SYNC** | 2 bytes | `0x55 0xAA` (Packet preamble sync marker) |
| **CMD** | 1 byte | Command or acknowledgement identifier |
| **LEN** | 2 bytes | Payload length in bytes (*Little-Endian*) |
| **PAYLOAD** | N bytes | Command-specific data |

### Commands & Acknowledgements:
- `0x01` : **PING** -> Response `0x81` (PONG with system status string)
- `0x02` : **EXEC** -> Payload: DOS command string (e.g. `DIR C:`). Response `0x82` with captured stdout
- `0x03` : **READ_SCREEN** -> Response `0x83` containing 4,000 bytes of text VRAM (`0xB800`)
- `0x04` : **SEND_KEY** -> Payload: `[ASCII, Scancode]`, injected into BIOS buffer
- `0x05` : **PUT_FILE** -> Payload: `filename\0` + binary file content
- `0xFF` : **QUIT** -> Gracefully terminates the daemon and returns to DOS prompt

---

## Quickstart Guide

### Prerequisites & Required Downloads

To run the virtual testbed, download the following components:

| Component | Description | Official Link |
|---|---|---|
| **86Box Emulator** | Cycle-accurate PC emulator (v6.0+ recommended) | [86box.net](https://86box.net/) · [GitHub Releases](https://github.com/86Box/86Box/releases) |
| **86Box ROMs Set** | BIOS ROMs for motherboards, video cards, sound cards | [86Box/roms Releases](https://github.com/86Box/roms/releases) *(extract into a `roms/` subfolder)* |
| **86Box Manager** *(Optional)* | Graphical VM manager to configure and launch VMs | [86BoxManager Releases](https://github.com/86Box/86BoxManager/releases) |
| **FreeDOS 1.4** | Open-source DOS installation images (CD-ROM / Floppy) | [freedos.org/download](https://www.freedos.org/download/) |
| **NASM** *(Optional)* | Netwide Assembler (only needed to recompile the 16-bit asm daemon) | [nasm.us](https://www.nasm.us/) |
| **Python 3.10+** | Host runtime for the InquiBench bridge CLI | [python.org](https://www.python.org/) |

---

### 1. Host Side Setup

Install required Python dependencies (`pyserial`):
```powershell
python -m pip install pyserial
```

Run automated end-to-end tests (PING, VER, DIR, READ_SCREEN):
```powershell
python host/test_agent.py
```

Launch the interactive remote DOS shell:
```powershell
python host/inquibench.py shell
```

Connect via physical COM port (*experimental / untested on real hardware*):
```powershell
python host/inquibench.py --endpoint COM3 shell
```

### 2. Guest Side (DOS / FreeDOS)

Launch the daemon from the `D:` drive:
```text
D:\INQUIBEN
```
*(Press `ESC` on the retro machine at any time to exit the daemon and return to the DOS prompt)*.

To recompile the DOS binary (using NASM):
```powershell
nasm -f bin guest/inquiben.asm -o guest/inquiben.com
```

---

## Test Virtual Machine Setup (DOS-Testbed)

The reference virtual test environment is configured under [86Box v6.0+](https://github.com/86Box/86Box/releases) (using the official [86Box ROMs](https://github.com/86Box/roms/releases) set) as follows:

- **Machine:** [Socket 7] ASUS P/I-P55T2P4 (Intel 430HX chipset)
- **Processor:** Intel Pentium 133 MHz (P54C) with Dynarec enabled
- **Memory:** 16 MB RAM (16,384 KB)
- **Video:** [PCI] S3 Trio64
- **Serial (COM1):** UART 16550A (`0x3F8`, `IRQ 4`) mapped to Named Pipe `\\.\pipe\86box_serial` (Server mode)

### Storage & Drive Architecture

The test virtual machine strictly separates operating system files from data and working storage:

| Drive | Type | Capacity / Interface | Format | Role & Usage |
|---|---|---|---|---|
| **`C:`** | **OS Disk** | 528 MB (IDE Primary Master 0:0) | FAT16 | **Operating System:** Hosts MS-DOS 6.22 (or FreeDOS 1.4) system files, `COMMAND.COM`, `HIMEM.SYS`, and `SMARTDRV.EXE`. Protected/read-only system volume. |
| **`D:`** | **DATA Disk** | 440 MB (IDE Primary Slave 0:1) | FAT16 | **Working & Agent Data:** Dedicated disk for the agent binaries (`INQUIBEN.COM`), temporary execution batch files (`RUN.BAT`), command outputs, benchmark suites, and user tools. |
| **`E:`** | **CD-ROM** | ATAPI 72x (IDE Secondary Master 1:0) | ISO 9660 | **Optical Drive:** Dedicated to mounting ISO images for drivers, software packages, and future OS upgrades (e.g. FreeDOS, Windows 98). |
| **`A:`** | **Floppy** | 3.5" 1.44 MB | FAT12 | Standard floppy drive for OS installation and recovery media. |

> **Note on Drive Separation:**
> To ensure reliability and fast recovery, the agent **never modifies Drive `C:`**. All automated script executions, file transfers, and runtime artifacts are directed exclusively to Drive `D:`.


---

## Development Status & Target Hardware

Refer to [HARDWARE.md](HARDWARE.md) for detailed environment and technical specifications:
- **Verified Virtual Environment (Current Phase):** 86Box v6.0 ([Socket 7] ASUS P/I-P55T2P4 motherboard, Intel Pentium 133 MHz, UART 16550A). **This is the only environment currently tested and validated.**
- **Planned Physical Target (Phase 2 - Untested):** HP t5720 Thin Client (AMD Geode NX 1500, native DB9M COM1 port) via FTDI USB-to-RS232 adapter and Null-Modem cable. *Operation on physical hardware is not yet tested and is planned for a later phase.*
