; PC-98 normal/high-resolution DOS .COM. NASM; strictly 8086 instructions.
bits 16
cpu 8086
org 100h

    jmp start
; Test tools locate this small public symbol directory in the actual binary.
db 'ROTO98SYM'
dw frame, du, dv, row_u, row_v, texture, transforms, stack_bottom, program_end

start:
    cld
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    sti
    mov ds, ax
    mov es, ax
    ; /S single page, /T 16 frames, /M mute, /P 2-phrase music preview, /? help.
    xor cx, cx
    mov cl, [80h]
    mov si, 81h
.args:
    jcxz .init
    lodsb
    cmp al, '?'
    jne .not_help
    jmp help
.not_help:
    cmp al, '2'
    jne .eight_arg
    mov byte [want256], 1
.eight_arg:
    cmp al, '8'
    jne .letter_arg
    mov byte [want256], 0
.letter_arg:
    and al, 0dfh
    cmp al, 'S'
    jne .test_arg
    mov byte [single_page], 1
.test_arg:
    cmp al, 'M'
    jne .preview_arg
    mov byte [sound_muted], 1
.preview_arg:
    cmp al, 'P'
    jne .short_arg
    mov word [preview_steps], 128
.short_arg:
    cmp al, 'T'
    jne .next_arg
    mov word [remaining], 16
.next_arg:
    loop .args
.init:
    call video_detect
    jc .video_error
    call video_setup
    jnc .video_ok
.video_error:
    mov dx, unsupported_text
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h
.video_ok:
    mov ah, 0dh
    int 18h                     ; hide text, retain text RAM and cursor
    push cs
    pop ds
    call video_init
.show:
    call video_show
    jnc .sound
    mov byte [exit_code], 1
    jmp quit
.sound:
    push cs
    pop ds
    call sound_init
frame:
    call setup_transform
    call render
    call wait_vsync
    cmp byte [hireso], 0
    jne .no_flip
    mov al, [draw_page]
    out 0a4h, al
    cmp byte [single_page], 0
    jne .no_flip
    xor al, 1
    mov [draw_page], al
    out 0a6h, al
.no_flip:
    cmp byte [sound_done], 0
    jne quit
    add word [angle], 2          ; 128 frames per rotation/zoom cycle
    and word [angle], 255
    cmp word [remaining], 0
    je .keyboard
    dec word [remaining]
    jz quit
.keyboard:
    mov ah, 06h
    mov dl, 0ffh
    int 21h                     ; nonblocking DOS input, no Ctrl-C abort
    jz frame
    cmp al, 27
    je quit
    and al, 0dfh
    cmp al, 'Q'
    jne frame
quit:
    call sound_stop
    call video_hide
    push cs
    pop ds
    call video_stop
    mov ah, 0ch
    int 18h                     ; restore DOS text visibility
    call sound_report
    mov ax, 4c00h
    mov al, [exit_code]
    int 21h
help:
    mov dx, help_text
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

palette:
    mov al, 37h                 ; indices 3 / 7
    out 0a8h, al
    mov al, 15h                 ; indices 1 / 5
    out 0aah, al
    mov al, 26h                 ; indices 2 / 6
    out 0ach, al
    mov al, 04h                 ; indices 0 / 4
    out 0aeh, al
    ret
clear_page:
    mov bx, 0a800h
.plane:
    mov es, bx
    xor di, di
    xor ax, ax
    mov cx, 16000
    rep stosw
    add bx, 0800h
    cmp bx, 0c000h
    jb .plane
    ret

setup_transform:
    mov bx, [angle]
    shl bx, 1
    shl bx, 1
    mov ax, [transforms+bx]
    mov [du], ax
    mov ax, [transforms+bx+2]
    mov [dv], ax
    ; Center the affine map on (80,50), texture center (32,32).
    mov ax, [du]
    mov bx, -80
    imul bx
    mov [row_u], ax
    mov ax, [dv]
    mov bx, 50
    imul bx
    add ax, [row_u]
    add ax, 8192
    mov [row_u], ax
    mov ax, [dv]
    mov bx, -80
    imul bx
    mov [row_v], ax
    mov ax, [du]
    mov bx, -50
    imul bx
    add ax, [row_v]
    add ax, 8192
    mov [row_v], ax
    ret

