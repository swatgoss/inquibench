; ==============================================================================
; HWPROBE.ASM - InquiBench Comprehensive Retro Hardware Interrogator
; Inspired by SpeedSys (Vladimir Afanasiev / Konstantin Ruzanov)
; Target: MS-DOS 6.22 / FreeDOS 1.4 / DOS 7.1 / Win98 DOS (80386+)
; Assembler: NASM (generates standalone 16-bit .COM executable)
; ==============================================================================

            org 100h
            bits 16

start:
            ; Check for 386+ CPU
            pushf
            pop ax
            and ax, 0FFFh
            push ax
            popf
            pushf
            pop ax
            and ax, 0F000h
            cmp ax, 0F000h
            jne is_386_plus
            mov dx, msg_no_386
            mov ah, 09h
            int 21h
            ret

is_386_plus:
            ; Display banner
            mov dx, msg_header
            mov ah, 09h
            int 21h

            ; ------------------------------------------------------------------
            ; 1. CPU IDENTIFICATION & CLOCK MEASUREMENT
            ; ------------------------------------------------------------------
            mov dx, msg_sec_cpu
            mov ah, 09h
            int 21h

            call probe_cpu

            ; ------------------------------------------------------------------
            ; 2. MOTHERBOARD, BIOS & CHIPSET
            ; ------------------------------------------------------------------
            mov dx, msg_sec_mb
            mov ah, 09h
            int 21h

            call probe_bios
            call probe_chipset

            ; ------------------------------------------------------------------
            ; 3. MEMORY CONFIGURATION
            ; ------------------------------------------------------------------
            mov dx, msg_sec_mem
            mov ah, 09h
            int 21h

            call probe_memory

            ; ------------------------------------------------------------------
            ; 4. PCI BUS TOPOLOGY
            ; ------------------------------------------------------------------
            mov dx, msg_sec_pci
            mov ah, 09h
            int 21h

            call probe_pci

            ; Footer
            mov dx, msg_footer
            mov ah, 09h
            int 21h
            ret

; ==============================================================================
; CPU Probing Routines
; ==============================================================================
probe_cpu:
            ; Check if CPUID is supported by toggling EFLAGS bit 21
            pushfd
            pop eax
            mov ecx, eax                ; save original EFLAGS
            xor eax, 00200000h          ; toggle bit 21
            push eax
            popfd
            pushfd
            pop eax
            push ecx
            popfd                       ; restore original EFLAGS
            xor eax, ecx
            test eax, 00200000h
            jnz has_cpuid

            ; No CPUID (386 / early 486)
            mov dx, str_cpu_no_cpuid
            mov ah, 09h
            int 21h
            ret

has_cpuid:
            ; CPUID EAX=0: Vendor String
            xor eax, eax
            cpuid
            mov [max_cpuid], eax
            mov [cpu_vendor], ebx
            mov [cpu_vendor+4], edx
            mov [cpu_vendor+8], ecx
            mov byte [cpu_vendor+12], '$'

            mov dx, str_cpu_vendor
            mov ah, 09h
            int 21h
            mov dx, cpu_vendor
            mov ah, 09h
            int 21h
            mov dx, str_crlf
            mov ah, 09h
            int 21h

            ; CPUID EAX=1: Family, Model, Stepping, Features
            cmp dword [max_cpuid], 1
            jb no_cpuid_features

            mov eax, 1
            cpuid
            mov [cpu_signature], eax
            mov [cpu_features], edx

            ; Display Model Name decoded
            mov dx, str_cpu_model
            mov ah, 09h
            int 21h

            call decode_cpu_name

            ; Display Family/Model/Stepping
            mov dx, str_cpu_fms
            mov ah, 09h
            int 21h

            ; Family = (EAX >> 8) & 0Fh
            mov eax, [cpu_signature]
            shr eax, 8
            and al, 0Fh
            mov ah, 0
            call print_dec

            mov dx, str_fms_model
            mov ah, 09h
            int 21h

            ; Model = (EAX >> 4) & 0Fh
            mov eax, [cpu_signature]
            shr eax, 4
            and al, 0Fh
            mov ah, 0
            call print_dec

            mov dx, str_fms_step
            mov ah, 09h
            int 21h

            ; Stepping = EAX & 0Fh
            mov eax, [cpu_signature]
            and al, 0Fh
            mov ah, 0
            call print_dec

            mov dx, str_crlf
            mov ah, 09h
            int 21h

            ; Features
            mov dx, str_cpu_feats
            mov ah, 09h
            int 21h
            call print_features
            mov dx, str_crlf
            mov ah, 09h
            int 21h

            ; Measure Clock Frequency via RDTSC (if TSC supported: bit 4 of EDX)
            test dword [cpu_features], 00000010h
            jz no_tsc_measure

            call measure_tsc_clock

