; Video backends. BIOS work area is read before touching video hardware.
; High-resolution hardware uses A4/A6 as GRCG mode/tile, NOT page selectors.
db 'ROTO98VID'
dw video_detect, video_init, video_stop, render256, hireso, want256
dw has_grcg, has_egc, hirow_seg, wait_vsync

video_detect:
    xor ax, ax
    mov es, ax
    mov al, [es:0501h]
    and al, 8
    mov [hireso], al
    jz .normal
    mov byte [single_page], 1
    cmp byte [want256], 0
    jne .unsupported
    clc
    ret
.normal:
    mov al, [es:054ch]
    and al, 2
    mov [has_grcg], al
    mov al, [es:054dh]
    and al, 40h
    mov [has_egc], al
    cmp byte [want256], 0
    je .ok
    test byte [es:045ch], 40h
    jz .unsupported
    mov byte [single_page], 1 ; packed framebuffer uses bank zero origin
.ok:
    clc
    ret
.unsupported:
    stc
    ret

video_setup:
    cmp byte [hireso], 0
    jne .high
    mov ah, 41h
    int 18h
    mov ah, 42h
    mov ch, 0c0h
    int 18h
    push cs
    pop ds
    clc
    ret
.high:
    mov word [hi_ucw+100h], hi_callback
    mov ax, cs
    mov [hi_ucw+102h], ax
    xor ah, ah                ; INT 1Dh GINIT, private 380h-byte UCW
    call hi_bios
    ret

hi_bios:
    push ds
    push bx
    push cx
    mov dx, hi_ucw
    mov cl, 4
    shr dx, cl
    mov bx, cs
    add dx, bx
    mov ds, dx
    int 1dh
    pop cx
    pop bx
    pop ds
    or ah, ah
    jnz .failed
    clc
    ret
.failed:
    stc
    ret
hi_callback:
    retf

video_show:
    cmp byte [hireso], 0
    je .normal
    mov ah, 11h               ; GSTART
    jmp hi_bios
.normal:
    mov ah, 40h
    int 18h
    clc
    ret

video_hide:
    cmp byte [hireso], 0
    je .normal
    mov ah, 12h               ; GSTOP
    jmp hi_bios
.normal:
    mov ah, 41h
    int 18h
    ret

video_init:
    cmp byte [hireso], 0
    jne .hires
    cmp byte [has_egc], 0
    je .legacy
    mov al, 7
    out 6ah, al
    mov al, 4                  ; select GRCG compatibility on EGC/PEGC
    out 6ah, al
    mov al, 6
    out 6ah, al
.legacy:
    xor al, al
    out 7ch, al
    out 0a4h, al
    out 0a6h, al
    out 6ah, al
    cmp byte [want256], 0
    jne init256
    call palette
    call video_clear
    cmp byte [single_page], 0
    jne .done
    mov al, 1
    out 0a6h, al
    call video_clear
    mov byte [draw_page], 1
.done:
    ret
.hires:
    xor al, al
    out 6ah, al
    out 0a4h, al              ; direct writes to all four 128KB planes
    call palette
    mov bx, 0c000h
    mov bp, 2
.half:
    mov es, bx
    xor di, di
    xor ax, ax
    mov cx, 32768
    rep stosw
    add bx, 1000h
    dec bp
    jnz .half
    ret

video_clear:
    cmp byte [has_grcg], 0
    jne .charger
    jmp clear_page
.charger:
    mov al, 80h               ; GRCG TDW, all four planes, black tile
    out 7ch, al
    xor al, al
    out 7eh, al
    out 7eh, al
    out 7eh, al
    out 7eh, al
    mov ax, 0a800h
    mov es, ax
    xor ax, ax
    xor di, di
    mov cx, 16000
    rep stosw
    out 7ch, al
    ret

