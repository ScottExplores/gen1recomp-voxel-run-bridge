# Scott's Tweaks

**0.12.8 makes voxel Kanto safer, clearer in third person, and more alive after
dark while keeping its original pixel identity.** Visible wild Pokémon can no
longer occupy or interrupt Pokémon Tower's scripted Marowak encounter. Indoor
third-person views open a small camera-side cross-section instead of cutting
away half the building, and one-sided ceiling surfaces keep elevated cameras
from looking into an opaque roof. The higher sun arc is joined by pixel lunar
phases, phase-matched reflections and moonlight, and a subtle Milky Way that is
most visible near the new moon. PIXEL HILLS adds an optional code-drawn
mountain, foothill, and forest horizon. A calendar-only seasonal rain mode adds
variety without GPS, a network connection, or a location permission. The
native-pixel Pocket Bag, selectable Pokémon art, voxel Kanto, visible wild
Pokémon, followers, Free Fly, and Scott's other tweaks remain one updater
package; no Gen 2/Stadium models or terrain are imported.

Scott's Tweaks is the next version of **Voxel Run Bridge**. The display name
is broader, but its internal mod ID remains `voxel_run_bridge`. Existing
installations therefore update in place, keep their settings, and do not
become a duplicate mod.

Version 0.12.8 keeps the existing updater identity and provides one categorized
**START > MOD MENUS > MOD SETTINGS** home for all of its settings. Its
features are:

- **Responsive Bag and PC:** press D-pad Left or Right through ALL, ITEMS,
  MEDICINE, POKé BALLS, TM/HM, and KEY ITEMS. The Pocket skin uses an original
  generated six-state 34×21-pixel backpack and repeating 4×4 blue dither; the
  optional Modern skin uses compact tabs. Every state keeps one fixed backpack
  silhouette and changes only its selected compartment. The selected Pocket
  plaque stays large and title-case while the full category name owns the top
  header. PC withdraw, deposit, and toss lists use the same organization.
- **Selectable Pokémon art:** press Left/Right on ART PACK for Crystal 2.0 or
  Battle Art Gen 1-5. Each Battle Art preset keeps its front and back
  generation together and saves immediately.
- **Cleaner staged Pokémon:** moving battle cards no longer receive their own
  unstable mobile shadow sample, removing the camera-motion bands while their
  normal arena shadows and lighting remain.
- **Clearer battle status:** staged HP/level cards gain a subtle translucent
  backing and the player's EXP progress below HP now animates as it grows.
  Current engines use their native Poké Ball glyph to mark caught wild species
  in both flat and staged battles; the staged renderer supplies a compatibility
  glyph on older builds. HUD text defaults WHITE and can be changed to BLACK;
  damaging moves show a green up or red down pixel cue when the engine's own
  type chart says they are effective or resisted.
- **Independent difficulty:** TRAINERS, BOSSES (Gym Leaders, Elite Four, and
  Champion), and WILD POKEMON each keep their own OFF/NORMAL/MEDIUM/HARD tier.
  Existing saves with the earlier single difficulty row seed all three once.
- **Pixel battle entry:** trainer and wild encounters use related three-band
  Poké Ball shutters, with opposite directions so the two remain distinct.
- **Built-in Pack and Pokegear:** Red's ITEM row appears as PACK, followed by
  CLOCK, MAP, PHONE, and RADIO Pokégear cards adapted to Red. It is entirely
  built in and never asks for a Gold ROM.
- **Shop counts:** the BUY screen shows how many of the selected item are
  already in the bag.
- **EXP.SHARE:** choose OFF, BUDDY (the active Pokemon plus its next healthy
  party mate), or ALL healthy party Pokemon. Either sharing mode permanently
  unlocks a visible key item in the bag.
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
  distance-based camera bob at 0.5X intensity by default. A sight trainer turns
  the first-person camera toward the trainer before the challenge dialogue.
- **Story-safe visible wilds:** the scripted Marowak trigger on Pokémon Tower
  6F stays reserved until that story encounter is complete. A visible wild
  cannot spawn, wander, chase, or begin its own battle on the trigger cell.
- **Cleaner third-person interiors:** CUTAWAY follows the camera and opens only
  a bounded nearby section while preserving the far and side room shell.
  Ceiling undersides remain visible from inside but do not become an opaque
  lid when the camera rises above a building.
