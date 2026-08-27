-- SPDX-License-Identifier: MIT
--
-- Scott's Tweaks: physical AYN Thor presentation.
--
-- This module is an independent implementation over Gen1Recomp's public
-- render.compose, render.hud, and SecondScreen contracts.  It deliberately
-- provides no desktop stacking, no touch translation, and no direct access to
-- battle-state drawing methods.  Battle Art integration uses only its public
-- Battle Stage export (v2 projection, v3 split-presentation request).

local ThorDualScreen = {
  API_VERSION = 1,
  -- This is a logical 10:9 transport surface, not a guessed panel size.  The
  -- public Android Presentation bridge integer-scales it to whichever second
  -- display is attached.  At 400x360 the canonical 160x144 UI has a crisp 2x
  -- playfield with room for Modern UI's responsive HUD, while 30 Hz readback
  -- stays well below the cost of a native-resolution buffer.
  OUTPUT_WIDTH = 400,
  OUTPUT_HEIGHT = 360,
  -- Keep the battle controls close to the hinge instead of centering the
  -- original bottom-of-Game-Boy-screen placement on Thor's lower panel.
  BATTLE_PANEL_TOP = 12,
  PUSH_HZ = 30,
  COMPOSE_PRIORITY = 20000,
  HUD_PRIORITY = 20000,
}

local BRIDGE_RECORD_KEY = "_scottsTweaksThorPresentation"
local HOOK_RECORD_KEY = "_scottsTweaksThorHookDispatch"
local EVENT_RECORD_KEY = "_scottsTweaksThorEventDispatch"
local WORLD_OVERLAY_ROUTE_KEY = "_scottsTweaksThorRouteWorldOverlay"
local START_MENU_LAYOUT_KEY = "_scottsTweaksThorStartLayout"
local PRIMARY_WORLD_OVERLAY_OPTIONS = {
  target = "primary",
  presentation = "ayn_thor",
  fullComposite = true,
}

-- BattleState's classic UI owns these exact source bands.  Moving the band as
-- one piece preserves the authored merged borders: TYPE/PP remains above the
-- move list, while ordinary wording/command boxes retain their full 20x6
-- bottom row.  Full-screen battle submenus are deliberately excluded below.
local BATTLE_PANEL_REGIONS = {
  messages = { y = 96, height = 48 },
  menu = { y = 96, height = 48 },
  -- Battle Art intentionally leaves the picture area transparent in split
  -- presentation.  These two menus use joined boxes that do not cover their
  -- complete source band, however, so the transparent upper-right remainder
  -- showed the Thor lower canvas' black clear.  Paper fills only that known
  -- remainder; every authored border/text pixel is still drawn from uiCanvas.
  moveSelect = {
    y = 64, height = 80,
    paper = { x = 88, y = 64, width = 72, height = 32 },
  },
  mimicSelect = {
    y = 56, height = 88,
    paper = { x = 128, y = 56, width = 32, height = 40 },
  },
}

-- Keep Start at the same 2x pixel scale as every other classic UI surface.
-- Eight double-spaced rows are the most the authored 18-tile screen can hold;
-- scrolling still covers any extra rows supplied by mods.
local THOR_START_VISIBLE_ROWS = 8

local unpackValues = table.unpack or unpack

local function pack(...)
  return { n = select("#", ...), ... }
end

local function finite(value)
  return type(value) == "number" and value == value
    and value > -math.huge and value < math.huge
end

local function positive(value, fallback)
  value = tonumber(value)
  if not finite(value) or value <= 0 then return fallback end
  return value
end

local function integer(value, fallback)
  value = positive(value, fallback)
  if not value then return nil end
  return math.max(1, math.floor(value + 0.5))
end

local function enabledValue(value)
  if value == true then return true end
  if value == false or value == nil then return false end
  if type(value) == "number" then return value ~= 0 end
  if type(value) ~= "string" then return false end
  local normalized = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return normalized ~= "" and normalized ~= "0" and normalized ~= "off"
    and normalized ~= "false" and normalized ~= "disabled"
    and normalized ~= "none"
end

local function dimensions(value)
  if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
  if type(value.getDimensions) == "function" then
    local ok, width, height = pcall(value.getDimensions, value)
    if ok then
      width, height = positive(width), positive(height)
      if width and height then return width, height end
    end
  end
  if type(value.getWidth) == "function"
      and type(value.getHeight) == "function" then
    local okW, width = pcall(value.getWidth, value)
    local okH, height = pcall(value.getHeight, value)
    width, height = okW and positive(width) or nil,
      okH and positive(height) or nil
    if width and height then return width, height end
  end
  return nil
end

local function release(resource)
  if resource and type(resource.release) == "function" then
    pcall(resource.release, resource)
  end
end

local function cover(sourceWidth, sourceHeight, targetWidth, targetHeight)
  sourceWidth, sourceHeight = positive(sourceWidth), positive(sourceHeight)
  targetWidth, targetHeight = positive(targetWidth), positive(targetHeight)
  if not (sourceWidth and sourceHeight and targetWidth and targetHeight) then
    return nil
  end
  local scale = math.max(targetWidth / sourceWidth,
    targetHeight / sourceHeight)
  return {
    x = (targetWidth - sourceWidth * scale) * 0.5,
    y = (targetHeight - sourceHeight * scale) * 0.5,
    width = sourceWidth * scale,
    height = sourceHeight * scale,
    scaleX = scale,
    scaleY = scale,
  }
end

local function contain(sourceWidth, sourceHeight, targetWidth, targetHeight)
  sourceWidth, sourceHeight = positive(sourceWidth), positive(sourceHeight)
  targetWidth, targetHeight = positive(targetWidth), positive(targetHeight)
  if not (sourceWidth and sourceHeight and targetWidth and targetHeight) then
    return nil
  end
  local scale = math.min(targetWidth / sourceWidth,
    targetHeight / sourceHeight)
  return {
    x = (targetWidth - sourceWidth * scale) * 0.5,
    y = (targetHeight - sourceHeight * scale) * 0.5,
    width = sourceWidth * scale,
    height = sourceHeight * scale,
    scaleX = scale,
    scaleY = scale,
  }
end

local function integerContain(sourceWidth, sourceHeight,
    targetWidth, targetHeight)
  local transform = contain(sourceWidth, sourceHeight,
    targetWidth, targetHeight)
  if not transform then return nil end
  local scale = transform.scaleX
  if scale >= 1 then scale = math.max(1, math.floor(scale)) end
  local width, height = sourceWidth * scale, sourceHeight * scale
  return {
    x = math.floor((targetWidth - width) * 0.5),
    y = math.floor((targetHeight - height) * 0.5),
    width = width,
    height = height,
    scaleX = scale,
    scaleY = scale,
  }
end

-- Gen 2's compose seam carries one window-sized scene under both uiCanvas and
-- worldCanvas.  Its ox/oy/scale fields locate the native 160x144 surface
-- inside that scene.  Convert that public mapping into the logical UI origin
-- stageLower expects; no Game2 or screen implementation access is required.
local function gen2SceneMap(ctx, uiWidth, uiHeight, generation)
  if type(ctx) ~= "table" or tonumber(generation or ctx.generation) ~= 2
      or not ctx.uiCanvas then return nil end
  local sourceScale = positive(ctx.scale)
  if not sourceScale then
    local vpw, vph = positive(ctx.vpw), positive(ctx.vph)
    sourceScale = vpw and positive(uiWidth) and vpw / uiWidth
      or vph and positive(uiHeight) and vph / uiHeight or nil
  end
  if not sourceScale then return nil end
  local sourceX, sourceY = tonumber(ctx.ox), tonumber(ctx.oy)
  if not finite(sourceX) or not finite(sourceY) then
    local sceneWidth, sceneHeight = dimensions(ctx.uiCanvas)
    if not (sceneWidth and sceneHeight) then return nil end
    sourceX = (sceneWidth - uiWidth * sourceScale) * 0.5
    sourceY = (sceneHeight - uiHeight * sourceScale) * 0.5
  end
  return { x = sourceX, y = sourceY, scale = sourceScale }
end

local function battlePanelRegion(phase, uiWidth, uiHeight)
  if tonumber(uiWidth) ~= 160 or tonumber(uiHeight) ~= 144 then return nil end
  local region = BATTLE_PANEL_REGIONS[phase]
  if not region then return nil end
  return {
    x = 0,
    y = region.y,
    width = 160,
    height = region.height,
    phase = phase,
    kind = "battle_" .. tostring(phase),
    placement = "top",
    paper = region.paper,
  }
end

local function graphicsGuard(graphics, body)
  if not graphics or type(graphics.push) ~= "function"
      or type(graphics.pop) ~= "function" then
    return false, "graphics state guard is unavailable"
  end
  local pushed, pushError = pcall(graphics.push, "all")
  if not pushed then return false, tostring(pushError) end
  local result = pack(xpcall(body, function(err) return tostring(err) end))
  local popped, popError = pcall(graphics.pop)
  if not result[1] then return false, tostring(result[2]) end
  if not popped then return false, tostring(popError) end
  return true, unpackValues(result, 2, result.n)
