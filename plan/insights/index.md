# Insights
| ID | Origin | Summary | Status |
|---|---|---|---|
| ins001 | ws001p001 | Original PC-9801 and U builds lack second VRAM; provide /S fallback. Hi-res XA/XL/RL use different memory maps and are out of scope. | resolved |
| ins003 | ws003p001 | High-resolution graphics BIOS uses INT 1Dh with private 380h-byte UCW; normal INT 18h graphics calls are incompatible. Corrected and model-tested; physical ROM remains untested. | resolved |
| ins004 | ws003p001 | ASW and NASM use different legal register encodings. Validate rendered pixels and sound behavior, not byte identity. | resolved |