no_cpuid_features:
            ret

no_tsc_measure:
            mov dx, str_cpu_no_tsc
            mov ah, 09h
            int 21h
            ret

; ------------------------------------------------------------------------------
; Measure CPU frequency using RDTSC and BIOS timer ticks
; ------------------------------------------------------------------------------
measure_tsc_clock:
            mov dx, str_cpu_freq
            mov ah, 09h
            int 21h

            ; Access BIOS timer tick at 0040:006Ch
            mov ax, 40h
            mov es, ax

            ; Wait for next tick edge to synchronize
            mov ax, [es:6Ch]
sync_tick:
            cmp ax, [es:6Ch]
            je sync_tick

            ; Read starting TSC
            rdtsc
            mov esi, eax                ; ESI = start TSC (low 32 bits)

            ; Target: wait for 2 ticks (approx 109.85 ms)
            mov ax, [es:6Ch]
            add ax, 2
wait_ticks:
            cmp ax, [es:6Ch]
            jne wait_ticks

            ; Read ending TSC
            rdtsc
            sub eax, esi                ; EAX = cycles in 2 ticks

            ; Formula: 2 ticks = 131072 / 1193182 s = 0.10985079 s
            ; Freq (MHz) = (cycles * 1193182) / (131072 * 1,000,000)
            ; Approx divisor for cycles -> MHz * 10:
            ; divisor = (131072 * 100000) / 1193182 = 10985
            xor edx, edx
            mov ecx, 10985
            div ecx                     ; EAX = MHz * 10

            ; Print integer part (EAX / 10)
            xor edx, edx
            mov ecx, 10
            div ecx                     ; EAX = MHz, EDX = tenth
            push edx

            call print_dec

            mov dl, '.'
            call print_char

            pop edx
            mov al, dl
            add al, '0'
            mov dl, al
            call print_char

            mov dx, str_mhz_suffix
            mov ah, 09h
            int 21h
            ret

; ------------------------------------------------------------------------------
; Decode CPU name based on Vendor + Signature
; ------------------------------------------------------------------------------
decode_cpu_name:
            ; Check Vendor
            cmp dword [cpu_vendor], "Genu"
            jne check_amd_vendor

            ; Intel Family
            mov eax, [cpu_signature]
            shr eax, 8
            and al, 0Fh
            cmp al, 4
            je name_i486
            cmp al, 5
            je name_pentium
            cmp al, 6
            je name_p6
            jmp name_generic_intel

name_pentium:
            ; Check Model (Pentium P54C vs P55C MMX)
            mov eax, [cpu_signature]
            shr eax, 4
            and al, 0Fh
            cmp al, 4
            je name_pentium_mmx
            cmp al, 8
            je name_pentium_mmx
            mov dx, str_p54c
            mov ah, 09h
            int 21h
            ret

name_pentium_mmx:
            mov dx, str_p55c
            mov ah, 09h
            int 21h
            ret

name_i486:
            mov dx, str_i486
            mov ah, 09h
            int 21h
            ret

name_p6:
            mov dx, str_p6
            mov ah, 09h
            int 21h
            ret

name_generic_intel:
            mov dx, str_intel_cpu
            mov ah, 09h
            int 21h
            ret

check_amd_vendor:
            cmp dword [cpu_vendor], "Auth"
            jne name_unknown
            mov dx, str_amd_cpu
            mov ah, 09h
            int 21h
            ret

name_unknown:
            mov dx, str_unknown_cpu
            mov ah, 09h
            int 21h
            ret

; ------------------------------------------------------------------------------
; Print CPU Feature Flags
; ------------------------------------------------------------------------------
print_features:
            mov edx, [cpu_features]
            test edx, 00000001h
            jz f_vme
            push dx
            mov dx, str_fpu
            mov ah, 09h
            int 21h
            pop dx
f_vme:
            test edx, 00000002h
            jz f_tsc
            push dx
            mov dx, str_vme
            mov ah, 09h
            int 21h
            pop dx
