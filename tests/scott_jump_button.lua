-- ROM-free contract for the manual jump button and bounded ledge hops.
-- Run from the mod root: luajit tests/scott_jump_button.lua
local checks = 0
local function eq(got, want, message)
  checks = checks + 1
  assert(got == want, ("%s: got %s, want %s"):format(
    message, tostring(got), tostring(want)))
end

local collisionResponder, collisionCalls, runtimeMissing
local Runtime = {}
function Runtime.wantsHook(name)
  eq(name, "movement.collision", "only the supported collision hook is queried")
  return collisionResponder ~= nil
end
function Runtime.call(name, next, allowed, ctx)
  eq(name, "movement.collision", "correct collision middleware name")
  collisionCalls[#collisionCalls + 1] = ctx
  return collisionResponder(next, allowed, ctx)
end
package.preload["src.mods.Runtime"] = function()
  if runtimeMissing then error("missing engine compatibility") end
  return Runtime
end

local install = assert(loadfile("lib/ScottJumpButton.lua"))()
local function fixture(options)
  options = options or {}
  collisionResponder, collisionCalls, runtimeMissing = nil, {}, false
  package.loaded["src.mods.Runtime"] = nil
  local keyboard, pad, back = {}, {}, false
  local player = { cellX = 3, cellY = 3, facing = "down", px = 48, py = 48 }
  local tiles = { ["3:4"] = 2 }
  local walkable, bounds = true, true
  local map = { id = "ROUTE_1", def = { tileset = "OVERWORLD" } }
  function map:inBounds(x, y)
    return bounds and x >= 0 and x <= 7 and y >= 0 and y <= 7
  end
  function map:cellTile(x, y) return tiles[x .. ":" .. y] or 1 end
  function map:isWalkableCell(x, y)
    return walkable and self:cellTile(x, y) ~= 2
  end
  local ow = { map = map, player = player, entities = { player },
    runner = { isRunning = function() return false end } }
  local game = { overworld = ow, save = { inventory = {}, flags = {}, party = {} },
    data = { field = { ledges = { { tileset = "OVERWORLD", ledgeTile = 2 } },
      tilePairs = { land = {} } } } }
  local top = ow
  game.stack = { top = function() return top end }
  local callbacks, commands, scripts, hook = {}, {}, {}, nil
  local mod = {
    options = { get = function(_, key) return options[key] end },
    commands = { register = function(_, name, fn) commands[name] = fn end },
    events = { on = function(_, name, fn) callbacks[name] = fn end },
    hooks = { wrap = function(_, name, fn)
      eq(name, "input.step", "jump uses the fixed input seam")
      hook = fn
    end },
    world = { queueScript = function(_, rows)
      scripts[#scripts + 1] = rows
      return true
    end },
  }
  love = {
    keyboard = { isDown = function(key) return keyboard[key] == true end },
    joystick = { getJoysticks = function()
      return { {
        isGamepad = function() return true end,
        isGamepadDown = function(_, key)
          if key == "back" then return back end
          return pad[key] == true
        end,
      } }
    end },
  }
  install(mod)
  local nextCalls = 0
  local function tick()
    return hook(function(g, dt)
      nextCalls = nextCalls + 1
      eq(g, game, "game forwarded to input chain")
      eq(dt, 1 / 60, "fixed dt forwarded to input chain")
      return "input-result", 42, false
    end, game, 1 / 60)
  end
  return { game = game, ow = ow, player = player, map = map, tiles = tiles,
    scripts = scripts, mod = mod, keyboard = keyboard, pad = pad,
    press = function() keyboard.space = true; return tick() end,
    release = function() keyboard.space = false; pad.y = false; return tick() end,
    tick = tick, emit = function(name, payload) callbacks[name](payload) end,
    setTop = function(value) top = value end,
    setWalkable = function(value) walkable = value end,
    setBounds = function(value) bounds = value end,
    setBack = function(value) back = value end,
    arc = function() commands.scott_ledge_leap_arc({ overworld = ow }) end,
    nextCalls = function() return nextCalls end }
end

local good = fixture()
local a, b, c = good.press()
eq(a, "input-result", "input first return preserved")
eq(b, 42, "input second return preserved")
eq(c, false, "input false return preserved")
eq(good.nextCalls(), 1, "input next called exactly once")
eq(#good.scripts, 1, "authored ledge can be hopped")
eq(good.scripts[1][1][1], "scott_ledge_leap_arc", "native arc command queued")
eq(good.scripts[1][2][1], "play_sound", "native sound command queued")
eq(good.scripts[1][3][1], "move_player", "native movement command queued")
eq(good.scripts[1][3][2], "down", "hop keeps facing")
eq(good.scripts[1][3][3], 2, "hop is bounded to two grid cells")
eq(good.player.cellX, 3, "jump does not teleport cell X")
eq(good.player.cellY, 3, "jump does not teleport cell Y")
eq(good.player.px, 48, "jump does not teleport pixels")
eq(next(good.game.save.inventory), nil, "jump grants no items or badges")
eq(next(good.game.save.flags), nil, "jump changes no story flags")
eq(#good.game.save.party, 0, "jump grants no Pokemon")
good.tick()
eq(#good.scripts, 1, "holding a key does not repeatedly queue hops")
good.release(); good.press()
eq(#good.scripts, 2, "a new key edge can hop again")
good.arc()
eq(good.player.hopFrames, 32, "two-cell hop uses native arc timer")
eq(good.player.hopTotal, 32, "native arc total matches timer")

for direction, offset in pairs({ up = { 0, -1 }, down = { 0, 1 },
    left = { -1, 0 }, right = { 1, 0 } }) do
  local f = fixture()
  f.player.facing = direction
  f.tiles["3:4"] = nil
  f.tiles[(3 + offset[1]) .. ":" .. (3 + offset[2])] = 2
  f.press()
  eq(#f.scripts, 1, "ledge hop works facing " .. direction)
  eq(f.scripts[1][3][2], direction, "queued direction matches " .. direction)
end

local disabled = fixture({ ledge_hops = false })
disabled.press()
eq(#disabled.scripts, 0, "LEDGE HOPS OFF never moves across a ledge")
eq(disabled.player.hopFrames, 16, "LEDGE HOPS OFF retains in-place cosmetic hop")
local wall = fixture()
wall.tiles["3:4"] = 99
wall.press()
eq(#wall.scripts, 0, "general walls never qualify as ledges")
eq(wall.player.hopFrames, 16, "facing a general wall only bounces in place")

local function noJump(label, mutate)
  local f = fixture()
  mutate(f)
  f.press()
  eq(#f.scripts, 0, label .. " blocks movement")
  eq(f.player.hopFrames, nil, label .. " blocks the cosmetic arc too")
end
for _, key in ipairs({ "moving", "inputLocked", "freeFlying", "surfing", "onBike" }) do
  noJump("player " .. key, function(f) f.player[key] = true end)
end
for _, key in ipairs({ "transitioning", "engaging", "emote", "teleportOut",
    "flyAnim", "flyArrive" }) do
  noJump("world " .. key, function(f) f.ow[key] = true end)
end
noJump("saved bike state", function(f) f.game.save.onBike = true end)
local active = fixture()
active.player.hopFrames = 1
active.press()
eq(#active.scripts, 0, "existing hop never queues another movement")
eq(active.player.hopFrames, 1, "existing hop timer stays untouched")
noJump("menu stack", function(f) f.setTop({ isMenu = true }) end)
noJump("battle event", function(f) f.emit("battle.started") end)
noJump("script event", function(f) f.emit("script.started") end)
noJump("runner already active before mod load", function(f)
  f.ow.runner.isRunning = function() return true end
end)
noJump("pending cutscene", function(f) f.ow.pendingScripts = { {} } end)
noJump("scripted movement", function(f) f.ow.scriptMoves = { {} } end)
noJump("nil facing", function(f) f.player.facing = nil end)
noJump("unknown facing", function(f) f.player.facing = "diagonal" end)
noJump("missing map", function(f) f.ow.map = nil end)
noJump("unsupported map API", function(f) f.map.cellTile = false end)
noJump("missing player", function(f) f.ow.player = nil end)
noJump("fractional logical cell", function(f) f.player.cellX = 3.5 end)
noJump("NaN logical cell", function(f) f.player.cellY = 0 / 0 end)
noJump("out-of-bounds logical cell", function(f) f.player.cellY = 8 end)
noJump("missing input stack", function(f) f.game.stack = nil end)
noJump("NPC on crossed ledge", function(f)
  f.ow.entities[2] = { cellX = 3, cellY = 4 }
end)
noJump("NPC targeting crossed ledge", function(f)
  f.ow.entities[2] = { cellX = 2, cellY = 4, targetX = 3, targetY = 4 }
end)

local function noTraversal(label, mutate)
  local f = fixture()
  mutate(f)
  f.press()
  eq(#f.scripts, 0, label .. " never queues traversal")
  eq(f.player.hopFrames, 16, label .. " safely falls back to cosmetic hop")
end
noTraversal("blocked landing tile", function(f) f.setWalkable(false) end)
noTraversal("out-of-bounds landing", function(f) f.player.cellY = 6; f.tiles["3:7"] = 2 end)
noTraversal("occupied landing", function(f)
  f.ow.entities[2] = { cellX = 3, cellY = 5 }
end)
noTraversal("reserved landing", function(f)
  f.ow.entities[2] = { cellX = 2, cellY = 5, targetX = 3, targetY = 5 }
end)
noTraversal("elevation tile pair", function(f)
  f.tiles["3:5"] = 3
  f.game.data.field.tilePairs.land = { { tileset = "OVERWORLD", a = 1, b = 3 } }
end)
noTraversal("reverse elevation tile pair", function(f)
  f.tiles["3:5"] = 3
  f.game.data.field.tilePairs.land = { { tileset = "OVERWORLD", a = 3, b = 1 } }
end)
noTraversal("missing script facade", function(f) f.mod.world = nil end)
noTraversal("missing engine collision contract", function() runtimeMissing = true end)
noTraversal("collision hook refuses crossed cell", function()
  collisionResponder = function(_, _, ctx) return ctx.toY ~= 4 end
end)
noTraversal("collision hook refuses landing", function()
  collisionResponder = function(_, _, ctx) return ctx.toY ~= 5 end
end)
noTraversal("broken collision hook", function()
  collisionResponder = function() error("another mod failed") end
end)
noTraversal("non-boolean collision approval", function()
  collisionResponder = function() return "truthy-but-not-approved" end
end)

local hooked = fixture()
collisionResponder = function(next, allowed, ctx)
  eq(ctx.mover, hooked.player, "collision receives actual player identity")
  eq(ctx.map, hooked.map, "collision receives actual map identity")
  eq(ctx.dir, "down", "collision receives hop direction")
  eq(ctx.reason, nil, "known ledge corridor has no collision refusal reason")
  eq(hooked.player.cellY, 3, "collision probing never mutates logical cell")
  return next(allowed)
end
hooked.press()
eq(#hooked.scripts, 1, "compatible collision hooks allow a bounded hop")
eq(#collisionCalls, 2, "both legs query the collision hook")
eq(collisionCalls[1].fromY, 3, "first leg begins at player cell")
eq(collisionCalls[1].toY, 4, "first leg crosses authored ledge")
eq(collisionCalls[2].fromY, 4, "second leg begins at ledge")
eq(collisionCalls[2].toY, 5, "second leg ends at validated landing")

local permissive = fixture()
permissive.setWalkable(false)
collisionResponder = function() return true end
permissive.press()
eq(#permissive.scripts, 0, "permissive hook cannot bypass a blocked landing")
eq(#collisionCalls, 0, "hard landing guards run before permissive hooks")

local follower = fixture()
follower.ow.entities[2] = { cellX = 3, cellY = 4, passable = true }
follower.ow.entities[3] = { cellX = 3, cellY = 5, passable = true }
follower.press()
eq(#follower.scripts, 1, "passable followers do not block ledge corridor")

local nested = fixture()
nested.emit("script.started"); nested.emit("script.started")
nested.emit("script.ended"); nested.press()
eq(#nested.scripts, 0, "ending one nested script does not clear remaining lock")
nested.release(); nested.emit("script.ended"); nested.press()
eq(#nested.scripts, 1, "final script end restores normal jumping")
local parallel = fixture()
parallel.emit("script.started", { ctx = { runner = { parallel = true } } })
parallel.press()
eq(#parallel.scripts, 1, "ambient parallel scripts do not steal jump input")
local reset = fixture()
reset.emit("script.started"); reset.emit("battle.started")
reset.emit("save.loaded"); reset.press()
eq(#reset.scripts, 1, "new save clears stale script and battle event locks")
local battleEnd = fixture()
battleEnd.emit("battle.started"); battleEnd.emit("battle.ended")
battleEnd.press()
eq(#battleEnd.scripts, 1, "battle end returns normal jump control")

local gamepad = fixture()
gamepad.pad.y = true; gamepad.tick()
eq(#gamepad.scripts, 1, "Y button hops a ledge")
gamepad.tick()
eq(#gamepad.scripts, 1, "held Y button has one edge")
local chord = fixture()
chord.pad.y = true; chord.setBack(true); chord.tick()
eq(#chord.scripts, 0, "Select+Y belongs to display control")
eq(chord.player.hopFrames, nil, "display chord does not bounce player")
local both = fixture()
both.keyboard.space, both.pad.y = true, true; both.tick()
eq(#both.scripts, 1, "keyboard and pad on same tick queue one hop")
local off = fixture({ jumpkey = "off", jumppad = "off" })
off.keyboard.space, off.pad.y = true, true; off.tick()
eq(#off.scripts, 0, "OFF bindings disable manual jump input")
local invalidBinding = fixture({ jumpkey = "invalid", jumppad = {} })
invalidBinding.press()
eq(#invalidBinding.scripts, 0, "invalid stored bindings safely disable input")
local custom = fixture({ jumpkey = "j", jumppad = "x" })
custom.keyboard.j = true; custom.tick()
eq(#custom.scripts, 1, "supported custom keyboard binding works")
local menuHeld = fixture()
menuHeld.setTop({ isMenu = true }); menuHeld.press()
menuHeld.setTop(menuHeld.ow); menuHeld.tick()
eq(#menuHeld.scripts, 0, "held menu key is not replayed when menu closes")
menuHeld.release(); menuHeld.press()
eq(#menuHeld.scripts, 1, "fresh press after closing menu works")

print(("PASS scott_jump_button (%d checks)"):format(checks))