end

local function neutralGraphics(graphics)
  if type(graphics.origin) == "function" then graphics.origin() end
  if type(graphics.setScissor) == "function" then graphics.setScissor() end
  if type(graphics.setShader) == "function" then graphics.setShader() end
  if type(graphics.setColor) == "function" then
    graphics.setColor(1, 1, 1, 1)
  end
end

local function callLogger(mod, level, message)
  local log = mod and mod.log
  local fn = log and log[level]
  if type(fn) == "function" then
    pcall(fn, log, "%s", tostring(message))
  end
end

local function optionEnabled(mod, key)
  local options = mod and mod.options
  local get = options and options.get
  if type(get) ~= "function" then return false end
  local ok, value = pcall(get, options, key)
  return ok and enabledValue(value) or false
end

local function findHandle(mod, id)
  if not mod or type(mod.find) ~= "function" then return nil end
  local ok, handle = pcall(mod.find, mod, id)
  if not ok then ok, handle = pcall(mod.find, id) end
  return ok and type(handle) == "table" and handle or nil
end

local function externalPresenterActive(mod)
  return findHandle(mod, "gen1recomp_ds") ~= nil
end

local function bridgeCall(bridge, name, ...)
  local fn = bridge and bridge[name]
  if type(fn) ~= "function" then return false, nil end
  local result = pack(pcall(fn, ...))
  if not result[1] then return false, result[2] end
  return true, unpackValues(result, 2, result.n)
end

local function bridgeAvailable(bridge)
  local ok, available = bridgeCall(bridge, "available")
  return ok and available == true
end

local function privateRecord(host, key)
  if type(host) ~= "table" then return nil end
  local ok, value = pcall(rawget, host, key)
  return ok and value or nil
end

local function setPrivateRecord(host, key, value)
  if type(host) ~= "table" then return false end
  return pcall(rawset, host, key, value)
end

-- mod.game is the Loader's sanctioned live-game facade.  Resolve it lazily so
-- a headless load (before game.ready) and Gold's per-instance facade both stay
-- valid, then use only the public stack:top shape and state identity fields.
local function liveGame(mod)
  if type(mod) ~= "table" then return nil end
  local ok, game = pcall(function() return mod.game end)
  if ok and type(game) == "table" then return game end
  -- Gen1Recomp 0.1.75 predates the sanctioned mod.game facade. Scott's
  -- Tweaks already declares engine_internals for its older-engine adapters,
  -- so fall back to that release's live singleton only when the property is
  -- genuinely absent. A present-but-invalid newer facade remains a hard
  -- failure instead of being silently masked.
  if not ok or game ~= nil then return nil end
  local okLegacy, legacy = pcall(require, "src.core.Game")
  return okLegacy and type(legacy) == "table" and legacy or nil
end

local function topState(mod)
  local game = liveGame(mod)
  local stack = game and game.stack
  if type(stack) ~= "table" or type(stack.top) ~= "function" then return nil end
  local ok, state = pcall(stack.top, stack)
  return ok and type(state) == "table" and state or nil
end

local function stackStates(mod)
  local game = liveGame(mod)
  local stack = game and game.stack
  return type(stack) == "table" and type(stack.states) == "table"
    and stack.states or nil
end

-- Gen 2 publishes the generation directly on render.compose.  Older Gen 1
-- releases predate that field, so retain the live save as the narrow fallback
-- and finally the historical Gen 1 default.  This value describes the game;
-- runtime.generation below independently describes presenter/F5 ownership.
local function gameGeneration(mod, ctx)
  local value = type(ctx) == "table" and tonumber(ctx.generation) or nil
  if value ~= 1 and value ~= 2 then
    local game = liveGame(mod)
    local save = game and game.save
    value = save and tonumber(save.generation) or nil
  end
  return value == 2 and 2 or 1
end

local function isGen2StartMenu(state)
  return type(state) == "table" and state.screenId == "Gen2StartMenu"
end

local function isGen2BattleState(state)
  if type(state) ~= "table" then return false end
  return state.screenId == "Gen2BattleState"
    or state.screenId == "Gen2BattleTransition"
end

local GEN2_SINGLE_SCREEN_STATES = {
  -- Boot/cinema screens are primary-screen experiences, not companion menus.
  Gen2CopyrightSplash = true,
  Gen2GameFreakPresents = true,
  Gen2GoldSilverIntro = true,
  Gen2CrystalSplash = true,
  Gen2CrystalIntro = true,
  Gen2TitleState = true,
  Gen2MainMenu = true,
  Gen2OakSpeech = true,
  Gen2GenderSelect = true,
  Gen2InitClock = true,
  Gen2NamePick = true,
  -- These own the animated primary scene.  The remaining Gen2* states are
  -- native gameplay menus/pages and are safe to route as a complete GB frame.
  Gen2EvolutionAnim = true,
  Gen2EggHatchAnim = true,
  Gen2MagnetTrainRide = true,
  Gen2TradeAnim = true,
  Gen2HallOfFame = true,
  Gen2Credits = true,
}

local function gen2SingleScreenState(state)
  if isGen2BattleState(state) then return true end
  return type(state) == "table"
    and GEN2_SINGLE_SCREEN_STATES[state.screenId] == true
end

-- Battle submenus (PACK, PARTY, a TextBox or a ChoiceBox) sit above the live
-- Gen2BattleState.  The current Gen 2 compositor intentionally exposes one
-- combined scene rather than independent battle-picture/UI surfaces, so the
-- presenter must stand aside for the complete battle stack instead of
-- pretending that a safe split exists.
local function gen2BattleActive(mod)
  local states = stackStates(mod)
  if type(states) == "table" then
    for index = #states, 1, -1 do
      if isGen2BattleState(states[index]) then return true end
    end
  end
  return isGen2BattleState(topState(mod))
end

local function gen2SingleScreenActive(mod)
  local states = stackStates(mod)
  if type(states) == "table" then
    for index = #states, 1, -1 do
      if gen2SingleScreenState(states[index]) then return true end
    end
  end
  return gen2SingleScreenState(topState(mod))
end

local function startMenuHasSideArt(state)
  local game = type(state) == "table" and state.game or nil
  local save, overworld = game and game.save, game and game.overworld
  if not (save and save.safari and overworld and overworld.map
      and type(overworld.inSafariStepZone) == "function") then
    return false
  end
  local ok, active = pcall(overworld.inSafariStepZone, overworld)
  return ok and active == true
end

local function isDialogueState(state)
  if type(state) ~= "table" then return false end
  -- 0.1.83+ publishes the explicit marker. A false marker is authoritative.
  if state.isTextBox ~= nil then return state.isTextBox == true end
  -- Gen1Recomp 0.1.75 predates that marker. Its TextBox is still uniquely
  -- identifiable without class access: paginated typewriter state, the live
  -- two-line glyph window, counters and the three authored text origins. Menus
  -- can share boxTx/boxTy geometry, but do not carry this combined state shape.
  return type(state.pages) == "table"
    and type(state.shown) == "table"
    and finite(tonumber(state.pageIndex))
    and finite(tonumber(state.lineIndex))
    and finite(tonumber(state.charIndex))
    and type(state.waiting) == "boolean"
    and type(state.done) == "boolean"
    and positive(state.maxCols) ~= nil
    and finite(tonumber(state.textX))
    and finite(tonumber(state.line1Y))
    and finite(tonumber(state.line2Y))
end

local function makeCanvas(graphics, width, height)
  if not graphics or type(graphics.newCanvas) ~= "function" then
    return nil, "canvas allocation is unavailable"
  end
  local ok, canvas = pcall(graphics.newCanvas, width, height,
    { dpiscale = 1, format = "rgba8" })
  if not ok or not canvas then
    ok, canvas = pcall(graphics.newCanvas, width, height)
  end
  if not ok or not canvas then return nil, tostring(canvas) end
  if type(canvas.setFilter) == "function" then
    pcall(canvas.setFilter, canvas, "nearest", "nearest", 0)
  end
  return canvas
end

local function validStageApi(stage)
  local apiVersion = type(stage) == "table" and tonumber(stage.apiVersion)
    or nil
  return apiVersion and apiVersion >= 2
    and type(stage.state) == "function"
    and type(stage.animationSurface) == "function"
end

-- A HUD contributor can use this tiny provider shape to identify something
-- that is visually part of the world/player rather than lower-screen UI. The
-- route itself is frame-local and lives only on Thor's private lower viewport;
-- an ordinary engine viewport never exposes it, so non-Thor drawing is
-- unchanged. Free Fly uses this for its first-person rider/mount cockpit.
local function validWorldOverlay(provider)
  return type(provider) == "table"
    and tonumber(provider.apiVersion) == 1
    and provider.kind == "player_mount"
    and type(provider.draw) == "function"
end

