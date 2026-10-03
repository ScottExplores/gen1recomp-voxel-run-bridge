# Scott's Tweaks nostalgia/movement review - 2026-10-03

## Scope

0.14.0 source on `codex/nostalgia-movement-polish`, based on public 0.13.1
(f485da99). Scott authorized publishing through the existing updater so he can
do live testing. This is not a controller/GPU-tested release. No live install
replacement, save conversion, Drive upload or ROM distribution is part of this
work. The unspecified "something like this" example was not attached, so no
unconfirmed visual/feature was invented.

Classic Rules defaults OFF. Custom trainer/boss/wild difficulty, trainer team
modes, visible/classic encounter modes, spawn amount, followers and all other
existing controls remain. The profile only changes effective rules when
explicitly enabled; it never resets their saved values. Turning it OFF and
fully restarting restores those preferences. Both the Classic profile and
Custom controls are tested through the real Loader/menu implementation.

Classic Rules protects the bundled game's battle/encounter/progression rules,
not a byte-identical cartridge experience: 3D presentation, running and optional
two-way ledge hops remain. Earned early flight is an explicitly selected travel
exception, not a vanilla mechanic or a claim that every story barrier is
impossible to bypass. Free Fly's native story gates are badge-map gates, not a
complete model of every Kanto quest, cave, NPC or sequence dependency. For a
strict first playthrough, leave early flight OFF and use native ledge direction.

Changing Classic Rules requires fully closing and reopening the application,
not developer F5: content registrations cannot safely be removed mid-session.
Previously acquired Pokemon, moves, items, evolution choices and story flags
are preserved. Separately installed gameplay mods remain authoritative; disable
them when you want the bundled classic profile.

## Findings addressed

- Manual jump accepted locked/airborne state, invalid facing and an occupied
  crossed ledge. The new checks also cover foreground scripts, battles,
  transitions, bikes/surf, destination tile pairs and real collision hooks.
- Free Fly's eligibility accepted any compatible partner when *another*
  partner was nominated by the engine's field-move chain. It now requires the
  selected partner; stale menu choices revalidate before unwinding menus.
- Changing to earned early flight while already in Pallet previously left
  the gift NPC available. Gift options now refresh those NPCs live, and gift
  conversations recheck the rule before granting anything, including after
  an asynchronous choice.
- Classic badge checks alone did not neutralize an old `freeFlyGift` exemption.
  Classic mode ignores the exemption without deleting the marker or partner.
- Several stored vendor values bypassed ordinary option getters. Classic
  overrides now reach explicit random-encounter reads and cached difficulty
  state, while leaving saved preferences intact.
- Gen 1's stored early-flight preference is ignored on the Gen 2 branch,
  where it has no visible control. Custom Johto gift/badge/gate choices are
  preserved instead of being silently masked by an unrelated Kanto setting.
- Legacy option imports marked completion despite persistence failures. Failed
  writes now restore save/live buckets and marker/list identities and retry.

One remaining presentation issue: the current engine's native mart greeting
opens a delayed, titleless dialogue list. Ordinary buying and Trade Stone
stock injection still work, but Scott's older `BUY BAG:n` count enhancement
does not attach. This is also present on baseline 0.13.1. The updated smoke
test follows the real clerk callback and explicitly records the missing
enhancement; it does not pretend that feature was fixed. Keep the native
cartridge layout until a separate count/readability design is play-tested.

## Verification

ROM-free checks use LuaJIT and a fresh official Gen1Recomp checkout, commit
`340e2567ec93d8ac74659d7091ebbec8925d7295`. They exercise production API-2
Loader/content/hooks plus synthetic maps and save fixtures. They do not
establish a rendered GPU frame, controller feel, a complete Red playthrough,
or physical Thor behavior. See tests/README.md for focused commands.

Selected checks passed on both the current official checkout and v0.1.96:
full-load 198 each, fused-load 857 each, and the earned-flight integration.
The final broader pass ran 26 suite/configuration combinations with 5,251
reported checks, plus two passing ledge suites. The final cross-generation
fix adds Gold/Silver/Crystal 60-check loader scenarios and a 126-check vendor
facade pass. Custom-mode integration now
covers all trainer/boss/wild difficulty tiers, independent live updates,
trainer-team randomizers, encounter modes and restored spawn preferences.
These are assertions across fixtures/configurations, not playthroughs.

## Distribution audit and release method

The official modkit still reports the same pre-existing 18 MK301 findings and
2 MK305 warnings as 0.13.1. They have not been suppressed or renamed away, and
we do not claim that linter passed. Inspection distinguishes their causes:

- Seventeen MK301 paths are mod-local Wilds generated art, metadata or comments.
  `VendorHost` re-roots those reads under this mod's vendor directory;
  the engine's asset facade uses `SafePath.join(mod.path, relative)`. They
  are not the engine's root ROM-derived cache, despite matching its substring.
- Crystal's remaining MK301 reads the player's locally imported battle-ball
  sheet at runtime and mentions the native fishing rod in a comment. The
  player's cache files are not in this repository or updater artifact.
- The two MK305 warnings are basename matches on authored follower constants
  and encounter-normalization code, not imported dataset files. No ROM dataset
  was supplied to this ROM-free test environment for the heuristic comparison.

The established README release process uses `git archive` from the committed
tree with export exclusions, rather than the synthetic strict fixture packer.
No binary assets changed in 0.14.0. `tools/check_release.ps1` checks the actual
ZIP's flat updater layout and manifest identity/version, exact-case runtime
sentinels, attribution notices, and exclusions for ROMs, patches, saves,
root-generated cache, nested archives and development material. Baseline
0.13.1 was also checked for ROM header signatures and bank-sized binary blobs;
none were found. This is an archive/provenance audit, not a legal opinion or
a claim that every historic third-party image was independently authored.

## Next recommendations

1. Play Red from Pallet through Brock, Mt Moon, Cerulean and Vermilion in first
   person, with save/load and menu interruptions around jumps and takeoff.
2. Keep arbitrary wall hopping out: authored low ledges are a bounded target;
   universal wall traversal can skip story triggers and strand the player.
3. Keep archive hygiene and provenance checks in the release process. A future
   adapter can move Crystal's runtime cache read to the official transform API;
   do not remove working custom assets simply to evade a substring heuristic.
4. Prefer movement comfort/readability over further mechanics: gentle bob,
   clear collision feedback, original music/art palettes and opt-in features.
