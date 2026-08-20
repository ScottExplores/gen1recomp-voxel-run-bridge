# Scott's Tweaks

**0.12.0 is the single-package Scott's Tweaks release.** The 3D voxel Kanto
renderer, visible wild Pokemon, followers, animated battle sprites, menu
icons, Free Fly integration, and Scott's gameplay tweaks are bundled so one
launcher update carries the full set. Separately installed copies are no
longer required; when one is present, the standalone copy remains the owner
and the matching bundled copy stands down.

Scott's Tweaks is the next version of **Voxel Run Bridge**. The display name
is broader, but its internal mod ID remains `voxel_run_bridge`. Existing
installations therefore update in place, keep their settings, and do not
become a duplicate mod.

Version 0.12.0 keeps the existing updater identity and provides one categorized
**START > MOD MENUS > MOD SETTINGS** home for all of its settings. Its
features are:

- **Built-in Pack and Pokegear:** Red's ITEM row can appear as PACK, followed
  by a separate POKéGEAR with a live clock and Red's native Kanto Map. It is
  entirely built in and never asks for a Pokemon Gold ROM.
- **Classic bag pockets:** press D-pad Left or Right to move in Gold order
  through ITEMS, BALLS, KEY ITEMS, and TM/HM while keeping the original Gen 1
  inventory underneath.
- **Shop counts:** the BUY screen shows how many of the selected item are
  already in the bag.
- **Experience modes:** choose VANILLA, LEAD ONLY, PARTY ALL, or EXP.SHARE.
  Selecting EXP.SHARE permanently unlocks a visible key item in the bag.
- **Trade Stone:** every Gen 1 mart sells a ₽500 stone that evolves Kadabra,
  Machoke, Graveler, or Haunter through the normal evolution sequence.
- **Trainer forfeits and rematches:** pay ¥200 to leave an ordinary trainer
  battle, then safely revisit defeated ordinary trainers or any of the eight
  Gym Leaders without replaying one-time story rewards. Authored journey
  dialogue and gentle rematch growth work offline.
- **Oak's spare starter:** in Red or Blue, return after the Oak's Lab rival
  battle and claim the one remaining starter ball once, when the party has
  room.
- **Built-in B running:** hold B while walking for an always-available 1.5X
  run by default. First-person voxel running receives a new, very light
  distance-based camera bob at 0.5X intensity by default.

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

These features never fabricate badges or rewrite story flags. Oak's starter
uses Gen1Recomp's normal gift flow, so receiving it intentionally updates the
party and Pokédex just like another legitimate gift Pokémon.

## One organized settings menu

Open **START > MOD MENUS > MOD SETTINGS** when Gen 1 Modern UI is enabled.
Without Modern UI, **MOD SETTINGS** appears directly on Start. The menu groups
the fused mod into view/camera, world, Pokemon art, battles, wild/followers,
movement, and menu/device categories. **OPTIONS SHOWN: BASIC / ALL** keeps the
normal screen short without changing any hidden value. The in-game Mod Manager
opens this same menu, and its schema uses the same saved values.

`MENU ICONS` is built while the mod loads. Changing that row saves the new
choice for the next restart; this keeps icon art and its true-color rendering
in sync with the engine's frozen content registry.

## Trainer forfeits and rematches

The incorporated Trainer Forfeit & Rematches 0.3.0 feature adds a ¥200
confirmation to RUN in ordinary trainer encounters. A successful payment
ends that battle without granting victory or applying blackout loss behavior.
Talking to a completed ordinary trainer offers a clean rematch. Brock, Misty,
Lt. Surge, Erika, Koga, Sabrina, Blaine, and Giovanni also become safely
repeatable only after their original badge/TM choreography is fully complete.
Giovanni remains gone; his Viridian Gym guide offers the repeat battle.

Rematches preserve original defeated flags and never replay badges, TMs, map
changes, or other one-time victory hooks. Journey dialogue is deterministic,
authored, offline, and stored under Scott's Tweaks' private trainer-memory
key. **TRAINER GROWTH: GENTLE** can raise repeat rosters modestly for that
battle without rewriting base trainer data.

**PAID FORFEIT** and **TRAINER REMATCHES** are independent. Turning the paid
RUN choice off leaves ordinary/Gym rematch availability, journey recording,
dialogue, and gentle growth working. Turning rematches off leaves only the
paid ordinary-trainer RUN choice.

## Oak's spare starter

In Red or Blue, finish the normal starter choice and Oak's Lab rival battle,
then interact with the sole ball left on Oak's table. If the party has fewer
than six Pokémon, the remaining level-5 starter joins through the engine's
normal gift flow and the ball is hidden permanently. With a full party, it
waits in the lab. Yellow is deliberately unchanged.

