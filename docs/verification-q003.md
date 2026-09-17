# Verification — q003, 2026-09-17

Both `ROTO.com` (NASM 2.16.03) and `ROTOASW.com` (ASW 1.42 Beta build 179)
are 31,154 bytes. Both target 8086 instructions. ASW reports zero errors and
zero warnings; NASM builds with the existing warnings-as-errors policy.

| Verification | NASM | ASW |
|---|---:|---:|
| `tests/verify.py` original visual regression | 8 passed | 8 passed |
| `tests/verify_sound.py` sound/PCM regression | 14 passed | 14 passed |
| `tests/verify_video.py` backend/capability/failure tests | 26 passed | 26 passed |
| Rebuild hashes and generated source | identical | identical |

Total: 96 executable model cases. The ASW regression is selected with
`$env:ROTO_BINARY='ROTOASW.com'`; remove that environment variable to test NASM.
`verify_video.py` always tests both binaries and compares their results.

The video cases include plain/GRCG/EGC/PEGC/high-resolution at three rotation
angles, PEGC packed output at three angles, unsupported mode rejection,
8-colour override, high-resolution single-page selection, GINIT failure and
GSTART failure cleanup. Pixel content, 256 palette entries, every 32KB bank,
the unused packed tail, high-resolution margins, fourth plane and text RAM
write protection are checked. High-resolution calls use a private UCW and
INT 1Dh; ordinary graphics INT 18h calls are explicitly rejected by that model.

`tests/dosbox-smoke.ps1 -Dosbox E:/DOSBox-X/dosbox-x.exe` passed all four
completion markers: normal double-page, normal single-page, NASM `/256 /M /T`,
ASW `/256 /M /T`. Each returned from sixteen frames to the DOS shell.

Reports are generated under ignored `build/`: `verification.json`,
`verification-asw.json`, `audio-verification.json`, `audio-verification-asw.json`,
`video-verification.json`, plus DOSBox output and completion markers.
Python syntax checks and source whitespace checks also passed.

Limitations: Unicorn uses modeled ports and BIOS services. DOSBox-X smoke tests
do not establish physical-machine display timing, and no actual high-resolution
BIOS ROM was executed. Real PC-98 hardware, H98 256-colour expansion boards and
third-party graphics accelerators were not tested. EGC uses GRCG compatibility;
there is no EGC-specific accelerated rotozoom renderer.
