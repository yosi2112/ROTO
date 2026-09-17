param([Parameter(Mandatory=$true)][string]$Dosbox)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force $outDir | Out-Null
$ok = Join-Path $outDir 'dosbox.ok'
$fail = Join-Path $outDir 'dosbox.fail'
foreach ($file in @($ok, $fail)) {
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
$config = Join-Path $outDir 'dosbox-test.conf'
@"
[sdl]
output=surface
fullscreen=false
[dosbox]
machine=pc98
memsize=16
captures=build
[cpu]
core=normal
cputype=386
cycles=fixed 30000
[mixer]
nosound=true
[autoexec]
mount c "$root"
c:
roto.com /T
if errorlevel 1 goto failed
echo DOUBLE_OK>build\dosbox.ok
roto.com /S /T
if errorlevel 1 goto failed
echo SINGLE_OK>>build\dosbox.ok
roto.com /256 /M /T
if errorlevel 1 goto failed
echo PACKED_OK>>build\dosbox.ok
rotoasw.com /256 /M /T
if errorlevel 1 goto failed
echo ASW_PACKED_OK>>build\dosbox.ok
exit
:failed
echo FAIL>build\dosbox.fail
exit
"@ | Set-Content -LiteralPath $config -Encoding ascii
$oldVideo = $env:SDL_VIDEODRIVER
$oldAudio = $env:SDL_AUDIODRIVER
try {
    $env:SDL_VIDEODRIVER = 'dummy'
    $env:SDL_AUDIODRIVER = 'dummy'
    $process = Start-Process -FilePath $Dosbox -ArgumentList '-conf', ('"'+$config+'"'), '-noconsole', '-nogui' -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $outDir 'dosbox-stdout.txt') -RedirectStandardError (Join-Path $outDir 'dosbox-stderr.txt') -PassThru
    if (!$process.WaitForExit(55000)) {
        $process.Kill()
        throw 'DOSBox-X exceeded the 55-second smoke-test timeout'
    }
    if ($process.ExitCode -ne 0 -or (Test-Path $fail) -or !(Test-Path $ok)) {
        throw 'DOSBox-X smoke test failed; see build/dosbox-stderr.txt'
    }
    $lines = @(Get-Content -LiteralPath $ok)
    if (($lines -join ',') -ne 'DOUBLE_OK,SINGLE_OK,PACKED_OK,ASW_PACKED_OK') { throw 'Missing completion markers' }
    Write-Output 'PASS DOSBox-X PC-98: planar pages and NASM/ASW packed /T returned to DOS'
} finally {
    $env:SDL_VIDEODRIVER = $oldVideo
    $env:SDL_AUDIODRIVER = $oldAudio
}
