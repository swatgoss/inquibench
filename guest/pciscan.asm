; ==============================================================================
; PCISCAN.ASM - InquiBench PCI Bus Topology Scanner
; Target: MS-DOS 6.22 / FreeDOS 1.4 / DOS 7.1 / Win98 DOS (80386+)
; Assembler: NASM (generates standalone 16-bit .COM executable)
; Mechanism: PCI Configuration Mechanism #1 (I/O 0xCF8 / 0xCFC)
; ==============================================================================

            org 100h
            bits 16

start:
            ; Check if 386+ CPU present
            pushf
            pop ax
            and ax, 0FFFh
            push ax
            popf
            pushf
            pop ax
            and ax, 0F000h
            cmp ax, 0F000h
            je cpu_too_old

            ; Display banner
            mov dx, msg_header
            mov ah, 09h
            int 21h

            ; Test PCI Configuration Mechanism #1
            ; Probe Bus 0, Dev 0, Func 0, Reg 0
            mov bh, 0
            mov bl, 0
            mov ah, 0
            call pci_read_dword
            cmp eax, 0FFFFFFFFh
            je check_pci_bios
            cmp ax, 0FFFFh
            je check_pci_bios

            mov dx, msg_mech1
            mov ah, 09h
            int 21h
            jmp start_scan

check_pci_bios:
            mov ax, 0B101h
            int 1Ah
            jc no_pci
            cmp ah, 0
            jne no_pci
            cmp edx, " PCI"
            jne no_pci

            mov dx, msg_bios
            mov ah, 09h
            int 21h

start_scan:
            mov word [dev_count], 0
            mov byte [scan_bus], 0

bus_loop:
            mov byte [scan_dev], 0

dev_loop:
            ; Check function 0 first
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3                   ; AL = (dev << 3) | 0
            mov bl, al
            mov ah, 0                   ; Reg 0 (Vendor/Device ID)
            call pci_read_dword

            cmp ax, 0FFFFh
            je next_dev
            cmp ax, 0000h
            je next_dev

            ; Read Header Type (Reg 0x0C, byte 2)
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            mov bl, al
            mov ah, 0Ch
            call pci_read_dword
            shr eax, 16
            mov [header_type], al       ; AL = Header Type

            ; Process function 0
            mov byte [scan_func], 0
            call process_function

            ; If bit 7 of Header Type is 0 -> Single-function device
            test byte [header_type], 80h
            jz next_dev

            ; Multi-function device: scan functions 1 to 7
            mov byte [scan_func], 1
func_loop:
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            or al, [scan_func]
            mov bl, al
            mov ah, 0
            call pci_read_dword

            cmp ax, 0FFFFh
            je next_func
            cmp ax, 0000h
            je next_func

            call process_function

next_func:
            inc byte [scan_func]
            cmp byte [scan_func], 8
            jb func_loop

next_dev:
            inc byte [scan_dev]
            cmp byte [scan_dev], 32
            jb dev_loop

            inc byte [scan_bus]
            cmp byte [scan_bus], 2       ; Scan Bus 0 and Bus 1
            jb bus_loop

            ; Summary
            mov dx, msg_summary
            mov ah, 09h
            int 21h

            mov ax, [dev_count]
            call print_dec
            mov dx, msg_found
            mov ah, 09h
            int 21h

            ret

cpu_too_old:
            mov dx, msg_err_cpu
            mov ah, 09h
            int 21h
            ret

no_pci:
            mov dx, msg_no_pci
            mov ah, 09h
            int 21h
            ret

