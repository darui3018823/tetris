; tetris.asm  -  Tetris in x86_64 NASM for Windows
; Build:    .\build.ps1
; Controls: ← → Move   ↑ Rotate   ↓ Soft-drop   Space Hard-drop   ESC Quit

bits 64
default rel

; ────────────────────────── Win32 constants ──────────────────────────────────
STD_OUTPUT_HANDLE               equ -11
ENABLE_PROCESSED_OUTPUT         equ 0x0001
ENABLE_VIRTUAL_TERMINAL_PROCESSING equ 0x0004

VK_LEFT   equ 0x25
VK_UP     equ 0x26
VK_RIGHT  equ 0x27
VK_DOWN   equ 0x28
VK_SPACE  equ 0x20
VK_ESCAPE equ 0x1B
VK_R      equ 0x52

; ────────────────────────── Layout ───────────────────────────────────────────
BOARD_COLS  equ 10
BOARD_ROWS  equ 20
; Board display: top-left cell at console (row=BOARD_Y, col=BOARD_X+1)
; Borders at (BOARD_Y-1, BOARD_X-1) and (BOARD_Y+BOARD_ROWS, BOARD_X+BOARD_COLS*2)
BOARD_X     equ 2           ; col of left border │ (1-indexed)
BOARD_Y     equ 2           ; row of top border  ─
CELL_W      equ 2           ; console chars per board cell

HUD_COL     equ 26          ; HUD panel start column
HUD_ROW     equ 2

FALL_LEVELS equ 10

; ────────────────────────── .data ────────────────────────────────────────────
section .data

title_str   db "TETRIS", 0
conout_str  db "CONOUT$", 0

; ANSI sequences
ESC_HIDE    db 0x1B,"[?25l",0
ESC_SHOW    db 0x1B,"[?25h",0
ESC_RESET   db 0x1B,"[0m",0
ESC_BOLD    db 0x1B,"[1m",0
ESC_CLEAR   db 0x1B,"[2J",0x1B,"[H",0

; Box-drawing (UTF-8)
BOX_TL  db 0xE2,0x94,0x8C,0   ; ┌
BOX_TR  db 0xE2,0x94,0x90,0   ; ┐
BOX_BL  db 0xE2,0x94,0x94,0   ; └
BOX_BR  db 0xE2,0x94,0x98,0   ; ┘
BOX_H   db 0xE2,0x94,0x80,0   ; ─
BOX_V   db 0xE2,0x94,0x82,0   ; │

; HUD strings
STR_NEXT    db "NEXT",0
STR_SCORE   db "SCORE",0
STR_LEVEL   db "LEVEL",0
STR_LINES   db "LINES",0
STR_C1      db "< > :Move",0
STR_C2      db " ^  :Rot",0
STR_C3      db " v  :Drop",0
STR_C4      db "SPC :Hard",0
STR_C5      db "ESC :Quit",0
STR_GO      db "GAME OVER",0
STR_RST     db "R=Restart",0

; Piece colors: index = piece type (1-7), value = ANSI bg color code
piece_bg_colors:
    db 0        ; 0 = empty (unused)
    db 46       ; 1 I  cyan
    db 43       ; 2 O  yellow
    db 45       ; 3 T  magenta
    db 42       ; 4 S  green
    db 41       ; 5 Z  red
    db 44       ; 6 J  blue
    db 47       ; 7 L  white

; Tetromino data: 7 pieces × 4 rotations × 4 rows = 112 bytes
; Each byte = bitmask of 4 cols (bit3=leftmost, bit0=rightmost)
tetromino_data:
; I (type 0, color 1)
    db 0b0000,0b1111,0b0000,0b0000  ; R0
    db 0b0010,0b0010,0b0010,0b0010  ; R1
    db 0b0000,0b0000,0b1111,0b0000  ; R2
    db 0b0100,0b0100,0b0100,0b0100  ; R3
; O (type 1, color 2)
    db 0b0000,0b0110,0b0110,0b0000
    db 0b0000,0b0110,0b0110,0b0000
    db 0b0000,0b0110,0b0110,0b0000
    db 0b0000,0b0110,0b0110,0b0000
; T (type 2, color 3)
    db 0b0000,0b0100,0b1110,0b0000  ; R0
    db 0b0000,0b0100,0b0110,0b0100  ; R1
    db 0b0000,0b1110,0b0100,0b0000  ; R2
    db 0b0000,0b0100,0b1100,0b0100  ; R3
; S (type 3, color 4)
    db 0b0000,0b0110,0b1100,0b0000
    db 0b0000,0b0100,0b0110,0b0010
    db 0b0000,0b0110,0b1100,0b0000
    db 0b0000,0b0100,0b0110,0b0010
; Z (type 4, color 5)
    db 0b0000,0b1100,0b0110,0b0000
    db 0b0000,0b0010,0b0110,0b0100
    db 0b0000,0b1100,0b0110,0b0000
    db 0b0000,0b0010,0b0110,0b0100
; J (type 5, color 6)
    db 0b0000,0b1000,0b1110,0b0000
    db 0b0000,0b0110,0b0100,0b0100
    db 0b0000,0b1110,0b0010,0b0000
    db 0b0000,0b0100,0b0100,0b1100
; L (type 6, color 7)
    db 0b0000,0b0010,0b1110,0b0000
    db 0b0000,0b0100,0b0100,0b0110
    db 0b0000,0b1110,0b1000,0b0000
    db 0b0000,0b1100,0b0100,0b0100

; Fall delay (ms) per level index 0-9  (NES/NTSC: frames/60*1000)
fall_delays:
    dd 717,633,550,467,383,300,217,133,100,83

; Score per lines cleared (multiplied by level)
score_table:
    dd 100,300,500,800

; Wall-kick offsets: 0, +1, -1
kick_offsets:
    db 0, 1, -1

; ────────────────────────── .bss ─────────────────────────────────────────────
section .bss

board:          resb 200        ; BOARD_ROWS × BOARD_COLS