- **Living pixel sky:** the sun travels on a noticeably higher arc. REAL CLOCK
  derives the Moon's phase from the device clock; accelerated day modes cycle
  it across eight in-game days. The pixel Moon, water reflection, moonlight,
  and night palette agree on that phase, while the dithered Milky Way is most
  apparent around a new moon.
- **Private seasonal rain:** LOCAL SEASON uses only the device's month and day
  for broad northern-temperate winter, spring, summer, and autumn rain habits.
  It never requests GPS or weather data and never contacts a service.
- **Lightweight pixel horizon:** PIXEL HILLS code-draws day/night-tinted
  mountain, foothill, and forest silhouettes behind the real map. It ships no
  new panorama asset and caps its geometry for the Thor.
- **Gapped Land:** compatible Pokemon Final, Dramatic Shape, and Battle Art
  renderers can cover the empty visual space beneath the horizon in outdoor
  first- and third-person views. This presentation option is on by default.
- **Free Fly Now:** Free Fly can take off immediately without the Thunder
  Badge. This compatibility option is on by default.
- **Free Fly cockpit control:** **FLY COCKPIT** shows the flying Pokémon in
  first-person while keeping the player's own head/rider out of the camera.
  On a physical Thor that mount appears only on the upper gameplay display;
  the default-off setting can still hide the cockpit picture entirely.
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

BASIC keeps the everyday choices compact. ALL restores the complete camera,
renderer, Battle Art source, Crystal provider, and Pokemon orientation controls.
The player-front, player-back, and opponent battle cards have independent flip
choices; changing one never mirrors a trainer portrait or another card.

Under **POKEMON ART**, press Left or Right on **ART PACK** to compare the
built-in **CRYSTAL 2.0** and **BATTLE ART G1** through **BATTLE ART G5**
pictures. Each Battle Art preset selects matching front and back generations
together; Gen 2 is the bundled Crystal-era Battle Art set, not another name for
the Crystal 2.0 provider. Press A for pack details. ALL mode retains the
separate expert source and generation rows for custom mixes.

Under **MENUS & DEVICE**, **BAG LOOK** switches between **POCKET** and
**MODERN** without changing inventory data. **PACK + POKéGEAR** independently
controls the Start-menu PACK name and four Pokégear cards, so the two choices
do not fight each other.

Under **WILD & FOLLOWERS**, **ENCOUNTER MODE: VISIBLE** means visible overworld
Pokemon on, classic step-based random battles off, and sprite-less hidden
markers off. Selecting it also replaces conflicting settings from an older
standalone Wilds install and rebuilds the current map once, so the label and
the live grass encounters cannot silently disagree.

Under **BATTLES**, **TRAINERS** and **BOSSES** independently select
OFF/NORMAL/MEDIUM/HARD dynamic difficulty. BOSSES covers the eight Gym
Leaders, Elite Four, Champion, and the optional Professor Oak fight; ordinary
rivals remain under TRAINERS. **WILD POKEMON** lives under **WILD & FOLLOWERS**
and uses the same four tiers. An older saved **DIFFICULTY** value initializes
only missing new controls in one durable migration, preserving any category
the player has already chosen.

Under **WORLD & WEATHER**, **DAYTIME: REAL CLOCK** follows local wall time and
the real lunar cycle. **GAME 20 MIN** and **GAME 1 HOUR** instead run complete
accelerated in-game days and move through a full Moon cycle in eight game days;
GAME 1 HOUR takes exactly 3,600 real seconds through morning, day, dusk, night,
and back to morning. The existing fixed DAY/NIGHT/DUSK/DAWN choices remain
available. The sun now rises visibly above the horizon in every moving mode;
the existing **NIGHT SKY** toggle controls the stars and Milky Way together.

In **OPTIONS SHOWN: ALL**, **WORLD & WEATHER > RAIN** adds **LOCAL SEASON**
beside OFF, SOMETIMES, and ALWAYS. LOCAL SEASON reads only the device calendar
and applies a broad northern-temperate seasonal pattern with stable daily
variation. It is not live local weather: there is no GPS, location lookup,
network request, or new permission. **SOMETIMES** remains the default.

In the same ALL-mode category, leave **HORIZON** on and select **HORIZON ART:
PIXEL HILLS** for a lightweight code-drawn mountain, foothill, and forest
horizon. It is pixel-quantized, follows day/night tint, and uses fixed handheld
geometry limits instead of adding a panorama image or distant 3D terrain.