; ------------------------------------------------------------------------------
; Process and print a single detected PCI function
; ------------------------------------------------------------------------------
process_function:
            inc word [dev_count]

            ; Read Vendor & Device ID (Reg 0)
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

            ; Read Revision & Class Code (Reg 8)
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            or al, [scan_func]
            mov bl, al
            mov ah, 8
            call pci_read_dword
            mov [curr_rev], al
            shr eax, 8
            mov [curr_progif], al
            shr eax, 8
            mov [curr_subclass], al
            shr eax, 8
            mov [curr_baseclass], al

            ; Read IRQ & Interrupt Pin (Reg 0x3C)
            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            or al, [scan_func]
            mov bl, al
            mov ah, 3Ch
            call pci_read_dword
            mov [curr_irq], al
            shr eax, 8
            mov [curr_intpin], al

            ; Print: "[BB:DD.F] "
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

            ; Print: "8086:7000 "
            mov ax, [curr_vendor]
            call print_hex_word
            mov dl, ':'
            call print_char
            mov ax, [curr_device]
            call print_hex_word

            ; Print Class Code: " [0600] "
            mov dx, str_class_bracket_open
            mov ah, 09h
            int 21h
            mov al, [curr_baseclass]
            call print_hex_byte
            mov al, [curr_subclass]
            call print_hex_byte
            mov dx, str_class_bracket_close
            mov ah, 09h
            int 21h

            ; Print Revision: "(rev 03) - "
            mov dx, str_rev_open
            mov ah, 09h
            int 21h
            mov al, [curr_rev]
            call print_hex_byte
            mov dx, str_rev_close
            mov ah, 09h
            int 21h

            ; Print Name or Class Description
            call print_device_desc

            ; Print IRQ if valid (1-15)
            mov al, [curr_irq]
            cmp al, 0
            je no_irq
            cmp al, 0FFh
            je no_irq
            cmp al, 16
            jae no_irq

            mov dx, str_irq_tag
            mov ah, 09h
            int 21h
            mov al, [curr_irq]
            mov ah, 0
            call print_dec
            mov dl, ']'
            call print_char

no_irq:
            mov dx, str_crlf
            mov ah, 09h
            int 21h

            ; Print BARs if applicable (skip Host Bridge to avoid confusion)
            cmp byte [curr_baseclass], 06h
            je skip_bars                ; Bridge device (Host/ISA)

            call print_bars

skip_bars:
            ret

; ------------------------------------------------------------------------------
; Print Base Address Registers (BAR0 to BAR5)
; ------------------------------------------------------------------------------
print_bars:
            mov byte [bar_idx], 0
bar_loop:
            mov al, [bar_idx]
            shl al, 2
            add al, 10h                 ; Reg = 0x10 + idx*4
            mov ah, al

            mov bh, [scan_bus]
            mov al, [scan_dev]
            shl al, 3
            or al, [scan_func]
            mov bl, al
            call pci_read_dword
            mov [curr_bar], eax

            ; Skip empty / disabled BARs
            cmp eax, 0
            je next_bar
            cmp eax, 0FFFFFFFFh
            je next_bar

            ; Print "       BARx: "
            mov dx, str_bar_prefix
            mov ah, 09h
            int 21h
            mov al, [bar_idx]
            add al, '0'
            mov dl, al
            call print_char
            mov dx, str_bar_colon
            mov ah, 09h
            int 21h

            mov eax, [curr_bar]
            call print_hex_dword

            mov eax, [curr_bar]
            test al, 1
            jnz bar_io

            mov dx, str_bar_mem
            mov ah, 09h
            int 21h
            jmp bar_crlf

bar_io:
            mov dx, str_bar_io
            mov ah, 09h
            int 21h

bar_crlf:
            mov dx, str_crlf
            mov ah, 09h
            int 21h

next_bar:
            inc byte [bar_idx]
            cmp byte [bar_idx], 6
            jb bar_loop
            ret

; ------------------------------------------------------------------------------
; Device Description Lookup
; ------------------------------------------------------------------------------
print_device_desc:
            cmp word [curr_vendor], 8086h
            je match_intel
            cmp word [curr_vendor], 5333h
            je match_s3
            cmp word [curr_vendor], 10ECh
            je match_realtek
            cmp word [curr_vendor], 10B7h
            je match_3com
            cmp word [curr_vendor], 1039h
            je match_sis
            jmp print_class_name

match_intel:
            cmp word [curr_device], 1250h
            je desc_i430hx
            cmp word [curr_device], 7000h
            je desc_piix3_isa
            cmp word [curr_device], 7010h
            je desc_piix3_ide
            cmp word [curr_device], 7020h
            je desc_piix3_usb
            cmp word [curr_device], 7110h
            je desc_piix4_isa
            cmp word [curr_device], 7111h
            je desc_piix4_ide
            cmp word [curr_device], 7112h
            je desc_piix4_usb
            mov dx, str_intel_generic
            mov ah, 09h
            int 21h
            jmp print_class_name

desc_i430hx:
            mov dx, str_dev_430hx
            mov ah, 09h
            int 21h
            ret
desc_piix3_isa:
            mov dx, str_dev_piix3_isa
            mov ah, 09h
            int 21h
            ret