local function stageApi(mod)
  if gameGeneration(mod) == 2 then return nil end
  -- In Scott's Tweaks, Battle Art is fused into this same loader entry and
  -- publishes its compatibility seam directly on the root mod exports. A
  -- standalone BATTLE_ART_VOXEL_FORK handle exists only in older/separate
  -- installs, so use it strictly as the compatibility fallback.
  local ownExports = mod and mod.exports
  local ownStage = type(ownExports) == "table" and ownExports.battleStage or nil
  if validStageApi(ownStage) then return ownStage end

  local handle = findHandle(mod, "BATTLE_ART_VOXEL_FORK")
  local exports = handle and handle.exports
  local stage = type(exports) == "table" and exports.battleStage or nil
  return validStageApi(stage) and stage or nil
end

local function stageState(mod)
  local stage = stageApi(mod)
  if not stage then return nil end
  local ok, state = pcall(stage.state)
  if not ok or type(state) ~= "table" or state.battle == nil
      or state.staged == false then
    return nil
  end
  return state
end

local function animationSurface(mod)
  local stage = stageApi(mod)
  if not stage then return nil end
  local state = stageState(mod)
  if not state then return nil end
  local okSurface, surface = pcall(stage.animationSurface, state.battle)
  if not okSurface or type(surface) ~= "table" then return nil end
  local canvasWidth, canvasHeight = dimensions(surface.canvas)
  local framebufferWidth = positive(surface.pw)
  local framebufferHeight = positive(surface.ph)
  local layerScale = positive(surface.scale)
  if not (canvasWidth and canvasHeight and framebufferWidth
      and framebufferHeight and layerScale and finite(tonumber(surface.lx))
      and finite(tonumber(surface.ly))) then
    return nil
  end
  return {
    canvas = surface.canvas,
    lx = tonumber(surface.lx),
    ly = tonumber(surface.ly),
    scale = layerScale,
    pw = framebufferWidth,
    ph = framebufferHeight,
  }
end

local function activeBattlePanel(mod, uiWidth, uiHeight)
  local state = stageState(mod)
  local battle = state and state.battle or nil
  -- Bag, party, naming, settings and yes/no screens can sit over a battle
  -- while its phase still says "messages".  Prefer the live stack identity
  -- when exposed, with waitingUI as the compatibility fallback; those screens
  -- must retain their complete 160x144 surface.
  if type(battle) ~= "table" or battle.waitingUI then return nil end
  local stack = battle.game and battle.game.stack or nil
  if type(stack) == "table" and type(stack.top) == "function" then
    local ok, top = pcall(stack.top, stack)
    if ok and top ~= battle then return nil end
  end
  return battlePanelRegion(battle.phase, uiWidth, uiHeight)
end

local function tileRegion(state, txKey, tyKey, twKey, thKey,
    uiWidth, uiHeight)
  if type(state) ~= "table" then return nil end
  local tx, ty = tonumber(state[txKey]), tonumber(state[tyKey])
  local tw, th = positive(state[twKey]), positive(state[thKey])
  if not (finite(tx) and finite(ty) and tw and th) then return nil end
  local region = {
    x = tx * 8, y = ty * 8,
    width = tw * 8, height = th * 8,
  }
  if region.x < 0 or region.y < 0
      or region.x + region.width > uiWidth
      or region.y + region.height > uiHeight then
    return nil
  end
  return region
end

local function smallChoiceRegion(state, uiWidth, uiHeight)
  -- ChoiceBox has no screenId: it is a lightweight overlay state. Require its
  -- behavioral fields as well as bounded tile geometry so an unrelated small
  -- menu is never mistaken for a dialogue answer.
  if type(state) ~= "table" or state.screenId ~= nil
      or state.isTextBox ~= nil or type(state.onChoose) ~= "function"
      or (state.index ~= 1 and state.index ~= 2) then
    return nil
  end
  local region = tileRegion(state, "tx", "ty", "tw", "th",
    uiWidth, uiHeight)
  if not region or region.width > uiWidth * 0.75
      or region.height > uiHeight * 0.75 then
    return nil
  end
  return region
end

local function dialogueBelowChoice(mod, choice, uiWidth, uiHeight)
  local states = stackStates(mod)
  if type(states) ~= "table" then return nil end
  for index = #states, 2, -1 do
    if states[index] == choice then
      local state = states[index - 1]
      if not isDialogueState(state) then return nil end
      return tileRegion(state, "boxTx", "boxTy", "boxTw", "boxTh",
        uiWidth, uiHeight)
    end
  end
  return nil
end

local function stackedChoicePanel(mod, uiWidth, uiHeight)
  if tonumber(uiWidth) ~= 160 or tonumber(uiHeight) ~= 144 then return nil end
  local choice = topState(mod)
  local choiceRegion = smallChoiceRegion(choice, uiWidth, uiHeight)
  if not choiceRegion then return nil end

  -- TextBox choices have the live TextBox immediately below them. Battle
  -- sayChoice draws its wording inside BattleState instead; current.choice is
  -- the narrow proof that waitingUI is this prompt rather than Bag/Party/etc.
  local dialogueRegion = dialogueBelowChoice(mod, choice, uiWidth, uiHeight)
  local kind = "dialogue_choice"
  if not dialogueRegion then
    local staged = stageState(mod)
    local battle = staged and staged.battle
    local current = type(battle) == "table" and battle.current or nil
    if battle and battle.waitingUI == true and type(current) == "table"
        and type(current.choice) == "function" then
      dialogueRegion = {
        x = 0, y = BATTLE_PANEL_REGIONS.messages.y,
        width = uiWidth, height = BATTLE_PANEL_REGIONS.messages.height,
      }
      kind = "battle_dialogue_choice"
    end
  end
  if not dialogueRegion then return nil end

  return {
    x = dialogueRegion.x,
    y = dialogueRegion.y,
    width = dialogueRegion.width,
    height = dialogueRegion.height + choiceRegion.height,
    kind = kind,
    placement = "stacked_choice",
    dialogue = dialogueRegion,
    choice = choiceRegion,
  }
end

local function ordinaryDialoguePanel(mod, uiWidth, uiHeight)
  if tonumber(uiWidth) ~= 160 or tonumber(uiHeight) ~= 144
      or stageState(mod) ~= nil then
    return nil
  end
  local state = topState(mod)
  if not isDialogueState(state) then return nil end
  local tx, ty = tonumber(state.boxTx), tonumber(state.boxTy)
  local tw, th = positive(state.boxTw), positive(state.boxTh)
  if not (finite(tx) and finite(ty) and tw and th) then return nil end
  local x, y, width, height = tx * 8, ty * 8, tw * 8, th * 8
  if x < 0 or y < 0 or x + width > uiWidth or y + height > uiHeight then
    return nil
  end
  return {
    x = x, y = y, width = width, height = height,
    kind = "overworld_dialogue", placement = "top",
  }
end

local function startMenuPanel(mod, uiWidth, uiHeight)
  if tonumber(uiWidth) ~= 160 or tonumber(uiHeight) ~= 144 then return nil end
  local state = topState(mod)
  -- Gold/Silver/Crystal already author the correct native PACK/POKéGEAR Start
  -- page as a full 160x144 composition.  It has Chrome.List geometry rather
  -- than Gen 1's tx/ty/tw/th fields and must never be resized or cropped as if
  -- it were the Kanto menu.
  if isGen2StartMenu(state) then return nil end
  if not state or state.screenId ~= "StartMenu"
      or startMenuHasSideArt(state) then return nil end
  local record = privateRecord(state, START_MENU_LAYOUT_KEY)
  if type(record) ~= "table" or record.owner ~= mod.id
      or record.ready ~= true then
    return nil
  end
  local tx, ty = tonumber(state.tx), tonumber(state.ty)
  local tw, th = positive(state.tw), positive(state.th)
  if not (finite(tx) and finite(ty) and tw and th) then return nil end
  local x, y, width, height = tx * 8, ty * 8, tw * 8, th * 8
  if x < 0 or y < 0 or x + width > uiWidth or y + height > uiHeight then
    return nil
  end
  return {
    x = x, y = y, width = width, height = height,
    kind = "start_menu", placement = "start",
  }
end

local function setSplitPresentation(mod, active)
  local stage = stageApi(mod)
  if not stage or (tonumber(stage.apiVersion) or 0) < 3
      or type(stage.setSplitPresentation) ~= "function" then
    return false
  end
  local ok, accepted = pcall(stage.setSplitPresentation, active == true)
  return ok and accepted == true
end

local function cloneStatus(runtime, mod, optionKey)
  local desired = optionEnabled(mod, optionKey)
  local external = externalPresenterActive(mod)
  local delegated = runtime.delegated == true or external
  return {
    apiVersion = ThorDualScreen.API_VERSION,
    optionKey = optionKey,
    mode = desired and "on" or "off",
    enabled = desired,
    active = runtime.active == true and not delegated,
    attached = bridgeAvailable(runtime.bridge),
    externalPresenter = external,
    delegated = delegated,
    delegateId = delegated and "gen1recomp_ds" or nil,
    blockedReason = delegated and "delegated_to_gen1recomp_ds"
      or runtime.faulted and "runtime_error" or nil,
    faulted = runtime.faulted == true,
    generation = runtime.generation,
    retired = runtime.retired == true,
    lastError = runtime.lastError,
    topSource = runtime.topSource,
    outputWidth = ThorDualScreen.OUTPUT_WIDTH,
    outputHeight = ThorDualScreen.OUTPUT_HEIGHT,
    outputPolicy = "logical_10_9_integer_scaled",
    pushHz = ThorDualScreen.PUSH_HZ,
    controllerOnly = true,
    touchPolling = false,
    battleSplit = runtime.splitRequested == true,
    gameGeneration = runtime.gameGeneration,
    compatibilityFallback = runtime.compatibilityFallback,
  }