Also in ALL mode, **VIEW & CAMERA > 3RD CEILING: CUTAWAY** keeps a small
camera-near side of an interior open while leaving the distant walls and roof
structure intact. NONE hides the third-person ceiling and FULL keeps the full
room shell.

Under **WILD & FOLLOWERS** in ALL mode, **CATCH HUD SIZE** changes only the
small Ball inventory/power HUD on the top gameplay screen during overworld
catching. Values 1–10 change its size; 5 is the default, and 0 hides that HUD
without turning off overworld catching, Ball switching, aiming, or throws.

Under **BATTLES**, **HUD COLOR: WHITE / BLACK** controls the Pokémon names,
levels, HP label, and HP numbers over staged scenery. WHITE is the new-install
default; old COLOR/INVERTED save tokens retain their original appearance.

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

## Bag, PC, and shop counts

The default **BAG LOOK: POCKET** view organizes the live Gen 1 inventory into
**ALL**, **ITEMS**, **MEDICINE**, **POKé BALLS**, **TM/HM**, and **KEY ITEMS**.
All is a neutral combined view; the other five views select one compartment on
Scott's original generated pixel backpack. **BAG LOOK: MODERN** presents the
same categories as compact responsive tabs. Press D-pad Left or Right to
change views. SELECT still reorders items by identity, so filtered row numbers
never corrupt the authoritative acquisition order.

The same presentation applies to PC **WITHDRAW**, **DEPOSIT**, and **TOSS**
lists while each native callback remains authoritative. This release
deliberately retains Gen1Recomp's native Bag/PC capacities and x99 quantity
limit; choosing a skin cannot change save mechanics or cartridge-export
limits. Unknown custom and explicitly battle-pocket items remain visible under
ITEMS, while custom balls, machines, non-tossable key items, and medicine use
their matching categories.

The layout responds to desktop, landscape handheld, and portrait phone
surfaces. On a physical Thor it requests a Bag-only 200×144 menu canvas, which
fills the 400px display width at exact 2× while keeping the original five-row
height. This prevents long item and pocket names from being squeezed without
changing battle or dialogue resolution. If a separately installed Modern Bag
UI is enabled, that copy remains the sole Bag/PC owner and Scott's BAG LOOK row
reports **OTHER MOD**.

When BUY is open at a mart, its title includes **BAG:N** for the currently
highlighted item. The count updates after a purchase and does not alter shop
prices or stock supplied by other mods.

## Built-in Pack and Pokegear

**PACK + POKéGEAR** defaults ON for new installs and needs no external file.
An existing explicitly saved OFF choice remains OFF. The native Red ITEM/ITEMS
callback is still used and merely appears as PACK. Bag presentation is owned by
the separate **BAG LOOK** choice above. Item use, battle actions,
GIVE-compatible callbacks, shops, saving, and Red's real inventory limits are
unchanged.

A separate **POKéGEAR** row appears immediately after PACK. Its four cards are
**CLOCK**, **MAP**, **PHONE**, and **RADIO**. CLOCK uses live time; MAP opens
Red's native Kanto Map; PHONE reads Scott's existing trainer/rematch history
without creating fake Gen II calls; and RADIO uses only songs already present
in the active Red data, restoring map music when it closes or retunes. Missing
capabilities explain themselves instead of becoming dead buttons. The chrome
is drawn from original primitives and imports no Gold/Crystal screen art.

Gen 1 Modern UI should stay installed. It can present the native Bag, Kanto
Map, and all of its other supported screens normally. Scott's Thor presenter
sends those same UI canvases to the lower screen without a second renderer.

## EXP.SHARE

**EXP. SHARE** is one three-way setting:

- **OFF** (default) leaves normal battle participation and a legitimately
  owned EXP.ALL completely unchanged.
- **BUDDY** splits one defeated-Pokemon award between the active Pokemon and
  its next conscious, non-Egg party mate. If only one is eligible, it receives
  the full award.
- **ALL** splits one award evenly across every conscious, non-Egg Pokemon in
  the party.

Either sharing mode permanently unlocks the passive **EXP.SHARE** key item in
the bag. The item is an indicator; this one setting remains authoritative. If
the bag is full, sharing still works and the item is added when room becomes
available. Changing modes does not remove it. Scott's Tweaks calls the
engine's public per-Pokemon EXP award seam directly, so leveling, move
learning, traded bonuses, and messages remain native while the real Route 15
EXP.ALL item and its story event are never granted, consumed, or edited.

