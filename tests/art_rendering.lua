-- Focused regressions for authored sprite transparency, independent battle
-- orientation controls, and Android/AYN logical-pixel sprite canvases.
-- Run with LuaJIT 2.1 or Lua 5.1:
--   luajit tests/art_rendering.lua <mod-root>

local argv = rawget(_G, "arg") or {}
local root = (argv[1] or "."):gsub("\\", "/"):gsub("/$", "")

local checks = 0
local function check(value, message)
  checks = checks + 1
  if not value then error(("check %d failed: %s"):format(checks, message), 0) end
end

local function eq(actual, expected, message)
  check(actual == expected, ("%s (expected %s, got %s)")
    :format(message, tostring(expected), tostring(actual)))
end

local function read(relative)
  local file = assert(io.open(root .. "/" .. relative, "rb"),
    "missing " .. relative)
  local body = file:read("*a")
  file:close()
  return body
end

-- BattlePics used to be wrapped once by Crystal with a predicate that closed
-- over that entry's weak image table. BattlePics survives a developer F5;
-- Crystal does not, so the wrapper then saw every freshly-created image as
-- ordinary ROM art and sealed its transparent limb gaps white. The provider
-- registry must replace the predicate under the same id, not stack it.
local BattlePics = assert(loadfile(root .. "/lib/BattlePics.lua"))({})
local oldImage, newImage, otherImage = {}, {}, {}
local oldGeneration = setmetatable({ [oldImage] = true }, { __mode = "k" })
local newGeneration = setmetatable({ [newImage] = true }, { __mode = "k" })

eq(BattlePics.registerTransparentProvider("crystal", function(img)
  return oldGeneration[img] == true
end), true, "Crystal registers its authored-alpha provider")
eq(BattlePics.preservesAuthoredTransparency(oldImage), true,
  "the current Crystal generation keeps authored transparent gaps")
eq(BattlePics.filled(oldImage, true), oldImage,
  "authored RGBA bypasses ROM paper reconstruction")
eq(BattlePics.preservesAuthoredTransparency(newImage), false,
  "a not-yet-registered generation is not guessed by image shape")

eq(BattlePics.registerTransparentProvider("crystal", function(img)
  return newGeneration[img] == true
end), true, "F5 refreshes the stable provider registration")
eq(BattlePics.preservesAuthoredTransparency(oldImage), false,
  "the stale weak-table predicate is replaced rather than retained")
eq(BattlePics.preservesAuthoredTransparency(newImage), true,
  "fresh Crystal frames retain authored alpha after F5")
eq(BattlePics.filled(newImage, true), newImage,
  "fresh frames cannot acquire white seams from the ROM fill path")

eq(BattlePics.registerTransparentProvider("broken", function()
  error("provider fault")
end), true, "a second authored-alpha provider can register")
eq(BattlePics.preservesAuthoredTransparency(newImage), true,
  "one faulty provider cannot disable a healthy provider")
eq(BattlePics.preservesAuthoredTransparency(otherImage), false,
  "unclaimed images still use the native ROM-paper policy")
eq(BattlePics.unregisterTransparentProvider("broken"), true,
  "a provider can release its registration")
eq(BattlePics.unregisterTransparentProvider("broken"), false,
  "releasing an absent provider is harmless")

-- The player front retains its historical saved values. Opponent and player
-- back cards have separate authored/flipped ladders, so fixing one direction
-- cannot silently turn the other card or a trainer portrait.
local Setting = {}
function Setting.new(key, label, values, labels, defaultIndex)
  local setting = {
    key = key, label = label, values = values, labels = labels,
    index = defaultIndex or 1,
  }
  function setting:get() return self.values[self.index] end
  function setting:setIndex(index)
    self.index = index
    return self:get()
  end
  return setting
end

local BattleArt = assert(loadfile(root .. "/lib/BattleArt.lua"))({
  require = function(name)
    assert(name == "ModSetting", "unexpected BattleArt dependency: " .. tostring(name))
    return Setting
  end,
  data = function() return {} end,
  mod = { id = "voxel_run_bridge" },
})

eq(BattleArt.frontFlipSetting.key, "frontFlip",
  "the historical player-front save key remains stable")
eq(BattleArt.frontFlipSetting:get(), "battle_art",
  "ordinary player-front art keeps the established face-opponent default")