end

function ThorDualScreen.install(mod, opts)
  assert(type(mod) == "table", "Thor Dual Screen needs the mod API")
  opts = type(opts) == "table" and opts or {}
  local optionKey = type(opts.optionKey) == "string" and opts.optionKey ~= ""
    and opts.optionKey or "dual_screen"
  local graphics = opts.graphics or (love and love.graphics)
  local timer = opts.timer or (love and love.timer)
  local now = type(opts.now) == "function" and opts.now or function()
    if timer and type(timer.getTime) == "function" then
      local ok, value = pcall(timer.getTime)
      if ok and finite(tonumber(value)) then return tonumber(value) end
    end
    return os.clock()
  end

  local runtime = {
    bridge = nil,
    bridgeRecord = nil,
    bridgeRequested = nil,
    generation = 1,
    gameGeneration = tonumber(opts.generation) == 2 and 2
      or gameGeneration(mod),
    compatibilityFallback = nil,
    retired = false,
    delegated = false,
    topCanvas = nil,
    topWidth = nil,
    topHeight = nil,
    topValid = false,
    topSource = nil,
    lowerCanvas = nil,
    pending = nil,
    active = false,
    faulted = false,
    lastError = nil,
    lastPushAt = nil,
    splitRequested = nil,
    warned = {},
    worldOverlayRouteLive = false,
    worldOverlayRouteGeneration = nil,
    worldOverlayRouteBridge = nil,
    worldOverlayProvider = nil,
    worldOverlayOwner = nil,
    -- Weak keys ensure an abandoned menu can never be kept alive by the
    -- presenter.  Live entries are restored on detach/OFF/F5 before control
    -- returns to the ordinary single-screen renderer.
    startMenus = setmetatable({}, { __mode = "k" }),
  }

  local function requestBattleSplit(on)
    on = on == true
    -- Gen 2's public compose payload is a single finished scene.  Scott's
    -- Gen 1 Battle Stage cannot separate that scene, even if an old standalone
    -- Battle Art handle happens to be installed beside this package.
    if runtime.gameGeneration == 2 then
      runtime.splitRequested = nil
      return false
    end
    if runtime.splitRequested == on then return true end
    local accepted = setSplitPresentation(mod, on)
    if accepted then
      runtime.splitRequested = on
      return true
    end
    -- Battle Stage v2 and a boot with no staged-battle provider are valid.
    -- Retain nil so a provider loaded later in this same process is probed.
    if not on then runtime.splitRequested = nil end
    return false
  end

  local function warnOnce(key, message)
    if runtime.warned[key] then return end
    runtime.warned[key] = true
    callLogger(mod, "warn", "Thor display: " .. tostring(message))
  end

  local function restoreStartMenu(state)
    if type(state) ~= "table" then return false end
    local record = privateRecord(state, START_MENU_LAYOUT_KEY)
    if type(record) ~= "table" or record.owner ~= mod.id then return false end
    state.maxVisible = record.maxVisible
    state.th = record.th
    state.scroll = record.scroll
    setPrivateRecord(state, START_MENU_LAYOUT_KEY, nil)
    runtime.startMenus[state] = nil
    if type(state.clampScroll) == "function" then
      pcall(state.clampScroll, state)
    end
    return true
  end

  local function restoreStartMenus()
    for state in pairs(runtime.startMenus) do restoreStartMenu(state) end
  end

  local function configureStartMenu(state, ready)
    -- Gen 2's native StartMenu already uses all eight available rows and owns
    -- Chrome.List scrolling.  Leaving every field untouched is what preserves
    -- its PACK and POKéGEAR artwork and keeps this module reload-safe.
    if isGen2StartMenu(state) then return false end
    if type(state) ~= "table" or state.screenId ~= "StartMenu"
        or startMenuHasSideArt(state)
        or type(state.items) ~= "table" or #state.items == 0
        or not finite(tonumber(state.tx)) or not finite(tonumber(state.ty))
        or not positive(state.tw) or not positive(state.th) then
      return false
    end
    local record = privateRecord(state, START_MENU_LAYOUT_KEY)
    if type(record) == "table" and record.owner == mod.id then
      if ready == true then record.ready = true end
      runtime.startMenus[state] = true
      return true
    end
    -- Refuse to trample another presenter's state decoration.  It is safer to
    -- retain the ordinary centered menu than to guess how to restore it.
    if record ~= nil then return false end
    record = {
      owner = mod.id,
      generation = runtime.generation,
      maxVisible = state.maxVisible,
      th = state.th,
      scroll = state.scroll,
      ready = ready == true,
    }
    if not setPrivateRecord(state, START_MENU_LAYOUT_KEY, record) then
      return false
    end
    runtime.startMenus[state] = true
    local rowStep = positive(state.rowStep, 2)
    state.maxVisible = math.min(THOR_START_VISIBLE_ROWS, #state.items)
    state.th = state.maxVisible * rowStep + 2
    if type(state.clampScroll) == "function" then
      pcall(state.clampScroll, state)
    end
    return true
  end

  local function markStartMenuReady(state)
    local record = privateRecord(state, START_MENU_LAYOUT_KEY)
    if type(record) == "table" and record.owner == mod.id then
      record.ready = true
    end
  end

  local function releaseCanvases()
    requestBattleSplit(false)
    restoreStartMenus()
    runtime.pending = nil
    runtime.active = false
    release(runtime.topCanvas)
    release(runtime.lowerCanvas)
    runtime.topCanvas, runtime.lowerCanvas = nil, nil
    runtime.topWidth, runtime.topHeight = nil, nil
    runtime.topValid, runtime.topSource = false, nil
    runtime.lastPushAt = nil
    runtime.worldOverlayRouteLive = false
    runtime.worldOverlayRouteGeneration = nil
    runtime.worldOverlayRouteBridge = nil
    runtime.worldOverlayProvider = nil
    runtime.worldOverlayOwner = nil
  end

  local function ownsBridgeRecord()
    local record = runtime.bridgeRecord
    return type(record) == "table" and record.owner == mod.id
      and record.runtime == runtime
      and privateRecord(runtime.bridge, BRIDGE_RECORD_KEY) == record
  end

  local function recordRequest(value)
    runtime.bridgeRequested = value
    if ownsBridgeRecord() then runtime.bridgeRecord.requested = value end
  end

  -- Old Loader hook buses disappear on F5, but the public SecondScreen module
  -- survives.  Its namespaced record hands the frozen world and enable request
  -- to the fresh generation and retires every old GPU resource exactly once.
  local function retireForHandoff(adoptTop)
    if runtime.retired then return nil end
    requestBattleSplit(false)
    -- A Start menu may be open during F5.  Return its live Menu instance to
    -- the engine-authored geometry before handing presentation to the fresh
    -- runtime; that runtime can then opt it back into the enlarged Thor layout
    -- under its own restoration record.
    restoreStartMenus()
    runtime.retired = true
    runtime.pending = nil
    runtime.active = false
    release(runtime.lowerCanvas)
    runtime.lowerCanvas = nil
    runtime.lastPushAt = nil
    local snapshot
    if adoptTop and runtime.topCanvas and runtime.topValid then
      snapshot = {
        canvas = runtime.topCanvas,
        width = runtime.topWidth,
        height = runtime.topHeight,
        source = runtime.topSource,
      }
      runtime.topCanvas = nil
    else
      release(runtime.topCanvas)
      runtime.topCanvas = nil
    end
    runtime.topWidth, runtime.topHeight = nil, nil
    runtime.topValid, runtime.topSource = false, nil
    return snapshot
  end

  local function setFault(message)
    requestBattleSplit(false)
    restoreStartMenus()
    runtime.faulted = true
    runtime.lastError = tostring(message)
    runtime.pending = nil
    runtime.active = false
    warnOnce("fault:" .. runtime.lastError, runtime.lastError)
    if runtime.bridge and runtime.bridgeRequested == true
        and not runtime.delegated and not externalPresenterActive(mod) then
      bridgeCall(runtime.bridge, "setEnabled", false)
      recordRequest(false)
    end
  end

  local function desired()
    return not runtime.retired and optionEnabled(mod, optionKey)
      and not runtime.faulted
      and not runtime.delegated and not externalPresenterActive(mod)
  end

  local function bindBridge(bridge)
    if runtime.retired then return false, "presenter generation is retired" end
    if runtime.bridge == bridge and ownsBridgeRecord() then return true end
    if runtime.bridge and ownsBridgeRecord() then
      if runtime.bridgeRequested == true and not runtime.delegated
          and not externalPresenterActive(mod) then
        bridgeCall(runtime.bridge, "setEnabled", false)
      end
      setPrivateRecord(runtime.bridge, BRIDGE_RECORD_KEY, nil)
    end
    runtime.bridge = bridge
    runtime.bridgeRecord = nil
    runtime.bridgeRequested = nil
    if type(bridge) ~= "table" then return false, "bridge is unavailable" end

    local previous = privateRecord(bridge, BRIDGE_RECORD_KEY)
    if previous ~= nil and (type(previous) ~= "table"
        or previous.owner ~= mod.id) then
      return false, "secondary display ownership record is unavailable"
    end

    local snapshot
    if type(previous) == "table" and previous.runtime ~= runtime then
      runtime.generation = math.max(1,
        (tonumber(previous.generation) or 0) + 1)
      runtime.bridgeRequested = previous.requested
      if type(previous.retire) ~= "function" then
        return false, "previous presenter cannot retire safely"
      end
      local ok, adopted = pcall(previous.retire, true)
      if not ok then
        return false, "previous presenter retirement failed: "
          .. tostring(adopted)
      end
      snapshot = adopted
    end
    if type(snapshot) == "table" and dimensions(snapshot.canvas) then
      runtime.topCanvas = snapshot.canvas
      runtime.topWidth = positive(snapshot.width)
      runtime.topHeight = positive(snapshot.height)
      runtime.topValid = runtime.topWidth ~= nil and runtime.topHeight ~= nil
      runtime.topSource = runtime.topValid and snapshot.source or nil
      if not runtime.topValid then
        release(runtime.topCanvas)
        runtime.topCanvas = nil
      end
    end

    local record = {
      owner = mod.id,
      apiVersion = ThorDualScreen.API_VERSION,
      generation = runtime.generation,
      runtime = runtime,
      requested = runtime.bridgeRequested,
      retire = retireForHandoff,
    }
    if not setPrivateRecord(bridge, BRIDGE_RECORD_KEY, record) then
      releaseCanvases()
      return false, "secondary display ownership record cannot be published"
    end
    runtime.bridgeRecord = record
    return true
  end

  local function relinquishBridge(bridge)
    runtime.bridge = bridge
    runtime.bridgeRecord = nil
    runtime.bridgeRequested = nil
    local previous = privateRecord(bridge, BRIDGE_RECORD_KEY)
    if type(previous) == "table" and previous.owner == mod.id then
      if previous.runtime ~= runtime and type(previous.retire) == "function" then
        pcall(previous.retire, false)
      else
        releaseCanvases()
      end
      setPrivateRecord(bridge, BRIDGE_RECORD_KEY, nil)
    else
      releaseCanvases()
    end
  end

  local function requestBridge(on)
    local bridge = runtime.bridge
    if runtime.retired or not bridge or not ownsBridgeRecord() then return false end
    if runtime.delegated or externalPresenterActive(mod) then
      -- The bridge is shared process state.  Do not turn it off underneath a
      -- separately installed presenter; simply relinquish our request record.
      recordRequest(nil)
      return false
    end
    on = on == true
    if runtime.bridgeRequested == on then return true end
    if not on and runtime.bridgeRequested == nil then
      recordRequest(false)
      return true
    end
    local ok, err = bridgeCall(bridge, "setEnabled", on)
    if not ok then
      setFault("secondary display enable failed: " .. tostring(err))
      return false
    end
    recordRequest(on)
    return true
  end

  local function ensureLowerCanvas()
    local width, height = dimensions(runtime.lowerCanvas)
    if width == ThorDualScreen.OUTPUT_WIDTH
        and height == ThorDualScreen.OUTPUT_HEIGHT then
      return runtime.lowerCanvas
    end
    local canvas, err = makeCanvas(graphics, ThorDualScreen.OUTPUT_WIDTH,
      ThorDualScreen.OUTPUT_HEIGHT)
    if not canvas then return nil, err end
    release(runtime.lowerCanvas)
    runtime.lowerCanvas = canvas
    return canvas
  end

  local function freshTopCanvas(width, height)
    width, height = integer(width), integer(height)
    if not (width and height) then return nil, "invalid primary dimensions" end
    local currentWidth, currentHeight = dimensions(runtime.topCanvas)
    if currentWidth == width and currentHeight == height then
      return runtime.topCanvas, false
    end
    local canvas, err = makeCanvas(graphics, width, height)
    if not canvas then return nil, err end
    return canvas, true
  end

  local function renderWorldInto(canvas, ctx, source, sourceKind,
      targetWidth, targetHeight)
    local sourceWidth, sourceHeight = dimensions(source)
    local transform = cover(sourceWidth, sourceHeight, targetWidth, targetHeight)
    if not transform then return false, "world surface has no dimensions" end
    local ok, err = graphicsGuard(graphics, function()
      graphics.setCanvas(canvas)
      neutralGraphics(graphics)
      graphics.clear(0, 0, 0, 1)
      if sourceKind == "worldCanvas" and ctx.renderer
          and type(ctx.renderer.blitCanvas) == "function" then
        local zones = ctx.worldZones or ctx.zones
        local drew, drawError = pcall(ctx.renderer.blitCanvas, ctx.renderer,
          source, transform.scaleX, transform.scaleY,
          zones, transform.scaleX, transform.scaleY,
          transform.x, transform.y, 0, 0, targetWidth, targetHeight, 1, 1)
        if not drew then error(drawError, 0) end
      else
        graphics.draw(source, transform.x, transform.y, 0,
          transform.scaleX, transform.scaleY)
      end
    end)
    return ok, err
  end

  local function updateTop(ctx)
    -- Gold/Silver/Crystal draw their world and stack into one public scene.
    -- Once any native UI state is present, keep the last clean overworld frame
    -- above and route the finished native scene below.  Overworld scripts are
    -- paused while these states own the stack, so this is also temporally
    -- faithful; more importantly, it never captures PACK/POKéGEAR/dialogue
    -- back onto the primary panel.
    if runtime.gameGeneration == 2 and topState(mod) ~= nil then
      return runtime.topValid == true
    end
    local source, sourceKind
    if ctx.worldOverride and dimensions(ctx.worldOverride) then
      source, sourceKind = ctx.worldOverride, "worldOverride"
    elseif ctx.worldActive == true and ctx.worldCanvas
        and dimensions(ctx.worldCanvas) then
      source, sourceKind = ctx.worldCanvas, "worldCanvas"
    else
      -- A save can boot directly into a menu before any world frame has been
      -- captured.  The old path refused presentation until the player closed
      -- that menu, which made a saved ON setting look broken even after the
      -- native panel had attached.  A neutral primary surface lets the menu
      -- appear below immediately; the first world frame replaces it normally.
      if runtime.topValid then return true end
      sourceKind = "blank"
    end

    local targetWidth = integer(ctx.pw,
      integer((tonumber(ctx.ww) or 1) * positive(ctx.dpiX, 1), 1))
    local targetHeight = integer(ctx.ph,
      integer((tonumber(ctx.wh) or 1) * positive(ctx.dpiY, 1), 1))
    local canvas, replacementOrError = freshTopCanvas(targetWidth, targetHeight)
    if not canvas then return false, replacementOrError end
    local replacement = replacementOrError == true
    local rendered, renderError
    if sourceKind == "blank" then
      rendered, renderError = graphicsGuard(graphics, function()
        graphics.setCanvas(canvas)
        neutralGraphics(graphics)
        graphics.clear(0, 0, 0, 1)
      end)
    else
      rendered, renderError = renderWorldInto(canvas, ctx, source,
        sourceKind, targetWidth, targetHeight)
    end
    if not rendered then
      if replacement then release(canvas) end
      return false, renderError
    end
    if replacement then
      release(runtime.topCanvas)
      runtime.topCanvas = canvas
    end
    runtime.topWidth, runtime.topHeight = targetWidth, targetHeight
    runtime.topValid = true
    runtime.topSource = sourceKind
    return true
  end

  local function stageLower(ctx)
    local canvas, canvasError = ensureLowerCanvas()
    if not canvas then return false, canvasError end
    local uiWidth = positive(ctx.uiw)
    local uiHeight = positive(ctx.uih)
    if not (uiWidth and uiHeight) and ctx.uiCanvas then
      uiWidth, uiHeight = dimensions(ctx.uiCanvas)
    end
    uiWidth, uiHeight = uiWidth or 160, uiHeight or 144
    local sceneMap = gen2SceneMap(ctx, uiWidth, uiHeight,
      runtime.gameGeneration)
    local gen2State = runtime.gameGeneration == 2 and topState(mod) or nil
    -- An empty Gen 2 stack is the live overworld.  The combined scene is
    -- already shown above, so leave the lower surface clear for render.hud
    -- contributors instead of mirroring the complete world onto both panels.
    local suppressScene = sceneMap ~= nil and gen2State == nil
    local transform = integerContain(uiWidth, uiHeight,
      ThorDualScreen.OUTPUT_WIDTH, ThorDualScreen.OUTPUT_HEIGHT)
    local panel = stackedChoicePanel(mod, uiWidth, uiHeight)
      or activeBattlePanel(mod, uiWidth, uiHeight)
      or ordinaryDialoguePanel(mod, uiWidth, uiHeight)
      or startMenuPanel(mod, uiWidth, uiHeight)
    local drawX, drawY = transform.x, transform.y
    local boxX, boxY = 0, 0
    local boxWidth, boxHeight = ThorDualScreen.OUTPUT_WIDTH,
      ThorDualScreen.OUTPUT_HEIGHT
    if panel and panel.placement == "start" then
      -- Start uses the normal full-surface integer scale (2x on the 400x360
      -- transport), but centers its authored narrow box instead of retaining
      -- the otherwise-empty left side of the 160x144 canvas. Its eight-row
      -- geometry spends the extra room vertically, not by widening the font.
      local scaleX, scaleY = transform.scaleX, transform.scaleY
      local fittedWidth = panel.width * scaleX
      local fittedHeight = panel.height * scaleY
      boxX = math.floor((ThorDualScreen.OUTPUT_WIDTH - fittedWidth) * 0.5)
      boxY = math.floor((ThorDualScreen.OUTPUT_HEIGHT - fittedHeight) * 0.5)
      boxWidth, boxHeight = fittedWidth, fittedHeight
      drawX = boxX - panel.x * scaleX
      drawY = boxY - panel.y * scaleY
      transform = {
        x = drawX, y = drawY,
        width = uiWidth * scaleX, height = uiHeight * scaleY,
        scaleX = scaleX, scaleY = scaleY,
      }
    elseif panel and panel.placement == "stacked_choice" then
      local dialogue, choice = panel.dialogue, panel.choice
      local scaleX, scaleY = transform.scaleX, transform.scaleY
      boxX = transform.x + dialogue.x * scaleX
      boxY = ThorDualScreen.BATTLE_PANEL_TOP
      boxWidth = dialogue.width * scaleX
      boxHeight = (dialogue.height + choice.height) * scaleY
      drawX = boxX - dialogue.x * scaleX
      drawY = boxY - dialogue.y * scaleY
    elseif panel then
      -- Treat the selected source band as one joined control cluster.  The
      -- source canvas origin moves upward while a tight scissor omits the
      -- now-empty battle-picture area; TYPE/PP and moves therefore stay joined
      -- and both battle and ordinary overworld dialogue begin at a small
      -- hinge-side margin.
      drawX = transform.x - panel.x * transform.scaleX
      drawY = ThorDualScreen.BATTLE_PANEL_TOP
        - panel.y * transform.scaleY
      boxX = transform.x
      boxY = ThorDualScreen.BATTLE_PANEL_TOP
      boxWidth = panel.width * transform.scaleX
      boxHeight = panel.height * transform.scaleY
    end
    local ok, err = graphicsGuard(graphics, function()
      graphics.setCanvas(canvas)
      neutralGraphics(graphics)
      graphics.clear(0, 0, 0, 1)
      if panel and panel.placement == "stacked_choice"
          and type(graphics.rectangle) == "function" then
        -- The question supplies its own full-width paper. Only the narrower
        -- answer row needs a paper-colored backing; the rest stays black.
        graphics.setColor(1, 1, 1, 1)
        graphics.rectangle("fill", boxX,
          boxY + panel.dialogue.height * transform.scaleY,
          boxWidth, panel.choice.height * transform.scaleY)
        graphics.setColor(1, 1, 1, 1)
      elseif panel and panel.paper and type(graphics.rectangle) == "function" then
        local paper = panel.paper
        graphics.setColor(1, 1, 1, 1)
        graphics.rectangle("fill",
          drawX + paper.x * transform.scaleX,
          drawY + paper.y * transform.scaleY,
          paper.width * transform.scaleX,
          paper.height * transform.scaleY)
        graphics.setColor(1, 1, 1, 1)
      end
      if panel and panel.placement == "stacked_choice" and ctx.uiCanvas then
        local function drawRegion(region, destinationX, destinationY)
          local regionDrawX = destinationX - region.x * transform.scaleX
          local regionDrawY = destinationY - region.y * transform.scaleY
          local regionWidth = region.width * transform.scaleX
          local regionHeight = region.height * transform.scaleY
          if sceneMap then
            local sceneScaleX = transform.scaleX / sceneMap.scale
            local sceneScaleY = transform.scaleY / sceneMap.scale
            if type(graphics.setScissor) == "function" then
              graphics.setScissor(destinationX, destinationY,
                regionWidth, regionHeight)
            end
            graphics.draw(ctx.uiCanvas,
              regionDrawX - sceneMap.x * sceneScaleX,
              regionDrawY - sceneMap.y * sceneScaleY,
              0, sceneScaleX, sceneScaleY)
            if type(graphics.setScissor) == "function" then
              graphics.setScissor()
            end
          elseif ctx.renderer and type(ctx.renderer.blitCanvas) == "function" then
            local drew, drawError = pcall(ctx.renderer.blitCanvas, ctx.renderer,
              ctx.uiCanvas, transform.scaleX, transform.scaleY,
              ctx.zones, transform.scaleX, transform.scaleY,
              regionDrawX, regionDrawY,
              destinationX, destinationY, regionWidth, regionHeight, 1, 1)
            if not drew then error(drawError, 0) end
          else
            if type(graphics.setScissor) == "function" then
              graphics.setScissor(destinationX, destinationY,
                regionWidth, regionHeight)
            end
            graphics.draw(ctx.uiCanvas, regionDrawX, regionDrawY, 0,
              transform.scaleX, transform.scaleY)
            if type(graphics.setScissor) == "function" then
              graphics.setScissor()
            end
          end
        end
        drawRegion(panel.dialogue, boxX, boxY)
        drawRegion(panel.choice,
          boxX + boxWidth - panel.choice.width * transform.scaleX,
          boxY + panel.dialogue.height * transform.scaleY)
      elseif ctx.uiCanvas and not sceneMap and ctx.renderer
          and type(ctx.renderer.blitCanvas) == "function" then
        local drew, drawError = pcall(ctx.renderer.blitCanvas, ctx.renderer,
          ctx.uiCanvas, transform.scaleX, transform.scaleY,
          ctx.zones, transform.scaleX, transform.scaleY,
          drawX, drawY,
          boxX, boxY, boxWidth, boxHeight, 1, 1)
        if not drew then error(drawError, 0) end
      elseif ctx.uiCanvas then
        local clipX, clipY, clipWidth, clipHeight = boxX, boxY,
          boxWidth, boxHeight
        if sceneMap and not panel then
          clipX, clipY = transform.x, transform.y
          clipWidth, clipHeight = transform.width, transform.height
        end
        if (panel or sceneMap) and type(graphics.setScissor) == "function" then
          graphics.setScissor(clipX, clipY, clipWidth, clipHeight)
        end
        if not suppressScene and sceneMap then
          local sceneScaleX = transform.scaleX / sceneMap.scale
          local sceneScaleY = transform.scaleY / sceneMap.scale
          graphics.draw(ctx.uiCanvas,
            drawX - sceneMap.x * sceneScaleX,
            drawY - sceneMap.y * sceneScaleY,
            0, sceneScaleX, sceneScaleY)
        elseif not suppressScene then
          graphics.draw(ctx.uiCanvas, drawX, drawY, 0,
            transform.scaleX, transform.scaleY)
        end
        if (panel or sceneMap) and type(graphics.setScissor) == "function" then
          graphics.setScissor()
        end
      end
    end)
    if not ok then return false, err end
    return true, {
      width = ThorDualScreen.OUTPUT_WIDTH,
      height = ThorDualScreen.OUTPUT_HEIGHT,
      gameX = drawX,
      gameY = drawY,
      gameWidth = transform.width,
      gameHeight = transform.height,
      scale = transform.scaleX,
      dpiX = 1,
      dpiY = 1,
      generation = runtime.gameGeneration,
      safeX = 0,
      safeY = 0,
      safeWidth = ThorDualScreen.OUTPUT_WIDTH,
      safeHeight = ThorDualScreen.OUTPUT_HEIGHT,
      safe = {
        x = 0, y = 0,
        width = ThorDualScreen.OUTPUT_WIDTH,
        height = ThorDualScreen.OUTPUT_HEIGHT,
      },
      fullSafe = {
        x = 0, y = 0,
        width = ThorDualScreen.OUTPUT_WIDTH,
        height = ThorDualScreen.OUTPUT_HEIGHT,
      },
      game = {
        x = drawX, y = drawY,
        width = transform.width, height = transform.height,
      },
      _scottsTweaksThorLower = true,
      _scottsTweaksThorNativeGen2 = sceneMap ~= nil and gen2State ~= nil,
      _scottsTweaksThorPanel = panel and {
        phase = panel.phase,
        kind = panel.kind,
        sourceX = panel.x,
        sourceY = panel.y,
        sourceWidth = panel.width,
        sourceHeight = panel.height,
        top = boxY,
      } or nil,
      _scottsTweaksThorBattlePanel = panel and panel.phase and {
        phase = panel.phase,
        sourceY = panel.y,
        sourceHeight = panel.height,
        top = boxY,
      } or nil,
    }
  end

  local function drawTop(ctx)
    local dpiX, dpiY = positive(ctx.dpiX, 1), positive(ctx.dpiY, 1)
    local windowWidth = positive(ctx.ww,
      runtime.topWidth and runtime.topWidth / dpiX or nil)
    local windowHeight = positive(ctx.wh,
      runtime.topHeight and runtime.topHeight / dpiY or nil)
    if not (runtime.topCanvas and runtime.topValid and windowWidth
        and windowHeight) then
      return false, "no live or frozen world surface is available"
    end
    local effect = animationSurface(mod)
    return graphicsGuard(graphics, function()
      if type(graphics.setCanvas) == "function" then graphics.setCanvas() end
      neutralGraphics(graphics)
      graphics.clear(0, 0, 0, 1)
      if type(graphics.setScissor) == "function" then
        graphics.setScissor(0, 0, windowWidth, windowHeight)
      end
      graphics.draw(runtime.topCanvas, 0, 0, 0, 1 / dpiX, 1 / dpiY)
      if effect then
        local transform = cover(effect.pw, effect.ph,
          runtime.topWidth, runtime.topHeight)
        if transform then
          graphics.draw(effect.canvas,
            (transform.x + effect.lx * transform.scaleX) / dpiX,
            (transform.y + effect.ly * transform.scaleY) / dpiY,
            0,
            effect.scale * transform.scaleX / dpiX,
            effect.scale * transform.scaleY / dpiY)
        end
      end
      if type(graphics.setScissor) == "function" then graphics.setScissor() end
    end)
  end

  local function shouldPush()
    local timestamp = now()
    if not finite(timestamp) then return true, nil end
    local interval = 1 / ThorDualScreen.PUSH_HZ
    if runtime.lastPushAt == nil or timestamp < runtime.lastPushAt
        or timestamp - runtime.lastPushAt + 1e-9 >= interval then
      return true, timestamp
    end
    return false, timestamp
  end

  local function pushLower()
    local due, timestamp = shouldPush()
    if not due then return true end
    local canvas = runtime.lowerCanvas
    if not canvas or type(canvas.newImageData) ~= "function" then
      return false, "lower display readback is unavailable"
    end
    local okData, imageData = pcall(canvas.newImageData, canvas)
    if not okData or not imageData then
      return false, "lower display readback failed: " .. tostring(imageData)
    end
    local okPush, pushedOrError = bridgeCall(runtime.bridge, "push", imageData,
      ThorDualScreen.OUTPUT_WIDTH, ThorDualScreen.OUTPUT_HEIGHT)
    release(imageData)
    if not okPush or pushedOrError == false then
      return false, "lower display push failed: " .. tostring(pushedOrError)
    end
    runtime.lastPushAt = timestamp
    return true
  end

  local function routeWorldOverlay(provider, owner)
    if not runtime.worldOverlayRouteLive or runtime.retired
        or not runtime.active
        or runtime.generation ~= runtime.worldOverlayRouteGeneration
        or runtime.bridge ~= runtime.worldOverlayRouteBridge
        or not validWorldOverlay(provider) then
      return false
    end
    if runtime.worldOverlayProvider ~= nil
        and runtime.worldOverlayProvider ~= provider then
      return false
    end
    runtime.worldOverlayProvider = provider
    runtime.worldOverlayOwner = type(owner) == "string"
      and owner or "world overlay"
    return true
  end

  local function drawWorldOverlay(game, viewport, provider, owner)
    if not validWorldOverlay(provider) then return true end
    local ok, err = graphicsGuard(graphics, function()
      if type(graphics.setCanvas) == "function" then graphics.setCanvas() end
      neutralGraphics(graphics)
      -- Validate again at the consumption boundary: an F5-capable provider
      -- may replace its export while the downstream HUD chain is running.
      if validWorldOverlay(provider) then
        local drew, drawError = pcall(provider.draw, game, viewport,
          PRIMARY_WORLD_OVERLAY_OPTIONS)
        if not drew then
          warnOnce("world-overlay:" .. tostring(owner),
            tostring(owner) .. " upper overlay failed: "
              .. tostring(drawError))
        end
      end
    end)
    return ok, err
  end

  local composeHook = function(nextFn, renderer, ctx)
    if runtime.retired then return nextFn(renderer, ctx) end
    runtime.pending = nil
    runtime.active = false
    ctx = type(ctx) == "table" and ctx or {}
    runtime.gameGeneration = gameGeneration(mod, ctx)
    runtime.compatibilityFallback = nil
    if externalPresenterActive(mod) then
      -- Ownership is sticky for this entry/boot.  If the legacy presenter is
      -- removed during a developer hot reload we still do not race its old
      -- wrappers or shared native bridge; a fresh entry owns the next boot.
      runtime.delegated = true
      runtime.bridgeRequested = nil
      requestBattleSplit(false)
    end
    local bound, bindError
    if runtime.delegated then
      relinquishBridge(ctx.secondScreen)
    else
      bound, bindError = bindBridge(ctx.secondScreen)
    end
    local physicalReady = bound and optionEnabled(mod, optionKey)
      and not runtime.faulted and not runtime.delegated
      and not externalPresenterActive(mod)
      and bridgeAvailable(runtime.bridge)
    if physicalReady then
      -- screen.pushed normally configured this before its first draw.  This
      -- lazy path covers a Start menu that was already open while Android's
      -- asynchronous Presentation attach completed; it becomes ready after
      -- the current (still ordinary-geometry) frame is safely staged.
      configureStartMenu(topState(mod), false)
    else
      restoreStartMenus()
    end
    local downstream = nextFn(renderer, ctx)
    if downstream == true then
      requestBattleSplit(false)
      return true
    end

    if runtime.delegated then
      requestBattleSplit(false)
      runtime.bridgeRequested = nil
      return downstream
    end
    if not bound then
      requestBattleSplit(false)
      if bindError and ctx.secondScreen ~= nil then
        setFault("secondary display handoff failed: " .. tostring(bindError))
      end
      return downstream
    end
    if not optionEnabled(mod, optionKey) then
      requestBattleSplit(false)
      requestBridge(false)
      return downstream
    end
    if runtime.faulted then
      requestBattleSplit(false)
      return downstream
    end

    if runtime.gameGeneration == 2 then
      local state = topState(mod)
      local fallback
      if gen2BattleActive(mod) then
        fallback = "gen2_battle_uses_stock_single_screen"
      elseif gen2SingleScreenActive(mod) then
        fallback = "gen2_primary_scene_uses_stock_single_screen"
      elseif state ~= nil and not runtime.topValid then
        -- Never manufacture a primary world from a combined scene that
        -- already contains PACK/POKéGEAR/dialogue.  One clean overworld frame
        -- is enough to arm native-menu routing on the next opening.
        fallback = "gen2_waiting_for_clean_world"
      elseif state == nil and ctx.worldActive ~= true then
        fallback = "gen2_non_world_screen"
      end
      if fallback then
        runtime.compatibilityFallback = fallback
        requestBattleSplit(false)
        requestBridge(false)
        return downstream
      end
    end
    -- Android creates its Presentation only after setEnabled(true).  Asking
    -- available() first deadlocked a cold boot: false prevented the enable
    -- request, so only a manual OFF/ON option change could ever attach it.
    -- Issue the saved ON request once as soon as the compose seam publishes
    -- its bridge; availability may turn true later on Android's UI thread.
    if not requestBridge(true) then
      requestBattleSplit(false)
      return downstream
    end
    if not bridgeAvailable(runtime.bridge) then
      requestBattleSplit(false)
      -- Keep the already-issued native enable request latched across a
      -- physical hot-unplug. Android's Presentation bridge will resume that
      -- same request when the panel returns; toggling it here both spams the
      -- transport and defeats the existing automatic-replug contract.
      return downstream
    end

    -- Arm Battle Stage v3 one frame before taking over composition. The frame
    -- that reached this hook was already drawn, so publishing it immediately
    -- would still contain the old move/pic layers on the lower panel. Falling
    -- through once lets the next engine draw produce the clean UI-only canvas;
    -- v2 providers simply skip this optional warm-up.
    local splitWasReady = runtime.splitRequested == true
    local splitReady = requestBattleSplit(true)
    if splitReady and not splitWasReady then return downstream end

    local topReady, topError = updateTop(ctx)
    if not topReady then
      requestBattleSplit(false)
      if topError then setFault("top surface failed: " .. tostring(topError)) end
      return downstream
    end
    local lowerReady, lowerViewportOrError = stageLower(ctx)
    if not lowerReady then
      requestBattleSplit(false)
      setFault("lower surface failed: " .. tostring(lowerViewportOrError))
      return downstream
    end
    markStartMenuReady(topState(mod))
    local topDrawn, topDrawError = drawTop(ctx)
    if not topDrawn then
      requestBattleSplit(false)
      setFault("primary presentation failed: " .. tostring(topDrawError))
      return downstream
    end

    runtime.pending = {
      bridge = runtime.bridge,
      viewport = lowerViewportOrError,
    }
    runtime.active = true
    return true
  end

  local hudHook = function(nextFn, game, viewport)
    if runtime.retired then return nextFn(game, viewport) end
    local pending = runtime.pending
    runtime.pending = nil
    if not pending or not runtime.active or not desired()
        or pending.bridge ~= runtime.bridge
        or not bridgeAvailable(runtime.bridge) then
      runtime.active = false
      return nextFn(game, viewport)
    end
    -- HUD hooks run against the lower canvas, but a small subset of their
    -- output can semantically belong to the player/world. Give those hooks a
    -- one-frame deferred route. The callback closes over this presenter
    -- generation and is invalidated immediately after the downstream chain,
    -- so landing, unplug, OFF, quit and F5 can never replay a stale mount.
    runtime.worldOverlayRouteLive = true
    runtime.worldOverlayRouteGeneration = runtime.generation
    runtime.worldOverlayRouteBridge = pending.bridge
    runtime.worldOverlayProvider = nil
    runtime.worldOverlayOwner = nil
    pending.viewport[WORLD_OVERLAY_ROUTE_KEY] = routeWorldOverlay
    local downstream
    local captured, captureError = graphicsGuard(graphics, function()
      graphics.setCanvas(runtime.lowerCanvas)
      neutralGraphics(graphics)
      downstream = pack(nextFn(game, pending.viewport))
    end)
    runtime.worldOverlayRouteLive = false
    runtime.worldOverlayRouteGeneration = nil
    runtime.worldOverlayRouteBridge = nil
    pending.viewport[WORLD_OVERLAY_ROUTE_KEY] = nil
    local overlayProvider = runtime.worldOverlayProvider
    local overlayOwner = runtime.worldOverlayOwner
    runtime.worldOverlayProvider = nil
    runtime.worldOverlayOwner = nil
    if not captured then
      setFault("lower HUD capture failed: " .. tostring(captureError))
      -- nextFn may already have run before a post-draw graphics error.  Never
      -- run a stateful HUD chain twice in one frame.
      if downstream then return unpackValues(downstream, 1, downstream.n) end
      return nextFn(game, viewport)
    end
    local overlaid, overlayError = drawWorldOverlay(game, viewport,
      overlayProvider, overlayOwner)
    if not overlaid then
      warnOnce("world-overlay-presentation",
        "upper world overlay presentation failed: " .. tostring(overlayError))
    end
    local pushed, pushError = pushLower()
    if not pushed then setFault(pushError) end
    if downstream then return unpackValues(downstream, 1, downstream.n) end
  end

  local hookRecord
  local eventRecord

  local function shutdown()
    if runtime.retired then return end
    -- A second install on one facade refreshes its dispatcher.  Releasing a
    -- stale controller must never tear down the newer generation.
    if hookRecord and hookRecord.runtime ~= runtime then
      retireForHandoff(false)
      return
    end
    if runtime.bridgeRequested == true and ownsBridgeRecord()
        and not runtime.delegated and not externalPresenterActive(mod) then
      bridgeCall(runtime.bridge, "setEnabled", false)
    end
    recordRequest(false)
    if ownsBridgeRecord() then
      setPrivateRecord(runtime.bridge, BRIDGE_RECORD_KEY, nil)
    end
    releaseCanvases()
    runtime.retired = true
  end

  local quitHook = function(nextFn, ...)
    shutdown()
    return nextFn(...)
  end

  assert(mod.hooks and type(mod.hooks.wrap) == "function",
    "Thor Dual Screen needs render hooks")
  hookRecord = privateRecord(mod.hooks, HOOK_RECORD_KEY)
  if hookRecord ~= nil and (type(hookRecord) ~= "table"
      or hookRecord.owner ~= mod.id or hookRecord.dispatcher ~= true) then
    error("Thor Dual Screen hook dispatcher is owned by another feature", 0)
  end
  if not hookRecord then
    hookRecord = {
      owner = mod.id,
      dispatcher = true,
      generation = 0,
      callbacks = {},
    }
    assert(setPrivateRecord(mod.hooks, HOOK_RECORD_KEY, hookRecord),
      "Thor Dual Screen cannot publish its hook dispatcher")
    mod.hooks:wrap("render.compose", function(nextFn, renderer, ctx)
      local callback = hookRecord.callbacks.compose
      if callback then return callback(nextFn, renderer, ctx) end
      return nextFn(renderer, ctx)
    end, ThorDualScreen.COMPOSE_PRIORITY)
    mod.hooks:wrap("render.hud", function(nextFn, game, viewport)
      local callback = hookRecord.callbacks.hud
      if callback then return callback(nextFn, game, viewport) end
      return nextFn(game, viewport)
    end, ThorDualScreen.HUD_PRIORITY)
    mod.hooks:wrap("core.quit_to_launcher", function(nextFn, ...)
      local callback = hookRecord.callbacks.quit
      if callback then return callback(nextFn, ...) end
      return nextFn(...)
    end, ThorDualScreen.COMPOSE_PRIORITY)
  end
  hookRecord.generation = (tonumber(hookRecord.generation) or 0) + 1
  hookRecord.runtime = runtime
  hookRecord.callbacks.compose = composeHook
  hookRecord.callbacks.hud = hudHook
  hookRecord.callbacks.quit = quitHook

  local function optionChanged(payload)
    if runtime.retired or type(payload) ~= "table" or payload.mod ~= mod.id
        or payload.key ~= optionKey then return end
    if enabledValue(payload.value) then
      runtime.faulted = false
      runtime.lastError = nil
      runtime.warned = {}
      requestBridge(true)
    else
      requestBridge(false)
      releaseCanvases()
    end
  end

  local function screenPushed(payload)
    if runtime.retired or type(payload) ~= "table" then return end
    if desired() and bridgeAvailable(runtime.bridge) then
      -- This event runs after construction but before the state's first draw,
      -- so the smaller visible window and its scroll calculation are already
      -- authoritative when the Start menu reaches uiCanvas.
      configureStartMenu(payload.state, true)
    end
  end

  local function screenPopped(payload)
    if type(payload) == "table" then restoreStartMenu(payload.state) end
  end

  if mod.events and type(mod.events.on) == "function" then
    eventRecord = privateRecord(mod.events, EVENT_RECORD_KEY)
    local inheritedEventRecord = eventRecord ~= nil
    if eventRecord ~= nil and (type(eventRecord) ~= "table"
        or eventRecord.owner ~= mod.id or eventRecord.dispatcher ~= true) then
      error("Thor Dual Screen event dispatcher is owned by another feature", 0)
    end
    if not eventRecord then
      eventRecord = {
        owner = mod.id,
        dispatcher = true,
        generation = 0,
      }
      assert(setPrivateRecord(mod.events, EVENT_RECORD_KEY, eventRecord),
        "Thor Dual Screen cannot publish its event dispatcher")
    end
    -- A 0.12.5 -> current F5 can encounter the prior one-event dispatcher.
    -- Add each missing public-event listener exactly once on that same bus.
    if inheritedEventRecord and eventRecord.optionsListener == nil then
      -- Every prior Scott presenter record installed this one listener.
      eventRecord.optionsListener = true
    end
    if not eventRecord.optionsListener then
      mod.events:on("mod.options_changed", function(payload)
        local callback = eventRecord.callback
        if callback then return callback(payload) end
      end)
      eventRecord.optionsListener = true
    end
    if not eventRecord.screenPushedListener then
      mod.events:on("screen.pushed", function(payload)
        local callback = eventRecord.screenPushed
        if callback then return callback(payload) end
      end)
      eventRecord.screenPushedListener = true
    end
    if not eventRecord.screenPoppedListener then
      mod.events:on("screen.popped", function(payload)
        local callback = eventRecord.screenPopped
        if callback then return callback(payload) end
      end)
      eventRecord.screenPoppedListener = true
    end
    eventRecord.generation = (tonumber(eventRecord.generation) or 0) + 1
    eventRecord.runtime = runtime
    eventRecord.callback = optionChanged
    eventRecord.screenPushed = screenPushed
    eventRecord.screenPopped = screenPopped
  end

  local public = {
    apiVersion = ThorDualScreen.API_VERSION,
    controllerOnly = true,
    getEnabled = function() return optionEnabled(mod, optionKey) end,
    getMode = function()
      return optionEnabled(mod, optionKey) and "on" or "off"
    end,
    secondDisplayAttached = function()
      return bridgeAvailable(runtime.bridge)
    end,
    getStatus = function() return cloneStatus(runtime, mod, optionKey) end,
  }
  mod.exports = type(mod.exports) == "table" and mod.exports or {}
  mod.exports.thorDualScreen = public

  return {
    apiVersion = ThorDualScreen.API_VERSION,
    exports = public,
    status = public.getStatus,
    release = function()
      shutdown()
      if hookRecord and hookRecord.runtime == runtime then
        hookRecord.callbacks.compose = nil
        hookRecord.callbacks.hud = nil
        hookRecord.callbacks.quit = nil
      end
      if eventRecord and eventRecord.runtime == runtime then
        eventRecord.callback = nil
        eventRecord.screenPushed = nil
        eventRecord.screenPopped = nil
      end
    end,
  }
end

ThorDualScreen.cover = cover
ThorDualScreen.contain = contain
ThorDualScreen.integerContain = integerContain
ThorDualScreen.enabledValue = enabledValue
ThorDualScreen.battlePanelRegion = battlePanelRegion

return ThorDualScreen
