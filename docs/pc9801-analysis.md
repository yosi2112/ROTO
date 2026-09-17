# PC-9801 source analysis

Historical q001/q002 analysis. The high-resolution exclusion below describes
the original release; q003 adds the backends described in [video-backends.md](video-backends.md).

Input: `E:/source/src/vm/pc9801/*`, inspected 2026-09-16. Original sources are
read-only and are not copied into the demo. The implementation is original assembly.

## Relevant hardware contracts

| Source | Observed behavior | Demo decision |
|---|---|---|
| `pc9801.cpp:742` onward | Character GDC is 60h/62h; graphics GDC is A0h/A2h. Display owns 68h/6Ah, 7Ch/7Eh, A4h/A6h and palette ports. | PC-98 BIOS initializes the GDC; A0h status is used for synchronization. No VGA interrupts or ports. |
| `membus.cpp:74` | A0000h text; A8000h–BFFFFh graphics; E0000h fourth plane on supported machines. | Three direct planes at segments A800h, B000h, B800h. Text memory is retained. |
| `display.cpp:495` | 6Ah data 00h selects 8 colors; 7Ch zero disables GRCG. | Use plain planar writes; no GRCG/EGC dependency. |
| `display.cpp:561` | A4h selects displayed VRAM page; A6h selects CPU drawing page independently. | Render entire hidden frame, wait for VSYNC and flip; `/S` holds both at page zero. |
| `display.cpp:589` | Digital palette A8h maps 3/7; AAh 1/5; ACh 2/6; AEh 0/4. | Write 37h, 15h, 26h, 04h respectively. Palette index bits are B/R/G. |
| `display.cpp:3092` | GDC address and pitch select scanlines; each plane byte represents eight horizontal pixels, MSB first. | Standard BIOS 640×400 mode, 80 bytes/row, 32,000 bytes/plane. |
| `pc9801.h:154` | XA/XL/RL are high-resolution. Original 9801 and U lack second VRAM; E lacks analog 16-color support. | Target normal-resolution models; `/S` for original 9801/U. Use digital 8 colors. |
| `keyboard.cpp:54` | Host key events become PC-98 scan codes via an 8251, not AT keyboard ports. | DOS INT 21h/AH=06h handles nonblocking console input. Esc/Q exits. |
| `../upd7220.cpp:204` | Status read includes VSYNC at bit 5 (20h). | Poll A0h for end then start of VSYNC; both waits have finite limits. |

The machine folder implements hardware, not a replacement INT 18h ROM BIOS.
BIOS calls were cross-checked against the primary-source
[ReactOS PC-98 implementation](https://doxygen.reactos.org/de/dbc/pc98video_8c_source.html):
AH=42h/CH=C0h sets the 640×400 color area; AH=40h/41h starts/stops graphics;
AH=0Ch starts text. AH=0Dh hides text during the demo.

## Remaining modules and scope

All 26 `.cpp`/`.h` files were inventoried by role. Header/source pairs define the
same device's state, public bus interface and serialization contract.

| Pair | Responsibility and relevance |
|---|---|
| `pc9801` | Model/CPU flags, device construction, IO wiring, interrupts and VM lifecycle. Determines compatibility boundaries. |
| `display` | Text/font RAM, planar graphics, digital/analog palette, GRCG/EGC, drawing and save states. Main rendering contract. |
| `membus` | Conventional/extended RAM, ROM, graphics mapping and EMS windows. Demo relies on ordinary DOS conventional memory and graphics apertures. |
| `keyboard` | Key tables and 8251 receive signaling. Use OS console interface. |
| `cpureg` | CPU control, reset, interrupt and clock-related interfaces. Not changed. |
| `dmareg` | DMA bank and address-mask registers. No DMA needed for CPU VRAM writes. |
| `floppy` | FDC control, drive/motor/density selection and event/IRQ handling. DOS loads the COM; no direct disk access. |
| `sasi` | SASI bus control, command/data handshaking, DMA and interrupt signaling. Not used. |
| `fmsound` | FM-board register access, PCM buffering/mixing and sound events. Demo uses the 26K/86 contracts. |
| `joystick` | YM2203 port input selection. Not used. |
| `mouse` | Mouse movement/button accumulation, port reads and timer interrupt signaling. Not used. |
| `serial` | Serial channel control and interrupt gating. Not used. |
| `cmt` | Cassette signal and tape file handling. Not used. |

## Rendering

An embedded 64×64, 8-color tiled texture is sampled on a 160×100 logical grid.
Each sample becomes a 4×4 output block. Coefficients are signed 8.8 fixed-point,
precomputed over 256 angles; the frame step is 2, with a sinusoidal zoom envelope.
For logical pixel `(x,y)`, texture coordinates are
`u=32+(x-80)*a-(y-50)*b`, `v=32+(x-80)*b+(y-50)*a`, wrapped modulo 64.
Two samples become one byte in each plane using 64-entry conversion tables.
Only three 80-byte row buffers are required. A private 1 KiB stack is in the COM.
All runtime instructions are constrained by NASM `cpu 8086`; no FPU is needed.

## Limits

This is a DOS foreground demo, entered from a normal text console. It returns to
visible DOS text, hides graphics, and resets VRAM selectors and GRCG. It does not
save/restore another application's graphics, palette or GDC configuration.
Console input should not be redirected. Single-page mode can tear. Frame rate is
CPU-dependent; no claim of 60 fps is made for 8086/V30 hardware. High-resolution
XA/XL/RL, IBM PC/VGA, and bare-metal boot are not targets.

## Sound contract and score

The supplied `fmsound.cpp` maps FM/SSG at 188h/18Ah (or 288h/28Ah), sound ID at
A460h, and 86 PCM at A466h/A468h/A46Ah/A46Ch/A66Eh. A460h's upper nibble is the
PCM board ID; 4/5 identify PC-9801-86 variants, while the lower bits are the OPNA
mask. The demo probes A460h, then writes and reads PSG register 0 at the selected
FM base twice before enabling audio. This avoids treating a WSS ID or floating bus
as an 86 board. This ID interpretation is documented by the
[PC-9800 sound-board reference](https://www.mfp.gr.jp/users/takas/prog/wssmix.html).

FM notes are written to YM2203/YM2608 FNUM/block registers and SSG tone periods;
the driver polls BUSY and uses a bounded delay. Timing uses DOS hundredths and
handles minute wrap without owning an IRQ vector. Each sixteenth is 100 ms (150
BPM, four subdivisions per beat), and the score is `bVI-bVII-i-i` in minor, with
four bars per key and 12 successive semitone keys. This is an original score.
On verified 86 hardware, PCM is signed 8-bit stereo at 11025 Hz through the FIFO.
Synthesized one-shots provide kick, snare, hat, tom and sweep/crash.
