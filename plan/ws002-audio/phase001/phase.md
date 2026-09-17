# ws002p001
Status: cleared
Implement original 150 BPM FM/SSG music: minor bVI-bVII-i-i, four-bar phrases,
successive semitone modulation through twelve keys. Preserve 8086 support.
Probe sound ID and actual SSG register response at 188h/288h; absent -> silence;
only verified 86 gets signed 8-bit stereo PCM one-shots. Bounded hardware waits.
Service timing between raster rows from DOS time, without IRQ/vector changes.
Add /M mute and status report; silence owned voices/PCM on normal exit.
Verification: build.ps1; COM size; sound machine-code harness for detector,
device writes, score, PCM payloads, timing wrap and exit.
## Execution Log
2026-09-16: implemented sound.asm and generated music_data.inc. Detection probes
A460h plus FM response at 188h/288h/88h; 26K-compatible FM+SSG is type 1 and
verified 86 is type 2. Added polled YM2203/YM2608 FM+SSG, DOS-time 150 BPM service,
12-key semitone modulation, /M mute, /P preview and bounded PCM FIFO writes.
Verification completed in phase002 sound harness. COM size 24,518 bytes.
