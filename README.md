# Scott's Tweaks

Scott's Tweaks is the next version of **Voxel Run Bridge**. The display name
is broader, but its internal mod ID remains `voxel_run_bridge`. Existing
installations therefore update in place, keep their settings, and do not
become a duplicate mod.

Version 0.4.3 contains ten independent tweaks:

- **Bag pockets:** press Left or Right to move among ITEMS, BALLS, TM/HM,
  and KEY ITEMS while keeping the original Gen 1 inventory underneath.
- **Shop counts:** the BUY screen shows how many of the selected item are
  already in the bag.
- **Experience modes:** choose VANILLA, LEAD ONLY, PARTY ALL, or EXP.SHARE.
  Selecting EXP.SHARE permanently unlocks a visible key item in the bag.
- **Trade Stone:** every Gen 1 mart sells a ₽500 stone that evolves Kadabra,
  Machoke, Graveler, or Haunter through the normal evolution sequence.

- **Gapped Land:** compatible Pokemon Final, Dramatic Shape, and Battle Art
  renderers can cover the empty visual space beneath the horizon in outdoor
  first- and third-person views. This presentation option is on by default.
- **Free Fly Now:** Free Fly can take off immediately without the Thunder
  Badge. This compatibility option is on by default.
- **Free Fly cockpit control:** the default-off **FLY COCKPIT** setting keeps
  Free Fly's extra Pokemon picture out of first-person view without changing
  the mount, third-person presentation, movement, or landing.
- **Badge-free HMs:** use Cut, Fly, Surf, Strength, and Flash without their
  badge. A party Pokemon must still actually know the move. Normal map,
  terrain, and story restrictions remain in effect.
- **Voxel Run Bridge:** movement-speed mods work while a supported voxel mod
  is driving the player in **1ST** or **3RD** person.
- **Pokemon Final cache result compatibility:** an early private cache screen
  no longer reports **COULD NOT START** after its build actually started. The
  corrected Pokemon Final package is detected by behavior and left untouched.

None of these features grants badges, teaches moves, changes story flags, or
edits a save's badge inventory.

## Bag pockets and shop counts

The default-on **BAG POCKETS** option presents the Gen 1 bag as four tabs:
**ITEMS**, **BALLS**, **TM/HM**, and **KEY ITEMS**. Press Left or Right inside
the bag to change tabs. SELECT still reorders items, and the order is written
back by item identity so filtering never corrupts the real bag order.

This is a view over the existing inventory, not a larger replacement bag.
Saving, item quantities, the Gen 1 slot limit, battle item use, selling, and
other mods' items remain owned by Gen1Recomp. Unknown custom items stay
visible under ITEMS. Turn **BAG POCKETS** off to use the original one-list bag.

When BUY is open at a mart, its title includes **BAG:N** for the currently
highlighted item. The count updates after a purchase and does not alter shop
prices or stock supplied by other mods.

## Experience modes

**EXP. MODE** is a four-way setting:

- **VANILLA** (default) leaves Gen 1 participation and a legitimately owned
  EXP.ALL completely unchanged.
- **LEAD ONLY** gives the award to the active, conscious Pokemon.
- **PARTY ALL** gives one full award to each conscious party member.
- **EXP.SHARE** uses Gen 1's split-share math and permanently unlocks a
  passive **EXP.SHARE** key item in the bag.

The custom EXP.SHARE item is an indicator; the Scott's Tweaks option remains
authoritative. If the bag is full, sharing still works and the item is added
when room becomes available. Changing modes does not remove it. The adapter
temporarily uses the engine's own EXP.ALL allocation path for one award and
then restores the exact real inventory value, so it never grants or consumes
the Route 15 EXP.ALL or changes its story event.

## Trade Stone

Every Gen 1 mart gains one additive **TRADE STONE** stock entry for **₽500**.
Use it on Kadabra, Machoke, Graveler, or Haunter to evolve into Alakazam,
Machamp, Golem, or Gengar. Invalid targets and battle use consume nothing;
canceling the party picker also consumes nothing. A valid use removes exactly
one stone and runs Gen1Recomp's standard non-cancelable item evolution movie,
including normal stat, Pokédex, event, and move-learning updates.

Normal link-trade evolutions are not replaced and still work. Custom items
remain in Gen1Recomp saves, but original-cartridge `.sav` export cannot encode
an item with no ROM byte ID and therefore omits remaining Trade Stones.

## Gapped Land

The default-on **GAPPED LAND** setting adds an independently generated land
plane beneath compatible voxel scenery. It is intended for the empty-looking
space between an outdoor map's edge and the painted horizon, such as the blue
gap visible around an isolated town from a first- or third-person camera.

The fill is purely visual. It does not add map cells, join cities or routes,
change collision, create landing places, or let the player walk outside the
real map. Sea maps remain sea, and the fill is skipped in interiors and under
special canopy scenery so it does not flatten places that are supposed to be
enclosed or water-covered.

