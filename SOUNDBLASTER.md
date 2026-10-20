# Sound Blaster Emulation & Retro Audio Knowledge Base (v2)
## MS-DOS 6.22 / MS-DOS 7.1 / Windows 98 SE

This document is the consolidated engineering reference for achieving **Sound Blaster (Pro / 16)**, **AdLib OPL3 FM**, and **MPU-401 MIDI** audio across retro computing platforms and Thin Clients cataloged from [Parky Towers](https://www.parkytowers.me.uk/thin/hware/hardware.shtml).

---

## 1. Quick Decision Matrix: The 3 Golden Pathways

For immediate hardware selection without reading the complete architectural breakdown, three proven pathways exist depending on your target software environment:

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              THE 3 GOLDEN HARDWARE PATHWAYS                            │
├────────────────────────────────┬───────────────────────────────┬───────────────────────┤
│ PATH 1: PURE REAL-MODE DOS     │ PATH 2: WIN98 SE + DOS PROMPT │ PATH 3: MODERN HDA    │
│ (DOS 6.22 & 7.1 "No EMM386")   │ (The Hybrid Gaming Powerhouse)│ (Thin Clients 2008+)  │
│                                │                               │                       │
│ • Best: Cyrix/NatSemi CS5530   │ • Best: HP t5720              │ • Best: HP t5740/t620 │
│   (Neoware Eon, Wyse 3125SE)   │   (Geode NX1500 / Socket A)   │   (Atom N280 / AMD)   │
│ • Alt: VIA VT8231 / VT82C686B  │ • Audio: SiS 7012 VxD driver  │ • Audio: SBEMU TSR    │
│   (HP t5700, HP t5710)         │   (v1.12d) for DirectSound 3D │   with JEMMEX + QPIEMU│
│ • Method: Native SMM or        │ • Method: Monolithic Ring 0   │ • Method: DPMI V86    │
│   Function 5 enabler (0 KB RAM)│   VxD with VSBD.VXD           │ • Result: Protected-  │
│ • Result: SB16/SBPro runs      │ • Result: Zero-latency audio  │   mode games work;    │
│   Ultima VII, Comanche, Doom.  │   and SB Pro in Win98 DOS.    │   Ultima VII fails.   │
└────────────────┴───────────────────────────────┴───────────────────────┘
```

| Operating Objective | Optimal Hardware Platform | Audio Controller | Driver / Enabler Stack | Effective Audio Standard | Operating Mode & Constraints |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Pure DOS Real-Mode**<br>*(Ultima VII, Wing Commander)* | **Cyrix / NatSemi CS5530**<br>(Neoware Eon, Wyse 3125SE) | Integrated CS5530A companion | `GX1SND.EXE` in `AUTOEXEC.BAT` | **Sound Blaster 16** + **AdLib OPL3** | **Mode 2 (SMM)**. 0 KB conventional RAM. Fully transparent to DOS. |
| **Pure DOS Real-Mode**<br>*(Ultima VII, Doom, Duke3D)* | **VIA VT8231 / VT82C686B**<br>(HP t5700, HP t5710) | Southbridge Function 5 (`D17F5`) + AC'97 Codec | [VIASBCFG](https://www.vogons.org/viewtopic.php?t=73270) or [VIA_AC97.866](https://github.com/oerg866/via_ac97.866) | **Sound Blaster Pro 2.0** + **AdLib OPL3** | **Mode 1 (DSP)**. 0 KB RAM for PCM; ~26 KB for OPL3 hardware NMI trap (`V97TSR.EXE`). |
| **Pure DOS via PCI Slot**<br>*(Any PC with open PCI)* | **Any Thin Client with PCI**<br>(HP t5720, t5730, t5740) | **ESS Solo-1 (ES1938S) PCI** | [UNISOUND](https://www.vogons.org/viewtopic.php?t=72553) or `ESSOLO.SYS` | **Sound Blaster Pro 2.0** + **Hardware ESFM** | **Mode 1 (TDMA)**. Transparent DMA bypasses chipset DDMA limits. 0 KB RAM. |
| **Windows 98 SE Hybrid**<br>*(DirectSound + DOS Boxes)* | **SiS 741GX / 963L**<br>(HP t5720) | SiS 7012 AC'97 Controller | [SiS 7012 VxD v1.12d](https://theretroweb.com/drivers/1935) (`a12112d.zip`) | **Sound Blaster Pro 2.0** (DOS Prompt) | **Ring 0 VxD**. Zero KMixer latency, native DS3D, automated `VSBD.VXD` DOS virtualization. |
| **Modern HDA (DPMI Only)**<br>*(Doom, Duke3D, Quake)* | **Intel HDA / AMD FCH**<br>(HP t5740, HP t610, t620) | High Definition Audio Codec (Realtek ALC) | [SBEMU](https://github.com/crazii/SBEMU) + `JEMMEX` + `HDPMI32i` | **Sound Blaster 16** (Emulated) | **Mode 4 (V86)**. Intercepts I/O via GPF. **Fails on flat real-mode games (*Ultima VII*)**. |

---

## 2. The 4 Physical DOS Operating Modes

Understanding retro audio requires distinguishing how I/O accesses to ports `220h` (Sound Blaster) and `388h` (AdLib FM) are trapped and routed to physical analog jacks:

```text
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                        DOS SOUND OUTPUT ARCHITECTURES: THE 4 MODES                                     │
├──────────────────────────┬──────────────────────────┬──────────────────────────┬───────────────────────────────────────┤
│ 1. TRUE ON-CHIP SB DSP   │ 2. SMM / VSA TRAPPING    │ 3. PHANTOM LPC DECODE    │ 4. SOFTWARE V86 TRAPPING              │
│    (VT82C686B, VT8231)   │    (Cyrix CS5530 / Geode)│    (VT8237, VX800/VX900) │    (SBEMU / JEMMEX on HDA / AC'97)    │
│                          │                          │                          │                                       │
│  CPU I/O 220h (OUT / IN) │  CPU I/O 220h (OUT / IN) │  CPU I/O 220h (OUT / IN) │  CPU I/O 220h (OUT / IN)              │
│         │                │         │                │         │                │         │                             │
│         ▼                │         ▼ (ASMI Ring -2) │         ▼                │         ▼ (Ring 0 GPF Exception)     │
│  [Hardware SBPro DSP]    │  [SMM Hypervisor/SMRAM]  │  [D17F0 LPC Bridge]      │  [SBEMU Ring 0 Emulation Core]        │
│         │ Scatter-Gather │         │ Translates I/O │         │ LAD[3:0] pins  │         │ Synthesizes PCM in RAM      │
│         ▼                │         ▼                │         ▼                │         ▼                             │
│  [AC-Link Digital Bus]   │  [AC'97 Bus Master DMA]  │  [Motherboard LPC Void]  │  [PCIe Bus-Master DMA Engine]         │
│         │                │         │                │         │ (No DAC link!) │         │ (Azalia CORB/RIRB Ring)     │
│         ▼                │         ▼                │         ▼                │         ▼                             │
│  [Analog AC'97 Codec]    │  [Analog AC'97 Codec]    │  [DEAD END / SILENCE]    │  [HDA Codec (e.g. Realtek ALC)]       │
│         │                │         │                │                          │         │                             │
│  🔊 ANALOG AUDIO OUT     │  🔊 ANALOG AUDIO OUT     │  🔇 SILENCE (0FFh)       │  🔊 ANALOG AUDIO OUT                  │
│  (0 KB TSR, Real-Mode)   │  (0 KB TSR, Real-Mode)   │  (Requires ISA riser)    │  (Requires DPMI / V86 manager)        │
└──────────────────────────┴──────────────────────────┴──────────────────────────┴───────────────────────────────────────┘
```

### Detailed Operating Mode Specifications

| Metric / Behavior | Mode 1: True Hardware DSP | Mode 2: CPU-Level SMM / VSA | Mode 3: Phantom LPC Decode | Mode 4: Software V86 Trapping |
| :--- | :--- | :--- | :--- | :--- |
| **Decode Mechanism** | Hardwired Sound Blaster Pro DSP inside Southbridge silicon. | Accelerated System Management Interrupt (ASMI) trapped by CPU hardware into Ring -2. | Southbridge LPC bridge claims `220h` on PCI and serializes cycles onto external `LAD[3:0]` pins. | Protected-Mode V86 I/O port trap (GPF) caught by memory manager (`JEMMEX` / `QPIEMU`). |
| **Emulation Core** | Dedicated hardware state machine. | Firmware microcode executing inside hidden SMRAM. | None (signals leave chipset onto unpopulated motherboard headers). | Software emulation state machine executing in host RAM ([SBEMU](https://github.com/crazii/SBEMU)). |
| **Audio Output Path** | Internal Scatter-Gather DMA streams AC-Link frames to onboard AC'97 codec. | SMM handler writes translated PCM directly to CS5530 AC'97 DMA engine. | **No electrical path to onboard DAC**. Cycles terminate in silence unless an ISA riser is wired. | Mixes PCM in RAM, then streams via 32/64-bit PCI bus-master DMA to HDA/AC'97 controller. |
| **Memory Footprint** | **0 KB TSR** for PCM digital audio; ~26 KB for OPL3 hardware NMI trap. | **0 KB RAM** (Completely invisible to DOS memory space). | 0 KB (Produces 0 audio on stock jacks). | ~10–30 KB conventional RAM (`SBEMU.EXE` + `JEMMEX` + `HDPMI32i`). |
| **Pure Real-Mode DOS**<br>*(Ultima VII, Comanche)* | **100% Compatible**<br>(No EMM386 or protected mode required). | **100% Compatible**<br>(Hypervisor runs in hardware SMM). | **Incompatible**<br>(Silent or freezes waiting for DSP ready). | **Incompatible**<br>(Flat real-mode memory managers crash under V86/EMM386). |

---

## 3. Master Hardware Matrix: Thin Clients & Silicon Families

All platforms are categorized by their silicon lineage and capabilities. Driver links point directly to [VOGONS Drivers](http://www.vogonsdrivers.com/) and community repositories:

| Silicon Family | Specific Chipset & Audio Core | DOS Mode | Thin Client Models (Parky Towers) | DOS Real-Mode (*Ultima VII*) | DOS DPMI (*Doom*, *Quake*) | Recommended Windows 98 SE Driver Package | Optimal Method & Setup Rules |
| :--- | :--- | :---: | :--- | :---: | :---: | :--- | :--- |
| **Family B**<br>*(Cyrix/Geode SMM)* | **Cyrix / NatSemi CS5530A**<br>(Hardware SB16 in SMM) | **Mode 2** | [Neoware Eon](https://www.parkytowers.me.uk/thin/neoware/Eon/)<br>[Neoware Capio](https://www.parkytowers.me.uk/thin/neoware/Capio/)<br>[Wyse 3125SE](https://www.parkytowers.me.uk/thin/wyse/3125se/)<br>[Wyse 3150SE](https://www.parkytowers.me.uk/thin/wyse/3150se/) | **YES (100%)** | **YES (100%)** | **VxD:** [MediaGX / CS5530 Suite (fileid=2152)](http://www.vogonsdrivers.com/getfile.php?fileid=2152)<br>*(Contains `CS5530.VXD` v1.30)* | Run `GX1SND.EXE` in `AUTOEXEC.BAT`. 0 KB TSR footprint. Flawless flat real-mode audio. |
| **Family A1**<br>*(VIA Legacy SBPro)* | **VIA VT82C686B**<br>(On-chip SBPro DSP in D17F5) | **Mode 1** | [Neoware CA2](https://www.parkytowers.me.uk/thin/neoware/CA2/) | **YES (100%)** | **YES (100%)** | **VxD:** [The Retro Web #269 (VIA AC97 v2.20a)](https://theretroweb.com/drivers/269)<br>& [VOGONS fileid=1363](http://www.vogonsdrivers.com/getfile.php?fileid=1363) | Use `VIASBCFG` ([fileid=1670](http://www.vogonsdrivers.com/getfile.php?fileid=1670)) or `VIA_AC97.866`. Run `VIASBCFG` + `VIAUDIO.COM` in `AUTOEXEC.BAT` before Win98 boots. |
| **Family A1**<br>*(VIA Legacy SBPro)* | **VIA VT8231 / VT8235**<br>(On-chip SBPro DSP in D17F5) | **Mode 1** | [HP t5700](https://www.parkytowers.me.uk/thin/hp/t5700/)<br>[HP t5710](https://www.parkytowers.me.uk/thin/hp/t5710/)<br>[Wyse 9450XE](https://www.parkytowers.me.uk/thin/wyse/9450xe/)<br>[Futro S200 / S300](https://www.parkytowers.me.uk/thin/Futro/s200/)<br>[HP t5515](https://www.parkytowers.me.uk/thin/hp/t5515/) | **YES (100%)** | **YES (100%)** | **VxD:** [The Retro Web #269 (VIA AC97 v2.20a)](https://theretroweb.com/drivers/269)<br>& [VOGONS fileid=1363](http://www.vogonsdrivers.com/getfile.php?fileid=1363) | `VIASBCFG` auto-detects HP t5710 and re-routes to IRQ 7 to eliminate USB interrupt conflicts. |
| **Family A2**<br>*(VIA Modern SATA)* | **VIA VT8237 / VT8237R**<br>(VT8237 AC'97, No SB DSP) | **Mode 4**<br>*(Mode 3 stock)* | [HP t5530](https://www.parkytowers.me.uk/thin/hp/t5530/)<br>[Igel 4210LX](https://www.parkytowers.me.uk/thin/Igel/4210/)<br>[Igel UD2 / UD3](https://www.parkytowers.me.uk/thin/Igel/ud/ud2/D200/) | **NO (Needs V86)** | **YES (SBEMU)** | **VxD:** [VIA AC'97 / Vinyl (fileid=1363)](http://www.vogonsdrivers.com/getfile.php?fileid=1363)<br>*(or TRW #2209)* | Pure DOS requires [SBEMU](https://github.com/crazii/SBEMU) (`sc_via82.c`). Stock jack produces no sound from register tweaks alone. |
| **Family A2**<br>*(VIA Media SoC)* | **VIA VX800 / VX820 / VX855 / VX900**<br>(Chrome9 / VT1708B HDA) | **Mode 4**<br>*(Mode 3 stock)* | [HP t5540](https://www.parkytowers.me.uk/thin/hp/t5540/)<br>[HP t5570 / t510](https://www.parkytowers.me.uk/thin/hp/t5570/)<br>[Futro S100](https://www.parkytowers.me.uk/thin/Futro/s100/)<br>[Wyse Cx0](https://www.parkytowers.me.uk/thin/wyse/cx0/) | **NO (Needs V86)** | **YES (SBEMU)** | **WDM:** [WDMHDA (HD Audio WDM)](https://github.com/andrew-hoffman/WDMHDA)<br>*(No VxD exists for Azalia)* | Requires SBEMU (`sc_inthd.c`, Device ID `1106:3288`). External ISA sound possible via dISAppointment riser. |
| **Family C1**<br>*(SiS Trident)* | **SiS 630 / 730**<br>(SiS 7018 Trident DSP Core) | **Mode 1** | Legacy Socket 370 / Socket A boards | **YES (100%)** | **YES (100%)** | **VxD:** [SiS 7018 Full DOS/Win9x (fileid=1532)](http://www.vogonsdrivers.com/getfile.php?fileid=1532) | Hardware legacy core derived from Trident 4DWave. Uses `T4DW.EXE` for 0 KB TSR PCM initialization. |
| **Family C2**<br>*(SiS MuTIOL)* | **SiS 963 / 963L**<br>(SiS 7012 AC'97 Controller) | **Mode 4**<br>*(Mode 1 via PCI)* | [HP t5720](https://www.parkytowers.me.uk/thin/hp/t5720/)<br>[Futro S400](https://www.parkytowers.me.uk/thin/Futro/s400/)<br>[Neoware CA5](https://www.parkytowers.me.uk/thin/neoware/CA5/) | **NO (Needs V86)** | **YES (100%)** | **VxD:** [SiS 7012 v1.12d (The Retro Web #1935)](https://theretroweb.com/drivers/1935)<br>([`a12112d.zip`](https://theretroweb.com/drivers/1935)) | **The Win98 Powerhouse**: Zero-latency DirectSound and automatic SBPro DOS prompt virtualization. Under pure DOS, add an **ESS Solo-1 PCI** card. |
| **Family D1**<br>*(Intel HDA)* | **Intel ICH7-M / Bay Trail**<br>(Intel Azalia HD Audio) | **Mode 4** | [HP t5740](https://www.parkytowers.me.uk/thin/hp/t5740/)<br>[Wyse 3030](https://www.parkytowers.me.uk/thin/wyse/3030/) | **NO (Needs V86)** | **YES (SBEMU)** | **WDM:** [WDMHDA (HD Audio WDM)](https://github.com/andrew-hoffman/WDMHDA)<br>*(No VxD exists for ICH HDA)* | Requires SBEMU (`sc_inthd.c`) with `JEMMEX` and `HDPMI32i`. WDMHDA driver provides sound under Win98. |
| **Family D2**<br>*(AMD / FCH)* | **AMD Geode CS5536 / SB600 / SB700 / Kabini FCH** | **Mode 4** | [HP t5730](https://www.parkytowers.me.uk/thin/hp/t5730/)<br>[HP t520 / t610 / t620](https://www.parkytowers.me.uk/thin/hp/t610/)<br>[Futro S450 / S900](https://www.parkytowers.me.uk/thin/Futro/s450/) | **NO (Needs V86)** | **YES (SBEMU)** | **WDM:** [WDMHDA (HD Audio WDM)](https://github.com/andrew-hoffman/WDMHDA) / [Realtek AC'97 (fileid=1321)](http://www.vogonsdrivers.com/getfile.php?fileid=1321) | SBEMU (`sc_cs5535.c` for Geode, `sc_inthd.c` for SB600/SB700/FCH). |

> [!NOTE]
> **Why "VxD" is Critical for Windows 98 SE:**
> Monolithic Ring 0 **VxD drivers** bypass Microsoft's **KMixer**, delivering **< 5 ms latency**, native hardware DirectSound 3D/EAX voices, and automatic Sound Blaster virtualization (`VSBD.VXD`) inside Windows 98 DOS windows without loading any DOS TSRs. In contrast, modern chips restricted to **WDM drivers** suffer from 30–100 ms latency, software CPU mixing, and broken DOS prompt emulation.

---

## 4. Deep Hardware Focus: The VIA Southbridge Split & LPC Modding

### The Architectural Paradox: D17F0 (LPC Bridge) vs D17F5 (Audio DSP)
Community reverse-engineering resolves why enabling VIA LPC registers on modern thin clients yields silence:

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        THE VIA SOUTHBRIDGE ARCHITECTURAL SPLIT                         │
├────────────────────────────────────────────────────────┬───────────────────────────────┤
│    VT82C686A/B & VT8231 (1999–2001)                    │    VT8233/37 & VX800/VX900    │
├────────────────────────────────────────────────────────┼───────────────────────────────┤
│  • Function 5 contains physical Sound Blaster DSP      │  • Function 5 SB DSP REMOVED  │
│  • Scatter-Gather DMA streams directly to AC'97 Codec  │  • Audio migrated to HDA ring │
│  • 100% Real-Mode DOS audio on stock 3.5mm jack        │  • Stock 3.5mm jack is SILENT │
│  • Enabled via VIASBCFG or VIA_AC97.866                │  • D17F0 writes go to LPC pins│
└────────────────────────────────────────────────────────┴───────────────────────────────┘
```

1. **VT82C686A/B & VT8231 (Family A1):** Contain an on-chip Sound Blaster Pro DSP inside Southbridge **Function 5** (`D17F5`). Writing to `D17F5` routes digitized audio through internal Scatter-Gather DMA directly to the external AC'97 codec.
2. **VT8233/35/37 & VX800/VX900 (Family A2):** VIA retained the legacy LPC bridge registers inside **Function 0** (`D17F0` `Rx6F`, `Rx53`), but **physically eliminated the Sound Blaster DSP from Function 5**.
3. **The Result:** On a stock thin client (e.g., HP t5540, t510), programming `Rx6F=04h` serializes cycles onto unpopulated motherboard LPC bus pins (`LAD[3:0]`). No audio reaches the analog headphone jack.
4. **Where D17F0 is Actually Useful:** Wiring an external **dISAppointment (LPC-to-ISA)** board to the LPC header allows true ISA Sound Blaster cards to decode those forwarded cycles in hardware!

### Hardware Modding: Enabling LPC Positive Decode (`VIALPC.ASM`)
This stand-alone real-mode assembly utility (0 KB TSR) programs PCI Configuration Mechanism #1 (`0CF8h`/`0CFCh`) to activate Sound Blaster, MIDI, Gameport, and DMA on LPC risers:

```nasm
; ============================================================================
; VIALPC.ASM - Forward 220h, 330h, 200h and DMA 1/5 to LPC Bus (dISAppointment)
; Target: VIA VT8237 / VX800 / VX820 / VX900 (Bus 0, Dev 17, Func 0)
; ============================================================================
.MODEL TINY
.386
.CODE
ORG 100h

START:
    CLI                         ; Disable interrupts during PCI config sequence

    ; --- 1. Rx53 (PC/PCI & LPC DMA Control): Master=1, DMA5=1, DMA1=1 ---
    MOV     EAX, 80008850h      ; Bus 0, Dev 17, Func 0, Offset 50h
    MOV     DX, 0CF8h
    OUT     DX, EAX
    MOV     DX, 0CFFh           ; Offset 50h + 3 = Rx53
    IN      AL, DX
    OR      AL, 92h             ; Bit 7 (Master), Bit 4 (DMA 5), Bit 1 (DMA 1)
    OUT     DX, AL

    ; --- 2. Rx6C (WSS 530h), Rx6D (Gameport 200h + MIDI 330h), Rx6F (SB 220h) ---
    MOV     EAX, 8000886Ch      ; Offset 6Ch
    MOV     DX, 0CF8h
    OUT     DX, EAX

    MOV     DX, 0CFCh           ; Rx6C: WSS Enable (530h-537h)
    IN      AL, DX
    AND     AL, 8Fh
    OR      AL, 40h
    OUT     DX, AL

    MOV     DX, 0CFDh           ; Rx6D: Gameport 200h + MIDI MPU-401 330h
    IN      AL, DX
    AND     AL, 0F0h
    OR      AL, 0Ch
    OUT     DX, AL

    MOV     DX, 0CFFh           ; Rx6F: Sound Blaster Positive Decode (220h-22Fh)
    IN      AL, DX
    AND     AL, 0F8h
    OR      AL, 04h
    OUT     DX, AL

    ; --- 3. Rx80 (Audio Access Monitoring for Power Management) ---
    MOV     EAX, 80008880h      ; Offset 80h
    MOV     DX, 0CF8h
    OUT     DX, EAX
    MOV     DX, 0CFCh           ; Rx80
    IN      AL, DX
    OR      AL, 02h             ; Monitor SB (220h) & AdLib (388h)
    OUT     DX, AL

    STI                         ; Re-enable interrupts
    MOV     AX, 4C00h           ; Exit cleanly to DOS (0 KB TSR)
    INT     21h

END START
```

*(Alternatively, use [PCIEDIT](https://github.com/oerg866/pciedit) in `AUTOEXEC.BAT` with: `PCIEDIT.EXE 1106 8353 VX800LPC.TXT`).*

---

## 5. Dedicated Add-on Alternatives (PCI Expansion)

When motherboard silicon lacks native DOS Sound Blaster logic, dedicated add-on cards in open expansion slots provide real-mode compatibility:

1. **ESS Solo-1 (ES1938S) PCI — The Gold Standard:**
   - **Audio Standard:** Sound Blaster Pro 2.0 (Enhanced stereo 44.1 kHz) + Hardware ESFM (Superior OPL3 clone).
   - **Why it Excels:** Employs an internal **TDMA (Transparent DMA)** controller that entirely bypasses motherboard chipset Distributed DMA (DDMA) or PC/PCI constraints. Works in virtually any PCI slot (including the **HP t5720**).
   - **Software:** Initialized in pure DOS via [UNISOUND](https://www.vogons.org/viewtopic.php?t=72553) or native drivers from [VOGONS Drivers fileid=691](http://www.vogonsdrivers.com/getfile.php?fileid=691) (`ESSOLO.SYS`, `ESSVOL.EXE`, and `ES1938.VXD`).
2. **Yamaha YMF724 / YMF744 / YMF754 PCI:**
   - **Audio Standard:** Sound Blaster Pro 2.0 + Authentic Yamaha OPL3 FM Synthesizer.
   - **Constraint:** Pure DOS PCM requires a motherboard with a physical PC/PCI cable header or functional D-DMA.
   - **Driver:** [Yamaha YMF724 (fileid=692)](http://www.vogonsdrivers.com/getfile.php?fileid=692) & [YMF744 (fileid=693)](http://www.vogonsdrivers.com/getfile.php?fileid=693) (DOS & Win9x).
3. **Ensoniq AudioPCI (ES1370 / ES1371 / Creative SB PCI 128):**
   - **Audio Standard:** Sound Blaster 16 / Pro via DOS TSR using 2MB/4MB/8MB ECW wavetable banks in RAM.
   - **Driver:** [DOS Initialization & Wavesets (fileid=373)](http://www.vogonsdrivers.com/getfile.php?fileid=373) & [Win9x Driver (fileid=1268)](http://www.vogonsdrivers.com/getfile.php?fileid=1268).

---

## 6. Software Tools, Utilities & Driver Directory

All key tools mentioned across this guide, their original authors, and exact download locations:

| Project / Tool | Author & Community Reference | Primary Purpose & Mechanics | Memory & TSR Impact |
| :--- | :--- | :--- | :--- |
| **[UNISOUND](https://www.vogons.org/viewtopic.php?t=72553)** | **JazeFox** (VOGONS) | Universal PnP hardware enabler for all major ISA sound cards (Creative SB16/AWE, ESS AudioDrive, Yamaha OPL3-SAx, Crystal CS423x, OPTi, ALS) and ESS Solo-1 PCI. Programs mixers and hardware registers directly. | **0 KB RAM** (Transient enabler, no TSR). |
| **[SBEMU](https://github.com/crazii/SBEMU)** | **crazii** (GitHub) | Software Sound Blaster 16 and OPL3 emulation for modern PCI, AC'97, and Intel/AMD High Definition Audio chips via Ring 0 V86 I/O port trapping (`JEMMEX` + `QPIEMU.DLL` + `HDPMI32i`). Streams PCM via native bus-mastering DMA. | ~10–30 KB conventional RAM. Incompatible with flat real-mode games (*Ultima VII*). |
| **[VIASBCFG](https://www.vogons.org/viewtopic.php?t=73270)** | **JazeFox** (VOGONS) | Unlocks hardware Sound Blaster Pro registers and unmutes AC'97 mixer on legacy VIA Southbridges (**VT82C686A/B**, **VT8231**) on motherboards whose BIOS hid legacy audio settings. | **0 KB RAM** (Transient enabler, no TSR). |
| **[VIA_AC97.866](https://github.com/oerg866/via_ac97.866)** | **oerg866** (Eric Voirin) | Modern replacement for VIA's official DOS stack on VT82C686 and VT8231. Provides mixer control (`VIA_AC97.EXE`) and an OPL3 FM TSR (`V97TSR.EXE`) hooked to hardware NMI traps on port `388h` using the Nuked-OPL3 core. | 0 KB for digital audio; ~26 KB for OPL3 TSR. 100% Real-Mode compatible. |
| **[VIAXFG](https://github.com/enaiel/viaxfg)** | **Enaiel** (GitHub) | Open-source CLI tool (DJGPP DPMI) to toggle VIA Southbridge Sound Blaster (`/ES`), FM (`/EF`), MIDI (`/EM`), and Joystick (`/EJ`) registers on-the-fly without rebooting. | **0 KB RAM** (Transient utility). |
| **[PCIEDIT & RG2TXT](https://github.com/oerg866/pciedit)** | **oerg866** (Eric Voirin) | DOS utility to read and write arbitrary PCI configuration registers via Configuration Mechanism #1. Includes `RG2TXT` to convert WPCREDIT `.RG` script files for batch execution in `AUTOEXEC.BAT`. | **0 KB RAM** (Transient utility). |
| **[RU (Read Universal)](http://ruexe.blogspot.com/)** | **James Wang** | Interactive real-mode hardware debugger capable of reading and modifying PCI/PCIe config spaces, Super I/O Logical Devices, CPU MSRs, and physical I/O ports. | Interactive diagnostic environment. |

### Vintage Driver Library Mirrors (VOGONS Drivers)
For downloading drivers directly to vintage PCs using old web browsers (without TLS 1.3 encryption):
* **Main Portal:** [VOGONS Drivers](http://www.vogonsdrivers.com/) | **No-SSL Mirror:** [http://nossl.vogonsdrivers.com/](http://nossl.vogonsdrivers.com/)
* **Secondary Archive:** [The Retro Web Driver Database](https://theretroweb.com/)
* **Direct Archive Downloads (VOGONS Drivers):**
  - **ESS Solo-1 (ES1938S) Win95/Win98/NT4:** [VOGONS Drivers fileid=691](http://www.vogonsdrivers.com/getfile.php?fileid=691) (`es1938.7z`)
  - **ESS Solo-1 / PCI Pure DOS Drivers:** [VOGONS Drivers fileid=60](http://www.vogonsdrivers.com/getfile.php?fileid=60) (`ESSDOS.zip`)
  - **ESS Solo-1 (ES1938) Windows 3.1x:** [VOGONS Drivers fileid=2175](http://www.vogonsdrivers.com/getfile.php?fileid=2175)
  - **Ensoniq AudioPCI (ES1370 / ES1371) DOS Drivers & Wavesets:** [VOGONS Drivers fileid=373](http://www.vogonsdrivers.com/getfile.php?fileid=373) & [Creative fileid=374](http://www.vogonsdrivers.com/getfile.php?fileid=374)
  - **Ensoniq AudioPCI ES1371/1373 Windows 9x:** [VOGONS Drivers fileid=1268](http://www.vogonsdrivers.com/getfile.php?fileid=1268)
  - **VIA AC'97 Combo Audio (VT82C686B / VT8231 / VT8233 / VT8237):** [VOGONS Drivers fileid=1363](http://www.vogonsdrivers.com/getfile.php?fileid=1363) (`ComboAudio_A1u370b.zip`)
  - **VIA VT1612 / VT82C686 DOS Sound Enabler (VIASBCFG):** [VOGONS Drivers fileid=1670](http://www.vogonsdrivers.com/getfile.php?fileid=1670) (`viasbcfg010a.zip`)
  - **VIA Audio 7012 / 7018 Full DOS Support Pack:** [VOGONS Drivers fileid=1532](http://www.vogonsdrivers.com/getfile.php?fileid=1532) (`viaaudio-dospack.rar`)
  - **Cyrix / NatSemi MediaGX & Geode CS5530 Suite (Win3.x, Win9x, NT):** [VOGONS Drivers fileid=2152](http://www.vogonsdrivers.com/getfile.php?fileid=2152) (`mediagx.zip`)
  - **Realtek AC'97 Audio Win9x/ME/2k/XP v3.62 WHQL (VxD & WDM):** [VOGONS Drivers fileid=1321](http://www.vogonsdrivers.com/getfile.php?fileid=1321) & [v3.41 fileid=1319](http://www.vogonsdrivers.com/getfile.php?fileid=1319)
  - **Yamaha OPL3-SAx Final Win9x Ref Driver v2343:** [VOGONS Drivers fileid=1064](http://www.vogonsdrivers.com/getfile.php?fileid=1064) (`95v2343.exe`)
  - **Aureal Vortex 2 SQ2500 Driver CD 2.040:** [VOGONS Drivers fileid=846](http://www.vogonsdrivers.com/getfile.php?fileid=846)
  - **C-Media CMI8738 DOS Drivers & Epic Games Fix:** [VOGONS Drivers fileid=632](http://www.vogonsdrivers.com/getfile.php?fileid=632)
* **Direct Archive Downloads (The Retro Web & GitHub):**
  - **VIA VT82C686B / VT8231 AC'97 v2.20a (Win9x):** [The Retro Web Driver #269](https://theretroweb.com/drivers/269)
  - **VIA 686 Pure DOS Audio Driver:** [The Retro Web Driver #376](https://theretroweb.com/drivers/376)
  - **SiS 7012 PCI Audio VxD v1.12d (`a12112d.zip`):** [The Retro Web Driver #1935](https://theretroweb.com/drivers/1935)
  - **Windows 98 SE HD Audio WDM Driver:** [WDMHDA GitHub (Andrew Hoffman)](https://github.com/andrew-hoffman/WDMHDA)
