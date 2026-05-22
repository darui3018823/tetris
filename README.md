# Tetris

x86_64 NASM アセンブリで書いた Windows TUI テトリスです。

## 必要なもの

| ツール | 入手方法 |
|--------|----------|
| NASM 3.x | `winget install NASM.NASM` |
| MinGW64 GCC | [MSYS2](https://www.msys2.org/) → `pacman -S mingw-w64-x86_64-gcc` |

インストール後のパス:
- `C:\Program Files\NASM\nasm.exe`
- `C:\msys64\mingw64\bin\gcc.exe`

## ビルド

```powershell
.\build.ps1
```

手動でやる場合:

```powershell
& "C:\Program Files\NASM\nasm.exe" -f win64 tetris.asm -o tetris.obj
& "C:\msys64\mingw64\bin\gcc.exe" -o tetris.exe tetris.obj -lkernel32 -nostartfiles -e main
```

## 実行

```powershell
.\tetris.exe
```

ターミナルは 80×25 以上推奨。

## 操作

| キー | 動作 |
|------|------|
| `←` `→` | 左右移動 |
| `↑` | 回転（時計回り） |
| `↓` | ソフトドロップ |
| `Space` | ハードドロップ |
| `R` | リスタート（ゲームオーバー時） |
| `ESC` | 終了 |

## スコア

| ライン消去 | 得点 |
|------------|------|
| 1ライン | 100 × レベル |
| 2ライン | 300 × レベル |
| 3ライン | 500 × レベル |
| 4ライン | 800 × レベル |

10ライン消去ごとにレベルアップ（最大10）。レベルが上がるほど落下速度が増します。

## 構成

```
tetris/
├── tetris.asm   # ゲーム本体（x86_64 NASM, ~1600行）
├── build.ps1    # ビルドスクリプト
└── README.md
```

## 技術メモ

- **アセンブラ**: NASM x86_64
- **リンカ**: MinGW64 GCC（`kernel32.dll` のみ使用）
- **描画**: ANSI VT100 エスケープシーケンス（`WriteFile` でバッファ一括出力）
- **入力**: `GetAsyncKeyState`（ノンブロッキング）
- **タイマー**: `GetTickCount64`
- **ABI**: Windows x64 calling convention（shadow space 32 bytes、callee-saved r12-r15）
- **回転**: SRS 壁キック簡易版（オフセット 0, +1, -1 の3試行）
- **DAS**: 初回 167ms、連続 33ms
