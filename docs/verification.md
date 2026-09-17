# Verification — 2026-09-16

Historical q002 results. Current binaries and validation are documented in
[verification-q003.md](verification-q003.md).

Delivered binary: `ROTO.com`, **24,518 bytes** after the q002 audio extension.

SHA256: `F27633DC56596735CF561CC8EAB94A2F1C5C9E407FAB94AF61EA7E5381B87C7F`

## Build

NASM 2.16.03, Python 3.12, Windows PowerShell host.
`build.ps1 -Python <bundled-python>` succeeded. Repeating the build produced
the same SHA256. NASM enforces 8086 instruction compatibility, warns as errors
(apart from the documented flat-binary absolute-address diagnostic), and checks
COM size. Python syntax compilation and diff whitespace checks passed.

## Machine-code tests

`<bundled-python> tests/verify.py` — **8 cases passed**, Unicorn 2.1.4.

| Case | Checked frames | Result |
|---|---:|---|
| Double page | 16 | Exact reference pixel match; alternating page 1/0 |
| Full-circle sample angles | 16 | Exact reference pixel match at 0,16,…,240 |
| Single page | 16 | Exact reference pixel match; page 0 only |
| Esc | 1 | DOS exit code 0; text visible, graphics off |
| Lowercase q | 1 | Same clean exit |
| VSYNC stuck low | 1 | Bounded polling, clean exit |
| VSYNC stuck high | 1 | Bounded polling, clean exit |
| Help | 0 | No graphics initialization, clean exit |

Every frame checks all 256,000 output pixels against a separate affine reference.
The harness checks every CPU memory write and rejects VRAM writes beyond the
32,000-byte visible region of any plane. Test frame PNGs were visually inspected.
This harness models hardware IO and BIOS/DOS services; it does not execute a ROM.

## DOSBox-X integration

`./tests/dosbox-smoke.ps1 -Dosbox E:/DOSBox-X/dosbox-x.exe` — **passed**.
Version: 2023.05.01. PC-98 machine, normal CPU core, 386, fixed 30,000 cycles.
The actual delivered COM ran `/T` and `/S /T`; both returned successfully and
the following DOS batch commands produced `DOUBLE_OK` and `SINGLE_OK` markers.
The log also records INT 18h/AH=42h/CH=C0h from both runs.
SDL dummy video/audio drivers and a hidden process made this a headless smoke
test; its screen was not visually captured. Pixel validation comes from the
machine-code harness above.

Physical PC-9801 hardware and a running build of the supplied Takeda emulator
were **not** tested. The latter's source was used to derive the hardware contract.

## Audio extension (q002)

`tests/verify_sound.py` passed 13 cases. It models absent, 26K at 188h/288h,
86 at 188h/288h, WSS ID, false 86 response, busy timeout, mute, score notes,
all 768 score steps across 12 keys, loop wrap, five PCM one-shot payloads,
full FIFO handling, DOS-minute wrap and register preservation. The PCM payloads
are generated locally as signed 8-bit stereo samples at 11025 Hz and are checked
for zero tails and exact FIFO lengths.

DOSBox-X 2023.05.01 smoke runs passed for `board26k` and `board86` with `/T`;
the emulator selected `PC-9801-26k` and `PC-9801-86` respectively and the COM
returned normally. Its `DX-CAPTURE` command did not emit a WAV with the dummy
audio backend, so WAV capture is not claimed. The board-selection logs and actual
PCM register behavior remain covered by the machine harness. Physical hardware
and the supplied emulator binary remain untested.
No physical-machine frame-rate guarantee is made.
