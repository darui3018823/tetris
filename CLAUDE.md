# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```powershell
.\build.ps1        # assemble + link → tetris.exe
.\tetris.exe       # run (terminal ≥ 80×25 recommended)
```

Manual build:
```powershell
& "C:\Program Files\NASM\nasm.exe" -f win64 tetris.asm -o tetris.obj
& "C:\msys64\mingw64\bin\gcc.exe" -o tetris.exe tetris.obj -lkernel32 -luser32 -nostartfiles -e main
```

Toolchain: NASM 3.x at `C:\Program Files\NASM\nasm.exe`, MinGW64 GCC at `C:\msys64\mingw64\bin\gcc.exe`.

There are no tests. Verification means running the binary and observing behavior.

## Architecture

Single file (`tetris.asm`, ~1855 lines). Three sections:

**`.data`** — all static data:
- `tetromino_data`: 7 pieces × 4 rotations × 4 rows = 112 bytes. Each byte is a 4-bit column bitmask (bit3=leftmost). Piece types are 0-indexed (0=I, 1=O, 2=T, 3=S, 4=Z, 5=J, 6=L).
- `piece_bg_colors`: maps type index to ANSI background color code. Color stored as `type+1` (so 0 = empty).
- `fall_delays`: 10 dwords (NES-style ms per level).
- `score_table`: 4 dwords for 1–4 line clears, multiplied by level.
- ANSI escape sequences and UTF-8 box-drawing characters as byte arrays.

**`.bss`** — mutable state:
- `board[200]`: flat 20×10 grid, each byte = color type (0=empty, 1–7=piece color).
- Current piece: `cur_type`, `cur_rot`, `cur_x`, `cur_y` (signed — negative means above visible area during spawn).
- Timers: `fall_time`, `lock_time`, `das_time` (all `GetTickCount64` ticks).
- `render_buf[16384]` + `render_len`: the output buffer flushed in one `WriteFile` call per frame.

**`.text`** — code sections in order:

| Subsystem | Key procedures |
|-----------|---------------|
| Render buffer | `buf_byte`, `buf_cstr`, `buf_uint`, `flush_buf`, `goto_xy`, `set_bg_color` |
| Drawing | `draw_cell`, `draw_board`, `draw_piece`/`erase_piece`/`show_piece`, `draw_next_preview`, `draw_hud`, `draw_action`, `draw_border` |
| Piece logic | `get_piece_row`, `check_collision`, `try_rotate`, `move_left`, `move_right`, `soft_drop`, `hard_drop`, `lock_piece`, `spawn_piece` |
| Game logic | `clear_lines`, `update_score`, `post_lock`, `check_tspin`, `init_game`, `full_redraw` |
| Input | `handle_input` (polls `GetAsyncKeyState` each frame; DAS: 167 ms initial, 33 ms repeat) |
| Entry | `main` → `init_console` → restart loop → `game_loop` |

## Game Loop (main)

`main` runs a ~60 fps busy loop (16 ms `Sleep` per tick):
1. `handle_input` — returns 0 (nothing), 1 (moved/rotated), or 2 (piece locked by player).
2. If locked → `post_lock` (T-spin check → `clear_lines` → `update_score` → `spawn_piece` → game-over check).
3. Gravity: compare `GetTickCount64` against `fall_time`; drop one row when elapsed ≥ `get_fall_delay()`.
4. Lock delay: once a piece lands, start `lock_time`; lock after 500 ms unless the piece slides off.

## ABI & Conventions

- Windows x64 calling convention throughout: 32-byte shadow space on every call, `rcx/rdx/r8/r9` for first four args.
- Callee-saved registers used to hold locals across calls: `r12`, `r13`, `r14`, `r15`, `rbx`.
- `PROC_ENTER`/`PROC_LEAVE` macros: push `rbp`, sub 32 for shadow, add 32, pop `rbp`, ret.
- All rendering is accumulated into `render_buf` and flushed as a single `WriteFile` — never call Win32 I/O directly.
- `cur_y` is a **signed** byte; pieces spawn at `cur_y = -1` so they enter from above row 0. Sign-extend with `movsx` before arithmetic.
