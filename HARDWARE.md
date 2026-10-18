# InquiBench - Hardware Specifications and Environment

This document records the hardware architecture, host infrastructure, virtualization configuration, and target platforms for the **InquiBench** automated hardware exploration and benchmark project.

---

## 1. Project Objective

Design and deploy a secure, robust bi-directional serial link (RS-232 / UART 16550) connecting:
- **Host Side:** An AI agent (Gemini) running on the host system with tool-calling capabilities (hardware topology interrogation, synthetic benchmarks, command execution, file upload/download, VRAM text screen capture, keystroke injection).
- **Guest Side:** A retro operating system (**MS-DOS 6.22, FreeDOS 1.4, DOS 7.1 / Windows 98**) running the `INQUIBEN.COM` daemon.

> [!IMPORTANT]
> **Testing Status:** The system is currently in active development and has been **tested exclusively in the 86Box virtual machine**. Operation on physical retro hardware represents a planned future milestone (Phase 2) and has **not yet been tested or verified on physical machines**.

---

## 2. Host Environment (AI Agent)

- **Role:** Executes the AI Agent (Gemini) and the host communication bridge (`host/host_bridge.py`).
- **Operating System:** Modern operating system with serial communication support (Windows with Named Pipe support or COM ports).
- **Software Dependencies:** Python 3.10+ (with `pyserial` for physical serial port communication).
- **Serial Interface:** Supports Windows Named Pipe (`\\.\pipe\86box_serial`) for virtualized testing, or standard RS-232 serial ports (`COMx`) for physical retro hardware.

---

## 3. Phase 1: Virtual Machine "DOS-Testbed" (86Box)

- **Emulator:** 86Box v6.0 (64-bit), Build 9001
- **VM Configuration:** Mirrored in `DOS-Testbed/86box.cfg`
- **Current Guest OS:** MS-DOS 6.22
- **Planned Target OS Matrix:** FreeDOS 1.4, MS-DOS 7.10 / Windows 98 SE

### Emulated Hardware Configuration
- **Motherboard / Chipset:** [Socket 7] ASUS P/I-P55T2P4 (Intel 430HX chipset)
- **Emulated CPU:** Intel Pentium (133 MHz, P54C) with Dynarec enabled
- **Emulated Memory:** 16 MB RAM (16,384 KB)
- **Video Adapter:** [PCI] S3 Trio64
- **Hard Drives:**
  - `hdd_01` (Primary Master 0:0): `DOS-OS.img` (528 MB, FAT16 system drive `C:`)
  - `hdd_02` (Primary Slave 0:1): `DOS-DATA.img` (440 MB, FAT16 data drive `D:`)
- **CD-ROM Drive:**
  - `cdrom_01` (Secondary Master 1:0): ATAPI CD-ROM (72x speed)
- **Floppy Drive A:** 3.5" 1.44 MB
- **Input Devices:** Standard AT Keyboard, PS/2 Mouse (leaves COM1 completely free)

### Virtual Serial Port (COM1)
- **Port:** COM1 (Standard I/O base `0x3F8`, `IRQ 4`)
- **UART Controller:** 16550A with hardware FIFO buffers enabled
- **Host Transport Channel:** **Windows Named Pipe**
  - **Pipe Name:** `\\.\pipe\86box_serial`
  - **Mode:** Server (`mode = 1` in 86Box)
  - **Baud Rate:** 115,200 bps
  - **Framing:** 8 Data Bits, No Parity, 1 Stop Bit (8N1)

---

## 4. Phase 2: Planned Physical Target & Interface (Future / Untested)

> **Development Disclaimer:**
> The hardware specifications listed below represent the planned hardware setup for Phase 2 bench testing. **This physical configuration has NOT yet been tested or verified.** All current development and testing have been performed solely in 86Box v6.0.

### Host Serial Interface (Planned)
- **Hardware:** **StarTech ICUSB2321F** (USB to RS232 Serial DB9 Adapter Cable, 1 Port, 1.8 m)
- **UART Chipset:** Genuine **FTDI FT232R**
  - Official FTDI Virtual COM Port (VCP) drivers
  - Automatic COM port retention (e.g. `COM3`)
  - Maximum speed supported: up to 921,600 bps (well above the required 115,200 bps)
  - Integrated hardware FIFOs: 128 bytes RX / 256 bytes TX
  - Connector: DB9 Male (DTE pinout)

### Target Physical Retro Machine: HP t5720 Thin Client
The **HP t5720** (documented on *ParkyTowers*) is a classic retro-computing platform ideal for fanless, silent MS-DOS 6.22 and Windows 98 SE execution:

- **Processor (CPU):** AMD Geode NX 1500 (Socket A / Socket 462)
  - Frequency: 1 GHz (FSB 266 MHz)
  - Ultra-low TDP: 9W (100% passive cooling)
  - Architecture: 32-bit x86 compatible (MMX, 3DNow! Professional, SSE)
- **Chipset:** SiS 741GX (Northbridge) + SiS 963L (Southbridge)
- **RAM:** 1x 200-pin DDR SODIMM slot (typically 512 MB DDR-333, expandable to 1 GB)
- **Graphics:** Integrated SiS Mirage Graphics (fully compatible with standard VESA / DOS modes)
- **Audio:** SiS 7012 AC'97 (compatible with DOS via SBEMU or optional PCI expansion card)
- **Internal Storage:** 44-pin IDE connector (Disk-On-Module / CompactFlash adapter)
- **Ports & Connectors:**
  - **1x Native RS-232 DB9 Male Serial Port (COM1):** Standard 16550A UART (`0x3F8`, `IRQ 4`)
  - **1x IEEE 1284 Parallel Port (DB25 Female)**
  - **2x PS/2 Ports:** Dedicated Keyboard and Mouse
  - **1x VGA Output (DB15)**
  - **6x USB 2.0 Ports**
  - **1x 10/100 Ethernet Port** (Realtek RTL8100C)
- **BIOS:** Phoenix Award BIOS (`F10` key at boot), supports booting from ATA Flash, USB, and Network

### Cabling between Host PC and HP t5720
- **Host Side:** StarTech ICUSB2321F cable (DB9 Male)
- **Target Side (HP t5720):** Native COM1 port (DB9 Male)
- **Interconnect:** **Null-Modem DB9 Female <-> DB9 Female Cable / Adapter** (crossover RXD/TXD pins 2 and 3, signal ground pin 5, handshake line loops).

---

## 5. Software Abstraction Layer

The host Python bridge uses an abstract transport layer:
- **Virtual Mode (Verified):** Connects to Windows Named Pipe `\\.\pipe\86box_serial` (tested in 86Box v6.0).
- **Physical Mode (Pending Validation):** Connects to serial port `COMx` via `pyserial` (to be validated in Phase 2).

While the binary packet framing (`0x55 0xAA`) and guest daemon (`INQUIBEN.COM`) are designed to be identical, only virtual transport has been validated to date.
