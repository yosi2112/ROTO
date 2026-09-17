# ws001p002
Status: ready
Scope: quality and regression verification before delivery.
Procedure: execute assembled machine code in an x86 harness with modeled PC-98 ports;
compare VRAM output with an independent affine reference; check page flips, bounds,
exit cleanup and bounded VSYNC polling; rebuild and compare bytes; inspect rendered output.
Verification: tests/verify.py passes; deterministic binary; no unexplained files or TODOs.
Hardware/BIOS emulation limits must be reported, not concealed as verified compatibility.
## Execution Log
2026-09-16: started after ws001p001. tests/verify.py passed all 8 cases (52 rendered
frames), including complete-circle angle samples, exact pixel checks, memory
bounds, page selection, Esc/Q, VSYNC timeout and help. Visual inspection passed.
tests/dosbox-smoke.ps1 passed on DOSBox-X 2023.05.01 in PC-98 mode: /T and /S /T
both returned to DOS with success markers. Rebuild SHA256 identical. Python
syntax/whitespace checks passed. Physical hardware and supplied emulator binary
not tested; documented in docs/verification.md. Status: cleared.