If `random_starters` is active, only this Oak feature stands aside; every
other Scott's Tweaks feature remains active.

## Bag pockets and shop counts

The default-on **CLASSIC BAG POCKETS** option presents the Gen 1 bag as four
tabs in Gold's order: **ITEMS**, **BALLS**, **KEY ITEMS**, and **TM/HM**. Press
D-pad Left or Right inside the bag to change tabs. SELECT still reorders items,
and the order is written back by item identity so filtering never corrupts the
real bag order.

This is a view over the existing inventory, not a larger replacement bag.
Saving, item quantities, the Gen 1 slot limit, battle item use, selling, and
other mods' items remain owned by Gen1Recomp. Unknown custom items stay
visible under ITEMS. With **PACK + POKéGEAR** off, turn **CLASSIC BAG POCKETS**
off to use the original one-list bag. PACK keeps this Red-inventory pocket
projection active without overwriting the saved classic preference.

When BUY is open at a mart, its title includes **BAG:N** for the currently
highlighted item. The count updates after a purchase and does not alter shop
prices or stock supplied by other mods.

## Built-in Pack and Pokegear

**PACK + POKéGEAR** is default OFF and needs no external file. When enabled,
the native Red ITEM/ITEMS row is presented as **PACK** with the exact same bag
callback. The four-pocket Red inventory view remains underneath, in the order
ITEMS, BALLS, KEY ITEMS, and TM/HM.

A separate **POKéGEAR** row appears immediately after PACK. It opens a small
native screen containing the current clock and Red's existing Kanto Map. This
does not copy or imitate Pokemon Gold artwork, and it deliberately omits fake
Phone/Radio systems that Red does not have.

Gen 1 Modern UI should stay installed. It can present the native Bag, Kanto
Map, and all of its other supported screens normally. Scott's Thor presenter
sends those same UI canvases to the lower screen without a second renderer.

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
capabilities rather than trusted by display name alone. Version 0.12.0 targets
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

Scott's Tweaks now supplies its own public `movement.speed` producer. Hold B
while walking to run immediately; no shoes item, quest, badge, or save unlock
is required. The default is 1.5X, with 1.25X and 2X choices. Bikes, surfing,
scripted movement, and input-locked scenes are excluded.

The original bridge remains the renderer-neutral adapter that carries the
same held-B result into a compatible voxel mod's continuous **1ST/3RD**
`FreeMove` walker. It samples the one public producer exactly once and restores
the renderer's temporary speed constant after every tick, including errors.

**RUN HEAD BOB** is a new Scott-authored first-person camera effect. It
advances from actual distance traveled rather than a timer, touches only a
per-frame camera proxy, and never mutates player height or collision. It
defaults on at the intentionally subtle **0.5X** intensity. Turn it off for a
completely steady first-person run.

### Do you need the run bridge?

- **Pokemon Final:** yes. Scott's Tweaks recognizes Pokemon Final's stable ID
  and carries its built-in run into the 1ST/3RD camera movement.
- **A standalone `running_shoes` mod:** that mod remains the sole running
  owner. Scott's internal producer and bob stand aside, and the corresponding
  Tweaks rows say **OTHER MOD** instead of stacking a second multiplier.
- **Run Mode or another `movement.speed` producer:** turn **B-BUTTON RUN** off
  if that producer should own the speed; the generic voxel bridge can still
  carry its result.
- **Dramaless Shape or PotatoVoxel:** this bridge supports their exported
  `FreeMove` module too.

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

## Standalone-mod transition and save migration

Scott's Tweaks now contains the MIT Trainer Forfeit 0.3.0, Oak's Spare Starter
0.1.1, and Scott's clean running producer. It does not copy private voxel or
dual-screen mods, and it does not copy the unlicensed thorkdev Running Shoes
source.

If `trainer_forfeit`, `oak_spare_starter`, or `running_shoes` is still enabled,
Scott's Tweaks detects it and delegates that corresponding feature instead of
installing a duplicate hook. Disable the old standalone mod when ready to use
the integrated controls. Other Tweaks remain active throughout the transition.

On the first load of each save, 0.5.0 and newer copy recognized legacy values only
when the corresponding new value was never explicitly stored:

- Trainer Forfeit rematch/dialogue/growth preferences and journey memory;
- Oak's one-time claimed marker;
- the distinctive 0.x Running Shoes enabled/speed/view-bob settings, or
  Scott Mod's run preferences; and
- old `gen1recomp_ds.enabled` into **THOR SECOND SCREEN**.

