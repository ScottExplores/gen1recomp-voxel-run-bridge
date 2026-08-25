-- A Scott's Tweaks battle-entry wipe on the engine's public transition seam.
--
-- Gen 1 already freezes the overworld, plays encounter music, pushes a
-- BattleTransition, holds on black, and only then pushes the battle. We change
-- only that transition's registered drawing record: three chunky horizontal
-- shutters follow small code-drawn pixel Poke Balls until the finished screen
-- is black. Trainer and wild battles reverse the alternating directions so
-- they are related but immediately distinct.
--
-- No image is embedded or decoded here. Every mark is an axis-aligned pixel
-- rectangle and every dimension derives from the same 160x144 logical frame
-- the original transition uses. Renderer:endFrame extends that drawing over
-- a widescreen/Thor primary without stretching the logical pixels; if that
-- narrow renderer seam is absent, the registered transition still draws on
-- the engine's normal 160x144 canvas.

local V = ...

local Wipe = {
  WILD_ID = "scotts_ball_wild",
  TRAINER_ID = "scotts_ball_trainer",
  FRAMES = 42,
  LOGICAL_W = 160,
  LOGICAL_H = 144,
}

local RENDER_MARKER = "_scottsTweaksBattleEntryWipe"
local FRAME_FIELD = "_scottsTweaksBattleEntryFrame"
local unpackValues = table.unpack or unpack

local function pack(...)
  return { n = select("#", ...), ... }
end

local function clamp01(value)
  value = tonumber(value) or 0
  if value ~= value then return 0 end
  return math.max(0, math.min(1, value))
end

-- Gen 1 movement is deliberately stepped rather than sub-pixel smooth. The
-- smoothstep controls the overall acceleration, then the two-logical-pixel
-- quantisation makes the leader land on authored-looking pixel positions.
local function easedProgress(progress)
  local t = clamp01(progress)
  return t * t * (3 - 2 * t)
end

function Wipe.layout(progress, width, height, trainer)
  width = math.max(1, math.floor(tonumber(width) or Wipe.LOGICAL_W))
  height = math.max(1, math.floor(tonumber(height) or Wipe.LOGICAL_H))
  local t = easedProgress(progress)
  local done = t >= 1
  local out = {}
  for band = 1, 3 do
    local y1 = math.floor((band - 1) * height / 3)
    local y2 = math.floor(band * height / 3)
    -- Wild: left, right, left. Trainer: right, left, right.
    local movesRight = ((band % 2) == 0)
    if trainer == true then movesRight = not movesRight end
    local raw = movesRight and (width * t) or (width * (1 - t))
    local quantum = math.max(1, math.floor(width / Wipe.LOGICAL_W) * 2)
    local leader = math.floor(raw / quantum + 0.5) * quantum
    leader = math.max(0, math.min(width, leader))
    if done then leader = nil end
    out[band] = {
      y = y1,
      height = y2 - y1,
      direction = movesRight and "right" or "left",
      leader = leader,
      -- Once the leader retires, every band is one ordinary full-screen
      -- rectangle. In particular, a completed left-moving band cannot use
      -- the now-nil leader as its X coordinate during the engine's black hold.
      blackX = done and 0 or (movesRight and 0 or leader),
      blackWidth = done and width
        or (movesRight and leader or (width - leader)),
    }
  end
  return out
end

local BALL = {
  "..KKKKK..",
  ".KRRRRRK.",
  "KRRRRRRRK",
  "KRRRRRRRK",
  "KKKWWWKKK",
  "KWWWKWWWK",
  "KWWWWWWWK",
  ".KWWWWWK.",
  "..KKKKK..",
}

local BALL_COLOR = {
  K = { 0.04, 0.04, 0.05, 1 },
  R = { 0.86, 0.12, 0.15, 1 },
  W = { 1.00, 0.98, 0.86, 1 },
}

local function drawBall(graphics, cx, cy, scale)
  scale = math.max(1, math.floor(scale or 1))
  local size = #BALL
  local ox = math.floor(cx - size * scale / 2)
  local oy = math.floor(cy - size * scale / 2)
  for row, pattern in ipairs(BALL) do
    for col = 1, #pattern do
      local key = pattern:sub(col, col)
      local color = BALL_COLOR[key]
      if color then
        graphics.setColor(color[1], color[2], color[3], color[4])
        graphics.rectangle("fill", ox + (col - 1) * scale,
          oy + (row - 1) * scale, scale, scale)
      end
    end
  end
end

