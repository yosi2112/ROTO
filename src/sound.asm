; Polled foreground FM/SSG score and 86 PCM. No IRQ, PIC or PIT ownership.
; All routines use the COM's DS; sound_service preserves every general register.
db 'ROTO98AUD'
dw sound_init, sound_service, sound_stop, sound_tick, sound_type, fm_base
dw music_row, music_score, pcm_table, last_time, time_debt, sound_muted
dw preview_steps, sound_done, fm_write, probe_opn

sound_init:
    cmp byte [sound_muted], 0
    jne .clock
    call detect_sound
    cmp byte [sound_type], 0
    je .clock
    ; Preserve PSG port direction bits (joystick and interrupt straps).
    mov dx, [fm_base]
    mov al, 7
    call fm_read
    and al, 0c0h
    mov [psg_direction], al
    or al, 3fh
    mov ah, al
    mov al, 7
    call fm_write
    mov si, fm_init_table
    mov cx, FM_INIT_PAIRS
.voice:
    lodsw
    call fm_write
    loop .voice
    cmp byte [sound_type], 2
    jne .ssg
    ; OPNA stereo enables for the three compatible FM channels.
    mov ax, 0c0b4h
    call fm_write
    inc al
    call fm_write
    inc al
    call fm_write
    call pcm_init
.ssg:
    mov dx, [fm_base]
    mov ax, 0508h
    call fm_write
    inc al
    call fm_write
    inc al
    call fm_write
    mov ah, [psg_direction]
    or ah, 38h                   ; tone A/B/C on; noise off
    mov al, 7
    call fm_write
.clock:
    call sound_time
    mov [last_time], ax
    call sound_tick              ; start first notes at t=0
    ret

detect_sound:
    mov dx, 0a460h
    in al, dx
    and al, 0f0h
    cmp al, 40h
    je .id86
    cmp al, 50h
    je .id86
.compatible:
    mov dx, 0188h
    call probe_opn
    jnc .opn
    mov dx, 0288h
    call probe_opn
    jnc .opn
    mov dx, 0088h              ; PC-9801-26/K legacy FM base
    call probe_opn
    jc .absent
.opn:
    mov byte [sound_type], 1
    mov [fm_base], dx
    ret
.id86:
    mov dx, 0188h
    cmp al, 50h
    jne .check86
    mov dx, 0288h
.check86:
    call probe_opn              ; ID alone is not proof that FM is present
    jc .compatible
    mov [fm_base], dx
    mov byte [sound_type], 2
.absent:
    ret

; Two read/write patterns in an 8-bit PSG tone register, restored even on failure.
; CF=0 iff an OPN-compatible register actually responds at DX.
probe_opn:
    push ax
    push bx
    push cx
    xor al, al
    call fm_read
    jc .failure
    mov bl, al
    mov ax, 5500h
    call fm_write
    jc .restore_bad
    xor al, al
    call fm_read
    jc .restore_bad
    cmp al, 55h
    jne .restore_bad
    mov ax, 0aa00h
    call fm_write
    jc .restore_bad
    xor al, al
    call fm_read
    jc .restore_bad
    cmp al, 0aah
    jne .restore_bad
    mov ah, bl
    xor al, al
    call fm_write
    jmp .return
.restore_bad:
    mov ah, bl
    xor al, al
    call fm_write
.failure:
    stc
.return:
    pop cx
    pop bx
    pop ax
    ret

; AX = data:register, DX = 188h or 288h. Preserves all registers, returns CF.
fm_write:
    push bx
    push dx
    mov bx, ax
    call fm_ready
    jc .done
    out dx, al
    call opn_delay
    add dx, 2
    mov al, bh
    out dx, al
    call opn_delay
    mov ax, bx
    clc
.done:
    pop dx
    pop bx
    ret
fm_read:
    push dx
    call fm_ready
    jc .done
    out dx, al
    call opn_delay
    add dx, 2
    in al, dx
    clc
.done:
    pop dx
    ret
fm_ready:
    push ax
    push cx
    mov cx, 2048
.busy:
    in al, dx
    test al, 80h
    jz .ready
    loop .busy
    stc
    jmp .done
.ready:
    clc
.done:
    pop cx
    pop ax
    ret
opn_delay:
    push ax
    push cx
    mov cx, 8
.delay:
    in al, 5fh                  ; PC-98 0.6 us I/O wait; >=4.8 us
    loop .delay
    pop cx
    pop ax
    ret

; DOS time -> centiseconds within minute (0..5999), including midnight wrap.
sound_time:
    mov ah, 2ch
    int 21h
    mov al, dh
    mov ah, 100
    mul ah
    xor dh, dh
    add ax, dx
    ret
sound_service:
    cmp byte [sound_type], 0
    jne .active
    cmp word [preview_steps], 0
    je .return
.active:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    call sound_time
    mov bx, ax
    sub ax, [last_time]
    jnc .elapsed
    add ax, 6000
