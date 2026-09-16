param([string]$Nasm = '', [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    if (!$Nasm) {
        $localNasm = Join-Path $PSScriptRoot 'tools/nasm-2.16.03/nasm.exe'
        if (Test-Path $localNasm) { $Nasm = $localNasm } else { $Nasm = 'nasm' }
    }
    & $Python src/make_assets.py
    if ($LASTEXITCODE -ne 0) { throw 'Asset generation failed' }
    & $Python src/make_music.py
    if ($LASTEXITCODE -ne 0) { throw 'Music generation failed' }
    New-Item -ItemType Directory -Force build | Out-Null
    & $Nasm -f bin -Wall -w-reloc-abs-word -Werror -I src/ -l build/roto.lst src/roto.asm -o ROTO.com
    if ($LASTEXITCODE -ne 0) { throw 'NASM assembly failed' }
    $size = (Get-Item ROTO.com).Length
    if ($size -le 0 -or $size -gt 65280) { throw 'Invalid COM size' }
    Get-FileHash ROTO.com -Algorithm SHA256
    Write-Output "ROTO.com: $size bytes"
} finally { Pop-Location }