Existing saves migrate without another setting: the former **LEAD ONLY** value
behaves as **BUDDY**, while former **PARTY ALL** and **EXP.SHARE** values behave
as **ALL**. The next save lifecycle writes the canonical value into both the
save and live Mod Manager so every settings screen reports the same choice.

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
capabilities rather than trusted by display name alone. Version 0.12.8 targets
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
Scott's Tweaks already bundles Free Fly 1.8.0, so no separate Free Fly download
is required. The badge adapter is also compatible with supported standalone
Free Fly installs when a player deliberately keeps one as the owner.

This does not add a badge, teach a move, or alter the save. Free Fly still
decides which Pokemon can carry the player and keeps its FLY eligibility,
story gates, map rules, and landing checks. Free Fly groups its Thunder Badge
takeoff rule and Soul Badge water-landing rule under the same **BADGE CHECKS**
option, so both badge checks are relaxed while **FREE FLY NOW** is on.

Turn **FREE FLY NOW** off in Scott's Tweaks to return control to Free Fly's
own saved **BADGE CHECKS** preference. Its exact previous value is restored.

The bundled 1.8.0 build uses capability detection, so its first- and
third-person flight support also finds Pokemon Final. If a standalone Free Fly
copy is intentionally enabled, it remains the owner; use 1.6.1 or newer for
Pokemon Final compatibility.

Free Fly can draw a separate mount picture at the bottom of an ordinary
single-screen first-person HUD. Scott's Tweaks exposes that choice as **FLY
COCKPIT**. It defaults to **OFF** for a clear view. True first person always
omits the separate rider/head card while retaining the flying Pokémon; third
person keeps its normal complete world-space composite. When the option is ON
on a physical Thor, Scott's presenter removes the copy from the lower UI and
draws the properly scaled mount once on the upper gameplay display instead.
Disconnecting or turning Thor mode off restores ordinary single-screen
routing. The adapter runs only while Free Fly's public state says flight is
active, so all movement, eligibility, and landing rules remain owned by Free
Fly. The adapter covers the verified 1.6.2 and bundled 1.8.0 HUD contracts;
unknown standalone versions stand aside safely.

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
completely steady first-person run. The historical raw 0.25 strength is shown
as **1X**; 0.25X, 0.4X, 0.5X, 0.6X, and 0.75X choices provide gentler motion.

### Do you need a separate run bridge?

No. The bridge is part of Scott's Tweaks; do not download Voxel Run Bridge as
a second mod. The cases below only explain when the built-in bridge is active:

- **Pokemon Final:** the built-in bridge recognizes Pokemon Final's stable ID
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
- old `gen1recomp_ds.enabled` into **THOR 2ND SCREEN**.

The import records one per-feature marker table in `voxel_run_bridge` save
data. It never deletes or edits an old mod namespace, and repeating the
lifecycle event is a no-op. A feature's marker remains pending while its
standalone provider is active, so a later claim, trainer-history update, or
preference change is imported after that provider is removed rather than
being stranded.

## Physical Thor second screen

**THOR 2ND SCREEN** is the one on/off authority for Scott's original
physical-AYN-Thor presenter. It routes supported menu surfaces only when a
real lower display is attached. On a normal PC, handheld with one display, or
missing second display, the game remains a normal single-screen layout. It
does not merge or redistribute the private upstream-derived Dual Screen or
Battle Art implementations.

When a saved **ON** preference starts on Android, Scott's Tweaks now requests
the native Presentation first and then checks attachment, so the lower display
comes up during cold boot without an OFF/ON toggle or leaving and reopening an
already-visible menu. A menu opened before the first world frame receives a
neutral upper image until live gameplay is available instead of blocking the
lower presentation.

During staged battles, the lower panel keeps wording, menus, and HUD chrome.
Pokemon cards, trainer cards, and move-effect sprites stay in the upper arena
instead of being duplicated below. Dialogue and command bands start near the
hinge at the top of the lower display; TYPE/PP and the move list stay joined
directly below that band, bringing the active choices toward the middle of the
device. Ordinary NPC/trainer dialogue uses that same hinge-side position.
Fight and Mimic selection panels fill their unused upper-right area with white
so the joined boxes remain flush. A question stays at the hinge and its small
YES/NO box is recomposed directly below it; white fills only that horizontal
answer band, leaving the rest of the lower display black. The original Start
menu keeps its borders, normal 2× text, narrow authored width, and eight
double-spaced rows while using 288 pixels of the lower display vertically. The
Safari Zone keeps its complete two-box steps/balls layout at the normal
full-surface scale. Full-screen Bag, Party, and settings surfaces remain
centered.
Disabling the option or unplugging the second display immediately restores the
ordinary single-screen composition.

