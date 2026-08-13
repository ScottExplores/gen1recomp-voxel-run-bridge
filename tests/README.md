# Tests

`main.lua` uses fake engine and voxel modules to verify the adapter without a
ROM. It covers foot and bike ratios, engine-style output clamping, invalid
hook output, no-producer behavior, scripted-movement gating, error-safe
constant restoration, native Running Shoes delegation, and the no-voxel
fallback.

Run it from the repository root with LuaJIT (`luajit tests/main.lua`) or point
the LOVE console executable at the test directory (`lovec tests`). The
`.modkitignore` file keeps this directory out of the player-facing ZIP.