The renderer is selected by its stable mod ID and then checked for the required
capabilities rather than trusted by display name alone. Version 0.4.3 targets
Pokemon Final, the verified Dramatic Shape 1.8.0-1.8.2 renderer contract, and
Battle Art Voxel Fork's published renderer modules.
If an active voxel provider does not expose the required renderer modules,
Scott's Tweaks leaves it untouched and every other tweak continues to work.

Switch **GAPPED LAND** off in Scott's Tweaks to remove only that extra visual
plane. Toggling it does not delete, start, or rebuild Pokemon Final's voxel
disk cache or invalidate its cached terrain. Only Scott's small runtime
underlay changes, and the completed disk cache remains reusable.

## Free Fly

Free Fly performs its own badge check outside Gen1Recomp's normal HM hook.
Scott's Tweaks detects Free Fly's real option schema and public flight-state
export, then holds its live **BADGE CHECKS** answer off while **FREE FLY NOW**
is enabled. It defaults to enabled, so there is no second setting to find.
This badge adapter is tested with Free Fly 1.5.0 and the current 1.6.2 release.

This does not add a badge, teach a move, or alter the save. Free Fly still
decides which Pokemon can carry the player and keeps its FLY eligibility,
story gates, map rules, and landing checks. Free Fly groups its Thunder Badge
takeoff rule and Soul Badge water-landing rule under the same **BADGE CHECKS**
option, so both badge checks are relaxed while **FREE FLY NOW** is on.

Turn **FREE FLY NOW** off in Scott's Tweaks to return control to Free Fly's
own saved **BADGE CHECKS** preference. Its exact previous value is restored.

For Pokemon Final, update Free Fly itself to **1.6.1 or newer** (1.6.2 is the
current verified release). Free Fly 1.6.1 changed its voxel-provider lookup
from the original Dramatic Shape ID
to capability detection, so its first- and third-person flight support also
finds Pokemon Final. Scott's Tweaks supports the badge toggle in both the
older 1.5.0 package and the current line, but it does not copy or replace Free
Fly's flight renderer.

Free Fly 1.6.2 also draws a separate mount picture at the bottom of its
first-person HUD. Scott's Tweaks exposes that presentation choice as **FLY
COCKPIT**. It defaults to **OFF** for a clear view. Turn it **ON** to restore
Free Fly's original cockpit picture. The adapter runs only during the HUD
pass and only while Free Fly's public state says flight is active, so the
world-space mount remains visible in third person and all flight rules remain
owned by Free Fly. Later Free Fly versions are left untouched until their HUD
contract is verified or they publish a native cockpit setting.

## Pokemon Final cache result compatibility

Some early Pokemon Final packages started **BUILD VOXEL CACHE** correctly but
left a false **COULD NOT START** message behind. Scott's Tweaks checks the
exported cache screen with an inert fake instance. It installs a small
post-wrapper only when that exact behavior is present, and clears the fallback
only after the cache reports that it is actually building. Real start errors
are not hidden.

This does not rebuild, clear, read, or change the disk cache. The exact
`1.8.1-scott.3` package contains the correction; later private packages are
left untouched until their cache-screen contract is separately audited. No
Pokemon Final source or assets are included in this public mod.

## Voxel running

The original bridge makes Gen1Recomp movement-speed mods work while a
supported voxel mod is driving the player in **1ST** or **3RD** person. That
includes Running Shoes mods that use the engine's public `movement.speed`
hook.

It does not grant shoes, add a quest, or choose a speed. It carries the speed
already selected by another mod from the normal grid walker into the voxel
mod's continuous `FreeMove` walker. Step out of first/third person and the
ordinary engine path takes over unchanged.