function Wipe.drawSurface(graphics, progress, width, height, trainer)
  if not (graphics and type(graphics.rectangle) == "function"
      and type(graphics.setColor) == "function") then return false end
  local savedColor
  if type(graphics.getColor) == "function" then
    local ok, r, g, b, a = pcall(graphics.getColor)
    if ok then savedColor = { r, g, b, a } end
  end
  width = math.max(1, math.floor(tonumber(width) or Wipe.LOGICAL_W))
  height = math.max(1, math.floor(tonumber(height) or Wipe.LOGICAL_H))
  local layout = Wipe.layout(progress, width, height, trainer)
  local scale = math.max(1, math.floor(math.min(
    width / Wipe.LOGICAL_W, height / Wipe.LOGICAL_H)))
  for _, band in ipairs(layout) do
    graphics.setColor(0, 0, 0, 1)
    graphics.rectangle("fill", band.blackX, band.y,
      band.blackWidth, band.height)
    if band.leader ~= nil then
      drawBall(graphics, band.leader, band.y + band.height / 2, scale)
    end
  end
  if savedColor then
    graphics.setColor(savedColor[1] or 1, savedColor[2] or 1,
      savedColor[3] or 1, savedColor[4] or 1)
  else
    graphics.setColor(1, 1, 1, 1)
  end
  return true
end

local rendererReady = false

local function transitionDraw(transition, progress, trainer)
  local renderer = transition and transition.game and transition.game.renderer
  if rendererReady and renderer then
    rawset(renderer, FRAME_FIELD, {
      progress = clamp01(progress), trainer = trainer == true,
    })
    return true
  end
  return Wipe.drawSurface(love and love.graphics, progress,
    Wipe.LOGICAL_W, Wipe.LOGICAL_H, trainer)
end

function Wipe.drawWild(transition, progress)
  return transitionDraw(transition, progress, false)
end

function Wipe.drawTrainer(transition, progress)
  return transitionDraw(transition, progress, true)
end

local function installRenderer(mod)
  local ok, Renderer = pcall(require, "src.render.Renderer")
  if not ok or type(Renderer) ~= "table"
      or type(Renderer.endFrame) ~= "function" then
    rendererReady = false
    return false
  end
  local record = rawget(Renderer, RENDER_MARKER)
  if type(record) == "table" and record.owner == mod.id then
    -- Renderer wrappers installed later are expected to call their captured
    -- inner method, so this stable dispatcher can be buried without being
    -- inactive. Refresh its module callback in place on every F5.
    record.module = Wipe
    rendererReady = true
    return true
  end
  if record ~= nil then
    rendererReady = false
    return false
  end

  record = { owner = mod.id, module = Wipe, inner = Renderer.endFrame }
  record.wrapper = function(self, ...)
    local results = pack(pcall(record.inner, self, ...))
    local frame = rawget(self, FRAME_FIELD)
    rawset(self, FRAME_FIELD, nil)
    if not results[1] then error(results[2], 0) end
    local current = record.module
    if type(frame) == "table" and type(current) == "table" then
      local graphics = love and love.graphics
      local w, h
      if graphics and type(graphics.getDimensions) == "function" then
        local okSize, sw, sh = pcall(graphics.getDimensions)
        if okSize then w, h = sw, sh end
      end
      current.drawSurface(graphics, frame.progress,
        w or current.LOGICAL_W, h or current.LOGICAL_H, frame.trainer)
    end
    return unpackValues(results, 2, results.n)
  end
  rawset(Renderer, "endFrame", record.wrapper)
  rawset(Renderer, RENDER_MARKER, record)
  rendererReady = true
  return true
end

-- Register and select the style only as one atomic capability. If a future
-- engine removes either public surface, native BattleTransition selection is
-- left untouched and its own eight Gen-1 wipes remain the fallback.
function Wipe.install(mod)
  local status = {
    active = false,
    reason = "transition_api_unavailable",
    wild = Wipe.WILD_ID,
    trainer = Wipe.TRAINER_ID,
  }
  if type(mod) ~= "table" or type(mod.content) ~= "table"
      or type(mod.content.transitions) ~= "table"
      or type(mod.content.transitions.register) ~= "function"
      or type(mod.hooks) ~= "table"
      or type(mod.hooks.wrap) ~= "function" then
    return status
  end

  local okRegister = pcall(function()
    mod.content.transitions:register(Wipe.WILD_ID, {
      frames = Wipe.FRAMES, draw = Wipe.drawWild,
    })
    mod.content.transitions:register(Wipe.TRAINER_ID, {
      frames = Wipe.FRAMES, draw = Wipe.drawTrainer,
    })
  end)
  if not okRegister then
    status.reason = "transition_registration_failed"
    return status
  end

  mod.hooks:wrap("transition.style", function(nextFn, ctx)
    local native = nextFn(ctx)
    if type(ctx) ~= "table" or ctx.game == nil
        or type(ctx.trainer) ~= "boolean" then
      return native
    end
    return ctx.trainer and Wipe.TRAINER_ID or Wipe.WILD_ID
  end)

  status.active = true
  status.reason = "pixel_ball_bands"
  status.renderer = installRenderer(mod) and "screen_space" or "logical_canvas"
  return status
end

return Wipe