; Return texture[(v>>8)&63][(u>>8)&63] in BX. AX=u, DX=v.
%macro sample 0
    mov bl, dh
    xor bh, bh
    shl bx, 1
    mov si, [tex_rows+bx]
    mov bl, ah
    xor bh, bh
    and bl, 63
    mov bl, [texture+bx+si]
%endmacro

render:
    cmp byte [want256], 0
    je .planar
    jmp render256
.planar:
    mov word [vram_row], 0
    mov word [hirow_seg], 0c5fdh ; (175*140+30) / 16 + C000h
    mov bp, 100
.row:
    call sound_service           ; music time independent of graphics frame count
    push bp
    mov ax, [row_u]
    mov dx, [row_v]
    xor di, di
    mov bp, 80
.pair:
    sample
    mov cx, bx
    shl cx, 1
    shl cx, 1
    shl cx, 1
    add ax, [du]
    add dx, [dv]
    sample
    or bx, cx
    mov cl, [lut_b+bx]
    mov [row_b+di], cl
    mov cl, [lut_r+bx]
    mov [row_r+di], cl
    mov cl, [lut_g+bx]
    mov [row_g+di], cl
    add ax, [du]
    add dx, [dv]
    inc di
    dec bp
    jnz .pair
    mov ax, 0a800h
    mov byte [plane_mask], 0eh
    mov si, row_b
    call copy_row
    mov ax, 0b000h
    mov byte [plane_mask], 0dh
    mov si, row_r
    call copy_row
    mov ax, 0b800h
    mov byte [plane_mask], 0bh
    mov si, row_g
    call copy_row
    add word [vram_row], 320
    add word [hirow_seg], 35     ; four 140-byte scanlines
    mov ax, [dv]
    sub [row_u], ax
    mov ax, [du]
    add [row_v], ax
    pop bp
    dec bp
    jz .done
    jmp .row
.done:
    ret
copy_row:
    cmp byte [hireso], 0
    je .normal
    mov ax, [hirow_seg]
    mov es, ax
    mov al, [plane_mask]
    out 0a4h, al
    mov di, 2
    mov dx, 4
.hi_line:
    push si
    mov cx, 40
    rep movsw
    pop si
    add di, 60
    dec dx
    jnz .hi_line
    ret
.normal:
    mov es, ax
    mov di, [vram_row]
    mov dx, 4
.line:
    push si
    mov cx, 40
    rep movsw
    pop si
    dec dx
    jnz .line
    ret

wait_vsync:
    ; GDC status bit 5. Bounded polling also tolerates absent/stuck VSYNC.
    mov cx, 0ffffh
.leave:
    in al, 0a0h
    test al, 20h
    jz .begin
    loop .leave
    ret
.begin:
    mov cx, 0ffffh
.enter:
    in al, 0a0h
    test al, 20h
    jnz .done
    loop .enter
.done:
    ret

angle dw 0
du dw 0
dv dw 0
row_u dw 0
row_v dw 0
vram_row dw 0
remaining dw 0
draw_page db 0
single_page db 0
exit_code db 0
help_text db 'ROTO - PC-98 normal / high-resolution, GRCG / EGC / PEGC',13,10
          db '/256: PEGC 256 colors. /8: compatible 8 colors (default).',13,10
          db 'Esc/Q: quit. /S: single page. /T: 16 frames. /M: mute.',13,10
          db '/P: 12.8s music preview. Auto 26K/86 FM+SSG, 86 PCM.',13,10,'$'
%include "video.asm"
%include "assets.inc"
%include "sound.asm"
row_b times 80 db 0
row_r times 80 db 0
row_g times 80 db 0
align 2
stack_bottom:
    times 1024 db 0
stack_top:
program_end:
%if ($-$$) > 0ff00h
    %error COM image exceeds single-segment capacity
%endif
