-- Focused, ROM-free checks for Scott's code-drawn battle-entry transition.
-- Run with:
--   lua tests/battle_entry_wipe.lua <mod-root>

local argv = rawget(_G, "arg") or {}
local sourceRoot = assert(argv[1], "Scott's Tweaks root required")
local unpackValues = table.unpack or unpack

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, ("not ok %d - %s"):format(checks, message))
end
local function eq(actual, expected, message)
  checks = checks + 1
  assert(actual == expected,
    ("not ok %d - %s (expected %s, got %s)"):format(
      checks, message, tostring(expected), tostring(actual)))
end

local graphics = { calls = {}, color = { 1, 1, 1, 1 } }
function graphics.setColor(r, g, b, a)
  graphics.color = { r, g, b, a }
end
function graphics.rectangle(mode, x, y, w, h)
  graphics.calls[#graphics.calls + 1] = {
    mode = mode, x = x, y = y, w = w, h = h,
    color = { unpackValues(graphics.color) },
  }
end
function graphics.getDimensions() return 400, 360 end
function graphics.getColor()
  return unpackValues(graphics.color)
end
_G.love = { graphics = graphics }

local Renderer = {}
Renderer.__index = Renderer
function Renderer:endFrame()
  self.baseCalls = (self.baseCalls or 0) + 1
  return "viewport", nil, "tail"
end
package.loaded["src.render.Renderer"] = nil
package.preload["src.render.Renderer"] = function() return Renderer end

local Wipe = assert(loadfile(sourceRoot .. "/lib/BattleEntryWipe.lua"))({})