init256:
    mov al, 7
    out 6ah, al
    mov al, 1
    out 6ah, al
    mov al, 21h
    out 6ah, al
    mov al, 6
    out 6ah, al
    mov ax, 0e000h
    mov es, ax
    mov word [es:0100h], 0     ; packed pixels
    mov word [es:0102h], 0     ; bank windows, no linear framebuffer
    mov word [es:4], 0
    mov word [es:6], 1
    xor bx, bx
.palette:
    mov al, bl
    out 0a8h, al
    mov al, bl
    and al, 7
    xor ah, ah
    mov si, ax
    mov al, [levels8+si]
    out 0aeh, al              ; B = index bits 0..2
    mov al, bl
    mov cl, 3
    shr al, cl
    and al, 7
    xor ah, ah
    mov si, ax
    mov al, [levels8+si]
    out 0ach, al              ; R = bits 3..5
    mov al, bl
    mov cl, 6
    shr al, cl
    xor ah, ah
    mov si, ax
    mov al, [levels4+si]
    out 0aah, al              ; G = bits 6..7
    inc bx
    cmp bx, 256
    jb .palette
    ; Clear visible 256000 bytes. Bank seven has only 26624 visible bytes.
    xor bx, bx
.clear:
    mov ax, 0e000h
    mov es, ax
    mov [es:4], bx
    mov ax, 0a800h
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 16384
    cmp bx, 7
    jne .fill
    mov cx, 13312
.fill:
    rep stosw
    inc bx
    cmp bx, 8
    jb .clear
    ret

render256:
    mov word [packed_bank], 0
    mov word [packed_offset], 0
    mov bp, 100
.row:
    call sound_service
    push bp
    mov ax, [row_u]
    mov dx, [row_v]
    xor di, di
    mov bp, 160
.pixel:
    mov bl, dh
    xor bh, bh
    shl bx, 1
    mov si, [tex_rows+bx]
    mov bl, ah
    xor bh, bh
    and bl, 63
    mov bl, [texture256+bx+si]
    mov [packed_row+di], bl
    mov [packed_row+di+1], bl
    mov [packed_row+di+2], bl
    mov [packed_row+di+3], bl
    add di, 4
    add ax, [du]
    add dx, [dv]
    dec bp
    jnz .pixel
    mov bp, 4
.line:
    mov si, packed_row
    mov bx, 640
.chunk:
    mov ax, 0e000h
    mov es, ax
    mov ax, [packed_bank]
    mov [es:4], ax
    mov ax, 0a800h
    mov es, ax
    mov di, [packed_offset]
    mov cx, 8000h
    sub cx, di
    cmp cx, bx
    jbe .copy
    mov cx, bx
.copy:
    sub bx, cx
    rep movsb
    cmp di, 8000h
    jne .offset
    xor di, di
    inc word [packed_bank]
.offset:
    mov [packed_offset], di
    or bx, bx
    jnz .chunk
    dec bp
    jnz .line
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

video_stop:
    cmp byte [hireso], 0
    je .normal
    xor al, al
    out 0a4h, al
    mov ah, 13h               ; GTERM
    jmp hi_bios
.normal:
    cmp byte [want256], 0
    je .pages
    mov ax, 0e000h
    mov es, ax
    mov word [es:4], 0
    mov word [es:6], 0
    mov al, 7
    out 6ah, al
    mov al, 20h
    out 6ah, al
    xor al, al
    out 6ah, al
    mov al, 6
    out 6ah, al
.pages:
    xor al, al
    out 7ch, al
    out 0a4h, al
    out 0a6h, al
    ret

hireso db 0
want256 db 0
has_grcg db 0
has_egc db 0
plane_mask db 0eh
hirow_seg dw 0
packed_bank dw 0
packed_offset dw 0
levels8 db 0,36,73,109,146,182,219,255
levels4 db 0,85,170,255
unsupported_text db 'ROTO: unsupported /256 mode or graphics BIOS initialization error.',13,10,'$'
packed_row times 640 db 0
align 16
hi_ucw:
    times 896 db 0
