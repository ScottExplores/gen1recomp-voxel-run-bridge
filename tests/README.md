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
a voxel provider. The suite also feature-detects Dramatic Sky Ride's exported
flight rules, exercises the same live `badge_checks` value its private
`startFlight` gate reads, proves takeoff no longer returns the THUNDERBADGE
error, and verifies REQUIRE FLY, story rules, inventory and saved DSR
preference behavior remain isolated.

Run it from the repository root with LuaJIT (`luajit tests/main.lua`) or point
the LOVE console executable at the test directory (`lovec tests`). The
`.modkitignore` file keeps this directory out of the player-facing ZIP.

`full_load.lua` additionally installs the package through Gen1Recomp's real
API-2 loader, verifies the stable ID/new display name and schema, and invokes
both HM hooks without a voxel provider. Run it from an engine checkout with:

```powershell
luajit C:\path\to\mod\tests\full_load.lua C:\path\to\mod C:\path\to\engine
```
