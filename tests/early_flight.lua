-- Earned early flight: ROM-free predicate and production Free Fly menu tests.
-- luajit tests/early_flight.lua <mod-root> [<engine-root>]
local argv = rawget(_G, "arg") or {}
local root = argv[1] or "."
local checks = 0
local function eq(got, want, label)
  checks = checks + 1
  assert(got == want, ("%s: got %s, want %s"):format(
    label, tostring(got), tostring(want)))
end
local function read(path)
  local f = assert(io.open(path, "rb"), "cannot read " .. path)
  local body = f:read("*a"); f:close(); return body
end
local EarlyFlight = assert(loadfile(root .. "/vendor/free_fly/lib/EarlyFlight.lua"))()
local function fixture()
  local mon = { species = "PIDGEY", hp = 12, moves = { { id = "TACKLE", pp = 35 } }, level = 8 }
  local game = { save = { party = { mon }, inventory = { BOULDERBADGE = true }, flags = {} },
    data = { pokemon = { PIDGEY = { tmhm = { "FLY" } }, RATTATA = { tmhm = {} } } } }
  return game, mon
end
local game, mon = fixture()
eq(EarlyFlight.eligible(game, mon, true, 1), true,
  "earned Boulder Badge unlocks owned compatible non-knower")
eq(mon.moves[1].id, "TACKLE", "early rule does not teach FLY")
eq(#mon.moves, 1, "early rule never adds a move slot")
eq(game.save.inventory.HM02, nil, "early rule never grants HM02")
eq(game.save.inventory.THUNDERBADGE, nil, "early rule never grants Thunder Badge")
eq(game.save.inventory.BOULDERBADGE, true, "earned badge stays unchanged")
eq(next(game.save.flags), nil, "early rule never changes story flags")
eq(#game.save.party, 1, "early rule never gives a Pokemon")
eq(EarlyFlight.eligible(game, mon, false, 1), false, "disabled early option is classic")
eq(EarlyFlight.eligible(game, mon, nil, 1), false, "nil early option is not implicit permission")
eq(EarlyFlight.eligible(game, mon, true, 2), false, "Gen 2 never uses Kanto early rule")
eq(EarlyFlight.eligible(game, mon, true, 3), false, "Gen 3 never uses Kanto early rule")
eq(EarlyFlight.eligible(game, mon, true, nil), false, "unknown generation fails closed")
game.save.inventory.BOULDERBADGE = nil
eq(EarlyFlight.eligible(game, mon, true, 1), false, "no Boulder Badge means no early flight")
game.save.inventory.THUNDERBADGE = true
eq(EarlyFlight.eligible(game, mon, true, 1), false, "a different badge does not unlock early rule")
game, mon = fixture(); mon.species = "RATTATA"
eq(EarlyFlight.eligible(game, mon, true, 1), false, "incompatible Rattata cannot be an early mount")
game, mon = fixture(); mon.species = "UNKNOWN"
eq(EarlyFlight.eligible(game, mon, true, 1), false, "unknown species fails closed")
game, mon = fixture()
local copy = { species = "PIDGEY", hp = 12, moves = {} }
eq(EarlyFlight.eligible(game, copy, true, 1), false, "PC or preview copy is not the actual party partner")
game.save.party = {}
eq(EarlyFlight.eligible(game, mon, true, 1), false, "partner removed from party cannot mount")
for _, hp in ipairs({ 0, -1, 0 / 0, math.huge, -math.huge, "12" }) do
  game, mon = fixture(); mon.hp = hp
  eq(EarlyFlight.eligible(game, mon, true, 1), false, "fainted or invalid HP cannot unlock early flight: " .. tostring(hp))
end
game, mon = fixture(); mon.hp = nil
eq(EarlyFlight.eligible(game, mon, true, 1), false, "missing HP is not a healthy partner")
eq(EarlyFlight.eligible(nil, mon, true, 1), false, "missing game fails closed")
eq(EarlyFlight.eligible(game, nil, true, 1), false, "missing partner fails closed")

if not argv[2] then
  print(("PASS early_flight predicate (%d checks); pass engine-root for integration"):format(checks))
  return
end

local engine = argv[2]
package.path = engine .. "/?.lua;" .. engine .. "/?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local EngineGame = require("src.core.Game")
local GV = require("src.core.GameVersion")
GV.set("red")
local data = require("tests.modkit.fixtures").fresh()
data.pokemon.PIDGEY = data.pokemon.FIXMON_A
data.pokemon.PIDGEY.tmhm = { "FLY" }
data.pokemon.RATTATA = data.pokemon.FIXMON_B
data.pokemon.RATTATA.tmhm = {}
data.pokemon.PIDGEOT = data.pokemon.FIXMON_C
data.pokemon.PIDGEOT.tmhm = { "FLY" }
data.moves.FLY = data.moves.FIX_CUT
data.maps.PALLET_TOWN = data.maps.FIX_TOWN
data.field.badgeGates = { ROUTE_23 = { badge = "EARTHBADGE" } }
local files, prefix = {}, "mods/free_fly/"
for _, relative in ipairs({ "manifest.json", "main.lua", "lib/shared/skylib.lua",
    "lib/EarlyFlight.lua", "lib/FlightInput.lua", "lib/FollowerLanding.lua", "lib/VoxelProvider.lua" }) do
  files[prefix .. relative] = read(root .. "/vendor/free_fly/" .. relative)
end
local run = T.sdk.loadMod("mods/free_fly", { data = data, fs = T.sdk.memfs(files), generation = 1 })
eq(run.mod ~= nil, true, "actual Free Fly loaded through API-2 Loader")
eq(#run.errors, 0, "actual Free Fly Loader reports no errors")
local exports = run.loader.exports.free_fly
eq(type(exports.isFlying), "function", "actual Free Fly flight-state API exists")
local options = run.loader.modOptions.free_fly or {}
run.loader.modOptions.free_fly = options
options.scotts_early_fly, options.scotts_classic = true, false
options.badges, options.gates, options.quickstart = true, true, false

local player = { cellX = 2, cellY = 2, px = 32, py = 32,
  facing = "down", sprite = {}, stepFrames = 16 }
local ow = { isOverworld = true, player = player,
  entities = { player }, npcs = {},
  camera = { follow = function() end },
  map = { id = "ROUTE_1", widthCells = 8, heightCells = 8,
    def = { tileset = "OVERWORLD", outdoor = true },
    inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 8 and y < 8 end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
    warpAtCell = function() return nil end,
    cellTile = function() return 1 end } }
local states = { ow }
local pops = 0
local stack = { states = states, top = function() return states[#states] end,
  pop = function() pops = pops + 1; return table.remove(states) end }
local mount = { species = "PIDGEY", hp = 12, level = 8,
  moves = { { id = "TACKLE", pp = 35 } } }
EngineGame.overworld, EngineGame.stack, EngineGame.data = ow, stack, data
EngineGame.renderer = { worldViewSize = function() return 160, 144 end }
EngineGame.save = { party = { mount }, inventory = { BOULDERBADGE = true }, flags = {} }
EngineGame.input = { wasPressed = function() return false end, isDown = function() return false end }
-- A capability-shaped first-person provider tests the unchanged FreeMove
-- adapter without pretending to render a hardware/gameplay screenshot.
local Map = require("src.world.Map")
local firstPerson = { yaw = 0.25, driving = function() return true end }
local freeMoveCalls, sawPermissive = 0, false
local FreeMove = { tick = function()
  freeMoveCalls = freeMoveCalls + 1
  sawPermissive = Map.__freeFlyPermissive == true
end }
local providerLib = { require = function(name)
  if name == "FreeMove" then return FreeMove end
  if name == "FirstPerson" then return firstPerson end
  if name == "VoxelState" then return { isFirstPerson = function() return true end } end
end }
EngineGame.mods = { exports = { BATTLE_ART_VOXEL_FORK = { lib = providerLib } } }
Runtime.emit("game.ready", { game = EngineGame })
eq(#run.errors, 0, "actual Free Fly engine wiring reports no errors")
local OC = require("src.world.OverworldController")
eq(type(OC.__freeFlyCrossGate2), "function", "actual Free Fly story seam guard is installed")
eq(type(OC.__freeFlyTick), "function", "actual Free Fly flight tick is installed")
local flyDef = data.moves.FLY
local function menu(selected, context)
  local old = { { label = "STATS", action = "stats" }, { label = "FLY", action = "fly" } }
  local nativeFly = old[2]
  local out = Runtime.call("ui.party.submenu", function(_, rows) return rows end,
    EngineGame, old, selected or mount, context or { overworld = ow })
  local free, fly
  for _, row in ipairs(out) do
    if row.label == "FREEFLY" then free = row end
    if row.action == "fly" then fly = row end
  end
  eq(fly, nativeFly, "vanilla FLY row is not replaced")
  eq(data.moves.FLY, flyDef, "vanilla FLY move definition is unchanged")
  return free, out
end
eq(menu() ~= nil, true, "actual menu offers early flight after Brock")
EngineGame.save.inventory.BOULDERBADGE = nil
eq(menu(), nil, "actual menu hides early flight before Brock")
local originalMoves = mount.moves
mount.freeFlyGift = true
mount.moves = { { id = "FLY", pp = 15 } }
eq(menu(), nil, "earned early mode refuses old gift exemption before the first badge")
eq(mount.freeFlyGift, true, "refused old gift is not stripped of its saved marker")
mount.moves, mount.freeFlyGift = originalMoves, nil
eq(EngineGame.save.inventory.BOULDERBADGE, nil, "actual menu never manufactures Boulder Badge")
EngineGame.save.inventory.BOULDERBADGE = true
mount.hp = 0
eq(menu(), nil, "actual menu rejects fainted early mount")
mount.hp = 12
eq(menu({ species = "PIDGEY", hp = 12, moves = {} }), nil, "actual menu rejects preview outside party")
EngineGame.save.party = { { species = "RATTATA", hp = 10, moves = {} } }
eq(menu(EngineGame.save.party[1]), nil, "actual menu rejects non-flying partner")
EngineGame.save.party = { mount }
options.scotts_early_fly = false
eq(menu(), nil, "early rule disabled keeps normal FLY eligibility")
local otherFlyer = { species = "PIDGEOT", hp = 20, moves = { { id = "FLY", pp = 15 } } }
EngineGame.save.party[2] = otherFlyer
EngineGame.save.inventory.THUNDERBADGE = true
local removeEligibility = Runtime.hooks:wrap("fieldmove.eligibility", function(next, ...)
  return next(...)
end, 0, "early_flight_test")
ow.partyKnows = function() return otherFlyer end
eq(menu(), nil, "another partner's FLY eligibility never leaks to selected non-knower")
eq(menu(otherFlyer) ~= nil, true, "actual FLY-knowing partner remains eligible")
ow.partyKnows = function() return mount end
eq(menu() ~= nil, true, "explicit engine nomination still supports a field-rule mod")
removeEligibility(); ow.partyKnows = nil
EngineGame.save.party[2], EngineGame.save.inventory.THUNDERBADGE = nil, nil
options.scotts_early_fly = true; options.scotts_classic = true
eq(menu() ~= nil, true, "Classic battles can combine with explicitly enabled earned early travel")
options.scotts_early_fly = false
eq(menu(), nil, "Classic without optional early travel keeps ordinary FLY rules")
options.scotts_early_fly = true
options.scotts_classic = false
eq(menu(mount, { overworld = ow, battle = {} }), nil, "battle party menu never offers early flight")
ow.player.onBike = true
eq(menu(), nil, "biking prevents early takeoff")
ow.player.onBike = nil
ow.map.def = { tileset = "HOUSE" }
eq(menu(), nil, "indoor maps prevent early takeoff")
ow.map.def = { tileset = "OVERWORLD", outdoor = true }

local stale = assert(menu())
states[2] = { isMenu = true }
EngineGame.save.inventory.BOULDERBADGE = nil
stale.onSelect(mount, EngineGame)
eq(exports.isFlying(), false, "stale early option rechecks earned badge at takeoff")
eq(player.freeFlying, nil, "denied stale takeoff never changes player flight state")
eq(pops, 0, "denied stale takeoff leaves party menus open")
eq(states[2].isMenu, true, "denied stale takeoff preserves current screen")
EngineGame.save.inventory.BOULDERBADGE = true
local function staleDenied(label, mutate, restore)
  local choice = assert(menu())
  mutate()
  choice.onSelect(mount, EngineGame)
  eq(exports.isFlying(), false, label .. " is revalidated at takeoff")
  eq(pops, 0, label .. " never unwinds the menu stack")
  restore()
end
staleDenied("party removal", function() EngineGame.save.party = {} end,
  function() EngineGame.save.party = { mount } end)
staleDenied("newly fainted mount", function() mount.hp = 0 end,
  function() mount.hp = 12 end)
staleDenied("changed early-flight option", function() options.scotts_early_fly = false end,
  function() options.scotts_early_fly = true end)
staleDenied("changed indoor map", function() ow.map.def = { tileset = "HOUSE" } end,
  function() ow.map.def = { tileset = "OVERWORLD", outdoor = true } end)
staleDenied("new bike state", function() player.onBike = true end,
  function() player.onBike = nil end)
staleDenied("new battle screen", function() states[3] = { isBattleScreen = true } end,
  function() states[3] = nil end)
states[2] = nil
local permitted = assert(menu())
permitted.onSelect(mount, EngineGame)
eq(exports.isFlying(), true, "actual menu starts flight with legitimately caught early partner")
eq(player.freeFlying, true, "actual takeoff marks only transient flight state")
eq(mount.moves[1].id, "TACKLE", "actual takeoff still never teaches FLY")
eq(#mount.moves, 1, "actual takeoff leaves move slots unchanged")
eq(EngineGame.save.inventory.THUNDERBADGE, nil, "actual takeoff never gives Thunder Badge")
eq(EngineGame.save.inventory.HM02, nil, "actual takeoff never gives HM02")
eq(next(EngineGame.save.flags), nil, "actual takeoff never rewrites story flags")
eq(#EngineGame.save.party, 1, "actual takeoff never gifts a partner")
FreeMove.tick(ow)
eq(freeMoveCalls, 1, "existing first-person free movement still receives flight tick")
eq(sawPermissive, true, "existing first-person adapter opens its scoped flight window")
eq(Map.__freeFlyPermissive, false, "first-person flight collision window always closes afterward")
eq(firstPerson.driving(), true, "early flight never forces a camera mode change")
eq(firstPerson.yaw, 0.25, "early flight never resets first-person look direction")
eq(options.badges, true, "early takeoff leaves water-landing badge checks enabled")
eq(options.gates, true, "early takeoff leaves story gates enabled")
eq(OC.__freeFlyCrossGate2(ow, "up", "ROUTE_23"), true,
  "early flight still refuses a genuinely unearned story gate")
eq(OC.__freeFlyCrossGate2(ow, "up", "ROUTE_2"), false,
  "early flight can cross ordinary open route seams")
eq(EngineGame.save.inventory.EARTHBADGE, nil, "refused story seam never grants gate badge")
ow.map.isWalkableCell = function() return false end
ow.map.isWaterCell = function() return true end
-- Holding a steering direction suppresses the optional cosmetic rise glide;
-- the actual fixed flight tick still runs its real water-landing predicate.
EngineGame.input.isDown = function(_, key) return key == "up" end
for _ = 1, 90 do OC.__freeFlyTick(ow, 1 / 60) end
eq(player.freeFlyCanLand, false, "early flyer cannot land in water without SURF")
EngineGame.save.party[2] = { species = "RATTATA", hp = 12, moves = { { id = "SURF", pp = 15 } } }
OC.__freeFlyTick(ow, 1 / 60)
eq(player.freeFlyCanLand, false, "SURF alone does not bypass earned Soul Badge for water landing")
EngineGame.save.inventory.SOULBADGE = true
OC.__freeFlyTick(ow, 1 / 60)
eq(player.freeFlyCanLand, true, "genuine SURF and Soul Badge permit water landing normally")
ow.map.isWalkableCell = function() return true end
ow.map.isWaterCell = function() return false end
EngineGame.input.isDown = function() return false end
Runtime.emit("save.loaded", {})
eq(exports.isFlying(), false, "save reload clears transient flight")

-- Classic also refuses old gift/badge bypass settings, but accepts an earned
-- vanilla FLY user with the genuine Thunder Badge.
options.scotts_classic = true; options.scotts_early_fly = false; options.badges = false
mount.freeFlyGift = true
eq(menu(), nil, "Classic ignores legacy gift marker without FLY")
mount.moves = { { id = "FLY", pp = 15 } }
eq(menu(), nil, "Classic ignores badge bypass without Thunder Badge")
EngineGame.save.inventory.THUNDERBADGE = true
eq(menu() ~= nil, true, "Classic allows ordinary earned vanilla flight")

-- A gift NPC left in Pallet must not grant a Pokemon after switching to an
-- earned-only exploration rule. Exercise the actual registered command and
-- script, including the asynchronous-choice recheck, through ScriptRunner.
local Commands = require("src.script.Commands")
local ScriptRunner = require("src.script.ScriptRunner")
local giftEnabled = assert(Commands.resolve(data, "free_fly:gift_enabled"))
local giftContext = { game = EngineGame, save = EngineGame.save }
options.quickstart = false
giftEnabled(giftContext)
eq(giftContext.lastCheck, false, "actual gift predicate refuses a disabled gift")
options.quickstart = true
giftEnabled(giftContext)
eq(giftContext.lastCheck, true, "actual gift predicate preserves custom quick start")
local giftRows
for _, entry in ipairs(data.map_scripts.PALLET_TOWN or {}) do
  local value = entry.value or entry
  if value.talk and value.talk.TEXT_FREE_FLY_PIDGEY then
    giftRows = value.talk.TEXT_FREE_FLY_PIDGEY
    break
  end
end
eq(type(giftRows), "table", "actual Pallet gift talk script is registered")
local giftGuardCount = 0
for _, row in ipairs(giftRows) do
  if row[1] == "free_fly:gift_enabled" then giftGuardCount = giftGuardCount + 1 end
end
eq(giftGuardCount, 2, "gift script guards both initial contact and accepted choice")
local seenGiftText, choiceCalls, grantCalls, flagCalls, teachCalls = 0, 0, 0, 0, 0
local disableAtChoice = false
local removeGiftTestHook = Runtime.hooks:wrap("script.command", function(nextFn, ctx, name, args)
  if name == "show_text" then seenGiftText = seenGiftText + 1 return end
  if name == "choice" then
    choiceCalls = choiceCalls + 1
    ctx.lastCheck = true
    if disableAtChoice then options.quickstart = false end
    return
  end
  if name == "give_pokemon" then grantCalls = grantCalls + 1 return end
  if name == "set_flag" then flagCalls = flagCalls + 1 return end
  if name == "free_fly:teach_fly" then teachCalls = teachCalls + 1 return end
  return nextFn(ctx, name, args)
end, -10000, "gift_guard_regression")
options.quickstart = false
local disabledRunner = ScriptRunner.new(EngineGame, ow)
disabledRunner:run(giftRows)
eq(disabledRunner:isRunning(), false, "disabled gift script ends immediately")
eq(seenGiftText, 0, "disabled gift script never opens its gift dialogue")
eq(choiceCalls, 0, "disabled gift script never offers a claim choice")
eq(grantCalls, 0, "disabled gift script cannot give a Pokemon")
options.quickstart = true; disableAtChoice = true
local staleGiftRunner = ScriptRunner.new(EngineGame, ow)
staleGiftRunner:run(giftRows)
eq(staleGiftRunner:isRunning(), false, "stale accepted gift script safely ends")
eq(choiceCalls, 1, "enabled gift reaches its actual claim choice")
eq(grantCalls, 0, "disabling at accepted choice prevents a new Pokemon")
eq(flagCalls, 0, "disabling at accepted choice leaves claim flags untouched")
eq(teachCalls, 0, "disabling at accepted choice cannot teach FLY")
options.quickstart = true; disableAtChoice = false
local customGiftRunner = ScriptRunner.new(EngineGame, ow)
customGiftRunner:run(giftRows)
eq(customGiftRunner:isRunning(), false, "enabled custom gift script still completes")
eq(grantCalls, 1, "enabled custom gift script still reaches its original grant")
eq(flagCalls, 1, "enabled custom gift script still reaches its original claim flag")
eq(teachCalls, 1, "enabled custom gift script still reaches its original move teaching")
removeGiftTestHook()

-- Use the production WorldAPI facade, with the same runtime-object seam an
-- overworld implements. Both a standalone quickstart edit and the hosted
-- Scott early-flight event must remove an already-existing gift immediately.
local priorMapId, priorObjects = ow.map.id, data.maps.PALLET_TOWN.objects
ow.map.id = "PALLET_TOWN"
local removedGiftIds = {}
function ow:removeRuntimeObject(id)
  removedGiftIds[#removedGiftIds + 1] = id
  data.maps.PALLET_TOWN.objects = {}
  return true
end
data.maps.PALLET_TOWN.objects = {
  { runtime = true, name = "FREE_FLY_PIDGEY", index = 77 },
}
options.quickstart = false
Runtime.emit("mod.options_changed", { mod = "free_fly", key = "quickstart", value = false })
eq(removedGiftIds[1], "PALLET_TOWN_obj_77", "live quickstart edit despawns the existing gift")
eq(#data.maps.PALLET_TOWN.objects, 0, "live quickstart edit removes persistent runtime object")
local giftMod
for index = 1, 20 do
  local name, value = debug.getupvalue(giftEnabled, index)
  if not name then break end
  if name == "mod" then giftMod = value break end
end
eq(type(giftMod), "table", "actual registered command retains its production mod facade")
local priorHosted = giftMod.options.hosted
giftMod.options.hosted = { hostId = "voxel_run_bridge", vendorId = "free_fly", prefix = "free_fly:" }
data.maps.PALLET_TOWN.objects = {
  { runtime = true, name = "FREE_FLY_PIDGEY", index = 78 },
}
Runtime.emit("mod.options_changed", { mod = "voxel_run_bridge", key = "early_flight", value = true })
eq(removedGiftIds[2], "PALLET_TOWN_obj_78", "hosted early-flight event despawns the existing gift")
eq(#data.maps.PALLET_TOWN.objects, 0, "hosted early-flight event removes its persistent runtime object")
giftMod.options.hosted = priorHosted
ow.map.id, data.maps.PALLET_TOWN.objects = priorMapId, priorObjects
ow.removeRuntimeObject = nil

run.release()
print(("PASS early_flight (%d checks including production-loader menu integration)"):format(checks))