**The bridge has no effect by itself.** Enable one movement-speed producer as
well, such as [MadeinTaly's Running Shoes](https://github.com/MadeinTaly/gen1recomp-running-shoes)
or [Run Mode](https://github.com/masterwebx/gen1recomp-run-mode). Those two
are the main reason this adapter exists: their normal run hook does not enter
voxel free movement on its own.

### Do you need the run bridge?

- **Pokemon Final + Running Shoes:** yes. Scott's Tweaks 0.4.3 recognizes
  Pokemon Final's own manifest ID and carries the run speed into its 1ST/3RD
  camera movement.
- **[thorkdev Running Shoes v0.2.2 or newer](https://github.com/thorkdev/gen1recomp-running-shoes/releases/tag/0.2.2)
  + Dramatic Shape/Battle Art Voxel Fork:** probably not. That Running Shoes
  release already contains a dedicated
  integration, and this bridge detects it and stays idle to prevent doubling
  the speed. That release also already provides a running-only camera bob:
  set **VIEW BOB** to **ON** and **BOB INTENSITY** to **0.5X** for the very
  light effect. Leave Battle Art's general **HEAD BOB** setting off if you
  want bobbing only while running.
- **An older/different `movement.speed` mod:** yes, this is the generic bridge.
- **Dramaless Shape or PotatoVoxel:** this bridge supports their exported
  `FreeMove` module too, including Running Shoes versions that do not know
  those mod IDs.

MadeinTaly's and thorkdev's projects both use the manifest ID
`running_shoes`, so Gen1Recomp treats them as alternative implementations;
do not install both at once.

Supported voxel manifest IDs:

- `POKEMON_FINAL`
- `DRAMATIC_SHAPE`
- `BATTLE_ART_VOXEL_FORK`
- `DRAMALESS_SHAPE`
- `potato_voxel`

Only one of those is expected to be active; the voxel projects conflict with
one another in their own manifests. PotatoVoxel's default low-power profile
currently hides the 1ST/3RD rungs, so its bridge support matters only when its
full camera ladder is enabled.

## Install or update

If Voxel Run Bridge or any Scott's Tweaks 0.2.x/0.3.x release is installed, open
Gen1Recomp's puzzle-piece / **MODS** panel and install the offered 0.4.3
update. It will appear as
**Scott's Tweaks** afterward, without creating a second entry.

For a first installation:

1. Open **MODS -> Import mod .zip** and choose
   `SCOTTS_TWEAKS-0.4.3.zip`.
2. Enable **Scott's Tweaks**, then restart the game if the manager asks.
3. Its **BAG POCKETS**, **GAPPED LAND**, **BADGE-FREE HMS**, and **FREE FLY
   NOW** options default to **ON**; **FLY COCKPIT** defaults to **OFF** and
   **EXP. MODE** defaults to **VANILLA**.
4. Update Free Fly to **1.6.1 or newer** and enable it for free-roaming flight.
5. For voxel running, also enable one supported voxel provider and a
   movement-speed mod such as Running Shoes.

The manager will ask for the `engine_internals` permission. Scott's Tweaks
uses Gen1Recomp's official content, screen, battle, field-move, and party-menu
seams, plus the existing voxel companion export. The internal permission also
supports the narrowly namespaced Trade Stone dispatcher on Gen1Recomp 0.1.75;
newer engines already dispatch the registered effect natively. It requests no
network or filesystem permission.

Restart after enabling, disabling, or updating this bridge. Its small
inter-mod wrapper is installed into the voxel provider's exported table and
cannot be safely swapped by the developer F5 hot-reload path.

## How badge-free HMs work

Gen1Recomp exposes `fieldmove.eligibility` for field-move eligibility and
`ui.party.submenu` for party actions. Scott's Tweaks calls the rest of each
hook chain first, then supplies only a missing action for a party Pokemon that
already knows the corresponding HM. Fly remains outdoor-only, Flash remains
dark-map-only, and Cut/Surf keep their normal facing-tile checks.

The implementation never sets a badge flag, so gym progression, obedience,
story gates, and other mods continue to see the real journey state.

## How voxel running works

The regular grid walker measures movement as frames per 16-pixel step and
calls `movement.speed` before each step. Voxel first/third person replaces
that path with `FreeMove.tick`, measured in pixels per frame, so the hook is
otherwise bypassed.

For each free-movement tick, this mod:

1. asks the normal `movement.speed` chain for the effective frame count using
   the same context as the grid player;
2. converts that result into a ratio (`base frames / effective frames`);
3. applies the ratio to the active voxel `WALK` or `BIKE` speed for one tick;
4. restores the original constants immediately, including on errors.

Unlike the grid walker, free movement samples `movement.speed` continuously.
That keeps held-button and terrain effects correct as the player crosses
cells. It also means a custom speed hook used with this bridge should behave
as a transformation of the supplied frame count rather than counting how
many times the hook itself was called. The context includes
`freeMove = true` and `continuous = true` so a hook can distinguish this path.

The bridge does not consult movement hooks while the player is already moving
under a script or has input locked. It therefore stays out of cutscenes and
NPC-controlled movement. A bug inside the underlying Running Shoes mod's
normal grid behavior is outside this adapter's scope.

## Develop and verify

Use the `dev` branch of
[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) as the SDK:

```powershell
python tools/modkit.py validate C:\path\to\voxel_run_bridge --strict --base fixture
python tools/modkit.py lint C:\path\to\voxel_run_bridge
python tools/modkit.py pack C:\path\to\voxel_run_bridge -o C:\path\to\dist\SCOTTS_TWEAKS-0.4.3.zip --base fixture
```

The archive is intentionally flat: `manifest.json` and `main.lua` are at its
root, which Gen1Recomp's importer accepts directly.

Version 0.4.3 is configured for Gen1Recomp's built-in GitHub update checks via
`ScottExplores/gen1recomp-voxel-run-bridge`.

The download is deliberately named `SCOTTS_TWEAKS-0.4.3.zip` to match the
name players see in the mod list. Its internal ID remains `voxel_run_bridge`
so existing installs and saved settings update in place rather than appearing
as a second mod.

## Provenance

This implementation was written against Gen1Recomp's documented movement
and rendering contracts and the voxel mods' exported module interfaces. The
Gapped Land plane is generated by Scott's Tweaks and includes no copied
renderer code, textures, or horizon art. It does not copy the existing
`thorkdev/gen1recomp-running-shoes` implementation, whose repository currently
does not declare a software license. That project is credited for publicly
demonstrating and documenting the first-person movement gap.

No ROM, extracted graphics, save data, or other game content is included.
