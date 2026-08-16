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
Free Fly preference remain isolated. It also covers the exact Free Fly 1.6.2
first-person HUD contract: hidden-by-default cockpit art, opt-in restoration,
third-person pass-through, multiple returns, error-safe restoration, and
refusal to patch an unverified future version. Pokemon Final cache-screen fixtures also
lock the behavior probe, successful-state check, return/error preservation,
ownership marker, idempotence, foreign-owner refusal, and exact restoration.
Gapped-land fixtures cover its default-on schema, compatible renderer
capability checks, outdoor first-/third-person gates, interior/canopy/sea-map
exclusions, live disable path, generated-geometry cleanup, gameplay-state
isolation, and the safe no-provider fallback.

`inventory_ui.lua` is the focused 376-check bag/shop suite. Its v0.1.75 and
v0.1.83 doubles verify four-pocket classification, Left/Right navigation,
per-pocket cursor memory, ID-based global reordering, option-off passthrough,
lower screen-factory composition, copied/idempotent Trade Stone stock, and a
live BUY BAG count without mutating stock or inventory.

`experience_trade.lua` is the focused 144-check EXP/item suite. It covers the
four-mode schema, idempotent EXP.SHARE unlock and PC/full-bag recovery,
vanilla/lead/party/share allocation, error-safe EXP.ALL restoration, all four
Trade Stone evolutions, invalid and battle use, standard ITEM evolution, and
the namespaced v0.1.75 effect bridge with bag pockets both on and off.

`gapped_land.lua` is the focused, ROM-free 61-check suite for that visual
layer. Run it from the repository root with either supported Lua runtime:

```powershell
lua tests\gapped_land.lua
luajit tests\gapped_land.lua
lua tests\inventory_ui.lua
luajit tests\inventory_ui.lua
lua tests\experience_trade.lua
luajit tests\experience_trade.lua
```

Run the broad suite from the repository root with LuaJIT
(`luajit tests/main.lua`) or point the LOVE console executable at the test
directory (`lovec tests`). The `.modkitignore` file keeps this directory out
of the player-facing ZIP.

`full_load.lua` additionally installs the package through Gen1Recomp's real
API-2 loader, verifies the stable ID/new display name, the new content and
settings rows, checks the gapped-land compatibility status, invokes both HM
hooks alongside Free Fly and a Pokemon Final provider, and runs the real
priority-sorted HUD chain to prove only the cockpit picture is suppressed.
Its current matrix contains 83 checks per supported engine fixture. Pass `compat` for the
v0.1.75 fixture and `native` for v0.1.83+ to assert the exact Trade Stone
dispatcher. Run it from an engine
checkout with:

```powershell
luajit C:\path\to\mod\tests\full_load.lua C:\path\to\mod C:\path\to\engine native
```

`voxel_full_load.lua` loads Scott's Tweaks with Pokemon Final and a real
`movement.speed` producer, then proves held-B speed reaches `FreeMove` exactly
once and its constants are restored. An extracted Free Fly directory is an
optional third argument (1.5.0 through 1.6.2 are covered); when supplied, the test
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