cur_type:       resb 1
cur_rot:        resb 1
cur_x:          resb 1
cur_y:          resb 1          ; signed: negative = above visible area
next_type:      resb 1

score:          resq 1
level:          resb 1
lines_cleared:  resd 1
game_over_flag: resb 1          ; 0=play, 1=over, 2=restart

fall_time:      resq 1          ; tick of last gravity step
lock_time:      resq 1          ; tick when piece first touched ground (0=airborne)
das_time:       resq 1          ; tick of last DAS repeat
das_active:     resb 1

prev_left:      resb 1
prev_right:     resb 1
prev_up:        resb 1
prev_space:     resb 1

hstdout:        resq 1
rand_seed:      resq 1

render_buf:     resb 16384
render_len:     resd 1

num_scratch:    resb 24         ; scratch for uint→string

; ────────────────────────── .text ────────────────────────────────────────────
section .text
global main

extern CreateFileA
extern GetStdHandle
extern GetConsoleMode
extern SetConsoleMode
extern SetConsoleTitleA
extern WriteFile
extern GetAsyncKeyState
extern GetTickCount64
extern Sleep
extern SetConsoleOutputCP
extern ExitProcess

; ─── Macros ──────────────────────────────────────────────────────────────────
%define SH 32                   ; shadow space size

%macro PROC_ENTER 0
    push rbp
    mov  rbp, rsp
    sub  rsp, SH
%endmacro

%macro PROC_LEAVE 0
    add  rsp, SH
    pop  rbp
    ret
%endmacro

; ═════════════════════════════════════════════════════════════════════════════
; RENDER BUFFER
; ═════════════════════════════════════════════════════════════════════════════

; buf_byte: append AL to render_buf  (trashes nothing extra)
buf_byte:
    push  rbx
    mov   ebx, [render_len]
    cmp   ebx, 16376
    jge   .skip
    lea   rcx, [render_buf]
    mov   [rcx + rbx], al
    inc   ebx
    mov   [render_len], ebx
.skip:
    pop   rbx
    ret

; buf_cstr: append NUL-terminated string at RCX
buf_cstr:
    push  rbx
    push  rsi
    mov   rsi, rcx
    mov   ebx, [render_len]
.loop:
    movzx eax, byte [rsi]
    test  al, al
    jz    .done
    cmp   ebx, 16376
    jge   .done
    lea   rcx, [render_buf]
    mov   [rcx + rbx], al
    inc   rsi
    inc   ebx
    jmp   .loop
.done:
    mov   [render_len], ebx
    pop   rsi
    pop   rbx
    ret

; buf_uint: append EAX as decimal
buf_uint:
    push  rbx
    push  rdi
    push  rsi
    lea   rdi, [num_scratch]
    xor   esi, esi          ; digit count
    test  eax, eax
    jnz   .digits
    mov   byte [rdi], '0'
    inc   esi
    jmp   .emit
.digits:
    mov   ecx, 10
.d_loop:
    xor   edx, edx
    div   ecx
    add   dl, '0'
    mov   [rdi + rsi], dl
    inc   esi
    test  eax, eax
    jnz   .d_loop
.emit:
    dec   esi
.rev:
    movzx eax, byte [rdi + rsi]
    call  buf_byte
    dec   esi
    jns   .rev
    pop   rsi
    pop   rdi
    pop   rbx
    ret

; flush_buf: WriteFile render_buf → stdout, reset length
flush_buf:
    push  rbp
    mov   rbp, rsp
    ; sub 64: 32 shadow + 8 written + 8 5th-arg + 16 padding  (64 mod 16 = 0, stays aligned)
    sub   rsp, 64

    mov   eax, [render_len]
    test  eax, eax
    jz    .done

    mov   qword [rsp + 32], 0   ; 5th arg: lpOverlapped = NULL
    mov   rcx, [hstdout]
    lea   rdx, [render_buf]
    mov   r8d, [render_len]
    lea   r9,  [rsp + 40]       ; &written
    call  WriteFile

    mov   dword [render_len], 0
.done:
    add   rsp, 64
    pop   rbp
    ret