eq(BattleArt.opponentFlipSetting.key, "opponentFlip",
  "opponent orientation has an independent save key")
eq(BattleArt.backFlipSetting.key, "backFlip",
  "player-back orientation has an independent save key")
eq(BattleArt.flipsOpponent(), false,
  "opponent art is authored-direction by default")
eq(BattleArt.flipsPlayerBack(), false,
  "player back art is authored-direction by default")
BattleArt.opponentFlipSetting:setIndex(2)
eq(BattleArt.flipsOpponent(), true,
  "the opponent control mirrors only when selected")
eq(BattleArt.flipsPlayerBack(), false,
  "opponent selection does not alter player back orientation")
BattleArt.backFlipSetting:setIndex(2)
eq(BattleArt.flipsPlayerBack(), true,
  "the player-back control mirrors only when selected")
eq(BattleArt.flipsPlayerFront(), true,
  "new controls do not change the historical player-front policy")

-- The BASIC Pokemon shortcuts may update more than one ownership key. Use
-- the real ModSetting transaction so a failed device write cannot commit one
-- side, leave another cached, or report a profile that disk never accepted.
local settingsMod = { id = "voxel_run_bridge" }
local ModSetting = assert(loadfile(root .. "/lib/ModSetting.lua"))({
  mod = settingsMod,
})
local sourceA = ModSetting.new("sourceA", "SOURCE A",
  { "authored", "modded" }, { "AUTHORED", "MODDED" })
local sourceB = ModSetting.new("sourceB", "SOURCE B",
  { "authored", "modded" }, { "AUTHORED", "MODDED" })
local savedArt = { sourceA = "authored", sourceB = "authored" }
local liveArt = { sourceA = "authored", sourceB = "authored" }
local artWrites = 0
local settingsGame = {
  save = { options = { modOptions = { voxel_run_bridge = savedArt } } },
  mods = { modOptions = { voxel_run_bridge = liveArt } },
  writeOptions = function()
    artWrites = artWrites + 1
    return false, "simulated read-only storage"
  end,
}
local changed, changeError = sourceA:setIndex(2, settingsGame)
eq(changed, nil, "a failed sprite setting reports no applied value")
check(tostring(changeError):find("read-only storage", 1, true) ~= nil,
  "a failed sprite setting returns its persistence error")
eq(settingsGame.save.options.modOptions.voxel_run_bridge, savedArt,
  "single-setting rollback preserves the save bucket identity")
eq(settingsGame.mods.modOptions.voxel_run_bridge, liveArt,
  "single-setting rollback preserves the live bucket identity")
eq(sourceA:get(), "authored",
  "single-setting rollback restores the cached setting index")
eq(savedArt.sourceA, "authored",
  "single-setting rollback restores the saved value")
eq(liveArt.sourceA, "authored",
  "single-setting rollback restores the live value")

local beforeProfileWrite = artWrites
local profileOk, profileError = ModSetting.transaction({
  { setting = sourceA, index = 2 },
  { setting = sourceB, index = 2 },
}, settingsGame)
eq(profileOk, false, "a failed two-sided ownership profile reports failure")
check(tostring(profileError):find("read-only storage", 1, true) ~= nil,
  "a failed ownership profile returns its persistence error")
eq(artWrites, beforeProfileWrite + 1,
  "a multi-setting ownership profile attempts one durable write")
eq(sourceA:get(), "authored",
  "profile rollback restores the first cached ownership value")
eq(sourceB:get(), "authored",
  "profile rollback restores the second cached ownership value")
eq(savedArt.sourceA, "authored",
  "profile rollback restores the first saved ownership value")
eq(savedArt.sourceB, "authored",
  "profile rollback restores the second saved ownership value")

settingsGame.writeOptions = function() artWrites = artWrites + 1 end
local beforeProfileSuccess = artWrites
eq(ModSetting.transaction({
  { setting = sourceA, index = 2 },
  { setting = sourceB, index = 2 },
}, settingsGame), true, "a durable ownership profile applies atomically")
eq(artWrites, beforeProfileSuccess + 1,
  "a successful ownership profile persists exactly once")
eq(savedArt.sourceA, "modded",
  "successful profile stores the first ownership value")
