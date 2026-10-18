; ==============================================================================
; INQUIBEN.ASM - InquiBench DOS Hardware Interrogator & Benchmark Agent
; Target: MS-DOS 6.22 / DOS 7.1 / Win98 DOS (8086/80386 compatible)
; Assembler: NASM (generates standalone 16-bit .COM executable)
; COM1: I/O Base 0x3F8, 115200 bps, 8N1
; ==============================================================================

            org 100h
            bits 16

start:
            ; Shrink memory block allocated to this .COM program
            ; so that child processes (COMMAND.COM ...) have free RAM
            mov bx, 1000h               ; 64 KB (4096 paragraphs)
            mov ah, 4Ah
            int 21h

            ; Display banner on local screen
            mov dx, msg_banner
            mov ah, 09h
            int 21h

            ; Initialize COM1 UART
            call init_uart

            mov dx, msg_ready
            mov ah, 09h
            int 21h

main_loop:
            ; Check local keyboard for ESC
            mov ah, 01h
            int 16h
            jz wait_for_frame
            mov ah, 00h
            int 16h
            cmp al, 27                  ; ESC key
            je exit_to_dos

wait_for_frame:
            ; Check if byte available on COM1
            call check_rx
            jz main_loop

            ; Read sync byte 1 (0x55)
            call read_byte
            cmp al, 55h
            jne main_loop

            ; Read sync byte 2 (0xAA)
            call read_byte
            cmp al, 0AAh
            jne main_loop

            ; Read CMD byte
            call read_byte
            mov [cmd_byte], al

            ; Read Length (2 bytes, little-endian)
            call read_byte
            mov [payload_len], al
            call read_byte
            mov [payload_len + 1], al

            ; Read Payload into buffer
            mov cx, [payload_len]
            mov di, payload_buf
read_payload_loop:
            jcxz payload_done
            call read_byte
            mov [di], al
            inc di
            dec cx
            jmp read_payload_loop
payload_done:
            mov byte [di], 0            ; Null-terminate for safety

            ; Dispatch command
            mov al, [cmd_byte]

            cmp al, 01h                 ; CMD_PING
            je do_ping

            cmp al, 02h                 ; CMD_EXEC
            je do_exec

            cmp al, 03h                 ; CMD_READ_SCREEN
            je do_screen

            cmp al, 04h                 ; CMD_SEND_KEY
            je do_key

            cmp al, 05h                 ; CMD_PUT_FILE
            je do_put_file

            cmp al, 0FFh                ; CMD_QUIT
            je exit_to_dos

            ; Unknown command, send error ACK
            mov al, 0E0h                ; ACK_ERR
            xor cx, cx
            call send_frame
            jmp main_loop

; ------------------------------------------------------------------------------
; CMD Handlers
; ------------------------------------------------------------------------------

; PING -> PONG response (0x81)
do_ping:
            mov si, msg_pong
            call strlen                 ; AX = length
            mov cx, ax
            mov di, payload_buf
            mov si, msg_pong
            rep movsb
            mov al, 81h                 ; ACK_PONG
            mov cx, ax
            call send_frame
            jmp main_loop

; READ_SCREEN -> Dumps 4000 bytes of text video RAM (0xB800:0000)
do_screen:
            push es
            push ds
            mov ax, 0B800h
            mov ds, ax
            xor si, si                  ; DS:SI -> B800:0000
            mov ax, cs
            mov es, ax
            mov di, screen_buf          ; ES:DI -> screen_buf
            mov cx, 2000                ; 2000 words = 4000 bytes
            rep movsw
            pop ds
            pop es

            call send_sync
            mov al, 83h                 ; ACK_SCREEN
            call send_byte
            mov ax, 4000
            call send_word

            mov si, screen_buf
            mov cx, 4000
send_screen_loop:
            lodsb
            call send_byte
            loop send_screen_loop

            jmp main_loop

; SEND_KEY -> Injects keystroke into BIOS keyboard buffer
; Payload: 2 bytes [ASCII, SCANCODE]
do_key:
            mov al, [payload_buf]       ; ASCII
            mov ah, [payload_buf + 1]   ; SCANCODE
            mov ch, ah
            mov cl, al
            mov ah, 05h                 ; BIOS write to keyboard buffer
            int 16h

            mov al, 80h                 ; ACK_OK
            xor cx, cx
            call send_frame
            jmp main_loop