.elapsed:
    mov [last_time], bx
    ; Cap anomalous pauses; at most four music steps per call.
    cmp ax, 40
    jbe .accumulate
    mov ax, 40
.accumulate:
    add [time_debt], ax
    mov bp, 4
.step:
    cmp word [time_debt], 10     ; 100 ms sixteenth note = 150 BPM
    jb .done
    sub word [time_debt], 10
    call sound_tick
    dec bp
    jnz .step
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.return:
    ret

sound_tick:
    cmp byte [sound_done], 0
    jne .return
    mov ax, [music_row]
    mov bx, 7
    mul bx
    mov si, music_score
    add si, ax
    cmp byte [sound_type], 0
    je .advance
    mov dx, [fm_base]
    xor di, di
.fm:
    lodsb
    cmp al, 255                 ; tie bass on alternate sixteenths
    je .fm_next
    xor ah, ah
    mov bx, ax
    shl bx, 1
    push bx
    mov ax, di
    mov ah, al
    mov al, 28h
    call fm_write              ; key off
    pop bx
    mov cx, [fm_notes+bx]
    mov ax, di
    add al, 0a4h
    mov ah, ch
    call fm_write              ; FNUM high/block before low
    mov ax, di
    add al, 0a0h
    mov ah, cl
    call fm_write
    mov ax, di
    mov ah, al
    or ah, 0f0h
    mov al, 28h
    call fm_write              ; all four operators key on
.fm_next:
    inc di
    cmp di, 3
    jb .fm
    xor di, di
.psg:
    lodsb
    xor ah, ah
    mov bx, ax
    shl bx, 1
    mov cx, [ssg_notes+bx]
    mov ax, di
    mov ah, cl
    call fm_write
    inc al
    mov ah, ch
    call fm_write
    add di, 2
    cmp di, 6
    jb .psg
    cmp byte [sound_type], 2
    jne .advance
    lodsb
    call pcm_play
.advance:
    inc word [music_row]
    cmp word [music_row], MUSIC_ROWS
    jb .preview
    mov word [music_row], 0
.preview:
    cmp word [preview_steps], 0
    je .return
    dec word [preview_steps]
    jnz .return
    mov byte [sound_done], 1
.return:
    ret

pcm_init:
    mov dx, 0a66eh
    in al, dx
    mov [pcm_old_mute], al
    and al, 0feh
    out dx, al
    mov dx, 0a468h
    mov al, 04h                ; stopped, 11025 Hz, FIFO IRQ disabled
    out dx, al
    mov dx, 0a46ah
    mov al, 70h                ; signed 8-bit stereo
    out dx, al
    mov dx, 0a466h
    mov al, 0a0h               ; PCM output attenuation = 0
    out dx, al
    ret
pcm_play:
    xor ah, ah
    mov bx, ax
    shl bx, 1
    shl bx, 1
    mov si, [pcm_table+bx]
    mov cx, [pcm_table+bx+2]
    mov dx, 0a468h
    mov al, 0ch                ; stop + reset FIFO, keep rate code 4
    out dx, al
    mov al, 04h
    out dx, al
.fill:
    mov dx, 0a466h
    in al, dx
    test al, 80h               ; unexpected full: abandon this hit, never spin
    jnz .return
    mov dx, 0a46ch
    lodsb
    out dx, al
    loop .fill
    mov dx, 0a468h
    mov al, 84h                ; play, no recording/IRQ
    out dx, al
.return:
    ret
sound_stop:
    cmp byte [sound_type], 0
    je .return
    mov dx, [fm_base]
    mov ax, 0028h
    call fm_write
    mov ah, 1
    call fm_write
    mov ah, 2
    call fm_write
    mov ax, 0008h
    call fm_write
    inc al
    call fm_write
    inc al
    call fm_write
    mov ah, [psg_direction]
    or ah, 3fh
    mov al, 7
    call fm_write
    mov ax, 3027h
    call fm_write
    cmp byte [sound_type], 2
    jne .return
    mov dx, 0a468h
    mov al, 0ch
    out dx, al
    mov al, 04h
    out dx, al
    mov dx, 0a66eh
    mov al, [pcm_old_mute]
    out dx, al
.return:
    ret

sound_report:
    mov dx, msg_silent
    cmp byte [sound_type], 0
    je .print
    mov dx, msg_26
    cmp byte [sound_type], 1
    je .print
    mov dx, msg_86
.print:
    mov ah, 09h
    int 21h
    ret

fm_base dw 0188h
sound_type db 0                 ; 0 absent/muted, 1 26K-compatible, 2 verified 86
sound_muted db 0
psg_direction db 0
pcm_old_mute db 1
music_row dw 0
last_time dw 0
time_debt dw 0
preview_steps dw 0
sound_done db 0
msg_silent db 'ROTO sound: none / muted',13,10,'$'
msg_26 db 'ROTO sound: 26K-compatible FM + SSG',13,10,'$'
msg_86 db 'ROTO sound: 86 FM + SSG + PCM',13,10,'$'
%include "music_data.inc"