desc_piix3_ide:
            mov dx, str_dev_piix3_ide
            mov ah, 09h
            int 21h
            ret
desc_piix3_usb:
            mov dx, str_dev_piix3_usb
            mov ah, 09h
            int 21h
            ret
desc_piix4_isa:
            mov dx, str_dev_piix4_isa
            mov ah, 09h
            int 21h
            ret
desc_piix4_ide:
            mov dx, str_dev_piix4_ide
            mov ah, 09h
            int 21h
            ret
desc_piix4_usb:
            mov dx, str_dev_piix4_usb
            mov ah, 09h
            int 21h
            ret

match_s3:
            cmp word [curr_device], 8811h
            je desc_s3_trio64
            cmp word [curr_device], 8812h
            je desc_s3_aurora
            cmp word [curr_device], 8901h
            je desc_s3_trio64v2
            cmp word [curr_device], 88C0h
            je desc_s3_virge
            mov dx, str_s3_generic
            mov ah, 09h
            int 21h
            jmp print_class_name

desc_s3_trio64:
            mov dx, str_dev_s3_trio64
            mov ah, 09h
            int 21h
            ret
desc_s3_aurora:
            mov dx, str_dev_s3_aurora
            mov ah, 09h
            int 21h
            ret
desc_s3_trio64v2:
            mov dx, str_dev_s3_trio64v2
            mov ah, 09h
            int 21h
            ret
desc_s3_virge:
            mov dx, str_dev_s3_virge
            mov ah, 09h
            int 21h
            ret

match_realtek:
            mov dx, str_dev_realtek
            mov ah, 09h
            int 21h
            ret
match_3com:
            mov dx, str_dev_3com
            mov ah, 09h
            int 21h
            ret
match_sis:
            mov dx, str_dev_sis
            mov ah, 09h
            int 21h
            ret

print_class_name:
            mov al, [curr_baseclass]
            cmp al, 00h
            je cls_pre20
            cmp al, 01h
            je cls_storage
            cmp al, 02h
            je cls_net
            cmp al, 03h
            je cls_display
            cmp al, 04h
            je cls_media
            cmp al, 05h
            je cls_mem
            cmp al, 06h
            je cls_bridge
            cmp al, 0Ch
            je cls_serial
            mov dx, str_cls_unknown
            mov ah, 09h
            int 21h
            ret

cls_pre20:
            mov dx, str_cls_pre20
            mov ah, 09h
            int 21h
            ret
cls_storage:
            mov dx, str_cls_storage
            mov ah, 09h
            int 21h
            ret
cls_net:
            mov dx, str_cls_net
            mov ah, 09h
            int 21h
            ret
cls_display:
            mov dx, str_cls_display
            mov ah, 09h
            int 21h
            ret
cls_media:
            mov dx, str_cls_media
            mov ah, 09h
            int 21h
            ret
cls_mem:
            mov dx, str_cls_mem
            mov ah, 09h
            int 21h
            ret
cls_bridge:
            mov dx, str_cls_bridge
            mov ah, 09h
            int 21h
            ret
cls_serial:
            mov dx, str_cls_serial
            mov ah, 09h
            int 21h
            ret

; ------------------------------------------------------------------------------
; Read PCI Dword via Mechanism #1
; Input:  BH = Bus, BL = (Dev << 3) | Func, AH = Register (0-0xFC)
; Output: EAX = 32-bit Configuration Dword
; Preserves all other registers
; ------------------------------------------------------------------------------
pci_read_dword:
            push edx
            push ebx
            push ecx

            ; Save register offset in CL before touching EAX
            mov cl, ah
            and cl, 0FCh

            ; EAX = 80000000h | (bus << 16) | (dev_func << 8) | reg
            movzx eax, bh
            shl eax, 16

            movzx edx, bl
            shl edx, 8
            or eax, edx

            movzx edx, cl
            or eax, edx

            or eax, 80000000h           ; Bit 31: Enable

            mov dx, 0CF8h
            out dx, eax

            mov dx, 0CFCh
            in eax, dx

            pop ecx
            pop ebx
            pop edx
            ret

; ------------------------------------------------------------------------------
; Formatting & Printing Helpers
; ------------------------------------------------------------------------------
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

print_hex_dword:
            push eax
            shr eax, 16
            call print_hex_word
            pop eax
            push eax
            call print_hex_word
            pop eax
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

