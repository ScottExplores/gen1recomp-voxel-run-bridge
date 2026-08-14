# Tests

`main.lua` uses fake engine and voxel modules to verify the adapter without a
ROM. It covers foot and bike ratios, engine-style output clamping, invalid
hook output, no-producer behavior, scripted-movement gating, error-safe
constant restoration, native Running Shoes delegation, and the no-voxel
fallback. It also locks the stable `voxel_run_bridge` id to the player-facing
`Scott's Tweaks` rename and exercises the default-on `hm_without_badges`
option through the real `fieldmove.eligibility` and `ui.party.submenu` hook
signatures. Those checks require a party member to know the HM, preserve and
de-duplicate other menu rows, keep FLY outdoors-only and FLASH dark-only,
leave battle menus untouched, and prove that HM support stays active without
a voxel provider. The suite also feature-detects Free Fly's public flight
state and real `badges` option, exercises the same live value its private
takeoff gate reads, proves takeoff no longer returns the THUNDERBADGE error,
and verifies FLY eligibility, story rules, inventory, and the player's saved
Free Fly preference remain isolated. Pokemon Final cache-screen fixtures also
lock the behavior probe, successful-state check, return/error preservation,
ownership marker, idempotence, foreign-owner refusal, and exact restoration.

Run it from the repository root with LuaJIT (`luajit tests/main.lua`) or point
the LOVE console executable at the test directory (`lovec tests`). The
`.modkitignore` file keeps this directory out of the player-facing ZIP.

`full_load.lua` additionally installs the package through Gen1Recomp's real
API-2 loader, verifies the stable ID/new display name and schema, and invokes
both HM hooks alongside Free Fly and a Pokemon Final provider. Run it from an
engine checkout with:

```powershell
luajit C:\path\to\mod\tests\full_load.lua C:\path\to\mod C:\path\to\engine
```

`voxel_full_load.lua` loads Scott's Tweaks with Pokemon Final and a real
`movement.speed` producer, then proves held-B speed reaches `FreeMove` exactly
once and its constants are restored. An extracted Free Fly directory is an
optional third argument (1.5.0 and 1.6.1 are covered); when supplied, the test
also validates the real `isFlying` export, `badges` schema, and live override.

```powershell
luajit tests\voxel_full_load.lua <mod-root> <engine-root> [extracted-free-fly-root]
```

The baseline fixture has 22 checks; supplying the real Free Fly directory
enables six more compatibility checks for a 28-check run.

`cache_compat_full_load.lua` reads `ScottPrecacheScreen.lua` directly from an
extracted local Pokemon Final package at test time; no private source is kept
in this repository. Run it once with the buggy `1.8.1-scott.2` directory and
once with the corrected `1.8.1-scott.3` directory against each supported
engine loader:

```powershell
luajit tests\cache_compat_full_load.lua <mod-root> <engine-root> <pokemon-final-.2-root> patched
luajit tests\cache_compat_full_load.lua <mod-root> <engine-root> <pokemon-final-.3-root> safe
```

The first run proves the wrapper is installed and clears only a confirmed
successful start. The second proves the corrected private function and module
table remain untouched.