eq(savedArt.sourceB, "modded",
  "successful profile stores the second ownership value")
eq(liveArt.sourceA, "modded",
  "successful profile updates the first live ownership value")
eq(liveArt.sourceB, "modded",
  "successful profile updates the second live ownership value")

-- The integrated BASIC shortcuts span Crystal's top-level preferences and
-- Battle Art's namespaced ownership keys. Exercise the real SpriteMenu and
-- SpriteControl modules with no standalone hub: one failed write must leave
-- both providers on the old coherent profile and invoke no runtime callback.
local txGame
settingsMod.options = { get = function(_, key)
  local bucket = txGame and txGame.mods and txGame.mods.modOptions
    and txGame.mods.modOptions.voxel_run_bridge
  return bucket and bucket[key]
end }
local TxBattleArt = assert(loadfile(root .. "/lib/BattleArt.lua"))({
  require = function(name)
    assert(name == "ModSetting", "unexpected transactional BattleArt dependency")
    return ModSetting
  end,
  data = function() return {} end,
  mod = settingsMod,
})
local TxSpriteControl = assert(loadfile(root .. "/lib/SpriteControl.lua"))({
  require = function(name)
    if name == "BattleArt" then return TxBattleArt end
    if name == "ModSetting" then return ModSetting end
    if name == "AnimatedBattleArt" then
      return { releasePlayerTrainer = function() end }
    end
    error("unexpected SpriteControl dependency: " .. tostring(name))
  end,
})
local crystalRuntimeCalls = {}
local crystalRuntimePlayer = "red.png"
local failCrystalPlayer
local crystalHandle = { version = "2.0.0", exports = {
  applyOption = function(key, value)
    crystalRuntimeCalls[#crystalRuntimeCalls + 1] = { key, value }
    if key == "crystalPlayerSprite" then
      crystalRuntimePlayer = value
      if failCrystalPlayer and value == failCrystalPlayer then
        error("simulated Crystal player refresh failure")
      end
    end
  end,
  playerSprite = function() return crystalRuntimePlayer end,
  listPlayerSprites = function() return { "red.png", "blue_flip.png" } end,
} }
local spriteMod = {
  id = "voxel_run_bridge",
  find = function(id)
    if id == "crystal_animated_sprites_with_shiny_visuals" then
      return crystalHandle
    end
    return nil
  end,
}
local TxSpriteMenu = assert(loadfile(root .. "/lib/SpriteMenu.lua"))({
  mod = spriteMod,
  require = function(name)
    if name == "BattleArt" then return TxBattleArt end
    if name == "ModSetting" then return ModSetting end
    if name == "SpriteControl" then return TxSpriteControl end
    error("unexpected SpriteMenu dependency: " .. tostring(name))
  end,
})
local txSaved = {
  battleArt = "animated", opponentTrainerSource = "modded",
  playerTrainerSource = "modded", playerView = "back",
}
local txLive = {
  battleArt = "animated", opponentTrainerSource = "modded",
  playerTrainerSource = "modded", playerView = "back",
}
local txWrites = 0
txGame = {
  save = { options = {
    crystalTrainers = "both", crystalFront = false,
    modOptions = { voxel_run_bridge = txSaved },
  } },
  mods = { modOptions = { voxel_run_bridge = txLive } },
  writeOptions = function()
    txWrites = txWrites + 1
    return false, "simulated second-stage failure"
  end,
}
TxBattleArt.setting:sync("animated")
TxBattleArt.opponentTrainerSourceSetting:sync("modded")
TxBattleArt.playerTrainerSourceSetting:sync("modded")
TxBattleArt.viewSetting:sync("back")
local txMenu = TxSpriteMenu.new()

-- In the fused build these imported Battle Art rows live under the real root
-- Loader id, not the historical renderer id. An explicit modern flip must win
-- over the retained Sprite Hub rollback bucket, and root option events must
-- drive the same reconciliation path as standalone Battle Art events.
txSaved.frontFlip = "battle_art"
txLive.frontFlip = "battle_art"
txGame.save.options.modOptions.scotts_sprite_hub = {
  playerFrontFlip = false,
}
txGame.mods.modOptions.scotts_sprite_hub = {
  playerFrontFlip = false,
}
eq(txMenu:migrateLegacyFlip(txGame), false,
  "legacy flip migration preserves an explicit fused-root choice")
eq(txSaved.frontFlip, "battle_art",
  "legacy flip migration does not overwrite the fused saved value")
eq(txLive.frontFlip, "battle_art",
  "legacy flip migration does not overwrite the fused live value")
local originalEnforce = txMenu.enforce
local rootEventEnforces = 0
txMenu.game = txGame
txMenu.enforce = function()
  rootEventEnforces = rootEventEnforces + 1
  return true
end
txMenu:onOptionsChanged({ mod = "voxel_run_bridge", key = "frontFlip" })
txMenu:onOptionsChanged({ mod = "BATTLE_ART_VOXEL_FORK", key = "frontFlip" })
eq(rootEventEnforces, 2,
  "fused and historical Battle Art events both reconcile sprite ownership")
txMenu.enforce = originalEnforce

local trainerOk, trainerError = txMenu:setTrainerSource(txGame, "battle_art")
eq(trainerOk, false,
  "combined trainer-source shortcut reports its failed durable write")
check(tostring(trainerError):find("second-stage failure", 1, true) ~= nil,
  "combined trainer-source shortcut returns the persistence detail")
eq(txWrites, 1, "combined trainer-source shortcut attempts one write")
eq(txGame.save.options.crystalTrainers, "both",
  "failed trainer shortcut restores Crystal's saved mode")
eq(txSaved.opponentTrainerSource, "modded",
  "failed trainer shortcut restores opponent ownership")
eq(txSaved.playerTrainerSource, "modded",
  "failed trainer shortcut restores player ownership")
eq(txLive.opponentTrainerSource, "modded",
  "failed trainer shortcut restores live opponent ownership")
eq(TxBattleArt.opponentTrainerSourceSetting:get(), "modded",
  "failed trainer shortcut restores cached ownership")
eq(#crystalRuntimeCalls, 0,
  "failed trainer shortcut never changes Crystal runtime")

txGame.writeOptions = function() txWrites = txWrites + 1 end
local beforeTrainerSuccess = txWrites
eq(txMenu:setTrainerSource(txGame, "battle_art"), true,
  "combined trainer-source shortcut applies after durable success")
eq(txWrites, beforeTrainerSuccess + 1,
  "successful trainer shortcut persists both providers once")
eq(txGame.save.options.crystalTrainers, "none",
  "successful trainer shortcut quiets Crystal trainer replacement")
eq(txSaved.opponentTrainerSource, "battle_art",
  "successful trainer shortcut stores opponent ownership")
eq(txSaved.playerTrainerSource, "battle_art",
  "successful trainer shortcut stores player ownership")
eq(#crystalRuntimeCalls, 1,
  "successful trainer shortcut refreshes Crystal only after persistence")

txGame.writeOptions = function()
  txWrites = txWrites + 1
  return false, "simulated view failure"
end
local callsBeforeViewFailure = #crystalRuntimeCalls
local viewOk = txMenu:setPlayerView(txGame, "front")
eq(viewOk, false, "combined player-view shortcut reports write failure")
eq(txGame.save.options.crystalFront, false,
  "failed player-view shortcut restores Crystal orientation")
eq(txSaved.playerView, "back",
  "failed player-view shortcut restores saved Battle Art view")
eq(txLive.playerView, "back",
  "failed player-view shortcut restores live Battle Art view")
eq(TxBattleArt.viewSetting:get(), "back",
  "failed player-view shortcut restores cached Battle Art view")
eq(#crystalRuntimeCalls, callsBeforeViewFailure,
  "failed player-view shortcut invokes no Crystal runtime callback")

local callsBeforeModeFailure = #crystalRuntimeCalls
local modeOk = txMenu:cycleCrystalMode(txGame, 1)
eq(modeOk, false, "combined Crystal mode reports write failure")
eq(txGame.save.options.crystalTrainers, "none",
  "failed Crystal mode restores its top-level preference")
eq(txSaved.playerTrainerSource, "battle_art",
  "failed Crystal mode restores player ownership")
eq(#crystalRuntimeCalls, callsBeforeModeFailure,
  "failed Crystal mode invokes no provider runtime callback")

-- A missing crystalPlayerSprite save key means Crystal is using its
-- game-specific runtime default, not nil. If the post-persist provider refresh
-- fails, rollback must restore that exact active sprite as well as the absent
-- key; assigning nil here would blank/diverge the player art until reload.
txGame.save.options.crystalPlayerSprite = nil
crystalRuntimePlayer = "red.png"
failCrystalPlayer = "blue_flip.png"
txGame.writeOptions = function() txWrites = txWrites + 1 end
local beforePlayerFailureWrites = txWrites
local beforePlayerFailureCalls = #crystalRuntimeCalls
local playerOk, playerError = txMenu:setCrystalOption(
  txGame, "crystalPlayerSprite", "blue_flip.png")
eq(playerOk, false,
  "failed Crystal player refresh reports the callback failure")
check(tostring(playerError):find("Crystal player refresh failure", 1, true) ~= nil,
  "failed Crystal player refresh returns the callback detail")
eq(txWrites, beforePlayerFailureWrites + 2,
  "failed Crystal player refresh persists new then restored snapshots")
eq(txGame.save.options.crystalPlayerSprite, nil,
  "failed Crystal player refresh restores the absent save key")
eq(crystalRuntimePlayer, "red.png",
  "failed Crystal player refresh restores the exact active default")
eq(crystalHandle.exports.playerSprite(), "red.png",
  "Crystal player getter remains coherent after rollback")
eq(crystalRuntimeCalls[beforePlayerFailureCalls + 1][2], "blue_flip.png",
  "Crystal player callback receives the requested sprite first")
eq(crystalRuntimeCalls[beforePlayerFailureCalls + 2][2], "red.png",
  "Crystal player callback rolls back to the captured runtime sprite")
failCrystalPlayer = nil

-- Execute the real OverworldBattle wrappers against a narrow BattleState
-- fixture. This distinguishes calls made into the ordinary lower UI canvas
-- from calls made into the transparent animation canvas routed upstairs.
-- It also proves the split flag is scoped to combat pictures/OAM: the battle
-- text and HUD methods continue through their normal presentation wrappers.
local currentCanvas
local madeCanvases = {}
local graphics = {}
local quadCreates, quadReleases, quadDraws = 0, 0, 0
local quadArgs = {}
function graphics.newCanvas(w, h, options)
  local canvas = { width = w, height = h, options = options }
  function canvas:getWidth() return self.width end
  function canvas:getHeight() return self.height end
  function canvas:setFilter(min, mag) self.filter = { min, mag } end
  madeCanvases[#madeCanvases + 1] = canvas
  return canvas
end
function graphics.newQuad(x, y, w, h, textureW, textureH)
  quadCreates = quadCreates + 1
  quadArgs[quadCreates] = { x, y, w, h, textureW, textureH }
  local quad = { released = false }
  function quad:release()
    if not self.released then
      self.released = true
      quadReleases = quadReleases + 1
    end
  end
  return quad
end
function graphics.draw()
  quadDraws = quadDraws + 1
end
function graphics.getCanvas() return currentCanvas end
function graphics.setCanvas(canvas) currentCanvas = canvas end
function graphics.getBlendMode() return "alpha", "alphamultiply" end
function graphics.setBlendMode() end
function graphics.getScissor() return nil end
function graphics.intersectScissor() end
function graphics.push() end
function graphics.pop() end
function graphics.translate() end
function graphics.scale() end
function graphics.setScissor() end
function graphics.clear() end
function graphics.setColor() end
function graphics.rectangle() end
function graphics.getDimensions() return 800, 480 end
function graphics.getColor() return 1, 1, 1, 1 end

local previousLove = rawget(_G, "love")
_G.love = { graphics = graphics }

local picCalls, textCalls, hudCalls = 0, 0, 0
local animCalls = {}
local BattleState = {
  update = function() end,
  drawAnimLayer = function()
    animCalls[#animCalls + 1] = currentCanvas or "lower"
    return "engine-animation"
  end,
  newTrainer = function() return {} end,
  newWild = function() return {} end,
  resolveBattleScale = function() return 1 end,
  picImage = function(_, image) return image end,
  backPlacement = function() return 0, 0, 1 end,
  frontPlacement = function() return 0, 0, 1 end,
  draw = function() return "engine-battle" end,
  drawPicsLayer = function() picCalls = picCalls + 1; return "engine-pics" end,
  drawTextArea = function() textCalls = textCalls + 1; return "engine-text" end,
  drawZonePass = function() return "engine-zones" end,
  drawHUDs = function() hudCalls = hudCalls + 1; return "engine-hud" end,
}
local OverworldState = { pushBattle = function() return "engine-push" end }
local Renderer = { endFrame = function() return "engine-frame" end }

local moduleNames = {
  "src.battle.BattleState", "src.world.OverworldController",
  "src.render.Renderer", "src.core.Game",
}
local oldLoaded, oldPreload = {}, {}
for _, name in ipairs(moduleNames) do
  oldLoaded[name], oldPreload[name] = package.loaded[name], package.preload[name]
  package.loaded[name] = nil
end
package.preload["src.battle.BattleState"] = function() return BattleState end
package.preload["src.world.OverworldController"] = function() return OverworldState end
package.preload["src.render.Renderer"] = function() return Renderer end
package.preload["src.core.Game"] = function() return { renderer = {} } end

local function setting(value)
  return { get = function() return value end }
end
local orientation = { side = "back", front = true, opponent = false, back = false }
local hudLayer = { width = 160, height = 144 }
function hudLayer:getDimensions() return self.width, self.height end
local fakeModules = {
  ModSetting = {
    new = function(_, _, values, _, defaultIndex)
      return setting(values[defaultIndex or 1])
    end,
  },
  BattleArena = {},
  BattleCam = {},
  BattleScene = { GB_W = 160, GB_H = 144, capture = {} },
  BattleDOF = { invalidate = function() end },
  BattleHud = {
    invalidate = function() end,
    flipGlyphs = function(_, _, draw) return draw() end,
    layerTexture = function(_, _, _, draw)
      draw()
      return hudLayer
    end,
    panel = function() end,
  },
  BattlePresentation = { suppressed = function() return false end },
  UiBackplates = {
    spritesUnlit = function() return false end,
    textboxFillStyle = function() return nil end,
    textboxUsesWhiteInk = function() return false end,
    hudUsesColor = function() return false end,
    hudUsesColorShadow = function() return false end,
    arenaWhite = function() return false end,
  },
  TextboxStyle = { withFill = function(_, _, draw) return draw() end },
  BattlePics = {
    filled = function(image) return image end,
    invalidate = function() end,
  },
  BattleArt = {
    playerSide = function() return orientation.side end,
    backPlacementSetting = setting("ui"),
    setting = setting("animated"),
    ownsSpeciesArt = function() return false end,
    speciesFor = function() return nil end,
    isExternal = function() return false end,
    isStaticFront = function() return false end,
    isShiny = function() return false end,
    metrics = function() return nil end,
    apply = function() end,
    invalidate = function() end,
    flipsPlayerFront = function() return orientation.front end,
    flipsPlayerBack = function() return orientation.back end,
    flipsOpponent = function() return orientation.opponent end,
  },
  AnimatedBattleArt = {
    hasWorldBack = function() return true end,
    hasPlayerTrainerFrame = function() return false end,
    finish = function() end,
    invalidate = function() end,
  },
  Gen6Backdrop = {},
  Voxel3D = { metalRenderer = function() return false end },
  ChunkMesher = {},
}
local fakeV = {
  require = function(name)
    local dependency = fakeModules[name]
    assert(dependency, "unexpected OverworldBattle dependency: " .. tostring(name))
    return dependency
  end,
  mod = { log = { info = function() end, warn = function() end } },
}

local OverworldBattle = assert(loadfile(root .. "/lib/OverworldBattle.lua"))(fakeV)
OverworldBattle.install()

local shot = {
  player = { 30, 92 }, enemy = { 120, 52 },
  lx = 8, ly = 12, scale = 3, pw = 800, ph = 480,
}
local stagedBattle = {
  dramaticShapeShot = shot,
  showPlayerBack = true,
  playerBackPic = {},
  animPlayer = {},
  animPlaying = true,
}

eq(OverworldBattle.setSplitPresentation(false), true,
  "single-screen presentation can be selected explicitly")
BattleState.drawPicsLayer(stagedBattle)
eq(picCalls, 1,
  "a non-split staged pinned picture still uses the engine picture draw")
BattleState.drawAnimLayer(stagedBattle, false)
eq(#animCalls, 2,
  "non-split OAM draws once in the lower composite and once for upper export")
eq(animCalls[1], "lower",
  "the ordinary non-split battle canvas retains its authored OAM")
check(animCalls[2] == madeCanvases[1],
  "the second non-split OAM draw targets the transparent upper surface")
local exported = OverworldBattle.animationSurface(stagedBattle)
check(exported and exported.canvas == madeCanvases[1],
  "non-split capture publishes the upper animation surface")

picCalls, animCalls = 0, {}
eq(OverworldBattle.setSplitPresentation(true), true,
  "physical split presentation can be selected explicitly")
BattleState.drawPicsLayer(stagedBattle)
eq(picCalls, 0,
  "split staged lower canvas draws no Pokemon or trainer picture")
BattleState.drawAnimLayer(stagedBattle, false)
eq(#animCalls, 1,
  "split staged OAM draws only once, into the exported upper surface")
check(animCalls[1] == madeCanvases[1],
  "split staged OAM never reaches the ordinary lower UI canvas")
exported = OverworldBattle.animationSurface(stagedBattle)
check(exported and exported.canvas == madeCanvases[1]
    and exported.lx == shot.lx and exported.ly == shot.ly,
  "split keeps the upper OAM surface and its physical projection metadata")

BattleState.drawTextArea(stagedBattle)
eq(textCalls, 1, "staged lower wording is drawn exactly once")
BattleState.drawHUDs(stagedBattle)
eq(hudCalls, 1, "staged lower HUD is drawn exactly once")
local flatBattle = { dramaticShapeShot = nil }
BattleState.drawPicsLayer(flatBattle)
eq(picCalls, 1,
  "split mode does not suppress ordinary flat-battle pictures")

-- The same installed renderer publishes the selected orientation as explicit
-- per-card metadata. Trainers stay authored even if every Pokemon switch is
-- on, preventing a direction repair from turning Red/Oak/another trainer.
local cardBattle = {
  enemy = { sprite = {} }, player = { sprite = {} },
  fxHidden = function() return false end,
}
orientation.side, orientation.opponent = "front", false
eq(OverworldBattle.sideTexture(cardBattle, "enemy").mirror, false,
  "opponent card preserves authored direction by default")
orientation.opponent = true
eq(OverworldBattle.sideTexture(cardBattle, "enemy").mirror, true,
  "opponent card consumes its independent flip control")
orientation.front = false
eq(OverworldBattle.sideTexture(cardBattle, "player").mirror, false,
  "player-front card can preserve provider-authored direction")
orientation.front = true
eq(OverworldBattle.sideTexture(cardBattle, "player").mirror, true,
  "player-front card retains the historical face-opponent choice")
orientation.side, orientation.back = "back", false
eq(OverworldBattle.sideTexture(cardBattle, "player").mirror, false,
  "player-back card preserves authored direction by default")
orientation.back = true
eq(OverworldBattle.sideTexture(cardBattle, "player").mirror, true,
  "player-back card consumes its independent flip control")
cardBattle.showEnemyTrainer, cardBattle.trainerPic = true, {}
eq(OverworldBattle.sideTexture(cardBattle, "enemy").mirror, false,
  "opponent trainer portraits are never mirrored by Pokemon controls")
cardBattle.showEnemyTrainer = false
cardBattle.showPlayerBack, cardBattle.playerBackPic = true, {}
eq(OverworldBattle.sideTexture(cardBattle, "player").mirror, false,
  "player trainer portraits are never mirrored by Pokemon controls")

-- Allocation regression/benchmark: a snapped HUD used to manufacture two
-- userdata Quads per frame. Exercise two seconds at 60 fps and prove the hot
-- path creates exactly the two geometry objects it needs. A texture-size or
-- band-geometry change must replace only the affected cache entries, while a
-- render-cache invalidation releases and lazily recreates both.
local snapBattle = {
  enemy = { fainted = false }, player = {}, blankForAskName = true,
  growInScale = function() return false end,
}
local snapShot = {
  canvas = {}, lx = 8, ly = 12, scale = 3, pw = 800, ph = 480,
}
local createsBeforeSnap, drawsBeforeSnap = quadCreates, quadDraws
for frame = 1, 120 do
  eq(OverworldBattle.snapHUDs(snapBattle, snapShot), true,
    "snapped HUD benchmark frame " .. frame .. " composites")
end
eq(quadCreates - createsBeforeSnap, 2,
  "120 snapped frames allocate one cached Quad per HUD band")
eq(quadDraws - drawsBeforeSnap, 240,
  "120 snapped frames still draw both HUD bands")
eq(quadArgs[createsBeforeSnap + 1][5], 160,
  "cached HUD Quad records the source texture width")
eq(quadArgs[createsBeforeSnap + 1][6], 144,
  "cached HUD Quad records the source texture height")

local beforeResize = quadCreates
hudLayer.width, hudLayer.height = 320, 288
eq(OverworldBattle.snapHUDs(snapBattle, snapShot), true,
  "a rebuilt HUD layer still composites")
eq(quadCreates - beforeResize, 2,
  "a HUD texture resize replaces both dimension-keyed Quads")
eq(quadArgs[quadCreates][5], 320,
  "replacement Quad uses the rebuilt texture width")
eq(quadArgs[quadCreates][6], 288,
  "replacement Quad uses the rebuilt texture height")

local enemyBand = OverworldBattle.HUD_BAND.enemy
local originalEnemyWidth = enemyBand[3]
local beforeGeometryChange = quadCreates
enemyBand[3] = originalEnemyWidth - 1
eq(OverworldBattle.snapHUDs(snapBattle, snapShot), true,
  "an edited HUD band still composites")
eq(quadCreates - beforeGeometryChange, 1,
  "changing one band replaces only that geometry-keyed Quad")
enemyBand[3] = originalEnemyWidth
eq(OverworldBattle.snapHUDs(snapBattle, snapShot), true,
  "restoring authored HUD geometry still composites")
eq(quadCreates - beforeGeometryChange, 2,
  "restoring one band replaces only its stale Quad")

local releasesBeforeInvalidate = quadReleases
local createsBeforeInvalidate = quadCreates
OverworldBattle.invalidate()
eq(quadReleases - releasesBeforeInvalidate, 2,
  "battle render invalidation releases both cached HUD Quads")
eq(OverworldBattle.snapHUDs(snapBattle, snapShot), true,
  "HUD bands lazily rebuild after render invalidation")
eq(quadCreates - createsBeforeInvalidate, 2,
  "post-invalidation HUD draw recreates one Quad per band")

OverworldBattle.setSplitPresentation(false)
for _, name in ipairs(moduleNames) do
  package.loaded[name], package.preload[name] = oldLoaded[name], oldPreload[name]
end
_G.love = previousLove

-- LÖVE canvases default to the window DPI. On the AYN/Android backend that
-- means a logical 16x16 cache can read back at a larger physical size and be
-- sampled as if it were still 16x16. Lock both Wilds canvas paths to a 1:1
-- logical-pixel backing and nearest filtering.
local animated = read("vendor/wilds/lib/animated_sprites.lua")
local spawn = read("vendor/wilds/lib/spawn_render.lua")
check(animated:find("love.graphics.newCanvas, card, card,", 1, true) ~= nil,
  "Wilds billboard cards use the guarded canvas constructor")
check(animated:find("{ dpiscale = 1 }", 1, true) ~= nil,
  "Wilds billboard cards force one physical pixel per logical pixel")
check(animated:find('canvas:setFilter("nearest", "nearest")', 1, true) ~= nil,
  "Wilds billboard cards keep pixel-art sampling")
check(spawn:find("love.graphics.newCanvas, CELL, CELL,", 1, true) ~= nil,
  "Wilds sheet fallback uses the guarded canvas constructor")
check(spawn:find("{ dpiscale = 1 }", 1, true) ~= nil,
  "Wilds sheet fallback forces one physical pixel per logical pixel")
check(spawn:find('canvas:setFilter("nearest", "nearest")', 1, true) ~= nil,
  "Wilds sheet fallback keeps the generated image pixel-sharp")
check(spawn:find('src:setFilter("nearest", "nearest")', 1, true) ~= nil,
  "Wilds sheet fallback samples its source without linear edge bleed")

print(("art_rendering: %d checks passed"):format(checks))