If the older `gen1recomp_ds` mod is still enabled, its presenter remains the
owner and this row reads **OTHER MOD** without accepting edits. Disable that
legacy mod and restart; Scott's row then returns to its normal **ON/OFF**
control, with the final legacy enabled preference imported only when no newer
Scott's Tweaks choice was already saved.

## Install or update

If Voxel Run Bridge or any earlier Scott's Tweaks release is installed, open
Gen1Recomp's puzzle-piece / **MODS** panel and install the offered 0.12.8
update. It will appear as **Scott's Tweaks** afterward without creating a
second entry.

For a first installation:

1. Open **MODS -> Import mod .zip** and choose
   `voxel_run_bridge-0.12.8.zip`.
2. Enable **Scott's Tweaks**, then restart the game if the manager asks.
3. Open **START > MOD MENUS > MOD SETTINGS**. The Pocket Bag, trainer
   features, Oak's starter, B running, light run bob, gapped land, badge-free
   HMs, Free Fly Now, visible wild Pokemon, and one follower default on.
   Classic random battles and hidden encounter markers default off. EXP.SHARE
   and all three difficulty categories default OFF; Fly Cockpit and Thor
   Second Screen default off; battle HUD text defaults WHITE;
   Pack + Pokegear defaults on; run speed defaults to 1.5X and
   bob to 0.5X.
4. Use the bundled Free Fly for free-roaming flight; no separate mod is needed.
5. For 1ST/3RD running, enable one supported voxel provider; no separate
   running mod is required.
6. If an older save retained PACK as OFF, open **START > MOD MENUS > MOD
   SETTINGS > MENUS & DEVICE** and switch **PACK + POKéGEAR** ON. No imported
   file, Gold ROM, or app replacement is required.

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
[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) as the SDK. Run the
focused Loader and compatibility suites in `tests/` under both Lua 5.1 and
LuaJIT. The fused content bundle intentionally contains full encounter and art
registries that the modkit's synthetic `fixture` base cannot resolve, so its
strict validator/packer is not the release gate for this repository.

After tests pass, build the updater ZIP from the committed tree. The repository
attributes supply the exact release exclusions:

```powershell
git archive --format=zip --output=dist/voxel_run_bridge-0.12.8.zip v0.12.8
```

The archive keeps `manifest.json`, `main.lua`, `LICENSE`, notices, and the
`modules/` directory at its root. Gen1Recomp's importer mounts those paths
unchanged; development tests and unrelated workspace files are excluded.

Version 0.12.8 is configured for Gen1Recomp's built-in GitHub update checks via
`ScottExplores/gen1recomp-voxel-run-bridge`.

The download is deliberately named `voxel_run_bridge-0.12.8.zip` so the
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

PIXEL HILLS adapts the procedural layered-ridge basis from MIT-licensed Kanto
Dynamic Weather 1.0.3. Scott's version code-draws its own pixel-quantized
silhouettes and includes no upstream art, weather runtime, renderer patch, or
dependency. The attribution and MIT terms are preserved in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

The consolidated release also incorporates Scott-owned MIT modules from Trainer Forfeit
0.3.0, Oak's Spare Starter 0.1.1, Scott Mod, and Scott's Sprite Menu. Their
copyright notices and MIT terms are preserved in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). The physical-Thor presenter
is new public code; no source from the private/upstream-derived Dual Screen or
Battle Art packages is included.

The responsive Bag/PC presentation adapts MIT-licensed Modern Bag UI 0.4.1 by
ish hodaszi/piftee. Its exact upstream license and commit are preserved beside
the adapted source and in the notices file. The upstream reference-derived PNG
is not distributed; Scott's six-state five-compartment backpack and tiny blue
dither tile are newly generated project assets with their prompts and logical-
pixel production cleanup recorded beside the files.

No ROM, extracted graphics, save data, or other game content is included or
requested by Scott's Tweaks.
