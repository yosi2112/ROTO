param([string]$AswRoot = 'E:/aswcurr', [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    & $Python src/make_assets.py
    if ($LASTEXITCODE -ne 0) { throw 'Asset generation failed' }
    & $Python src/make_music.py
    if ($LASTEXITCODE -ne 0) { throw 'Music generation failed' }
    & $Python src/make_asw.py
    if ($LASTEXITCODE -ne 0) { throw 'ASW source generation failed' }
    New-Item -ItemType Directory -Force build | Out-Null
    & (Join-Path $AswRoot 'bin/asw.exe') src/asw/roto.asm -o build/roto-asw.p
    if ($LASTEXITCODE -ne 0) { throw 'ASW assembly failed' }
    & (Join-Path $AswRoot 'bin/p2bin.exe') build/roto-asw.p ROTOASW.com -r '$-$'
    if ($LASTEXITCODE -ne 0) { throw 'ASW binary conversion failed' }
    $size = (Get-Item ROTOASW.com).Length
    if ($size -le 0 -or $size -gt 65280) { throw 'Invalid COM size' }
    Get-FileHash ROTOASW.com -Algorithm SHA256
    Write-Output "ROTOASW.com: $size bytes"
} finally { Pop-Location }