f_tsc:
            test edx, 00000010h
            jz f_msr
            push dx
            mov dx, str_tsc
            mov ah, 09h
            int 21h
            pop dx
f_msr:
            test edx, 00000020h
            jz f_cx8
            push dx
            mov dx, str_msr
            mov ah, 09h
            int 21h
            pop dx
f_cx8:
            test edx, 00000100h
            jz f_mmx
            push dx
            mov dx, str_cx8
            mov ah, 09h
            int 21h
            pop dx
f_mmx:
            test edx, 00800000h
            jz f_done
            push dx
            mov dx, str_mmx
            mov ah, 09h
            int 21h
            pop dx
f_done:
            ret

; ==============================================================================
; Motherboard & BIOS Probing
; ==============================================================================
probe_bios:
            ; BIOS Date is always at fixed location F000:FFF5 (8 chars)
            mov dx, str_bios_date
            mov ah, 09h
            int 21h

            mov ax, 0F000h
            mov es, ax
            mov si, 0FFF5h
            mov cx, 8
print_date_loop:
            mov al, [es:si]
            mov dl, al
            call print_char
            inc si
            loop print_date_loop

            mov dx, str_crlf
            mov ah, 09h
            int 21h

            ; Search F000:0000..FFFF for Award / AMI / Phoenix BIOS string
            mov dx, str_bios_vendor
            mov ah, 09h
            int 21h

            call find_bios_vendor
            ret

find_bios_vendor:
            ; Search for "Award"
            mov ax, 0F000h
            mov es, ax
            xor di, di
            mov cx, 0FFF0h
search_award:
            cmp dword [es:di], "Awar"
            je found_award
            inc di
            loop search_award

            ; Search for "AMI"
            xor di, di
            mov cx, 0FFF0h
search_ami:
            cmp dword [es:di], "Amer"
            je found_ami
            inc di
            loop search_ami

            mov dx, str_generic_bios
            mov ah, 09h
            int 21h
            ret

found_award:
            mov dx, str_award_bios
            mov ah, 09h
            int 21h
            ret

found_ami:
            mov dx, str_ami_bios
            mov ah, 09h
            int 21h
            ret

; ------------------------------------------------------------------------------
; Chipset Probing (PCI Bus 0, Dev 0, Func 0)
; ------------------------------------------------------------------------------
probe_chipset:
            mov dx, str_chipset_tag
            mov ah, 09h
            int 21h

            ; Read PCI 00:00.0 (Host Bridge)
            mov bh, 0
            mov bl, 0
            mov ah, 0
            call pci_read_dword

            cmp eax, 12508086h
            je cs_430hx
            cmp eax, 122D8086h
            je cs_430fx
            cmp eax, 70308086h
            je cs_430vx
            cmp eax, 71008086h
            je cs_430tx
            cmp eax, 71908086h
            je cs_440bx
            cmp eax, 71808086h
            je cs_440lx

            ; Generic display
            mov ax, [curr_vendor]
            call print_hex_word
            mov dl, ':'
            call print_char
            mov ax, [curr_device]
            call print_hex_word
            mov dx, str_crlf
            mov ah, 09h
            int 21h
            ret

cs_430hx:
            mov dx, str_cs_430hx
            mov ah, 09h
            int 21h
            ret
cs_430fx:
            mov dx, str_cs_430fx
            mov ah, 09h
            int 21h
            ret
cs_430vx:
            mov dx, str_cs_430vx
            mov ah, 09h
            int 21h
            ret
cs_430tx:
            mov dx, str_cs_430tx
            mov ah, 09h
            int 21h
            ret
cs_440bx:
            mov dx, str_cs_440bx
            mov ah, 09h
            int 21h
            ret
cs_440lx:
            mov dx, str_cs_440lx
            mov ah, 09h
            int 21h
            ret

; ==============================================================================
; Memory Probing Routines
; ==============================================================================
probe_memory:
            ; 1. Conventional Memory via INT 12h
            mov dx, str_mem_conv
            mov ah, 09h
            int 21h

            int 12h                     ; AX = KB of conventional memory
            call print_dec
            mov dx, str_kb_suffix
            mov ah, 09h
            int 21h

            ; 2. Extended Memory via INT 15h AH=88h
            mov dx, str_mem_ext
            mov ah, 09h
            int 21h

            mov ah, 88h
            int 15h                     ; AX = Extended memory in KB (above 1 MB)
            jc ext_mem_error
            cmp ax, 0
            je ext_mem_cmos

            mov [ext_mem_kb], ax
            call print_dec
            mov dx, str_kb_suffix
            mov ah, 09h
            int 21h

            ; Total RAM in MB
            mov dx, str_mem_total
            mov ah, 09h
            int 21h

            movzx eax, word [ext_mem_kb]
            add eax, 1024               ; Add lower 1 MB
            xor edx, edx
            mov ecx, 1024
            div ecx                     ; EAX = Total MB
            call print_dec
            mov dx, str_mb_suffix
            mov ah, 09h
            int 21h
            ret