; EXEC -> Creates D:\RUN.BAT and runs it via COMMAND.COM /C D:\RUN.BAT
do_exec:
            ; Delete any previous D:\OUT.TMP
            mov ah, 41h
            mov dx, out_filename
            int 21h

            ; Create D:\RUN.BAT
            mov ah, 3Ch
            xor cx, cx
            mov dx, bat_filename
            int 21h
            jc exec_failed
            mov [file_handle], ax

            ; Write command from payload_buf
            mov si, payload_buf
            call strlen
            mov cx, ax
            mov ah, 40h
            mov bx, [file_handle]
            mov dx, payload_buf
            int 21h

            ; Write redirection: " > D:\OUT.TMP\r\n"
            mov ah, 40h
            mov bx, [file_handle]
            mov cx, str_redir_len
            mov dx, str_redir
            int 21h

            ; Close D:\RUN.BAT
            mov ah, 3Eh
            mov bx, [file_handle]
            int 21h

            ; Set up EXEC parameter block
            mov word [exec_param_block], 0        ; Inherit environment
            mov word [exec_param_block + 2], cmd_tail
            mov word [exec_param_block + 4], cs
            mov word [exec_param_block + 6], 5Ch  ; Default FCB 1 in PSP
            mov word [exec_param_block + 8], cs
            mov word [exec_param_block + 10], 6Ch ; Default FCB 2 in PSP
            mov word [exec_param_block + 12], cs

            ; Save stack
            mov [saved_sp], sp
            mov [saved_ss], ss

            ; Execute COMMAND.COM /C D:\RUN.BAT
            mov dx, comspec_str
            mov bx, exec_param_block
            mov ax, 4B00h
            int 21h

            ; Restore stack
            mov ss, [saved_ss]
            mov sp, [saved_sp]

            ; Read back D:\OUT.TMP and send over serial
            call send_out_file
            jmp main_loop

exec_failed:
            mov al, 0E2h                ; ERR_EXEC
            xor cx, cx
            call send_frame
            jmp main_loop

; PUT_FILE -> Creates/writes file to disk
do_put_file:
            mov si, payload_buf
find_null:
            lodsb
            test al, al
            jnz find_null

            ; SI now points to file data
            mov dx, payload_buf         ; Filename
            mov bx, si                  ; Data ptr

            mov ax, si
            sub ax, payload_buf
            mov cx, [payload_len]
            sub cx, ax
            mov [temp_size], cx

            ; Create / overwrite file
            mov ah, 3Ch
            xor cx, cx
            int 21h
            jc put_file_err
            mov [file_handle], ax

            ; Write data
            mov ah, 40h
            mov bx, [file_handle]
            mov cx, [temp_size]
            mov dx, si
            int 21h

            ; Close file
            mov ah, 3Eh
            mov bx, [file_handle]
            int 21h

            mov al, 80h                 ; ACK_OK
            xor cx, cx
            call send_frame
            jmp main_loop

put_file_err:
            mov al, 0E1h                ; ERR_FILE
            xor cx, cx
            call send_frame
            jmp main_loop

; ------------------------------------------------------------------------------
; Helper Functions
; ------------------------------------------------------------------------------

send_out_file:
            ; Open D:\OUT.TMP
            mov dx, out_filename
            mov ax, 3D00h               ; Read-only
            int 21h
            jc out_open_failed
            mov [file_handle], ax

            ; Read up to 8000 bytes into payload_buf
            mov ah, 3Fh
            mov bx, [file_handle]
            mov cx, 8000
            mov dx, payload_buf
            int 21h
            mov [payload_len], ax

            ; Close file
            mov ah, 3Eh
            mov bx, [file_handle]
            int 21h

            ; Delete D:\OUT.TMP
            mov ah, 41h
            mov dx, out_filename
            int 21h

            ; Send ACK_EXEC (0x82) with file output
            mov al, 82h
            mov cx, [payload_len]
            call send_frame
            ret

out_open_failed:
            mov al, 82h
            xor cx, cx
            call send_frame
            ret

; Send frame: AL = CMD, CX = Payload length, payload at payload_buf
send_frame:
            push cx                     ; Save length
            push ax                     ; Save CMD

            call send_sync              ; Sends 0x55, 0xAA

            pop ax                      ; Restore CMD
            call send_byte              ; Transmit CMD

            pop cx                      ; Restore length
            mov ax, cx
            call send_word              ; Transmit length

            jcxz .done
            mov si, payload_buf
.send_loop:
            lodsb
            call send_byte
            loop .send_loop
.done:
            ret

