# Ledger
2026-09-17: MG003 / ws003-video completed; latest queue q003 finished and archived.
Branch run/q003 from bb9551e; implementation checkpoint ba42ebe.
ws003p001 and ws003p002 cleared. No next queue authorized.
Both COMs are 31,154 bytes; NASM 2.16.03 and ASW 1.42 Beta build 179.
NASM SHA256 C57264EDE7AA410E05DB69A7D51CA205D3A2AC1F22FD149C8BE533B9F5D254CA.
ASW SHA256 B28632975F75493563AE79420F2112BBA31CBE746B9FFE2D063ADD07E3E175CC.
96 modeled executable tests and four DOSBox-X smoke paths passed; reproducible builds.
Artifacts: src/asw/roto.asm, build-asw.ps1, ROTO.com, ROTOASW.com.
Current evidence: docs/verification-q003.md; hardware contracts: docs/video-backends.md.
Limitations: real hardware and high-resolution ROM untested; EGC GRCG-compatible
path only, no EGC blitter acceleration or high-resolution 256-colour add-on support.
GNA instructions were read during implementation, not before it; recorded honestly
in ws003p001. Old ledger branch differed from actual initial main/bb9551e state.
Delivery retained on run/q003 following the prior recorded main-integration restriction.
q001/q002 history preserved; q003 archived at history/q003.md.