ext_mem_cmos:
            ; Fallback: read CMOS reg 30h/31h
            mov al, 31h
            out 70h, al
            in al, 71h
            mov ah, al
            mov al, 30h
            out 70h, al
            in al, 71h
            call print_dec
            mov dx, str_kb_suffix
            mov ah, 09h
            int 21h
            ret

ext_mem_error:
            mov dx, str_mem_err
            mov ah, 09h
            int 21h
            ret

; ==============================================================================
; PCI Bus Probing Routines
; ==============================================================================
probe_pci:
            mov byte [scan_bus], 0
pci_bus_loop:
            mov byte [scan_dev], 0
pci_dev_loop:
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            mov bl, al
            mov ah, 0
            call pci_read_dword

            cmp ax, 0FFFFh
            je pci_next_dev
            cmp ax, 0000h
            je pci_next_dev

            ; Read Header Type
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            mov bl, al
            mov ah, 0Ch
            call pci_read_dword
            shr eax, 16
            mov [header_type], al

            mov byte [scan_func], 0
            call pci_print_func

            test byte [header_type], 80h
            jz pci_next_dev

            ; Multi-function device
            mov byte [scan_func], 1
pci_func_loop:
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            or al, [scan_func]
            mov bl, al
            mov ah, 0
            call pci_read_dword

            cmp ax, 0FFFFh
            je pci_next_func
            cmp ax, 0000h
            je pci_next_func

            call pci_print_func

pci_next_func:
            inc byte [scan_func]
            cmp byte [scan_func], 8
            jb pci_func_loop

pci_next_dev:
            inc byte [scan_dev]
            cmp byte [scan_dev], 32
            jb pci_dev_loop

            inc byte [scan_bus]
            cmp byte [scan_bus], 2
            jb pci_bus_loop
            ret

pci_print_func:
            ; Read Register 0 (Vendor & Device)
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            or al, [scan_func]
            mov bl, al
            mov ah, 0
            call pci_read_dword

            mov [curr_vendor], ax
            shr eax, 16
            mov [curr_device], ax

            ; Read IRQ
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            or al, [scan_func]
            mov bl, al
            mov ah, 3Ch
            call pci_read_dword
            mov [curr_irq], al

            ; Print: "    [00:00.0] 8086:1250 - "
            mov dx, str_indent4
            mov ah, 09h
            int 21h

            mov dl, '['
            call print_char
            mov al, [scan_bus]
            call print_hex_byte
            mov dl, ':'
            call print_char
            mov al, [scan_dev]
            call print_hex_byte
            mov dl, '.'
            call print_char
            mov al, [scan_func]
            add al, '0'
            mov dl, al
            call print_char
            mov dx, str_close_bracket
            mov ah, 09h
            int 21h

            mov ax, [curr_vendor]
            call print_hex_word
            mov dl, ':'
            call print_char
            mov ax, [curr_device]
            call print_hex_word
            mov dx, str_space
            mov ah, 09h
            int 21h

            ; Print Device Description
            call pci_lookup_desc

            ; Print IRQ if valid
            mov al, [curr_irq]
            cmp al, 0
            je pci_no_irq
            cmp al, 0FFh
            je pci_no_irq
            cmp al, 16
            jae pci_no_irq

            mov dx, str_irq_tag
            mov ah, 09h
            int 21h
            mov al, [curr_irq]
            mov ah, 0
            call print_dec
            mov dl, ']'
            call print_char

pci_no_irq:
            mov dx, str_crlf
            mov ah, 09h
            int 21h
            ret

pci_lookup_desc:
            cmp word [curr_vendor], 8086h
            je pci_intel
            cmp word [curr_vendor], 5333h
            je pci_s3
            mov dx, str_generic_pci
            mov ah, 09h
            int 21h
            ret

