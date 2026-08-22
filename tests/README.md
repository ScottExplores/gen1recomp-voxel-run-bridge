# Tests

`art_rendering.lua` locks the sprite repairs that are easy to miss on a
desktop display: Crystal's authored transparency survives a developer F5,
opponent/player-back orientation controls stay independent, and both Wilds
sprite-card canvas paths use 1:1 DPI with nearest filtering for Android/AYN:

```powershell
luajit tests\art_rendering.lua <mod-root>
```

The suite currently contains 244 checks and also installs the real staged-battle
wrappers: split mode must omit lower-screen Pokemon, trainer, and move OAM
while preserving the upper animation surface and lower text/HUD. Its setting
checks also prove one- and two-key sprite ownership edits roll back save, live,
and cached values after a failed device write. The combined Crystal/Battle Art
trainer, player-view, and Crystal-mode shortcuts likewise persist once and
leave both providers untouched when that write fails. A stable 120-frame HUD
draw also allocates only the two warm-up quads, with resize and invalidation
rebuilding exactly the stale entries.

`crystal_party_art.lua` drives the real fused Loader and Crystal provider with
normal and shiny Gen 1 frames. It proves party/Summary lookup reaches the
bundled exact-case assets, normal and shiny frames differ, authored alpha stays
on the transparent path, and the resulting card uses 1:1 DPI with nearest
sampling. The runner exercises both LuaJIT and Lua 5.1:

```powershell
.\tests\run_crystal_party_art.ps1 -ModRoot <mod-root> -EngineRoot <engine-root>
```

`run_fused.ps1` stages the complete fused code tree through a real Gen1Recomp
loader. Its renderer/menu/Wilds assertions cover every canonical ALL row once,
BASIC/ALL input, atomic encounter-mode migration, live current-map respawn,
classic-roll suppression, AI-pipeline recovery, and insertion of revealed
grass Pokemon into the Gen 1 draw list:

```powershell
.\tests\run_fused.ps1 -ModRoot <mod-root> -EngineRoot <engine-root>
```

`vendor_host_assets.lua` verifies Android-case asset rerooting and the hosted
single-/multi-option writers. `unique_menu_icons_options.lua` verifies that an
icon-mode change is saved for restart without mutating the frozen registry.
`coexist_standalone.lua` proves a separately installed renderer remains the
owner while Scott's Tweaks still loads:

```powershell
luajit tests\vendor_host_assets.lua <mod-root>
luajit tests\unique_menu_icons_options.lua <mod-root>
luajit tests\coexist_standalone.lua <mod-root> <engine-root> <file-list>
```

`wilds_follower_gold_seam.lua` loads the real 0.1.88 and 0.1.96 Gen 2 map
implementations. It locks the engine's id-only neighbor shape, cross-map
follower cell lookup, destination `mapId` rebinding, and guest retention after
a world rebuild:

```powershell
luajit tests\wilds_follower_gold_seam.lua <mod-root> <engine-.88> <engine-.96>
```

`wilds_follower_gen1_walk.lua` uses the real Gen 1 Player, NPC, Collision, and
SpriteRenderer modules. Four ordinary grid steps must leave the same follower
exactly one vacated cell behind, attached to both native world containers,
drawable, and backed by Scott's bundled six-frame GSC art. Run it once with
each supported engine and Lua runtime:

```powershell
luajit tests\wilds_follower_gen1_walk.lua <mod-root> <engine-root>
lua tests\wilds_follower_gen1_walk.lua <mod-root> <engine-root>
```

`wilds_behavior_tick_alloc.lua` protects the handheld Wilds hot path. It
simulates 12 visible Pokemon for 600 rendered frames, verifies the fixed 30 Hz
AI cadence, and keeps total Lua allocation below the cross-runtime 384 KiB
budget with no per-entity allocation growth:

```powershell
luajit tests\wilds_behavior_tick_alloc.lua <mod-root>
lua tests\wilds_behavior_tick_alloc.lua <mod-root>
```

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
Free Fly preference remain isolated. It also covers the verified Free Fly
1.6.2 and bundled 1.8.0 first-person HUD contract: hidden-by-default cockpit
art, opt-in restoration,
third-person pass-through, multiple returns, error-safe restoration, and
refusal to patch an unverified future version. Pokemon Final cache-screen fixtures also
lock the behavior probe, successful-state check, return/error preservation,
ownership marker, idempotence, foreign-owner refusal, and exact restoration.
Gapped-land fixtures cover its default-on schema, compatible renderer
capability checks, outdoor first-/third-person gates, interior/canopy/sea-map
exclusions, live disable path, generated-geometry cleanup, gameplay-state
isolation, and the safe no-provider fallback.