send_sync:
            push ax
            mov al, 55h
            call send_byte
            mov al, 0AAh
            call send_byte
            pop ax
            ret

send_word:
            push ax
            call send_byte              ; Low byte
            pop ax
            mov al, ah
            call send_byte              ; High byte
            ret

strlen:
            push si
            xor ax, ax
strlen_loop:
            cmp byte [si], 0
            je strlen_done
            inc si
            inc ax
            jmp strlen_loop
strlen_done:
            pop si
            ret

; ------------------------------------------------------------------------------
; UART 16550A Routines (COM1 = 0x3F8)
; ------------------------------------------------------------------------------

COM1_BASE   equ 3F8h
UART_RBR    equ COM1_BASE + 0
UART_THR    equ COM1_BASE + 0
UART_DLL    equ COM1_BASE + 0
UART_DLM    equ COM1_BASE + 1
UART_IER    equ COM1_BASE + 1
UART_FCR    equ COM1_BASE + 2
UART_LCR    equ COM1_BASE + 3
UART_MCR    equ COM1_BASE + 4
UART_LSR    equ COM1_BASE + 5

init_uart:
            mov dx, UART_IER
            xor al, al
            out dx, al

            ; DLAB = 1
            mov dx, UART_LCR
            mov al, 80h
            out dx, al

            ; Baud rate 115200: Divisor = 1
            mov dx, UART_DLL
            mov al, 01h
            out dx, al
            mov dx, UART_DLM
            xor al, al
            out dx, al

            ; 8N1
            mov dx, UART_LCR
            mov al, 03h
            out dx, al

            ; Enable FIFO, clear buffers
            mov dx, UART_FCR
            mov al, 0C7h
            out dx, al

            ; DTR, RTS, OUT2
            mov dx, UART_MCR
            mov al, 0Bh
            out dx, al
            ret

check_rx:
            mov dx, UART_LSR
            in al, dx
            test al, 01h
            ret

; Read byte with continuous ESC key checking so daemon NEVER hangs
read_byte:
            push dx
.read_wait:
            ; Check if ESC was pressed locally on keyboard
            mov ah, 01h
            int 16h
            jz .test_uart
            mov ah, 00h
            int 16h
            cmp al, 27                  ; ESC key
            je exit_to_dos

.test_uart:
            mov dx, UART_LSR
            in al, dx
            test al, 01h
            jz .read_wait

            mov dx, UART_RBR
            in al, dx
            pop dx
            ret

send_byte:
            push dx
            push ax
            mov ah, al
.send_wait:
            mov dx, UART_LSR
            in al, dx
            test al, 20h
            jz .send_wait
            mov dx, UART_THR
            mov al, ah
            out dx, al
            pop ax
            pop dx
            ret

exit_to_dos:
            mov dx, msg_exit
            mov ah, 09h
            int 21h
            mov ax, 4C00h
            int 21h

; ------------------------------------------------------------------------------
; Initialized Data Section
; ------------------------------------------------------------------------------

msg_banner  db 0Dh, 0Ah
            db "==============================================", 0Dh, 0Ah
            db "  InquiBench v1.2 - Retro Hardware Agent     ", 0Dh, 0Ah
            db "  COM1: 115200 bps, 8N1 | (Press ESC to exit) ", 0Dh, 0Ah
            db "==============================================", 0Dh, 0Ah, "$"

msg_ready   db "[+] InquiBench active and listening on COM1...", 0Dh, 0Ah, "$"
msg_exit    db 0Dh, 0Ah, "[*] Exiting InquiBench. Returning to DOS.", 0Dh, 0Ah, "$"
msg_pong    db "PONG: InquiBench DOS Agent Active (MS-DOS 6.22 / 86Box)", 0

comspec_str db "C:\DOS\COMMAND.COM", 0
bat_filename db "D:\RUN.BAT", 0
out_filename db "D:\OUT.TMP", 0

str_redir   db " > D:\OUT.TMP", 0Dh, 0Ah
str_redir_len equ $ - str_redir

; Command line tail for COMMAND.COM: " /C D:\RUN.BAT" + CR
cmd_tail    db 15, " /C D:\RUN.BAT", 0Dh

cmd_byte    db 0
payload_len dw 0
temp_size   dw 0
file_handle dw 0
saved_sp    dw 0
saved_ss    dw 0

exec_param_block times 14 db 0

; ------------------------------------------------------------------------------
; Uninitialized Data (BSS)
; ------------------------------------------------------------------------------
section .bss
payload_buf resb 8192
screen_buf  resb 4096