pci_intel:
            cmp word [curr_device], 1250h
            je pci_i430hx
            cmp word [curr_device], 7000h
            je pci_piix3_isa
            cmp word [curr_device], 7010h
            je pci_piix3_ide
            cmp word [curr_device], 7020h
            je pci_piix3_usb
            mov dx, str_intel_generic
            mov ah, 09h
            int 21h
            ret

pci_i430hx:
            mov dx, str_dev_430hx
            mov ah, 09h
            int 21h
            ret
pci_piix3_isa:
            mov dx, str_dev_piix3_isa
            mov ah, 09h
            int 21h
            ret
pci_piix3_ide:
            mov dx, str_dev_piix3_ide
            mov ah, 09h
            int 21h
            ret
pci_piix3_usb:
            mov dx, str_dev_piix3_usb
            mov ah, 09h
            int 21h
            ret

pci_s3:
            cmp word [curr_device], 8811h
            je pci_s3_trio64
            mov dx, str_s3_generic
            mov ah, 09h
            int 21h
            ret

pci_s3_trio64:
            mov dx, str_dev_s3_trio64
            mov ah, 09h
            int 21h
            ret

; ------------------------------------------------------------------------------
; Read PCI Dword via Mechanism #1
; Input:  BH = Bus, BL = (Dev << 3) | Func, AH = Reg (0-0xFC)
; Output: EAX = Dword
; ------------------------------------------------------------------------------
pci_read_dword:
            push edx
            push ebx
            push ecx

            mov cl, ah
            and cl, 0FCh

            movzx eax, bh
            shl eax, 16

            movzx edx, bl
            shl edx, 8
            or eax, edx

            movzx edx, cl
            or eax, edx

            or eax, 80000000h

            mov dx, 0CF8h
            out dx, eax
            mov dx, 0CFCh
            in eax, dx

            pop ecx
            pop ebx
            pop edx
            ret

; ==============================================================================
; Helper Output Routines
; ==============================================================================
print_char:
            push ax
            mov ah, 02h
            int 21h
            pop ax
            ret

print_hex_byte:
            push ax
            push bx
            mov bl, al
            shr al, 4
            call print_hex_nibble
            mov al, bl
            and al, 0Fh
            call print_hex_nibble
            pop bx
            pop ax
            ret

print_hex_nibble:
            cmp al, 10
            sbb al, 69h
            das
            mov dl, al
            call print_char
            ret

print_hex_word:
            push ax
            xchg al, ah
            call print_hex_byte
            xchg al, ah
            call print_hex_byte
            pop ax
            ret

print_dec:
            push ax
            push bx
            push cx
            push dx
            xor cx, cx
            mov bx, 10
dec_div:
            xor dx, dx
            div bx
            push dx
            inc cx
            test ax, ax
            jnz dec_div
dec_print:
            pop dx
            add dl, '0'
            call print_char
            loop dec_print
            pop dx
            pop cx
            pop bx
            pop ax
            ret

; ==============================================================================
; Constant Strings
; ==============================================================================
msg_header  db 0Dh, 0Ah
            db "==================================================================", 0Dh, 0Ah
            db "  InquiBench System & Hardware Interrogator v1.0                  ", 0Dh, 0Ah
            db "  Inspired by SpeedSys / Automated Retro Hardware Profiler        ", 0Dh, 0Ah
            db "==================================================================", 0Dh, 0Ah, "$"

msg_sec_cpu db 0Dh, 0Ah, "[1. PROCESSOR ARCHITECTURE]", 0Dh, 0Ah, "$"
msg_sec_mb  db 0Dh, 0Ah, "[2. MOTHERBOARD & BIOS]", 0Dh, 0Ah, "$"
msg_sec_mem db 0Dh, 0Ah, "[3. MEMORY SUBSYSTEM]", 0Dh, 0Ah, "$"
msg_sec_pci db 0Dh, 0Ah, "[4. PCI BUS TOPOLOGY]", 0Dh, 0Ah, "$"

msg_footer  db "==================================================================", 0Dh, 0Ah
            db "[+] Hardware scan completed successfully.", 0Dh, 0Ah, 0Dh, 0Ah, "$"

msg_no_386  db "[-] Error: 80386 or higher CPU required.", 0Dh, 0Ah, "$"

