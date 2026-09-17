# ws003p002
Status: in-progress
Scope: quality and convention verification, tests, documentation, reproducibility.
Depends: ws003p001.
Commands: build.ps1; build-asw.ps1; tests/verify.py; tests/verify_sound.py;
tests/verify_video.py; src/make_asw.py deterministic regeneration.
Criteria: all commands pass; high-resolution writes preserve text RAM; packed
pixels cross every 32KB boundary correctly; unsupported /256 exits before video
changes; original planar and audio regression tests pass; ASW artifact tested.
Physical machines and real high-resolution ROM execution are not available and
must remain explicitly unverified, rather than counted as passing tests.

## Execution Log