The import records one per-feature marker table in `voxel_run_bridge` save
data. It never deletes or edits an old mod namespace, and repeating the
lifecycle event is a no-op. A feature's marker remains pending while its
standalone provider is active, so a later claim, trainer-history update, or
preference change is imported after that provider is removed rather than
being stranded.

## Physical Thor second screen

**THOR SECOND SCREEN** is the one on/off authority for Scott's original
physical-AYN-Thor presenter. It routes supported menu surfaces only when a
real lower display is attached. On a normal PC, handheld with one display, or
missing second display, the game remains a normal single-screen layout. It
does not merge or redistribute the private upstream-derived Dual Screen or
Battle Art implementations.

If the older `gen1recomp_ds` mod is still enabled, its presenter remains the
owner and this row reads **OTHER MOD** without accepting edits. Disable that
legacy mod and restart; Scott's row then returns to its normal **ON/OFF**
control, with the final legacy enabled preference imported only when no newer
Scott's Tweaks choice was already saved.

## Install or update

If Voxel Run Bridge or any earlier Scott's Tweaks release is installed, open
Gen1Recomp's puzzle-piece / **MODS** panel and install the offered 0.12.0
update. It will appear as **Scott's Tweaks** afterward without creating a
second entry.

For a first installation:

1. Open **MODS -> Import mod .zip** and choose
   `voxel_run_bridge-0.12.0.zip`.
2. Enable **Scott's Tweaks**, then restart the game if the manager asks.
3. Open **START > MOD MENUS > MOD SETTINGS**. Classic bag pockets, trainer
   features, Oak's starter, B running, light run bob, gapped land, badge-free
   HMs, Free Fly Now, visible wild Pokemon, and one follower default on.
   Classic random battles and hidden encounter markers default off. EXP
   defaults to Vanilla; Fly Cockpit, Thor Second Screen, and Pack + Pokegear
   default off; run speed defaults to 1.5X and bob to 0.5X.
4. Update Free Fly to **1.6.1 or newer** and enable it for free-roaming flight.
5. For 1ST/3RD running, enable one supported voxel provider; no separate
   running mod is required.
6. To use PACK and POKéGEAR, open **START > MOD MENUS > MOD SETTINGS >
   MENUS & DEVICE** and switch **PACK + POKéGEAR** ON. No imported file or app
   replacement is required.

The manager will ask for the `engine_internals` permission. Scott's Tweaks
uses Gen1Recomp's official content, screen, battle, field-move, and party-menu
seams, plus the existing voxel companion export. The internal permission also
supports the narrowly namespaced Trade Stone dispatcher on Gen1Recomp 0.1.75;
newer engines already dispatch the registered effect natively. It requests no
network or filesystem permission.

Restart after enabling or disabling a whole mod. Developer F5 entry reloads
reuse owned process-global dispatchers and refresh their generation-local
callbacks instead of stacking movement or camera wrappers.

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
python tools/modkit.py pack C:\path\to\voxel_run_bridge -o C:\path\to\dist\voxel_run_bridge-0.12.0.zip --base fixture
```

The archive keeps `manifest.json`, `main.lua`, `LICENSE`, notices, and the
`modules/` directory at its root. Gen1Recomp's importer mounts those paths
unchanged; development tests and unrelated workspace files are excluded.

Version 0.12.0 is configured for Gen1Recomp's built-in GitHub update checks via
`ScottExplores/gen1recomp-voxel-run-bridge`.

The download is deliberately named `voxel_run_bridge-0.12.0.zip` so the
launcher selects it first from the matching GitHub release. Its internal ID
remains `voxel_run_bridge`, so existing installs and saved settings update in
place rather than appearing as a second mod.

## Provenance

The original Scott's Tweaks code was written against Gen1Recomp's documented
movement/rendering contracts and voxel mods' exported module interfaces. The
Gapped Land plane is generated by Scott's Tweaks and includes no copied
renderer code, textures, or horizon art. It does not copy the existing
`thorkdev/gen1recomp-running-shoes` implementation, whose repository currently
does not declare a software license. That project is credited for publicly
demonstrating and documenting the first-person movement gap.

The consolidated release also incorporates Scott-owned MIT modules from Trainer Forfeit
0.3.0, Oak's Spare Starter 0.1.1, Scott Mod, and Scott's Sprite Menu. Their
copyright notices and MIT terms are preserved in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). The physical-Thor presenter
is new public code; no source from the private/upstream-derived Dual Screen or
Battle Art packages is included.

No ROM, extracted graphics, save data, or other game content is included or
requested by Scott's Tweaks.