str_cpu_vendor  db "    Vendor:         ", "$"
str_cpu_model   db "    CPU Model:      ", "$"
str_cpu_fms     db "    Stepping Info:  Family ", "$"
str_fms_model   db ", Model ", "$"
str_fms_step    db ", Stepping ", "$"
str_cpu_feats   db "    Features:      ", "$"
str_cpu_freq    db "    Clock Speed:    ", "$"
str_mhz_suffix  db " MHz (measured via RDTSC & PIT)", 0Dh, 0Ah, "$"

str_cpu_no_cpuid db "    CPU:            80386 / 80486 (No CPUID)", 0Dh, 0Ah, "$"
str_cpu_no_tsc   db "    Clock:          No TSC (Time Stamp Counter)", 0Dh, 0Ah, "$"

str_p54c        db "Intel Pentium (P54C)", 0Dh, 0Ah, "$"
str_p55c        db "Intel Pentium MMX (P55C)", 0Dh, 0Ah, "$"
str_i486        db "Intel 486 Series", 0Dh, 0Ah, "$"
str_p6          db "Intel P6 Architecture (Pentium Pro / II)", 0Dh, 0Ah, "$"
str_intel_cpu   db "Intel x86 Processor", 0Dh, 0Ah, "$"
str_amd_cpu     db "AMD K5/K6 Processor", 0Dh, 0Ah, "$"
str_unknown_cpu db "x86 Compatible Processor", 0Dh, 0Ah, "$"

str_fpu         db " FPU", "$"
str_vme         db " VME", "$"
str_tsc         db " TSC", "$"
str_msr         db " MSR", "$"
str_cx8         db " CMPXCHG8B", "$"
str_mmx         db " MMX", "$"

str_bios_date   db "    BIOS Date:      ", "$"
str_bios_vendor db "    BIOS Type:      ", "$"
str_award_bios  db "Award Modular BIOS v4.51PG", 0Dh, 0Ah, "$"
str_ami_bios    db "AMI (American Megatrends) BIOS", 0Dh, 0Ah, "$"
str_generic_bios db "Standard PC Compatible BIOS", 0Dh, 0Ah, "$"

str_chipset_tag db "    Chipset:        ", "$"
str_cs_430hx    db "Intel 82430HX (Triton II / 430HX)", 0Dh, 0Ah, "$"
str_cs_430fx    db "Intel 82430FX (Triton / 430FX)", 0Dh, 0Ah, "$"
str_cs_430vx    db "Intel 82430VX (Triton II / 430VX)", 0Dh, 0Ah, "$"
str_cs_430tx    db "Intel 82430TX (Triton II / 430TX)", 0Dh, 0Ah, "$"
str_cs_440bx    db "Intel 82440BX (Seattle / 440BX)", 0Dh, 0Ah, "$"
str_cs_440lx    db "Intel 82440LX (440LX)", 0Dh, 0Ah, "$"

str_mem_conv    db "    Conventional:   ", "$"
str_mem_ext     db "    Extended:       ", "$"
str_mem_total   db "    Total Memory:   ", "$"
str_kb_suffix   db " KB", 0Dh, 0Ah, "$"
str_mb_suffix   db " MB", 0Dh, 0Ah, "$"
str_mem_err     db "Error reading extended memory", 0Dh, 0Ah, "$"

str_indent4     db "    ", "$"
str_close_bracket db "] ", "$"
str_space       db " - ", "$"
str_crlf        db 0Dh, 0Ah, "$"
str_irq_tag     db " [IRQ: ", "$"

str_dev_430hx       db "Intel 82439HX Host/PCI Bridge", "$"
str_dev_piix3_isa   db "Intel 82371SB (PIIX3) PCI-to-ISA Bridge", "$"
str_dev_piix3_ide   db "Intel 82371SB (PIIX3) Bus-Master IDE Controller", "$"
str_dev_piix3_usb   db "Intel 82371SB (PIIX3) USB UHCI Controller", "$"
str_intel_generic   db "Intel PCI Device", "$"
str_dev_s3_trio64   db "S3 Trio64 / Trio32 (86C764/765) PCI Video", "$"
str_s3_generic      db "S3 Graphics Device", "$"
str_generic_pci     db "PCI Device", "$"

; ==============================================================================
; Uninitialized Variables
; ==============================================================================
max_cpuid       dd 0
cpu_vendor      times 16 db 0
cpu_signature   dd 0
cpu_features    dd 0
ext_mem_kb      dw 0

scan_bus        db 0
scan_dev        db 0
scan_func       db 0
header_type     db 0
curr_vendor     dw 0
curr_device     dw 0
curr_irq        db 0