; ------------------------------------------------------------------------------
; Constant Strings
; ------------------------------------------------------------------------------
msg_header  db 0Dh, 0Ah
            db "==================================================================", 0Dh, 0Ah
            db "  InquiBench - PCI Bus Topology Scanner (MS-DOS)                  ", 0Dh, 0Ah
            db "  Interrogating PCI configuration space (Mechanism #1)...          ", 0Dh, 0Ah
            db "==================================================================", 0Dh, 0Ah, "$"

msg_mech1   db "[+] PCI Configuration Mechanism #1 detected.", 0Dh, 0Ah
            db "------------------------------------------------------------------", 0Dh, 0Ah, "$"

msg_bios    db "[+] PCI BIOS detected via INT 1Ah.", 0Dh, 0Ah
            db "------------------------------------------------------------------", 0Dh, 0Ah, "$"

msg_summary db "------------------------------------------------------------------", 0Dh, 0Ah
            db "[+] Scan Complete. Total PCI Functions Found: ", "$"
msg_found   db 0Dh, 0Ah, 0Dh, 0Ah, "$"

msg_err_cpu db "[-] Error: 80386 or higher CPU required.", 0Dh, 0Ah, "$"
msg_no_pci  db "[-] Error: No PCI bus detected on this system.", 0Dh, 0Ah, "$"

str_close_bracket db "] ", "$"
str_space   db " - ", "$"
str_crlf    db 0Dh, 0Ah, "$"
str_irq_tag db " [IRQ: ", "$"

str_class_bracket_open  db " [", "$"
str_class_bracket_close db "] ", "$"
str_rev_open            db "(rev ", "$"
str_rev_close           db ") - ", "$"

str_bar_prefix db "       BAR", "$"
str_bar_colon  db ": ", "$"
str_bar_mem    db " (Memory Mapped)", "$"
str_bar_io     db " (I/O Ports)", "$"

str_dev_430hx       db "Intel 82439HX (TXC) Host/PCI Bridge", "$"
str_dev_piix3_isa   db "Intel 82371SB (PIIX3) PCI-to-ISA Bridge", "$"
str_dev_piix3_ide   db "Intel 82371SB (PIIX3) Bus-Master IDE Controller", "$"
str_dev_piix3_usb   db "Intel 82371SB (PIIX3) USB UHCI Controller", "$"
str_dev_piix4_isa   db "Intel 82371AB/EB (PIIX4) PCI-to-ISA Bridge", "$"
str_dev_piix4_ide   db "Intel 82371AB/EB (PIIX4) IDE Controller", "$"
str_dev_piix4_usb   db "Intel 82371AB/EB (PIIX4) USB Controller", "$"
str_intel_generic   db "Intel Device ", "$"

str_dev_s3_trio64   db "S3 Trio64 / Trio32 (86C764/765) PCI Video", "$"
str_dev_s3_aurora   db "S3 Aurora64V+ PCI Video", "$"
str_dev_s3_trio64v2 db "S3 Trio64V2/DX PCI Video", "$"
str_dev_s3_virge    db "S3 ViRGE 3D Video Controller", "$"
str_s3_generic      db "S3 Graphics Device ", "$"

str_dev_realtek     db "Realtek Ethernet Controller", "$"
str_dev_3com        db "3Com Ethernet Adapter", "$"
str_dev_sis         db "SiS Chipset Controller", "$"

str_cls_pre20       db "Legacy / Pre-PCI 2.0 Device", "$"
str_cls_storage     db "Mass Storage Controller", "$"
str_cls_net         db "Network Controller", "$"
str_cls_display     db "Display Controller", "$"
str_cls_media       db "Multimedia / Audio Device", "$"
str_cls_mem         db "Memory Controller", "$"
str_cls_bridge      db "Bridge Device", "$"
str_cls_serial      db "Serial Bus Controller (USB)", "$"
str_cls_unknown     db "PCI Device", "$"

; ------------------------------------------------------------------------------
; Variables
; ------------------------------------------------------------------------------
scan_bus    db 0
scan_dev    db 0
scan_func   db 0
bar_idx     db 0

curr_vendor dw 0
curr_device dw 0
curr_rev    db 0
curr_progif db 0
curr_subclass db 0
curr_baseclass db 0
curr_irq    db 0
curr_intpin db 0
header_type db 0
dev_count   dw 0
curr_bar    dd 0
