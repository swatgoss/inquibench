# InquiBench with Antigravity IDE: An AI Copilot for Retro MS-DOS

> **"What if you could pair Gemini with your vintage MS-DOS machine?"**

InquiBench is not just a benchmarking tool—it is a **bridge between modern agentic AI (Google Gemini via Antigravity IDE) and vintage retro hardware (MS-DOS 6.22, FreeDOS 1.4, DOS 7.1 / Windows 98)**.

Whether you are configuring an authentic vintage PC (via physical COM port) or an accurate cycle-exact virtual machine (via 86Box), Antigravity IDE gives Gemini **direct hands on your DOS machine** to create, optimize, benchmark, and maintain retro games and software.

```
┌────────────────────────────────────────────────────────┐
│  MODERN PC: Antigravity IDE + Google Gemini AI         │
│  - Pair-programmer, compiler, code generator           │
│  - Inspects DOS screen, edits batch files, uploads tools│
└──────────────────────────┬─────────────────────────────┘
                           │  Serial Link (115,200 bps)
                           │  Named Pipe (86Box) or RS-232 COM (Real PC)
┌──────────────────────────▼─────────────────────────────┐
│  RETRO MACHINE: MS-DOS 6.22 / FreeDOS / Win98           │
│  - Real Silicon (HP t5720, Socket 7, 486, Pentium)      │
│  - Cycle-exact Emulation (86Box ASUS P55T2P4)           │
│  - INQUIBEN.COM (1.1 KB resident daemon)                │
└────────────────────────────────────────────────────────┘
```

---

## 1. What You Can Do for Retrogaming

### 🎮 Automated Memory Optimization for Picky Games
Games like *Ultima VII*, *Wing Commander II*, or *Falcon 3.0* require over 600–615 KB of conventional memory and will crash with EMS/XMS conflicts.
* **Ask Gemini:** *"Optimize my CONFIG.SYS and AUTOEXEC.BAT to free at least 610 KB of conventional memory while keeping CD-ROM and mouse drivers loaded."*
* **Gemini will:**
  1. Run `MEM /C /P` to inspect current UMB and conventional memory allocations.
  2. Edit `CONFIG.SYS` with optimal `DEVICEHIGH`, `UMB`, and `EMM386.EXE RAM/NOEMS` parameters.
  3. Load drivers (`UIDE.SYS`, `CTMOUSE.EXE`) in high memory.
  4. Verify available memory after reboot.

### 🔊 Sound Card & Hardware Conflict Resolution
* **Ask Gemini:** *"Why is there no digital sound in Doom on this machine? Check IRQ and DMA conflicts."*
* **Gemini will:**
  1. Run `PCISCAN` and `HWPROBE` over serial to map all active IRQs, DMAs, and PCI BARs.
  2. Check `BLASTER` environment variable (`SET BLASTER=A220 I5 D1 H5 P330 T6`).
  3. Detect whether IRQ 5 or IRQ 7 is taken by another PCI/ISA device and reconfigure the sound initialization batch accordingly.

### ⚡ Rapid Retro Development & Prototyping
Want to write a 16-bit DOS game, a demo, a TSR utility, or a trainer?
* Write your code (x86 Assembly, Open Watcom C, Turbo Pascal, QuickBASIC) inside Antigravity IDE.
* **Ask Gemini:** *"Compile this intro screen in NASM, upload it to the DOS machine, run it, and tell me if the text attributes render properly."*
* **Gemini will:**
  1. Compile the code locally or prepare the DOS build batch.
  2. Upload the binary via serial (`inquibench put`).
  3. Execute it inside DOS.
  4. Read the 80x25 text screen directly from VRAM (`0xB800`) to confirm the result.

### 📊 Automated Benchmarking Suites
* **Ask Gemini:** *"Run our benchmark suite: measure the real CPU clock, run 3DBench and Doom timedemo, and log the results."*
* **Gemini will:**
  1. Measure real clock speed via RDTSC + PIT 8254 calibration (`HWPROBE`).
  2. Launch `DOOM -timedemo demo3 -nosound` or `PCPBENCH`.
  3. Capture execution time and compute real-time frames per second.
  4. Save a structured benchmark report on your modern machine.

---

## 2. Getting Started in Antigravity IDE

### Zero-Cost Free Tier Setup
You can use Antigravity IDE with any standard **personal Google account (Free Tier)**:
* **Autocompletion & In-line edits (`Ctrl+I`):** 100% free and unlimited.
* **Collaborative Agent:** Generous weekly quota that resets automatically every 7 days.

### Quick Setup:
1. **Clone & Open:** Open this repository folder in Antigravity IDE (`File -> Open Folder`).
2. **Python Environment:** In the Antigravity IDE terminal:
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install pyserial
   ```
3. **Start 86Box VM (Virtual Lab):**
   ```powershell
   .\86Box.exe --config DOS-Testbed\86box.cfg
   ```
4. **Start the DOS Agent:**
   In the DOS window, type:
   ```text
   D:\INQUIBEN.COM
   ```
5. **Start Collaborating with Gemini!**
   Open the sidebar chat in Antigravity IDE and start prompting.

---

## 3. Example Prompts to Try with Gemini

Here are real workflows you can run right away in the Antigravity IDE chat:

| Goal | What to ask Gemini in Antigravity IDE |
|---|---|
| **Hardware Health Check** | *"Ping the DOS machine and audit its hardware specs (CPU, clock, BIOS, RAM)."* |
| **PCI Topology Inspection** | *"Show me the PCI bus topology of the DOS machine in lspci -tvnn format."* |
| **Inspect DOS Display** | *"What is currently showing on the DOS screen right now?"* |
| **Run DOS Commands** | *"Execute 'DIR D:\' on the DOS machine and tell me how much free disk space is left."* |
| **Deploy a Tool** | *"Upload this custom utility to D:\TEST.COM and run it with /? to show its help."* |
| **Batch Automation** | *"Create a batch file on D:\ that benchmarks the system and writes the output to D:\LOG.TXT."* |

---

## 4. Hardware Connection Modes

* **Mode 1: Virtual Testbed (86Box v6.0+) [Default / Verified]**
  Connects over Windows Named Pipe `\\.\pipe\86box_serial`. Zero physical cables needed, perfect for developing, testing configurations, and validating game setups before deploying to real hardware.
* **Mode 2: Physical Retro PC (HP t5720, Socket 7, 486, Pentium) [Phase 2]**
  Connects over a standard RS-232 serial cable (USB-to-Serial adapter + Null-Modem cable on COM1). Target baudrate: **115,200 bps (8N1)**.
* **Mode 3: Offline Bootable USB / Floppy [Field Audit]**
  Copy `HWPROBE.COM` and `PCISCAN.COM` onto a bootable FreeDOS USB key with an `FDAUTO.BAT` autorun script. Boot any machine, get `HWREPORT.TXT`, and inspect it back in Antigravity IDE with `inquibench lspci --file REPORT.TXT -tvnn`.

---

## 5. Architectural Philosophy

1. **Non-Intrusive Guest Footprint:** The resident DOS daemon (`INQUIBEN.COM`) takes only **1.1 KB** of RAM. Over 520–600 KB remains completely available for games and memory-hungry applications.
2. **Protected OS Volume:** The operating system drive (`C:`) is treated as read-only. All AI experiments, scripts, benchmarks, and temporary files live on Drive `D:`.
3. **AI Vision Without Video Capture:** By directly reading text video memory (`0xB800`), Gemini can "read" the DOS screen instantly over serial with zero video capture hardware required.