`inventory_ui.lua` is the focused 1,124-check bag/shop suite. Its modeled
v0.1.75, v0.1.83, v0.1.88, and v0.1.96 surfaces verify four-pocket
classification, Crystal-style 20×18 Pack drawing, two-line rows, quantities,
descriptions, Left/Right navigation, per-pocket cursor and scroll memory,
ID-based global reordering, option-off passthrough, preserved Red callbacks,
lower screen-factory composition, copied/idempotent Trade Stone stock, and a
live BUY BAG count without mutating stock or inventory. This remains the
partial-install fallback contract.

`modern_bag_integration.lua` is the 174-check release contract for the normal
bundled Bag/PC owner. It verifies the default Pocket and selectable Modern
skins, All plus five category views, Scott-specific classification fallbacks,
native callback multi-returns, PC Withdraw/Deposit/Toss decoration, native
per-pocket/x99 and PC-50 limits, procedural no-raster backpack drawing,
landscape and portrait sizing, idempotent reload ownership, and
standalone-provider stand-down under both runtimes:

```powershell
luajit tests\modern_bag_integration.lua <mod-root>
lua tests\modern_bag_integration.lua <mod-root>
```

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

`consolidated_features.lua` drives the incorporated trainer and Oak modules
under the `voxel_run_bridge` namespace. It covers the live paid-forfeit off
switch, ¥200 payment, reward-safe rematch checkpoint marker, namespaced
exports/state, exact base-talk delegation, standalone-provider delegation,
Random Starters owning only Oak's Lab, paid-forfeit/rematch independence, and
the leased raw-Overworld dispatcher across a two-entry hot reload.

`migrations.lua` verifies the per-save one-time import, deep-copied trainer
memory, explicit-new-value precedence, live/save option mirroring, one-write
persistence, idempotence, preservation of every legacy namespace, and F5's
save-first/fresh-Loader reconciliation with standard live option events. It
also proves thrown and explicit-false storage failures restore bucket identity
and values without emitting a false live event. Both
focused suites run under Lua 5.1 and LuaJIT:

```powershell
lua tests\consolidated_features.lua
luajit tests\consolidated_features.lua
lua tests\migrations.lua
luajit tests\migrations.lua
```

`running_hot_reload.lua` performs four real API-2 Loader entry loads while the
same voxel `FreeMove` and `FirstPerson` tables remain alive. It proves the bob
callback refreshes, wrapper identities remain stable, the provider tick is
called once, the 1.5X multiplier is applied once, temporary speed is restored,
multi-returns survive, camera lift never mutates player state, and enabling
then removing standalone Running Shoes suspends and resumes the same dispatcher:

```powershell
luajit tests\running_hot_reload.lua <mod-root> <engine-root>
```

`thor_dual_screen.lua` is the focused clean-presenter suite. It checks the
public render/display seams in both 0.1.88 and 0.1.96, stock single-screen
fallthrough, physical lower-display routing, frozen upper/live lower menu
composition, scaling, fault recovery, legacy `gen1recomp_ds` delegation,
same-facade identity, and two real API-2 Loader entries. Select each fixture
as the live Loader once; every invocation contains 250 checks and runs under
both LuaJIT and Lua 5.1:

```powershell
luajit tests\thor_dual_screen.lua <mod-root> <engine-.88> <engine-.96> <engine-.88>
luajit tests\thor_dual_screen.lua <mod-root> <engine-.88> <engine-.96> <engine-.96>
lua tests\thor_dual_screen.lua <mod-root> <engine-.88> <engine-.96> <engine-.88>
lua tests\thor_dual_screen.lua <mod-root> <engine-.88> <engine-.96> <engine-.96>
```

`full_load.lua` additionally installs the package through Gen1Recomp's real
API-2 loader, verifies the stable ID/new display name, the new content and
settings rows, checks the gapped-land compatibility status, invokes both HM
hooks alongside Free Fly and a Pokemon Final provider, and runs the real
priority-sorted HUD chain to prove only the cockpit picture is suppressed.
Its current matrix contains 192 checks per supported engine fixture. Pass `compat` for the
v0.1.75 fixture and `native` for v0.1.83+ to assert the exact Trade Stone
dispatcher. Run it from an engine
checkout with:

```powershell
luajit C:\path\to\mod\tests\full_load.lua C:\path\to\mod C:\path\to\engine native
```

`gen2_ui.lua` contains 132 checks for the built-in, ROM-free PACK + POKeGEAR
flow: Red's ITEM/ITEMS callback remains authoritative, source descriptors are
not mutated, Pokegear follows ITEM/ITEMS/PACK spellings, all four cards retain
Crystal order, the clock is live, Kanto Map opens through Red's native screen,
Phone reads trainer history without writes, Radio uses only available Red
songs and restores map music, missing capabilities remain honest, and a second
Loader entry safely refreshes the screen factory.

```powershell
luajit tests\gen2_ui.lua <mod-root>
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
