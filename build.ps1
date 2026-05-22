# build.ps1 - Build script for Tetris (NASM x64 + MinGW64 GCC)

$NASM  = "C:\Program Files\NASM\nasm.exe"
$GCC   = "C:\msys64\mingw64\bin\gcc.exe"
$SRC   = "tetris.asm"
$OBJ   = "tetris.obj"
$EXE   = "tetris.exe"

# Check for NASM
if (-not (Test-Path $NASM)) {
    Write-Host "NASM not found. Installing via winget..."
    winget install NASM.NASM --silent
    if (-not (Test-Path $NASM)) {
        Write-Error "NASM install failed. Install manually: winget install NASM.NASM"
        exit 1
    }
}

# Check for GCC
if (-not (Test-Path $GCC)) {
    Write-Error "GCC not found at $GCC. Install MSYS2 with mingw-w64-x86_64-gcc."
    exit 1
}

Write-Host "Assembling $SRC..."
& $NASM -f win64 $SRC -o $OBJ
if ($LASTEXITCODE -ne 0) { Write-Error "Assembly failed"; exit 1 }

Write-Host "Linking $OBJ..."
& $GCC -o $EXE $OBJ -lkernel32 -luser32 -nostartfiles -e main
if ($LASTEXITCODE -ne 0) { Write-Error "Link failed"; exit 1 }

Write-Host "Build OK -> $EXE"
