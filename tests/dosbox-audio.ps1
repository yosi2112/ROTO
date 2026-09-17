param(
    [Parameter(Mandatory=$true)][string]$Dosbox,
    [ValidateSet('board26k','board86','off')][string]$Board = 'board86',
    [int]$Port = 0,
    [switch]$Preview
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tag = "$Board-$Port"
$relative = "build/audio-$tag"
$outDir = Join-Path $root $relative
New-Item -ItemType Directory -Force $outDir | Out-Null
$mode = if ($Preview) { '/P' } else { '/T' }
$command = if ($Preview) { "dx-capture /A /-D roto.com $mode" } else { "roto.com $mode" }
$config = Join-Path $outDir 'run.conf'
@"
[sdl]
output=surface
fullscreen=false
[dosbox]
machine=pc98
memsize=16
captures=$outDir
show recorded filename=false
[pc98]
pc-98 fm board=$Board
pc-98 fm board io port=$Port
[cpu]
core=normal
cputype=386
cycles=fixed 30000
[mixer]
nosound=false
rate=44100
[autoexec]
mount c "$root"
c:
$command
exit
"@ | Set-Content -LiteralPath $config -Encoding ascii
$oldVideo, $oldAudio = $env:SDL_VIDEODRIVER, $env:SDL_AUDIODRIVER
try {
    $env:SDL_VIDEODRIVER = 'dummy'
    $env:SDL_AUDIODRIVER = 'dummy'
    $process = Start-Process -FilePath $Dosbox -ArgumentList '-conf', ('"'+$config+'"'), '-noconsole', '-nogui' -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $outDir 'stdout.txt') -RedirectStandardError (Join-Path $outDir 'stderr.txt') -PassThru
    $timeout = if ($Preview) { 180000 } else { 55000 }
    if (!$process.WaitForExit($timeout)) {
        $process.Kill()
        throw "DOSBox-X $tag timed out"
    }
    if ($process.ExitCode -ne 0) { throw "DOSBox-X $tag failed" }
    $log = Get-Content (Join-Path $outDir 'stderr.txt') -Raw
    $expected = switch ($Board) {
        'board26k' { 'PC-9801-26k' }
        'board86' { 'PC-9801-86' }
        'off' { 'FM board is disabled' }
    }
    if (!$log.Contains($expected)) { throw "Wrong board selection for ${tag}" }
    $wav = @(Get-ChildItem -LiteralPath $outDir -Filter '*.wav' -ErrorAction SilentlyContinue)
    if ($Preview -and !$wav) {
        Write-Warning "DX-CAPTURE did not emit WAV on this DOSBox-X build; board selection and COM exit still passed"
    }
    Write-Output "PASS DOSBox-X ${tag}: board selected; COM exited$(if($wav){'; WAV captured'})"
} finally {
    $env:SDL_VIDEODRIVER, $env:SDL_AUDIODRIVER = $oldVideo, $oldAudio
}