; goto_xy: emit ESC[row+1;col+1H  (RCX=row 0-based, RDX=col 0-based)
goto_xy:
    push  r12
    push  r13
    mov   r12d, ecx
    mov   r13d, edx
    mov   al, 0x1B
    call  buf_byte
    mov   al, '['
    call  buf_byte
    mov   eax, r12d
    inc   eax
    call  buf_uint
    mov   al, ';'
    call  buf_byte
    mov   eax, r13d
    inc   eax
    call  buf_uint
    mov   al, 'H'
    call  buf_byte
    pop   r13
    pop   r12
    ret

; set_bg_color: emit ESC[ALm  (AL = ANSI code, e.g. 41-47)
set_bg_color:
    push  rbx
    movzx ebx, al
    mov   al, 0x1B
    call  buf_byte
    mov   al, '['
    call  buf_byte
    mov   eax, ebx
    call  buf_uint
    mov   al, 'm'
    call  buf_byte
    pop   rbx
    ret

; buf_reset: emit ESC[0m
buf_reset:
    push  rcx
    lea   rcx, [ESC_RESET]
    call  buf_cstr
    pop   rcx
    ret

; ═════════════════════════════════════════════════════════════════════════════
; CONSOLE SETUP
; ═════════════════════════════════════════════════════════════════════════════

init_console:
    push  rbp
    mov   rbp, rsp
    ; Frame: 32 shadow + 24 (args5-7) + 8 mode_local = 64 (16-byte aligned)
    sub   rsp, 64

    mov   ecx, 65001            ; UTF-8 codepage
    call  SetConsoleOutputCP

    ; CreateFileA("CONOUT$", GENERIC_READ|GENERIC_WRITE, FILE_SHARE_READ|WRITE,
    ;             NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL)
    lea   rcx, [conout_str]
    mov   edx, 0xC0000000        ; GENERIC_READ | GENERIC_WRITE
    mov   r8d, 3                 ; FILE_SHARE_READ | FILE_SHARE_WRITE
    xor   r9d, r9d               ; lpSecurityAttributes = NULL
    mov   qword [rsp + 32], 3   ; OPEN_EXISTING
    mov   qword [rsp + 40], 0x80 ; FILE_ATTRIBUTE_NORMAL
    mov   qword [rsp + 48], 0   ; hTemplateFile = NULL
    call  CreateFileA
    mov   [hstdout], rax

    ; GetConsoleMode → [rsp+56]  (above arg slots; zero first as fallback)
    mov   qword [rsp + 56], 0
    mov   rcx, [hstdout]
    lea   rdx, [rsp + 56]
    call  GetConsoleMode

    ; OR in PROCESSED(1) | WRAP_AT_EOL(2) | VT(4) = 7
    mov   eax, [rsp + 56]
    or    eax, ENABLE_PROCESSED_OUTPUT | 0x0002 | ENABLE_VIRTUAL_TERMINAL_PROCESSING
    mov   rcx, [hstdout]
    mov   edx, eax
    call  SetConsoleMode

    lea   rcx, [title_str]
    call  SetConsoleTitleA

    lea   rcx, [ESC_HIDE]
    call  buf_cstr
    call  flush_buf

    add   rsp, 64
    pop   rbp
    ret

cleanup_console:
    PROC_ENTER
    lea   rcx, [ESC_SHOW]
    call  buf_cstr
    lea   rcx, [ESC_RESET]
    call  buf_cstr
    ; Move cursor below board so the shell prompt appears there
    mov   ecx, BOARD_Y + BOARD_ROWS + 1
    xor   edx, edx
    call  goto_xy
    call  flush_buf
    PROC_LEAVE

; ═════════════════════════════════════════════════════════════════════════════
; LCG RANDOM  →  0-6 in EAX
; ═════════════════════════════════════════════════════════════════════════════
lcg_rand:
    mov   rax, [rand_seed]
    mov   rcx, 6364136223846793005
    imul  rax, rcx
    mov   rcx, 1442695040888963407
    add   rax, rcx
    mov   [rand_seed], rax
    shr   rax, 33
    movzx eax, al
    xor   edx, edx
    mov   ecx, 7
    div   ecx
    mov   eax, edx          ; remainder 0-6
    ret

; ═════════════════════════════════════════════════════════════════════════════
; GET_PIECE_ROW: row bitmask
; In:  CL=type, DL=rot, R8B=row  → AL
; ═════════════════════════════════════════════════════════════════════════════
get_piece_row:
    movzx eax, cl           ; type  * 16
    imul  eax, 16
    movzx ecx, dl           ; rot   * 4
    imul  ecx, 4
    add   eax, ecx
    movzx ecx, r8b          ; + row
    add   eax, ecx
    lea   rcx, [tetromino_data]
    movzx eax, byte [rcx + rax]
    ret

; ═════════════════════════════════════════════════════════════════════════════
; CHECK_COLLISION
; In:  CL=type, DL=rot, R8B=px(col), R9B=py(row signed)
; Out: AL=0 clear, AL=1 collision
; ═════════════════════════════════════════════════════════════════════════════
check_collision:
    push  r12
    push  r13
    push  r14
    push  r15
    push  rbx

    movzx r12d, cl          ; type
    movzx r13d, dl          ; rot
    movsx r14d, r8b         ; px (signed: negative = piece origin left of board)
    movsx r15d, r9b         ; py (signed)

    xor   ebx, ebx          ; piece row 0..3
.pr_loop:
    cmp   ebx, 4
    jge   .clear

    mov   cl,  r12b
    mov   dl,  r13b
    mov   r8b, bl
    call  get_piece_row
    movzx r11d, al          ; bitmask in r11d  (lea rcx,[board] later clobbers rcx/ecx)
    test  r11d, r11d
    jz    .pr_next

    ; iterate cols
    xor   r8d, r8d          ; piece col 0..3
.pc_loop:
    cmp   r8d, 4
    jge   .pr_next

    mov   eax, 3
    sub   eax, r8d
    bt    r11d, eax         ; CF = bit(3-col) of bitmask
    jnc   .pc_next

    ; board position
    mov   eax, r15d         ; by = py + piece_row
    add   eax, ebx
    js    .pc_next          ; above top row is OK (piece spawns there)
    cmp   eax, BOARD_ROWS
    jge   .collide          ; below bottom

    mov   edx, r14d         ; bx = px + piece_col
    add   edx, r8d
    js    .collide           ; left wall
    cmp   edx, BOARD_COLS
    jge   .collide          ; right wall

    ; check board cell
    imul  eax, BOARD_COLS
    add   eax, edx
    lea   rcx, [board]
    movzx eax, byte [rcx + rax]
    test  eax, eax
    jnz   .collide

.pc_next:
    inc   r8d
    jmp   .pc_loop
.pr_next:
    inc   ebx
    jmp   .pr_loop

.clear:
    xor   eax, eax
    jmp   .done
.collide:
    mov   eax, 1
.done:
    pop   rbx
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; DRAW_CELL: render one board cell
; In:  CL=board_row, DL=board_col, R8B=color_type (0=empty)
; ═════════════════════════════════════════════════════════════════════════════
draw_cell:
    push  r12
    push  r13
    push  r14

    movzx r12d, cl
    movzx r13d, dl
    movzx r14d, r8b

    ; cursor position
    mov   ecx, BOARD_Y
    add   ecx, r12d
    mov   eax, r13d
    imul  eax, CELL_W
    mov   edx, BOARD_X + 1         ; +1 to skip left border
    add   edx, eax
    call  goto_xy

    test  r14d, r14d
    jz    .empty

    ; filled: set background color, two spaces, reset
    lea   rcx, [piece_bg_colors]
    movzx eax, byte [rcx + r14]
    call  set_bg_color
    mov   al, ' '
    call  buf_byte
    call  buf_byte
    call  buf_reset
    jmp   .done
.empty:
    mov   al, '.'
    call  buf_byte
    call  buf_byte
.done:
    pop   r14
    pop   r13
    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; DRAW_BOARD: render all 200 cells
; ═════════════════════════════════════════════════════════════════════════════
draw_board:
    push  r12
    push  r13

    xor   r12d, r12d        ; row
.row:
    cmp   r12d, BOARD_ROWS
    jge   .done
    xor   r13d, r13d        ; col
.col:
    cmp   r13d, BOARD_COLS
    jge   .next_row

    mov   eax, r12d
    imul  eax, BOARD_COLS
    add   eax, r13d
    lea   rcx, [board]
    movzx r8d, byte [rcx + rax]

    mov   cl,  r12b
    mov   dl,  r13b
    mov   r8b, r8b
    call  draw_cell

    inc   r13d
    jmp   .col
.next_row:
    inc   r12d
    jmp   .row
.done:
    pop   r13
    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; DRAW_PIECE: render or erase current piece
; AL=0 → erase (show board cell underneath), AL=1 → draw colored
; ═════════════════════════════════════════════════════════════════════════════
draw_piece:
    push  rbx
    push  r12
    push  r13
    push  r14
    push  r15

    movzx r15d, al          ; draw flag (0=erase,1=draw)

    xor   r12d, r12d        ; piece row 0..3
.pr:
    cmp   r12d, 4
    jge   .done

    movzx ecx, byte [cur_type]
    movzx edx, byte [cur_rot]
    mov   r8b, r12b
    call  get_piece_row
    movzx r13d, al          ; row bitmask

    xor   r14d, r14d        ; piece col 0..3
.pc:
    cmp   r14d, 4
    jge   .pr_next

    ; test bit
    mov   eax, r13d
    mov   ecx, 3
    sub   ecx, r14d
    shr   eax, cl
    and   eax, 1
    test  eax, eax
    jz    .pc_next

    ; board position
    movsx ebx, byte [cur_y]
    add   ebx, r12d         ; board row
    js    .pc_next
    cmp   ebx, BOARD_ROWS
    jge   .pc_next

    movsx ecx, byte [cur_x]
    add   ecx, r14d         ; board col
    js    .pc_next
    cmp   ecx, BOARD_COLS
    jge   .pc_next

    ; determine display color
    test  r15d, r15d
    jz    .erase_color
    movzx r8d, byte [cur_type]
    inc   r8d               ; color = type + 1
    jmp   .cell_draw
.erase_color:
    ; show board contents at this cell
    push  rbx
    push  rcx
    imul  ebx, BOARD_COLS
    add   ebx, ecx
    lea   rdx, [board]
    movzx r8d, byte [rdx + rbx]
    pop   rcx
    pop   rbx
.cell_draw:
    ; ebx = board_row, ecx = board_col, r8d = color
    mov   edx, ecx          ; edx = board_col (save before cl clobbers ecx)
    mov   cl,  bl           ; cl  = board_row
    call  draw_cell

.pc_next:
    inc   r14d
    jmp   .pc
.pr_next:
    inc   r12d
    jmp   .pr
.done:
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    pop   rbx
    ret

; ─── Thin wrappers ───────────────────────────────────────────────────────────
erase_piece:
    xor   al, al
    jmp   draw_piece

show_piece:
    mov   al, 1
    jmp   draw_piece

draw_next_preview:
    push  r12
    push  r13
    push  r14
    push  r15

    movzx r15d, byte [next_type]

    xor   r12d, r12d        ; pr = piece row
.pr_loop:
    cmp   r12d, 4
    jge   .done

    xor   r13d, r13d        ; pc = piece col
.pc_loop:
    cmp   r13d, 4
    jge   .next_pr

    ; fetch bitmask for this row
    mov   cl,  r15b
    xor   dl,  dl
    mov   r8b, r12b
    call  get_piece_row
    movzx r14d, al

    ; test bit for this col
    mov   eax, r14d
    mov   ecx, 3
    sub   ecx, r13d
    shr   eax, cl
    and   eax, 1

    ; goto cell position
    push  rax
    mov   ecx, HUD_ROW + 2
    add   ecx, r12d
    mov   edx, HUD_COL
    mov   eax, r13d
    imul  eax, CELL_W
    add   edx, eax
    call  goto_xy
    pop   rax

    test  eax, eax
    jz    .draw_e

    ; draw filled
    movzx eax, byte [next_type]
    inc   eax
    lea   rcx, [piece_bg_colors]
    movzx eax, byte [rcx + rax]
    call  set_bg_color
    mov   al, ' '
    call  buf_byte
    call  buf_byte
    call  buf_reset
    jmp   .col_done
.draw_e:
    mov   al, ' '
    call  buf_byte
    call  buf_byte
.col_done:
    inc   r13d
    jmp   .pc_loop
.next_pr:
    inc   r12d
    jmp   .pr_loop
.done:
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; DRAW_HUD: update score / level / lines numbers
; ═════════════════════════════════════════════════════════════════════════════
draw_hud:
    ; Score
    mov   ecx, HUD_ROW + 8
    mov   edx, HUD_COL
    call  goto_xy
    mov   rax, [score]
    call  buf_uint
    mov   al, ' '
    call  buf_byte
    call  buf_byte
    call  buf_byte

    ; Level
    mov   ecx, HUD_ROW + 11
    mov   edx, HUD_COL
    call  goto_xy
    movzx eax, byte [level]
    call  buf_uint
    mov   al, ' '
    call  buf_byte
    call  buf_byte

    ; Lines
    mov   ecx, HUD_ROW + 14
    mov   edx, HUD_COL
    call  goto_xy
    mov   eax, [lines_cleared]
    call  buf_uint
    mov   al, ' '
    call  buf_byte
    call  buf_byte
    call  buf_byte
    ret

; ═════════════════════════════════════════════════════════════════════════════
; DRAW_BORDER: static frame + HUD labels
; ═════════════════════════════════════════════════════════════════════════════
draw_border:
    push  r12

    ; ── top edge ─────────────────────────────────────────────────────────────
    mov   ecx, BOARD_Y - 1
    mov   edx, BOARD_X - 1
    call  goto_xy
    lea   rcx, [BOX_TL]
    call  buf_cstr
    xor   r12d, r12d
.top_h:
    cmp   r12d, BOARD_COLS * CELL_W
    jge   .top_h_done
    lea   rcx, [BOX_H]
    call  buf_cstr
    inc   r12d
    jmp   .top_h
.top_h_done:
    lea   rcx, [BOX_TR]
    call  buf_cstr

    ; ── sides ─────────────────────────────────────────────────────────────────
    xor   r12d, r12d
.sides:
    cmp   r12d, BOARD_ROWS
    jge   .sides_done
    mov   ecx, BOARD_Y
    add   ecx, r12d
    mov   edx, BOARD_X - 1
    call  goto_xy
    lea   rcx, [BOX_V]
    call  buf_cstr
    mov   ecx, BOARD_Y
    add   ecx, r12d
    mov   edx, BOARD_X + BOARD_COLS * CELL_W
    call  goto_xy
    lea   rcx, [BOX_V]
    call  buf_cstr
    inc   r12d
    jmp   .sides
.sides_done:

    ; ── bottom edge ───────────────────────────────────────────────────────────
    mov   ecx, BOARD_Y + BOARD_ROWS
    mov   edx, BOARD_X - 1
    call  goto_xy
    lea   rcx, [BOX_BL]
    call  buf_cstr
    xor   r12d, r12d
.bot_h:
    cmp   r12d, BOARD_COLS * CELL_W
    jge   .bot_h_done
    lea   rcx, [BOX_H]
    call  buf_cstr
    inc   r12d
    jmp   .bot_h
.bot_h_done:
    lea   rcx, [BOX_BR]
    call  buf_cstr

    ; ── HUD labels ────────────────────────────────────────────────────────────
    %macro HUD_LABEL 2          ; row-offset, label_ref
        mov  ecx, HUD_ROW + %1
        mov  edx, HUD_COL
        call goto_xy
        lea  rcx, [%2]
        call buf_cstr
    %endmacro

    HUD_LABEL 0,  STR_NEXT
    HUD_LABEL 7,  STR_SCORE
    HUD_LABEL 10, STR_LEVEL
    HUD_LABEL 13, STR_LINES
    HUD_LABEL 16, STR_C1
    HUD_LABEL 17, STR_C2
    HUD_LABEL 18, STR_C3
    HUD_LABEL 19, STR_C4
    HUD_LABEL 20, STR_C5

    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; LOCK_PIECE: copy piece cells onto board
; ═════════════════════════════════════════════════════════════════════════════
lock_piece:
    push  r12
    push  r13

    movzx r12d, byte [cur_type]
    movzx r13d, byte [cur_rot]

    xor   ebx, ebx          ; piece row
.pr:
    cmp   ebx, 4
    jge   .done

    mov   cl,  r12b
    mov   dl,  r13b
    mov   r8b, bl
    call  get_piece_row
    movzx ecx, al
    test  ecx, ecx
    jz    .pr_next

    movzx edx, al           ; bitmask
    xor   r8d, r8d          ; piece col
.pc:
    cmp   r8d, 4
    jge   .pr_next

    mov   eax, edx
    mov   ecx, 3
    sub   ecx, r8d
    shr   eax, cl
    and   eax, 1
    test  eax, eax
    jz    .pc_next

    movsx eax, byte [cur_y]
    add   eax, ebx
    js    .pc_next
    cmp   eax, BOARD_ROWS
    jge   .pc_next

    movsx ecx, byte [cur_x]
    add   ecx, r8d
    js    .pc_next
    cmp   ecx, BOARD_COLS
    jge   .pc_next

    imul  eax, BOARD_COLS
    add   eax, ecx
    lea   rcx, [board]
    movzx r9d, byte [cur_type]
    inc   r9d
    mov   [rcx + rax], r9b

.pc_next:
    inc   r8d
    jmp   .pc
.pr_next:
    inc   ebx
    jmp   .pr
.done:
    pop   r13
    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; CLEAR_LINES → EAX = number of lines cleared
; ═════════════════════════════════════════════════════════════════════════════
clear_lines:
    push  rbx
    push  r12
    push  r13
    push  rdi
    push  rsi

    mov   r12d, BOARD_ROWS - 1  ; read ptr (bottom)
    mov   r13d, BOARD_ROWS - 1  ; write ptr (bottom)
    xor   ebx, ebx              ; cleared count

.scan:
    cmp   r12d, 0
    jl    .fill_zeros

    ; check if row r12 is full
    mov   eax, r12d
    imul  eax, BOARD_COLS       ; row base offset
    lea   rdx, [board]
    xor   ecx, ecx              ; col
.check_col:
    cmp   ecx, BOARD_COLS
    jge   .is_full
    lea   rsi, [rdx + rax]
    movzx r8d, byte [rsi + rcx]
    test  r8d, r8d
    jz    .not_full
    inc   ecx
    jmp   .check_col
.not_full:
    ; copy row r12 → row r13 if different
    cmp   r12d, r13d
    je    .no_copy_needed
    mov   eax, r12d
    imul  eax, BOARD_COLS
    lea   rsi, [rdx + rax]
    mov   eax, r13d
    imul  eax, BOARD_COLS
    lea   rdi, [rdx + rax]
    mov   ecx, BOARD_COLS
    rep movsb
.no_copy_needed:
    dec   r12d
    dec   r13d
    jmp   .scan

.is_full:
    inc   ebx
    dec   r12d
    jmp   .scan

.fill_zeros:
    ; zero-fill rows 0..r13d
    test  r13d, r13d
    js    .done
    lea   rdx, [board]
.fill_loop:
    cmp   r13d, 0
    jl    .done
    mov   eax, r13d
    imul  eax, BOARD_COLS
    lea   rdi, [rdx + rax]
    xor   eax, eax
    mov   ecx, BOARD_COLS
    rep stosb
    dec   r13d
    jmp   .fill_loop

.done:
    mov   eax, ebx
    pop   rsi
    pop   rdi
    pop   r13
    pop   r12
    pop   rbx
    ret

; ═════════════════════════════════════════════════════════════════════════════
; UPDATE_SCORE (EAX = lines cleared)
; ═════════════════════════════════════════════════════════════════════════════
update_score:
    push  r12
    mov   r12d, eax
    test  r12d, r12d
    jz    .done

    add   [lines_cleared], r12d

    dec   r12d
    cmp   r12d, 3
    jle   .idx_ok
    mov   r12d, 3
.idx_ok:
    lea   rcx, [score_table]
    mov   eax, [rcx + r12*4]
    movzx ecx, byte [level]
    imul  eax, ecx
    cdqe
    add   [score], rax

    ; level up every 10 lines
    mov   eax, [lines_cleared]
    xor   edx, edx
    mov   ecx, 10
    div   ecx
    inc   eax                   ; target level
    movzx ecx, byte [level]
    cmp   eax, ecx
    jle   .done
    cmp   eax, 10
    jle   .set_lv
    mov   eax, 10
.set_lv:
    mov   [level], al
.done:
    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; GET_FALL_DELAY → EAX (ms)
; ═════════════════════════════════════════════════════════════════════════════
get_fall_delay:
    movzx eax, byte [level]
    dec   eax
    cmp   eax, FALL_LEVELS - 1
    jle   .ok
    mov   eax, FALL_LEVELS - 1
.ok:
    lea   rcx, [fall_delays]
    mov   eax, [rcx + rax*4]
    ret

; ═════════════════════════════════════════════════════════════════════════════
; SPAWN_PIECE: promote next → cur, generate new next
; ═════════════════════════════════════════════════════════════════════════════
spawn_piece:
    PROC_ENTER

    movzx eax, byte [next_type]
    mov   [cur_type], al
    mov   byte [cur_rot], 0
    mov   byte [cur_x],   (BOARD_COLS / 2) - 2
    mov   byte [cur_y],   0

    call  lcg_rand
    mov   [next_type], al

    call  GetTickCount64
    mov   [fall_time], rax
    mov   qword [lock_time], 0

    PROC_LEAVE

; ═════════════════════════════════════════════════════════════════════════════
; TRY_ROTATE: CW rotation with wall kick
; ═════════════════════════════════════════════════════════════════════════════
try_rotate:
    push  r12
    push  r13
    push  r14

    movzx r12d, byte [cur_type]
    movzx r13d, byte [cur_rot]
    inc   r13d
    and   r13d, 3               ; new rotation

    lea   r14, [kick_offsets]
    xor   ecx, ecx              ; kick index 0..2
.kick_loop:
    cmp   ecx, 3
    jge   .no_rot

    movsx eax, byte [r14 + rcx]
    movzx r8d, byte [cur_x]
    add   r8d, eax              ; try_x

    push  rcx                   ; save kick index
    mov   cl,  r12b             ; type
    mov   dl,  r13b             ; new_rot
    movsx r9d, byte [cur_y]
    mov   r9b, r9b
    call  check_collision
    pop   rcx
    test  al, al
    jz    .apply_kick

    inc   ecx
    jmp   .kick_loop

.apply_kick:
    movsx eax, byte [r14 + rcx]
    movzx edx, byte [cur_x]
    add   edx, eax
    mov   [cur_x], dl
    mov   [cur_rot], r13b
.no_rot:
    pop   r14
    pop   r13
    pop   r12
    ret

; ═════════════════════════════════════════════════════════════════════════════
; MOVE_LEFT / MOVE_RIGHT
; ═════════════════════════════════════════════════════════════════════════════
move_left:
    movzx r8d, byte [cur_x]
    dec   r8d
    movzx ecx, byte [cur_type]
    movzx edx, byte [cur_rot]
    movsx r9d, byte [cur_y]
    mov   r9b, r9b
    call  check_collision
    test  al, al
    jnz   .done
    movzx eax, byte [cur_x]
    dec   eax
    mov   [cur_x], al
.done:
    ret

move_right:
    movzx r8d, byte [cur_x]
    inc   r8d
    movzx ecx, byte [cur_type]
    movzx edx, byte [cur_rot]
    movsx r9d, byte [cur_y]
    mov   r9b, r9b
    call  check_collision
    test  al, al
    jnz   .done
    movzx eax, byte [cur_x]
    inc   eax
    mov   [cur_x], al
.done:
    ret

; ═════════════════════════════════════════════════════════════════════════════
; SOFT_DROP → AL=0 moved, AL=1 locked
; ═════════════════════════════════════════════════════════════════════════════
soft_drop:
    movsx r9d, byte [cur_y]
    inc   r9d
    movzx ecx, byte [cur_type]
    movzx edx, byte [cur_rot]
    movzx r8d, byte [cur_x]
    mov   r8b, r8b
    mov   r9b, r9b
    call  check_collision
    test  al, al
    jz    .move
    call  lock_piece
    mov   al, 1
    ret
.move:
    movsx eax, byte [cur_y]
    inc   eax
    mov   [cur_y], al
    xor   al, al
    ret

; ═════════════════════════════════════════════════════════════════════════════
; HARD_DROP
; ═════════════════════════════════════════════════════════════════════════════
hard_drop:
.loop:
    call  soft_drop
    test  al, al
    jz    .loop
    ret

; ═════════════════════════════════════════════════════════════════════════════
; POST_LOCK: clear lines, update score, draw board, spawn, check game over
; Returns: AL=1 game over
; ═════════════════════════════════════════════════════════════════════════════
post_lock:
    PROC_ENTER

    call  clear_lines
    call  update_score
    call  draw_board
    call  draw_next_preview
    call  spawn_piece
    call  draw_next_preview

    ; check if new piece spawns into collision
    movzx ecx, byte [cur_type]
    movzx edx, byte [cur_rot]
    movzx r8d, byte [cur_x]
    mov   r8b, r8b
    movsx r9d, byte [cur_y]
    mov   r9b, r9b
    call  check_collision
    test  al, al
    jz    .ok

    ; game over
    call  show_piece
    call  draw_hud
    call  flush_buf
    mov   al, 1
    PROC_LEAVE

.ok:
    call  show_piece
    call  draw_hud
    call  flush_buf
    xor   al, al
    PROC_LEAVE

; ═════════════════════════════════════════════════════════════════════════════
; HANDLE_INPUT → EAX: 0=nothing, 1=redraw done, 2=locked
; ═════════════════════════════════════════════════════════════════════════════
handle_input:
    PROC_ENTER
    sub   rsp, 16           ; extra locals

    xor   r10d, r10d        ; result (use volatile r10, not callee-saved r12)

    ; ── ESC ──────────────────────────────────────────────────────────────────
    mov   ecx, VK_ESCAPE
    call  GetAsyncKeyState
    and   eax, 0x8000
    jz    .chk_left
    call  cleanup_console
    xor   ecx, ecx
    call  ExitProcess

    ; ── LEFT ─────────────────────────────────────────────────────────────────
.chk_left:
    mov   ecx, VK_LEFT
    call  GetAsyncKeyState
    and   eax, 0x8000
    jz    .left_release

    movzx ecx, byte [prev_left]
    test  ecx, ecx
    jnz   .left_das

    ; fresh press
    mov   byte [prev_left], 1
    call  erase_piece
    call  move_left
    call  show_piece
    mov   r10d, 1
    call  GetTickCount64
    mov   [das_time], rax
    mov   byte [das_active], 0
    jmp   .chk_right

.left_das:
    call  GetTickCount64
    mov   rcx, [das_time]
    sub   rax, rcx
    movzx ecx, byte [das_active]
    test  ecx, ecx
    jnz   .left_rep
    cmp   rax, 167
    jl    .chk_right
    mov   byte [das_active], 1
    jmp   .left_do_move
.left_rep:
    cmp   rax, 33
    jl    .chk_right
.left_do_move:
    call  GetTickCount64
    mov   [das_time], rax
    call  erase_piece
    call  move_left
    call  show_piece
    mov   r10d, 1
    jmp   .chk_right

.left_release:
    mov   byte [prev_left], 0
    mov   byte [das_active], 0

    ; ── RIGHT ────────────────────────────────────────────────────────────────
.chk_right:
    mov   ecx, VK_RIGHT
    call  GetAsyncKeyState
    and   eax, 0x8000
    jz    .right_release

    movzx ecx, byte [prev_right]
    test  ecx, ecx
    jnz   .right_das

    mov   byte [prev_right], 1
    call  erase_piece
    call  move_right
    call  show_piece
    mov   r10d, 1
    call  GetTickCount64
    mov   [das_time], rax
    mov   byte [das_active], 0
    jmp   .chk_up

.right_das:
    call  GetTickCount64
    mov   rcx, [das_time]
    sub   rax, rcx
    movzx ecx, byte [das_active]
    test  ecx, ecx
    jnz   .right_rep
    cmp   rax, 167
    jl    .chk_up
    mov   byte [das_active], 1
    jmp   .right_do_move
.right_rep:
    cmp   rax, 33
    jl    .chk_up
.right_do_move:
    call  GetTickCount64
    mov   [das_time], rax
    call  erase_piece
    call  move_right
    call  show_piece
    mov   r10d, 1
    jmp   .chk_up

.right_release:
    mov   byte [prev_right], 0

    ; ── UP (rotate) ──────────────────────────────────────────────────────────
.chk_up:
    mov   ecx, VK_UP
    call  GetAsyncKeyState
    and   eax, 0x8000
    jz    .up_release

    movzx ecx, byte [prev_up]
    test  ecx, ecx
    jnz   .chk_down

    mov   byte [prev_up], 1
    call  erase_piece
    call  try_rotate
    call  show_piece
    mov   r10d, 1
    jmp   .chk_down

.up_release:
    mov   byte [prev_up], 0

    ; ── DOWN (soft drop) ─────────────────────────────────────────────────────
.chk_down:
    mov   ecx, VK_DOWN
    call  GetAsyncKeyState
    and   eax, 0x8000
    jz    .chk_space

    call  erase_piece
    call  soft_drop
    test  al, al
    jnz   .locked_by_input
    call  show_piece
    mov   r10d, 1
    jmp   .chk_space

    ; ── SPACE (hard drop) ────────────────────────────────────────────────────
.chk_space:
    mov   ecx, VK_SPACE
    call  GetAsyncKeyState
    and   eax, 0x8000
    jz    .space_release

    movzx ecx, byte [prev_space]
    test  ecx, ecx
    jnz   .done

    mov   byte [prev_space], 1
    call  erase_piece
    call  hard_drop
.locked_by_input:
    mov   r10d, 2           ; locked
    jmp   .done

.space_release:
    mov   byte [prev_space], 0

.done:
    mov   eax, r10d
    add   rsp, 16
    PROC_LEAVE

; ═════════════════════════════════════════════════════════════════════════════
; GAME_OVER_SCREEN: display message, wait R / ESC
; Returns: game_over_flag set (1=quit, 2=restart)
; ═════════════════════════════════════════════════════════════════════════════
game_over_screen:
    PROC_ENTER

    mov   ecx, BOARD_Y + BOARD_ROWS / 2 - 1
    mov   edx, BOARD_X + 1
    call  goto_xy
    lea   rcx, [ESC_BOLD]
    call  buf_cstr
    lea   rcx, [STR_GO]
    call  buf_cstr
    call  buf_reset

    mov   ecx, BOARD_Y + BOARD_ROWS / 2
    mov   edx, BOARD_X + 1
    call  goto_xy
    lea   rcx, [STR_RST]
    call  buf_cstr
    call  flush_buf

.wait:
    mov   ecx, VK_R
    call  GetAsyncKeyState
    and   eax, 0x8000
    jnz   .restart

    mov   ecx, VK_ESCAPE
    call  GetAsyncKeyState
    and   eax, 0x8000
    jnz   .quit

    mov   ecx, 16
    call  Sleep
    jmp   .wait

.restart:
    mov   byte [game_over_flag], 2
    PROC_LEAVE
.quit:
    call  cleanup_console
    xor   ecx, ecx
    call  ExitProcess

; ═════════════════════════════════════════════════════════════════════════════
; INIT_GAME: zero everything, seed, spawn first piece
; ═════════════════════════════════════════════════════════════════════════════
init_game:
    PROC_ENTER
    push  rdi

    lea   rdi, [board]
    xor   eax, eax
    mov   ecx, 200
    rep   stosb

    mov   byte [cur_type],  0
    mov   byte [cur_rot],   0
    mov   byte [cur_x],     3
    mov   byte [cur_y],     0
    mov   byte [next_type], 0
    mov   qword [score],    0
    mov   byte [level],     1
    mov   dword [lines_cleared], 0
    mov   byte [game_over_flag], 0
    mov   byte [prev_left],   0
    mov   byte [prev_right],  0
    mov   byte [prev_up],     0
    mov   byte [prev_space],  0
    mov   byte [das_active],  0
    mov   qword [lock_time],  0
    mov   dword [render_len], 0

    call  GetTickCount64
    mov   [rand_seed], rax

    call  lcg_rand
    mov   [next_type], al
    call  spawn_piece

    pop   rdi
    PROC_LEAVE

; ═════════════════════════════════════════════════════════════════════════════
; FULL_REDRAW: clear screen and draw everything
; ═════════════════════════════════════════════════════════════════════════════
full_redraw:
    PROC_ENTER

    lea   rcx, [ESC_CLEAR]
    call  buf_cstr
    call  draw_border
    call  draw_board
    call  show_piece
    call  draw_next_preview
    call  draw_hud
    call  flush_buf

    PROC_LEAVE

; ═════════════════════════════════════════════════════════════════════════════
; MAIN
; ═════════════════════════════════════════════════════════════════════════════
main:
    push  rbp
    mov   rbp, rsp
    push  r12               ; save callee-saved regs BEFORE shadow space
    push  r13
    sub   rsp, 32           ; shadow space (RSP now 16-aligned)

    call  init_console

.restart:
    call  init_game
    call  full_redraw

.game_loop:
    ; ── Input ────────────────────────────────────────────────────────────────
    call  handle_input
    mov   r12d, eax         ; 0=nothing, 1=moved, 2=locked

    cmp   r12d, 2
    jne   .gravity

    ; locked by player input
    call  post_lock
    test  al, al
    jnz   .do_game_over
    jmp   .gravity

    ; ── Gravity ──────────────────────────────────────────────────────────────
.gravity:
    ; Lock delay check (runs every tick when piece is on ground)
    cmp   qword [lock_time], 0
    jz    .fall_check

    ; Verify piece is still on ground (player may have slid it off)
    movsx r9d, byte [cur_y]
    inc   r9d
    movzx ecx, byte [cur_type]
    movzx edx, byte [cur_rot]
    movzx r8d, byte [cur_x]
    mov   r8b, r8b
    mov   r9b, r9b
    call  check_collision
    test  al, al
    jz    .cancel_lock           ; piece can fall again - cancel lock timer

    ; Still on ground - check if 500 ms have elapsed
    call  GetTickCount64
    mov   rcx, [lock_time]
    sub   rax, rcx
    cmp   rax, 500
    jb    .sleep                 ; not yet

    ; Lock delay expired: lock the piece
    call  erase_piece
    call  soft_drop              ; calls lock_piece internally
    mov   qword [lock_time], 0
    call  post_lock
    test  al, al
    jnz   .do_game_over
    jmp   .sleep

.cancel_lock:
    mov   qword [lock_time], 0

    ; Fall timer check
.fall_check:
    call  get_fall_delay         ; EAX = delay ms
    push  rax
    call  GetTickCount64
    mov   rcx, [fall_time]
    sub   rax, rcx               ; elapsed ms
    pop   rcx                    ; delay ms
    cmp   rax, rcx
    jb    .sleep

    ; Fall timer fired - can the piece move down?
    movsx r9d, byte [cur_y]
    inc   r9d
    movzx ecx, byte [cur_type]
    movzx edx, byte [cur_rot]
    movzx r8d, byte [cur_x]
    mov   r8b, r8b
    mov   r9b, r9b
    call  check_collision
    test  al, al
    jnz   .on_ground             ; piece is resting on something

    ; Piece can fall
    call  erase_piece
    call  soft_drop
    call  GetTickCount64
    mov   [fall_time], rax       ; reset fall timer after each step
    call  show_piece
    call  draw_hud
    call  flush_buf
    jmp   .sleep

.on_ground:
    ; Fall timer fired but piece can't fall - start lock timer if not yet running
    cmp   qword [lock_time], 0
    jne   .sleep
    call  GetTickCount64
    mov   [lock_time], rax
    mov   [fall_time], rax       ; reset fall timer

.sleep:
    call  flush_buf
    mov   ecx, 16
    call  Sleep
    jmp   .game_loop

.do_game_over:
    call  game_over_screen
    movzx eax, byte [game_over_flag]
    cmp   eax, 2
    je    .restart
    ; ESC handled inside game_over_screen, won't reach here normally
    jmp   .exit

.exit:
    call  cleanup_console
    add   rsp, 32
    pop   r13
    pop   r12
    xor   ecx, ecx
    call  ExitProcess