local wild = Wipe.layout(0.5, 160, 144, false)
eq(#wild, 3, "wild wipe has exactly three horizontal bands")
eq(wild[1].direction, "left", "wild top leader moves left")
eq(wild[2].direction, "right", "wild middle leader moves right")
eq(wild[3].direction, "left", "wild bottom leader moves left")
eq(wild[1].y, 0, "top band starts at the top edge")
eq(wild[1].height, 48, "top band is one third of the Gen-1 frame")
eq(wild[2].y, 48, "middle band follows without a seam")
eq(wild[3].y + wild[3].height, 144,
  "bottom band reaches the final screen row")
check(wild[1].blackWidth > 0 and wild[1].blackWidth < 160,
  "halfway wild band has a moving black shutter")

local trainer = Wipe.layout(0.5, 160, 144, true)
eq(trainer[1].direction, "right", "trainer top reverses the wild rhythm")
eq(trainer[2].direction, "left", "trainer middle reverses direction")
eq(trainer[3].direction, "right", "trainer bottom reverses direction")

local complete = Wipe.layout(1, 160, 144, false)
for i, band in ipairs(complete) do
  eq(band.blackX, 0, "complete band starts at the left edge " .. i)
  eq(band.blackWidth, 160, "complete band covers the full width " .. i)
  eq(band.leader, nil, "complete band retires its leader " .. i)
end

graphics.calls = {}
check(Wipe.drawSurface(graphics, 1, 160, 144, false),
  "completed wipe draws safely throughout the native black hold")
eq(#graphics.calls, 3,
  "completed wipe draws only its three full-width black bands")
for i, call in ipairs(graphics.calls) do
  eq(call.x, 0, "completed hold band has a numeric left edge " .. i)
  eq(call.w, 160, "completed hold band remains full-width " .. i)
end

graphics.calls = {}
graphics.setColor(0.2, 0.3, 0.4, 0.5)
check(Wipe.drawSurface(graphics, 0.5, 160, 144, false),
  "logical-canvas fallback draws successfully")
local sawRed, sawWhite, sawBlack = false, false, false
for _, call in ipairs(graphics.calls) do
  local c = call.color
  sawBlack = sawBlack or (c[1] == 0 and c[2] == 0 and c[3] == 0)
  sawRed = sawRed or (c[1] == 0.86 and c[2] == 0.12)
  sawWhite = sawWhite or (c[1] == 1 and c[2] == 0.98)
  eq(call.mode, "fill", "wipe is built only from filled pixel rectangles")
end
check(sawBlack and sawRed and sawWhite,
  "code-drawn leaders contain black, red and warm-white pixels")
eq(graphics.color[1], 0.2, "wipe restores incoming red graphics colour")
eq(graphics.color[2], 0.3, "wipe restores incoming green graphics colour")
eq(graphics.color[3], 0.4, "wipe restores incoming blue graphics colour")
eq(graphics.color[4], 0.5, "wipe restores incoming graphics alpha")

local registered, hook
local mod = {
  id = "voxel_run_bridge",
  content = { transitions = {
    register = function(_, id, def)
      registered = registered or {}
      registered[id] = def
    end,
  } },
  hooks = {
    wrap = function(_, name, fn)
      eq(name, "transition.style", "installer uses the public style seam")
      hook = fn
    end,
  },
}
local status = Wipe.install(mod)
eq(status.active, true, "transition installs when both public APIs exist")
eq(status.reason, "pixel_ball_bands", "transition reports its visual style")
eq(status.renderer, "screen_space", "renderer seam extends it to the primary")
eq(registered[Wipe.WILD_ID].frames, Wipe.FRAMES,
  "wild transition registers its bounded frame budget")
eq(registered[Wipe.TRAINER_ID].frames, Wipe.FRAMES,
  "trainer transition registers the same frame budget")
eq(hook(function() return "native" end, { game = {}, trainer = false }),
  Wipe.WILD_ID, "wild encounter selects the wild pixel-band style")
eq(hook(function() return "native" end, { game = {}, trainer = true }),
  Wipe.TRAINER_ID, "trainer encounter selects the trainer style")
eq(hook(function() return "native" end, {}), "native",
  "unknown transition context preserves the engine's native choice")

local renderer = setmetatable({}, Renderer)
graphics.calls = {}
registered[Wipe.WILD_ID].draw({ game = { renderer = renderer } }, 0.5)
eq(#graphics.calls, 0,
  "widescreen transition defers drawing until the finished composite")
local a, b, c = renderer:endFrame()
eq(a, "viewport", "renderer wrapper preserves its first return")
eq(b, nil, "renderer wrapper preserves an interior nil")
eq(c, "tail", "renderer wrapper preserves its final return")
check(#graphics.calls > 3,
  "finished-composite path draws bands and pixel leaders")
local callsAfterFrame = #graphics.calls
renderer:endFrame()
eq(#graphics.calls, callsAfterFrame,
  "frame-local wipe payload never leaks into the next frame")

local wrapper = Renderer.endFrame
local mod2 = {
  id = mod.id,
  content = mod.content,
  hooks = mod.hooks,
}
Wipe.install(mod2)
eq(Renderer.endFrame, wrapper,
  "F5-style reinstall refreshes rather than stacking renderer wrappers")

-- An independently owned finished-frame wrapper may sit outside Scott's
-- dispatcher. Reinstall must refresh the buried record, not abandon the
-- screen-space path or jump outside the provider's ordering.
local foreignCalls = 0
local foreignWrapper = function(self, ...)
  foreignCalls = foreignCalls + 1
  return wrapper(self, ...)
end
Renderer.endFrame = foreignWrapper
Wipe.install(mod2)
eq(Renderer.endFrame, foreignWrapper,
  "F5 refresh leaves a later provider's outer renderer wrapper in place")
graphics.calls = {}
registered[Wipe.TRAINER_ID].draw({ game = { renderer = renderer } }, 0.5)
renderer:endFrame()
eq(foreignCalls, 1, "later renderer provider remains active")
check(#graphics.calls > 3,
  "buried wipe dispatcher retains finished-screen rendering after F5")

-- A renderer failure cannot leave a stale frame payload armed for a later
-- recovered frame.
local record = Renderer._scottsTweaksBattleEntryWipe
local workingInner = record.inner
record.inner = function() error("synthetic renderer failure") end
registered[Wipe.WILD_ID].draw({ game = { renderer = renderer } }, 0.5)
local okFailure = pcall(renderer.endFrame, renderer)
eq(okFailure, false, "renderer failures still propagate through the wipe")
eq(rawget(renderer, "_scottsTweaksBattleEntryFrame"), nil,
  "failed frame clears its pending wipe payload")
record.inner = workingInner
local callsBeforeRecovery = #graphics.calls
renderer:endFrame()
eq(#graphics.calls, callsBeforeRecovery,
  "recovered renderer does not replay the failed frame's wipe")

print(("ok - Scott's pixel battle-entry wipe (%d checks)"):format(checks))
