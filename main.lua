-- Scott's Tweaks
--
-- This keeps the original Voxel Run Bridge identity so existing installs and
-- GitHub updates continue in place, while giving Scott one small home for
-- related quality-of-life rules.

local Runtime = require("src.mods.Runtime")
local Game = require("src.core.Game")
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")

local unpackValues = table.unpack or unpack

local VOXEL_IDS = {
  "POKEMON_FINAL",
  "DRAMATIC_SHAPE",
  "BATTLE_ART_VOXEL_FORK",
  "DRAMALESS_SHAPE",
  "potato_voxel",
}

local HM_ACTIONS = {
  CUT = "cut",
  FLY = "fly",
  SURF = "surf",
  STRENGTH = "strength",
  FLASH = "flash",
}

local FREE_FLY_ID = "free_fly"
local FREE_FLY_OPTION = "free_fly_without_badges"
local FREE_FLY_COCKPIT_OPTION = "free_fly_cockpit"
local FREE_FLY_BADGES_KEY = "badges"
local POKEMON_FINAL_ID = "POKEMON_FINAL"
local CACHE_START_MARKER = "_scottsTweaksCacheStartHook"
local GAPPED_LAND_OPTION = "gapped_land"
local BAG_POCKETS_OPTION = "bag_pockets"
local GEN2_MENUS_OPTION = "gen2_menus"
local EXPERIENCE_MODE_OPTION = "experience_mode"
local EXP_SHARE_ID = "SCOTTS_EXP_SHARE"
local TRADE_STONE_ID = "SCOTTS_TRADE_STONE"
local TRADE_STONE_EFFECT = "SCOTTS_TRADE_STONE_EFFECT"
local GAPPED_LAND_RENDER_MARKER = "_scottsTweaksGappedLandRenderHook"
local GAPPED_LAND_INVALIDATE_MARKER = "_scottsTweaksGappedLandInvalidateHook"
local VOXEL_BRIDGE_MARKER = "_scottsTweaksVoxelRunBridge"
local GAPPED_LAND_RADIUS = 1024
local GAPPED_LAND_CELL = 64
-- Native terrain and Flora's detailed apron occupy roughly y=-2..-37.
-- Keep the broad procedural ground below both so it only fills the void.
local GAPPED_LAND_Y = -40
local RELEASE_VERSION = "0.12.2"

local OPTION_DEFAULTS = {
  hm_without_badges = true,
  free_fly_without_badges = true,
  free_fly_cockpit = false,
  gapped_land = true,
  bag_pockets = true,
  gen2_menus = true,
  experience_mode = "vanilla",
  trainer_forfeit_enabled = true,
  trainer_rematches = true,
  trainer_adaptive_dialogue = true,
  trainer_growth = "gentle",
  oak_spare_starter = true,
  running_enabled = true,
  running_speed = 1.5,
  simple_menu = true,
  running_view_bob = true,
  -- Raw camera amplitude. 0.25 is the historical effect now presented as
  -- 1X; the gentler new-install default is half of that (0.5X).
  running_bob_intensity = 0.125,
  dual_screen = false,
}

local TRADE_EVOLUTIONS = {
  KADABRA = "ALAKAZAM",
  MACHOKE = "MACHAMP",
  GRAVELER = "GOLEM",
  HAUNTER = "GENGAR",
}

local BAG_POCKETS = {
  { id = "items", label = "ITEMS" },
  { id = "balls", label = "BALLS" },
  { id = "key", label = "KEY ITEMS" },
  { id = "machines", label = "TM/HM" },
}

-- Crystal's PACK fits five two-line entries beside the pocket picture.  The
-- picture below is drawn from original primitives rather than copied ROM art;
-- keeping the measurements on the same 20x18 tile grid preserves the useful
-- part of the cartridge layout on every supported Gen1Recomp renderer.
local GOLD_PACK_VISIBLE_ROWS = 5

-- Red does not contain the item-description table that Gold/Crystal does.
-- Prefer data supplied by the engine or another content mod, then cover the
-- effects whose exact meaning is stable in Gen 1.  Everything else receives a
-- deliberately conservative category description instead of a blank panel or
-- a guessed mechanic.
local GOLD_PACK_DESCRIPTIONS = {
  POTION = "RESTORES 20 HP TO ONE POKéMON.",
  SUPER_POTION = "RESTORES 50 HP TO ONE POKéMON.",
  HYPER_POTION = "RESTORES 200 HP TO ONE POKéMON.",
  MAX_POTION = "FULLY RESTORES ONE POKéMON'S HP.",
  FULL_RESTORE = "FULLY RESTORES HP AND STATUS.",
  REVIVE = "REVIVES A FAINTED POKéMON WITH HALF ITS HP.",
  MAX_REVIVE = "FULLY REVIVES A FAINTED POKéMON.",
  ANTIDOTE = "CURES POISON IN ONE POKéMON.",
  BURN_HEAL = "HEALS A BURN ON ONE POKéMON.",
  ICE_HEAL = "THAWS ONE FROZEN POKéMON.",
  AWAKENING = "WAKES ONE SLEEPING POKéMON.",
  PARLYZ_HEAL = "CURES PARALYSIS IN ONE POKéMON.",
  FULL_HEAL = "CURES ALL STATUS PROBLEMS.",
  ETHER = "RESTORES 10 PP TO ONE MOVE.",
  MAX_ETHER = "FULLY RESTORES PP TO ONE MOVE.",
  ELIXER = "RESTORES 10 PP TO ALL MOVES.",
  MAX_ELIXER = "FULLY RESTORES PP TO ALL MOVES.",
  PP_UP = "RAISES THE MAXIMUM PP OF ONE MOVE.",
  RARE_CANDY = "RAISES A POKéMON BY ONE LEVEL.",
  ESCAPE_ROPE = "ESCAPES FROM A CAVE OR DUNGEON.",
  REPEL = "REPELS WEAK WILD POKéMON FOR 100 STEPS.",
  SUPER_REPEL = "REPELS WEAK WILD POKéMON FOR 200 STEPS.",
  MAX_REPEL = "REPELS WEAK WILD POKéMON FOR 250 STEPS.",
  POKE_DOLL = "HELPS ESCAPE FROM A WILD POKéMON.",
  FIRE_STONE = "MAKES CERTAIN POKéMON EVOLVE.",
  THUNDER_STONE = "MAKES CERTAIN POKéMON EVOLVE.",
  WATER_STONE = "MAKES CERTAIN POKéMON EVOLVE.",
  LEAF_STONE = "MAKES CERTAIN POKéMON EVOLVE.",
  MOON_STONE = "MAKES CERTAIN POKéMON EVOLVE.",
  BICYCLE = "A FOLDING BICYCLE FOR FAST TRAVEL.",
  TOWN_MAP = "A MAP OF THE KANTO REGION.",
  ITEMFINDER = "CHECKS THE AREA FOR HIDDEN ITEMS.",
  POKE_FLUTE = "A FLUTE THAT WAKES SLEEPING POKéMON.",
  OLD_ROD = "USE BY WATER TO FISH FOR POKéMON.",
  GOOD_ROD = "A GOOD ROD FOR FISHING FOR POKéMON.",
  SUPER_ROD = "THE BEST ROD FOR FISHING FOR POKéMON.",
  EXP_ALL = "SHARES BATTLE EXP WITH THE PARTY.",
  [EXP_SHARE_ID] = "SHARES EXP WHEN EXP. MODE IS EXP.SHARE.",
  [TRADE_STONE_ID] = "EVOLVES A POKéMON THAT NORMALLY EVOLVES BY TRADE.",
}

local goldPackInkShader
local goldPackInkShaderAttempted = false

local function getGoldPackInkShader(graphics)
  if goldPackInkShaderAttempted then return goldPackInkShader end
  goldPackInkShaderAttempted = true
  if type(graphics.newShader) ~= "function" then return nil end
  local ok, shader = pcall(graphics.newShader, [[
    vec4 effect(vec4 color, Image texture, vec2 texture_coords,
        vec2 screen_coords) {
      vec4 source = Texel(texture, texture_coords);
      return vec4(color.rgb, source.a * color.a);
    }
  ]])
  if ok then goldPackInkShader = shader end
  return goldPackInkShader
end

local GAPPED_LAND_VOXEL_IDS = {
  "POKEMON_FINAL",
  "DRAMATIC_SHAPE",
  "BATTLE_ART_VOXEL_FORK",
}

-- These maps deliberately read as open sea at the horizon. A green apron
-- there would hide geography instead of filling an accidental visual void.
local GAPPED_LAND_SEA_MAPS = {
  CINNABAR_ISLAND = true,
  ROUTE_19 = true,
  ROUTE_20 = true,
  ROUTE_21 = true,
}

local function pack(...)
  return { n = select("#", ...), ... }
end

local function traceback(err)
  if debug and debug.traceback then
    return debug.traceback(tostring(err), 2)
  end
  return tostring(err)
end

local findMod

-- Read this mod's modules through the API-2 path-scoped reader so the same
-- package works from a folder or a ZIP mount. No global package.path entry is
-- needed and another mod cannot shadow these files.
local function loadOwn(mod, relative)
  if type(mod.read) ~= "function" then
    return nil, "path-scoped mod reader unavailable"
  end
  local okRead, source = pcall(mod.read, mod, relative)
  if not okRead or type(source) ~= "string" then
    return nil, okRead and (relative .. " is missing") or source
  end
  local compile = loadstring or load
  local chunk, err = compile(source,
    "@" .. tostring(mod.path or mod.id) .. "/" .. relative)
  if not chunk then return nil, err end
  if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
  local okLoad, result = xpcall(chunk, traceback)
  if not okLoad then return nil, result end
  return result
end

local function installFeatureModules(mod)
  if type(mod.read) ~= "function" then return end

  local Settings, settingsErr = loadOwn(mod, "modules/settings.lua")
  if type(Settings) ~= "table" or type(Settings.new) ~= "function" then
    mod.exports.moduleErrors = mod.exports.moduleErrors or {}
    mod.exports.moduleErrors.settings = tostring(settingsErr or "invalid module")
    if mod.log and mod.log.warn then
      mod.log:warn("Scott's Tweaks modules unavailable: %s",
        tostring(settingsErr or "invalid settings module"))
    end
    return
  end

  local settings = Settings.new(mod, OPTION_DEFAULTS)
  local context = {
    releaseVersion = RELEASE_VERSION,
    defaults = OPTION_DEFAULTS,
    settings = settings,
    loadOwn = function(relative) return loadOwn(mod, relative) end,
    findMod = function(id) return findMod(mod, id) end,
  }
  mod.exports.settings = {
    get = function(key, fallback) return settings:get(key, fallback) end,
    set = function(game, key, value) return settings:set(game, key, value) end,
    defaults = OPTION_DEFAULTS,
  }

  local function install(relative, exportKey, optional)
    local installer, loadErr = loadOwn(mod, relative)
    if type(installer) ~= "function" then
      if not optional then
        mod.exports.moduleErrors = mod.exports.moduleErrors or {}
        mod.exports.moduleErrors[exportKey] = tostring(loadErr or "invalid installer")
        if mod.log and mod.log.warn then
          mod.log:warn("%s unavailable: %s", exportKey,
            tostring(loadErr or "invalid installer"))
        end
      end
      return nil
    end
    local ok, result = xpcall(function()
      return installer(mod, context)
    end, traceback)
    if not ok then
      mod.exports.moduleErrors = mod.exports.moduleErrors or {}
      mod.exports.moduleErrors[exportKey] = tostring(result)
      if mod.log and mod.log.warn then
        mod.log:warn("%s failed safely: %s", exportKey, tostring(result))
      end
      return nil
    end
    return result
  end

  install("modules/migrations.lua", "migrations")
  install("modules/trainer_forfeit.lua", "trainerForfeit")
  install("modules/oak_spare_starter.lua", "oakSpareStarter")
  install("modules/running.lua", "running")

  -- PACK + POKeGEAR use Red's existing controllers and Kanto map directly.
  -- No external ROM or decoded-art controller is required.
  install("modules/gen2_ui.lua", "gen2Ui")
  -- The physical-Thor presenter publishes a narrow table API rather than an
  -- installer chunk. Load it once after the central dual_screen option exists.
  local Thor, thorLoadErr = loadOwn(mod, "modules/thor_dual_screen.lua")
  if type(Thor) ~= "table" or type(Thor.install) ~= "function" then
    mod.exports.moduleErrors = mod.exports.moduleErrors or {}
    mod.exports.moduleErrors.thorDualScreen = tostring(
      thorLoadErr or "invalid Thor presenter module")
    if mod.log and mod.log.warn then
      mod.log:warn("thorDualScreen unavailable: %s",
        tostring(thorLoadErr or "invalid Thor presenter module"))
    end
  else
    local okThor, thorResult = xpcall(function()
      return Thor.install(mod, { optionKey = "dual_screen" })
    end, traceback)
    if not okThor then
      mod.exports.moduleErrors = mod.exports.moduleErrors or {}
      mod.exports.moduleErrors.thorDualScreen = tostring(thorResult)
      if mod.log and mod.log.warn then
        mod.log:warn("thorDualScreen failed safely: %s", tostring(thorResult))
      end
    end
  end
  install("modules/tweaks_menu.lua", "tweaksMenu")
end

local function finiteNumber(value, fallback)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then
    return fallback
  end
  return value
end

local function runningShoesOwnsFreeMove(FreeMove)
  return type(FreeMove) == "table"
    and type(rawget(FreeMove, "runningShoesTick")) == "function"
    and type(rawget(FreeMove, "runningShoesInner")) == "function"
end

findMod = function(mod, id)
  -- Battle Art and the bundled community mods no longer exist as separate mods,
  -- so the engine's find cannot see them. Every feature that used to detect a
  -- companion by id -- the run head bob asking the voxel renderer for FreeMove
  -- and FirstPerson, Gapped Land, the movement bridge -- looks them up through
  -- here, so answering centrally keeps those features working unchanged.
  local exports = mod.exports
  if (id == "BATTLE_ART_VOXEL_FORK" or id == mod.id)
      and type(exports) == "table" and type(exports.lib) == "table" then
    return { id = id, version = exports.version, exports = exports }
  end
  local host = exports and exports.vendorHost
  if host and host.loaded and host.loaded[id] then
    return host.loaded[id]
  end
  if type(mod.find) ~= "function" then return nil end
  local ok, found = pcall(mod.find, id)
  if not ok then ok, found = pcall(mod.find, mod, id) end
  return ok and found or nil
end

-- Pokemon Final is private, but it deliberately publishes its cached module
-- loader through mod.exports.lib for small companion adapters.  Some early
-- packages started the disk-cache job successfully and then left the fallback
-- "could not start" text on the screen.  Detect that behavior with a fake
-- screen instance; do not key the patch merely to a version label, and do not
-- carry any Pokemon Final source in this mod.
local function hasCacheStartMessageBug(start)
  local calls = 0
  local fake = {
    game = {},
    message = "probe",
    precache = {
      beginDisk = function()
        calls = calls + 1
        return true
      end,
    },
  }
  local ok = pcall(start, fake, false)
  return ok and calls == 1 and fake.message == "could not start"
end

local function installPokemonFinalCacheCompatibility(mod)
  local status = {
    active = false,
    reason = "pokemon_final_not_active",
    screen = "not_checked",
  }
  local restorers = {}

  status.restore = function()
    local changed = false
    for index = #restorers, 1, -1 do
      if restorers[index]() then changed = true end
    end
    if changed then
      status.active = false
      status.reason = "restored"
    end
    return changed
  end
  mod.exports.pokemonFinalCacheCompat = status

  local handle = findMod(mod, POKEMON_FINAL_ID)
  if not handle then return status end

  local version = handle.version
    or (handle.exports and handle.exports.version)
  status.version = version
  -- These are the only private package revisions whose module contract was
  -- locally verified.  A later build must opt in by exhibiting a newly audited
  -- contract rather than inheriting a raw-table patch forever.
  if version ~= "1.8.1-scott.2" and version ~= "1.8.1-scott.3" then
    status.reason = "unsupported_pokemon_final_version"
    status.screen = "not_checked"
    return status
  end

  local exports = handle.exports
  local lib = exports and exports.lib
  if type(lib) ~= "table" or type(lib.require) ~= "function" then
    status.reason = "module_loader_unavailable"
    status.screen = "unavailable"
    return status
  end

  local okScreen, Screen = pcall(lib.require, "ScottPrecacheScreen")
  if not okScreen or type(Screen) ~= "table" then
    status.reason = "cache_screen_unavailable"
    status.screen = "unavailable"
    return status
  end

  local original = rawget(Screen, "_start")
  if type(original) ~= "function" then
    status.reason = "cache_start_unavailable"
    status.screen = "unavailable"
    return status
  end

  local existing = rawget(Screen, CACHE_START_MARKER)
  if existing ~= nil then
    if type(existing) == "table" and existing.owner == mod.id
        and type(existing.original) == "function"
        and type(existing.wrapper) == "function"
        and rawget(Screen, "_start") == existing.wrapper then
      status.active = true
      status.reason = "already_installed"
      status.screen = "patched"
      restorers[#restorers + 1] = function()
        if rawget(Screen, CACHE_START_MARKER) ~= existing
            or rawget(Screen, "_start") ~= existing.wrapper then
          return false
        end
        rawset(Screen, "_start", existing.original)
        rawset(Screen, CACHE_START_MARKER, nil)
        return true
      end
    else
      status.reason = "cache_start_owned_by_another_mod"
      status.screen = "foreign_owner"
    end
    return status
  end

  if not hasCacheStartMessageBug(original) then
    status.reason = "already_safe"
    status.screen = "already_safe"
    return status
  end

  local function wrappedStart(self, ...)
    local result = pack(original(self, ...))
    -- Only the known false fallback is eligible, and only after the public
    -- precache status confirms that a build actually started.  Real errors,
    -- stale messages, and unfamiliar state shapes are left untouched.
    if self and self.message == "could not start" then
      local precache = self.precache
      if type(precache) == "table" and type(precache.status) == "function" then
        local okStatus, current = pcall(precache.status, self.game)
        if okStatus and type(current) == "table"
            and current.state == "building" then
          self.message = nil
        end
      end
    end
    return unpackValues(result, 1, result.n)
  end

  local marker = {
    owner = mod.id,
    version = RELEASE_VERSION,
    original = original,
    wrapper = wrappedStart,
  }
  -- Installation is deliberately last: every feature/ownership check above
  -- has completed before the shared exported table changes.
  rawset(Screen, "_start", wrappedStart)
  rawset(Screen, CACHE_START_MARKER, marker)
  restorers[#restorers + 1] = function()
    if rawget(Screen, CACHE_START_MARKER) ~= marker
        or rawget(Screen, "_start") ~= wrappedStart then
      return false
    end
    rawset(Screen, "_start", original)
    rawset(Screen, CACHE_START_MARKER, nil)
    return true
  end

  status.active = true
  status.reason = "patched"
  status.screen = "patched"
  mod.log:info("patched Pokemon Final %s cache start result", tostring(version))
  return status
end

-- Scott's Battle Art Kanto is fused into this build rather than shipped as a
-- separate mod, so one Scott's Tweaks update carries the renderer too. Battle
-- Art's own loader reads lib/ and data/ relative to the mod root -- which is
-- this mod's root now -- so it runs unmodified and only needs the mod handle.
-- It publishes its module table on mod.exports.lib exactly as the standalone
-- build did, which is the seam the voxel lookups below already understand.
local function installBattleArt(mod)
  -- Two voxel renderers must never drive the same map. If the player already
  -- runs one -- including a standalone copy of Battle Art -- the fused one
  -- stands down and Scott's Tweaks behaves exactly as it did before the
  -- fusion, compat layers and all.
  for _, id in ipairs(VOXEL_IDS) do
    local found = mod.find(id)
    if found and found.exports and type(found.exports.lib) == "table" then
      -- Recorded rather than logged: standing down is the ordinary outcome for
      -- anyone running another renderer, and this path must not add per-load
      -- log noise to the bridge's warn-once accounting.
      mod.exports.fusedRenderer = { installed = false, reason = "external_voxel", provider = id }
      return false
    end
  end
  if type(mod.read) ~= "function" then
    mod.log:warn("path-scoped reader unavailable; fused renderer not installed")
    return false
  end
  local okRead, source = pcall(mod.read, mod, "battle_art_main.lua")
  if not okRead or type(source) ~= "string" then
    mod.log:warn("battle_art_main.lua is missing; fused renderer not installed")
    return false
  end
  local compile = loadstring or load
  local chunk, err = compile(source,
    "@" .. tostring(mod.path or mod.id) .. "/battle_art_main.lua")
  if not chunk then
    mod.log:warn("battle_art_main.lua did not compile: %s", tostring(err))
    return false
  end
  -- xpcall with trailing arguments is a 5.2 extension; a closure keeps this
  -- working on plain 5.1 as well as LuaJIT.
  local okRun, runErr = xpcall(function() return chunk(mod) end, traceback)
  if not okRun then
    mod.log:warn("fused renderer failed to start: %s", tostring(runErr))
    return false
  end
  mod.exports.fusedRenderer = { installed = true, provider = "BATTLE_ART_VOXEL_FORK" }
  return true
end

-- The fused renderer publishes on this mod's own exports, so it is answered
-- before any external provider is probed.
-- The vendor host is built before the renderer so the renderer can be handed a
-- handle that sees the bundled mods. Battle Art asks the engine for companions
-- by id -- SpriteMenu looks up Crystal that way to decide who owns sprite
-- drawing -- and the engine cannot see a bundled mod, so without this the
-- renderer concluded Crystal was absent while Crystal was running and had
-- already taken sprite ownership, leaving no Pokemon drawn anywhere.
local function newVendorHost(mod)
  local VendorHost, err = loadOwn(mod, "modules/vendor_host.lua")
  if type(VendorHost) ~= "table" or type(VendorHost.new) ~= "function" then
    mod.exports.vendored = { installed = false, reason = tostring(err or "unavailable") }
    return nil
  end
  return VendorHost.new(mod)
end

-- Same mod, same exports table -- only `find` differs. Lookups are lazy, so a
-- handle made before the bundled mods are installed still resolves them later.
local function hostedHandle(mod, host)
  if not host then return mod end
  local proxy = setmetatable({}, { __index = mod })
  proxy.exports = mod.exports
  proxy.find = function(first, second) return host:_find(first, second) end
  return proxy
end

local function installVendoredMods(mod, host)
  if not host then return end
  host:installAll()
  mod.exports.vendorHost = host
  mod.exports.vendored = host:status()
end

local function findOwnVoxel(mod)
  local lib = mod.exports and mod.exports.lib
  if type(lib) == "table" and type(lib.require) == "function" then
    return "BATTLE_ART_VOXEL_FORK", mod, lib
  end
  return nil
end

local function findVoxelMod(mod)
  local ownId, ownHandle, ownLib = findOwnVoxel(mod)
  if ownId then return ownId, ownHandle, ownLib end
  for _, id in ipairs(VOXEL_IDS) do
    local found = mod.find(id)
    local lib = found and found.exports and found.exports.lib
    if type(lib) == "table" then return id, found, lib end
  end
  return nil
end

local function moveId(move)
  if type(move) == "table" then return move.id end
  if type(move) == "string" then return move end
  return nil
end

local function knowsMove(mon, wanted)
  for _, move in ipairs((mon and mon.moves) or {}) do
    if moveId(move) == wanted then return true end
  end
  return false
end

local function partyMemberKnowing(save, wanted)
  for _, mon in ipairs((save and save.party) or {}) do
    if knowsMove(mon, wanted) then return mon end
  end
  return nil
end

local function optionEnabled(mod, key, fallback)
  local ok, value = pcall(mod.options.get, mod.options, key)
  if not ok or value == nil then return fallback end
  return value == true
end

local function optionValue(mod, key, fallback)
  local ok, value = pcall(mod.options.get, mod.options, key)
  if not ok or value == nil then return fallback end
  return value
end

-- vendorHost is passed so the bundled mods' schemas ride the same define():
-- the engine keeps exactly one schema per mod id, so defining ours alone here
-- would erase every bundled row from the Mod Manager (each define REPLACES
-- the schema wholesale). Bundled keys arrive prefixed "<vendorId>:<key>".
local function defineOptions(mod, vendorHost)
  local schema = {
    {
      key = "simple_menu",
      type = "toggle",
      label = "OPTIONS SHOWN",
      default = true,
      help = "ON shows BASIC everyday controls; OFF shows ALL advanced tuning controls too. Hidden values are never changed.",
    },
    {
      key = "hm_without_badges",
      type = "toggle",
      label = "BADGE-FREE HMS",
      default = true,
      help = "Use CUT, FLY, SURF, STRENGTH and FLASH without badges. A party Pokemon must still know the move.",
    },
    {
      key = FREE_FLY_OPTION,
      type = "toggle",
      label = "FREE FLY NOW",
      default = true,
      help = "Let Free Fly take off without THUNDERBADGE. FLY eligibility, STORY GATES and terrain rules stay under Free Fly's control.",
    },
    {
      key = FREE_FLY_COCKPIT_OPTION,
      type = "toggle",
      label = "FLY COCKPIT",
      default = false,
      help = "Show the rider and flying Pokemon in first-person. On a physical Thor they appear on the upper gameplay display; third-person flight is unchanged.",
    },
    {
      key = GAPPED_LAND_OPTION,
      type = "toggle",
      label = "GAPPED LAND",
      default = true,
      help = "Fill the distant visual gap below the horizon in outdoor 1ST/3RD views. The added ground is not walkable.",
    },
    {
      key = BAG_POCKETS_OPTION,
      type = "toggle",
      label = "CLASSIC POCKETS",
      default = true,
      help = "Organize the classic Red bag into ITEMS, BALLS, KEY ITEMS and TM/HM pockets. Use D-pad Left or Right to change pockets. PACK + POKeGEAR keeps this projection active while its menu is on.",
    },
    {
      key = GEN2_MENUS_OPTION,
      type = "toggle",
      label = "PACK + POKéGEAR",
      default = true,
      help = "Use the Crystal-style four-pocket PACK plus CLOCK, MAP, PHONE and RADIO cards adapted to Red. No Gold ROM is required; Gen 1 Modern UI can stay on.",
    },
    {
      key = EXPERIENCE_MODE_OPTION,
      type = "choice",
      label = "EXP. MODE",
      default = "vanilla",
      choices = {
        { "VANILLA", "vanilla" },
        { "LEAD ONLY", "lead" },
        { "PARTY ALL", "party" },
        { "EXP.SHARE", "share" },
      },
      help = "VANILLA keeps normal rules. LEAD ONLY rewards the active Pokemon. PARTY ALL gives full EXP to every healthy party member. EXP.SHARE permanently unlocks its bag item.",
    },
    {
      key = "trainer_forfeit_enabled",
      type = "toggle",
      label = "PAID FORFEIT",
      default = true,
      help = "Offer a safe ¥200 RUN choice in ordinary trainer battles. A separate Trainer Forfeit mod remains the owner when it is enabled.",
    },
    {
      key = "trainer_rematches",
      type = "toggle",
      label = "TRAINER REMATCHES",
      default = true,
      help = "Offer reward-safe rematches after ordinary trainers and all eight Gym Leaders are fully completed.",
    },
    {
      key = "trainer_adaptive_dialogue",
      type = "toggle",
      label = "JOURNEY DIALOGUE",
      default = true,
      help = "Use offline authored rematch lines chosen from the current journey and prior results.",
    },
    {
      key = "trainer_growth",
      type = "choice",
      label = "TRAINER GROWTH",
      default = "gentle",
      choices = { { "OFF", "off" }, { "GENTLE", "gentle" } },
      help = "GENTLE lets repeat challengers improve modestly without changing their species or moves.",
    },
    {
      key = "oak_spare_starter",
      type = "toggle",
      label = "OAK SPARE STARTER",
      default = true,
      help = "After the lab rival battle, let Oak's one remaining ball be claimed once. Random Starters owns the lab when enabled.",
    },
    {
      key = "running_enabled",
      type = "toggle",
      label = "B-BUTTON RUN",
      default = true,
      help = "Hold B while walking to run immediately. Bikes, surfing, scripts and locked movement keep their normal speed.",
    },
    {
      key = "running_speed",
      type = "choice",
      label = "RUN SPEED",
      default = 1.5,
      choices = { { "1.25X", 1.25 }, { "1.5X", 1.5 }, { "2X", 2 },
                  { "2.5X", 2.5 }, { "3X", 3 }, { "4X", 4 } },
      help = "Choose the held-B walking multiplier.",
    },
    {
      key = "running_view_bob",
      type = "toggle",
      label = "RUN HEAD BOB",
      default = true,
      help = "Add a very light, distance-based first-person camera motion while running.",
    },
    {
      key = "running_bob_intensity",
      type = "choice",
      label = "BOB INTENSITY",
      default = 0.125,
      choices = {
        { "0.25X", 0.0625 }, { "0.4X", 0.1 }, { "0.5X", 0.125 },
        { "0.6X", 0.15 }, { "0.75X", 0.1875 }, { "1X", 0.25 },
        { "1.5X", 0.375 }, { "2X", 0.5 }, { "3X", 0.75 }, { "4X", 1 },
      },
      help = "Scale running camera motion. The former 0.25 effect is now 1X; the gentler new-install default is 0.5X.",
    },
    {
      key = "dual_screen",
      type = "toggle",
      label = "THOR 2ND SCREEN",
      default = false,
      help = "Use the physical AYN Thor lower display for menus when it is attached. Single-screen systems stay unchanged.",
    },
  }

  local seen = {}
  for _, row in ipairs(schema) do seen[row.key] = true end
  local function append(rows, source)
    for _, row in ipairs(rows or {}) do
      assert(type(row) == "table" and type(row.key) == "string",
        tostring(source) .. " option row needs a key")
      assert(not seen[row.key],
        ("duplicate canonical option key %s from %s"):format(
          tostring(row.key), tostring(source)))
      seen[row.key] = true
      schema[#schema + 1] = row
    end
  end

  -- Battle Art deliberately publishes rather than defines this contribution
  -- when fused, so the Loader sees one complete schema instead of a sequence
  -- of partial replacements.
  append(mod.exports and mod.exports.battleArtOptionSchema, "Battle Art")
  if vendorHost and type(vendorHost.mergedSchema) == "function" then
    append(vendorHost:mergedSchema(), "bundled mod")
  end
  mod.options:define(schema)
  mod.exports.optionSchema = schema
end

local function constructScreen(factory, builtin, ...)
  if type(factory) == "function" then return factory(...) end
  if type(factory) == "table" and type(factory.new) == "function" then
    return factory.new(...)
  end
  return builtin.new(...)
end

local function playMenuSound(game, id)
  pcall(function()
    require("src.core.Sound").play(game.data, id or "Press_AB")
  end)
end

local function showUiMessage(game, message, onDone)
  game.stack:push(require("src.render.TextBox").new(game, message, onDone))
end

local function tradeEvolutionFor(data, mon)
  if not (data and data.pokemon and mon and mon.species) then return nil end
  local def = data.pokemon[mon.species]
  for _, evolution in ipairs((def and def.evolutions) or {}) do
    if evolution.method == "TRADE" then
      local target = evolution.species or evolution.into
      if target and data.pokemon[target] then return target end
    end
  end
  local fallback = TRADE_EVOLUTIONS[mon.species]
  if fallback and data.pokemon[fallback] then return fallback end
  return nil
end

local function pocketForItem(id, def, ItemEffects)
  if (def and def.machine) or id:match("^TM_") or id:match("^HM_") then
    return "machines"
  end
  if (ItemEffects and ItemEffects.isBall and ItemEffects.isBall(id))
      or (def and def.ball) then
    return "balls"
  end
  if id == EXP_SHARE_ID or id == "EXP_ALL"
      or (def and (def.keyItem or def.tossable == false)) then
    return "key"
  end
  return "items"
end

local function goldPackMove(game, def)
  local machine = def and def.machine
  local id = type(machine) == "table" and machine.move or nil
  if not id then return nil, nil end
  local move = game and game.data and game.data.moves
    and game.data.moves[id]
  local name = move and move.name or tostring(id):gsub("_", " ")
  return id, name, move
end

local function goldPackDescription(game, id, def, pocketId)
  local _, moveName, move = goldPackMove(game, def)
  if move then
    local description = move.description or move.desc
    if type(description) == "string" and description ~= "" then
      return description
    end
  end

  local supplied = def and (def.description or def.desc)
  if type(supplied) == "table" then
    supplied = table.concat(supplied, "\n")
  end
  if type(supplied) == "string" and supplied ~= "" then return supplied end
  if moveName then return "TEACHES " .. moveName .. " TO A POKéMON." end

  local known = GOLD_PACK_DESCRIPTIONS[id]
  if known then return known end
  if pocketId == "balls" then
    return "A BALL USED TO CATCH WILD POKéMON."
  elseif pocketId == "key" then
    return "AN IMPORTANT ITEM FOR YOUR ADVENTURE."
  elseif pocketId == "machines" then
    return "TEACHES A MOVE TO A POKéMON."
  end
  return "A USEFUL ITEM KEPT IN THE PACK."
end

local function goldPackTextLines(Font, text, maxWidth, maxLines)
  text = tostring(text or "")
    :gsub("<NEXT>", "\n")
    :gsub("<LINE>", "\n")
    :gsub("%s*\r%s*", "\n")
  local lines = {}
  local function width(value)
    local ok, result = pcall(Font.width, value)
    return ok and tonumber(result) or (#value * 8)
  end
  for segment in (text .. "\n"):gmatch("(.-)\n") do
    local line
    for word in segment:gmatch("%S+") do
      local candidate = line and (line .. " " .. word) or word
      if line and width(candidate) > maxWidth then
        lines[#lines + 1] = line
        line = word
      else
        line = candidate
      end
    end
    if line then lines[#lines + 1] = line end
    if #lines >= maxLines then break end
  end
  return lines
end

local function drawGoldPack(game, list, pocket, state)
  local G = love and love.graphics
  if type(G) ~= "table" or type(G.setColor) ~= "function"
      or type(G.rectangle) ~= "function" then return false end
  local okFont, Font = pcall(require, "src.render.Font")
  if not okFont or type(Font) ~= "table" or type(Font.draw) ~= "function"
      or type(Font.width) ~= "function" then return false end

  local function color(r, g, b, a) G.setColor(r, g, b, a or 1) end
  local function fill(r, g, b, x, y, w, h)
    color(r, g, b)
    G.rectangle("fill", x, y, w, h)
  end
  local function outline(r, g, b, x, y, w, h)
    color(r, g, b)
    G.rectangle("line", x, y, w, h)
  end
  local function text(value, x, y)
    color(0.07, 0.06, 0.10)
    Font.draw(value, x, y)
  end
  local function inkText(value, x, y, r, g, b)
    local shader = getGoldPackInkShader(G)
    if shader and type(G.setShader) == "function" then
      local previous = type(G.getShader) == "function" and G.getShader() or nil
      G.setShader(shader)
      color(r, g, b)
      local okDraw, drawResult = pcall(Font.draw, value, x, y)
      local okRestore, restoreResult = pcall(G.setShader, previous)
      if not okDraw then error(drawResult, 0) end
      if not okRestore then error(restoreResult, 0) end
      return
    end
    -- Shaderless renderers are not expected on supported LÖVE builds, but a
    -- visible system-font label is preferable to black cartridge ink on the
    -- black header if a minimal test/driver disables shaders.
    if type(G.print) == "function" then
      color(r, g, b)
      G.print(value, x, y)
    else
      text(value, x, y)
    end
  end
  local function triangle(mode, x, y, direction)
    if type(G.polygon) ~= "function" then return end
    if direction == "left" then
      G.polygon(mode, x + 6, y, x, y + 4, x + 6, y + 8)
    elseif direction == "up" then
      G.polygon(mode, x, y + 6, x + 4, y, x + 8, y + 6)
    elseif direction == "down" then
      G.polygon(mode, x, y, x + 4, y + 6, x + 8, y)
    else
      G.polygon(mode, x, y, x + 6, y + 4, x, y + 8)
    end
  end

  -- Pack_InitGFX's 20x18 panel: one header row, an eleven-row pocket/list
  -- body and the six-row description box from Crystal's pack.asm.
  fill(1, 1, 1, 0, 0, 160, 144)
  fill(0.02, 0.02, 0.03, 0, 0, 160, 8)
  fill(0.20, 0.43, 0.78, 0, 8, 40, 88)
  for y = 8, 88, 8 do
    fill(0.32, 0.58, 0.90, 0, y, 40, 3)
    for x = (math.floor(y / 8) % 2) * 4, 36, 8 do
      fill(0.12, 0.31, 0.65, x, y + 3, 4, 3)
    end
  end
  fill(1, 1, 1, 40, 8, 120, 88)

  color(1, 1, 1)
  triangle("fill", 2, 0, "left")
  triangle("fill", 11, 0, "right")
  inkText("POCKET", 22, 0, 1, 1, 1)
  local header = pocket.id == "balls" and "BALLS" or pocket.label
  local headerWidth = Font.width(header)
  inkText(header, math.max(80, 156 - headerWidth), 0, 0.95, 0.30, 0.82)

  -- An original, ROM-free silhouette in the same 5x3-tile picture area.
  fill(0.96, 1, 0.96, 4, 24, 32, 24)
  outline(0.10, 0.48, 0.22, 7, 27, 26, 18)
  outline(0.10, 0.48, 0.22, 12, 24, 16, 7)
  outline(0.10, 0.48, 0.22, 13, 32, 14, 9)
  fill(0.10, 0.48, 0.22, 5, 32, 3, 10)
  fill(0.10, 0.48, 0.22, 33, 32, 3, 10)

  fill(0.75, 0.04, 0.18, 2, 57, 36, 25)
  fill(0.02, 0.02, 0.03, 5, 60, 30, 19)
  local plaque = pocket.id == "machines" and "TMHM"
    or (pocket.id == "key" and "KEY")
    or (pocket.id == "balls" and "BALL" or "ITEM")
  local plaqueWidth = Font.width(plaque)
  inkText(plaque, 20 - math.floor(plaqueWidth / 2), 66, 1, 1, 1)

  local rows = list.items or {}
  if #rows == 0 then
    text("NOTHING HERE.", 56, 48)
  else
    for visible = 1, GOLD_PACK_VISIBLE_ROWS do
      local index = (list.scroll or 0) + visible
      local row = rows[index]
      if not row then break end
      local y = 16 + (visible - 1) * 16
      local selected = index == list.index
      if selected then
        color(0.78, 0.02, 0.16)
        triangle("fill", 48, y, "right")
      elseif list.swapIndex == index or state.swapId == row.value then
        color(0.78, 0.02, 0.16)
        triangle("line", 48, y, "right")
      end
      text(row.label, 56, y)
      local def = game.data and game.data.items and game.data.items[row.value]
      local _, moveName = goldPackMove(game, def)
      if pocket.id == "machines" and moveName then
        text(moveName, 64, y + 8)
      elseif pocket.id == "items" or pocket.id == "balls" then
        local count = game.save and game.save.inventory
          and game.save.inventory[row.value] or 0
        text("\195\151" .. tostring(count), 64, y + 8)
      end
    end
  end

  color(0.07, 0.06, 0.10)
  if (list.scroll or 0) > 0 then triangle("fill", 148, 10, "up") end
  if (list.scroll or 0) + GOLD_PACK_VISIBLE_ROWS < #rows then
    triangle("fill", 148, 88, "down")
  end

  -- The selected item's explanation is always present.  Red's data does not
  -- normally carry descriptions, so goldPackDescription supplies accurate,
  -- effect-aware fallbacks rather than exposing an empty decorative box.
  if type(Font.drawBox) == "function" then
    color(1, 1, 1)
    Font.drawBox(0, 12, 20, 6)
  else
    fill(1, 1, 1, 0, 96, 160, 48)
    outline(0.07, 0.06, 0.10, 0, 96, 159, 47)
  end
  local current = rows[list.index]
  local description
  if current then
    local def = game.data and game.data.items and game.data.items[current.value]
    description = goldPackDescription(game, current.value, def, pocket.id)
  else
    description = "NO ITEMS IN THIS POCKET."
  end
  for index, line in ipairs(goldPackTextLines(Font, description, 144, 2)) do
    text(line, 8, 104 + (index - 1) * 16)
  end
  color(1, 1, 1)
  return true
end

local function installInventoryFeatures(mod)
  local ItemEffects = require("src.inventory.ItemEffects")
  local Bag = require("src.inventory.Bag")

  -- v0.1.83 dispatches registered item effects directly.  The decorated bag
  -- below also handles this exact item on v0.1.75, whose public registry
  -- existed before the consumer-side dispatch was added.
  mod.content.item_effects:register(TRADE_STONE_EFFECT, {
    needsTarget = true,
    battle = false,
    field = true,
    use = function(ctx)
      local target = tradeEvolutionFor(ctx.data, ctx.target)
      if not target then
        return "failed", { "It won't have\nany effect." }
      end
      return "consumed", nil, { evolveTo = target }
    end,
  })
  mod.content.items:register(TRADE_STONE_ID, {
    id = TRADE_STONE_ID,
    name = "TRADE STONE",
    price = 500,
    effect = TRADE_STONE_EFFECT,
    needsTarget = true,
    tossable = true,
  })
  mod.content.items:register(EXP_SHARE_ID, {
    id = EXP_SHARE_ID,
    name = "EXP.SHARE",
    price = 0,
    keyItem = true,
    pocket = "KEY_ITEM",
    tossable = false,
    needsTarget = false,
  })

  -- Gen1Recomp v0.1.75 exposed item_effects content but its consumer did not
  -- dispatch it. Probe that behavior with inert synthetic data: v0.1.83+
  -- stays entirely native, while the older engine receives an exact-ID
  -- adapter. An owned wrapper is first restored on developer hot reload so
  -- a corrected implementation is never frozen in the process-global module.
  local existingTradeHook = rawget(ItemEffects, "_scottsTweaksTradeStoneHook")
  local restoredOwnedHook = false
  if type(existingTradeHook) == "table"
      and existingTradeHook.owner == mod.id
      and ItemEffects.needsTarget == existingTradeHook.wrapperNeedsTarget
      and ItemEffects.use == existingTradeHook.wrapperUse then
    ItemEffects.needsTarget = existingTradeHook.originalNeedsTarget
    ItemEffects.use = existingTradeHook.originalUse
    rawset(ItemEffects, "_scottsTweaksTradeStoneHook", nil)
    existingTradeHook = nil
    restoredOwnedHook = true
  end

  local function nativeItemEffectDispatch()
    local probeId = "__SCOTTS_ITEM_EFFECT_PROBE"
    local probeEffectId = "__SCOTTS_ITEM_EFFECT_PROBE_EFFECT"
    local called = false
    local probeEffect = {
      needsTarget = true,
      battle = false,
      field = true,
      use = function(ctx)
        called = ctx and ctx.itemId == probeId
        return "scotts_probe"
      end,
    }
    local probeData = {
      items = {
        [probeId] = {
          id = probeId,
          name = "PROBE",
          price = 0,
          effect = probeEffectId,
          needsTarget = true,
        },
      },
      item_effects = { [probeEffectId] = probeEffect },
      pokemon = {}, text = {}, field = {}, constants = {},
    }
    local okTarget, needsTarget = pcall(ItemEffects.needsTarget,
      probeId, probeData.items[probeId], probeData)
    local okUse, result = pcall(ItemEffects.use, probeData,
      { inventory = {} }, probeId, { species = "PROBE" })
    return okTarget and needsTarget == true
      and okUse and result == "scotts_probe" and called
  end

  local tradeAdapterMode = "native_item_effects"
  if not nativeItemEffectDispatch() and not existingTradeHook then
    local baseNeedsTarget = ItemEffects.needsTarget
    local baseUse = ItemEffects.use
    local function isLiveTradeStone(data, id, itemDef)
      itemDef = itemDef or (data and data.items and data.items[id])
      return id == TRADE_STONE_ID and type(itemDef) == "table"
        and itemDef.effect == TRADE_STONE_EFFECT
    end
    local wrappedNeedsTarget = function(id, itemDef, data, ...)
      if isLiveTradeStone(data, id, itemDef) then return true end
      return baseNeedsTarget(id, itemDef, data, ...)
    end
    local wrappedUse = function(data, save, id, target, battle, moveIndex, ow, ...)
      local itemDef = data and data.items and data.items[id]
      local effect = data and data.item_effects
        and data.item_effects[TRADE_STONE_EFFECT]
      if isLiveTradeStone(data, id, itemDef)
          and type(effect) == "table" and type(effect.use) == "function" then
        if (battle and effect.battle == false)
            or (not battle and effect.field == false) then
          local text = data.text and data.text._ItemUseNotTimeText
            or "It can't be used\nright now."
          return "failed", { text }
        end
        return effect.use({
          data = data,
          save = save,
          itemId = id,
          item = itemDef,
          target = target,
          battle = battle,
          moveIndex = moveIndex,
          overworld = ow,
        })
      end
      return baseUse(data, save, id, target, battle, moveIndex, ow, ...)
    end
    ItemEffects.needsTarget = wrappedNeedsTarget
    ItemEffects.use = wrappedUse
    rawset(ItemEffects, "_scottsTweaksTradeStoneHook", {
      owner = mod.id,
      version = RELEASE_VERSION,
      originalNeedsTarget = baseNeedsTarget,
      originalUse = baseUse,
      wrapperNeedsTarget = wrappedNeedsTarget,
      wrapperUse = wrappedUse,
    })
    tradeAdapterMode = "v0.1.75_compatibility"
  elseif existingTradeHook then
    tradeAdapterMode = "existing_compatibility_chain"
  elseif restoredOwnedHook then
    tradeAdapterMode = "native_after_hot_reload_cleanup"
  end

  local pocketStatus = {
    active = true,
    mode = "screen_pockets",
    pockets = { "items", "balls", "key", "machines" },
  }
  local shopStatus = {
    active = true,
    tradeStone = TRADE_STONE_ID,
    price = 500,
    ownedCount = true,
  }
  mod.exports.bagPockets = pocketStatus
  mod.exports.shopTweaks = shopStatus
  mod.exports.tradeStone = {
    id = TRADE_STONE_ID,
    price = 500,
    evolutions = TRADE_EVOLUTIONS,
    adapter = tradeAdapterMode,
  }

  local priorBag = mod.content.screens:get("BagMenu")
  local builtinBag = require("src.ui.BagMenu")

  local function decorateBag(game, opts, list)
    if type(list) ~= "table" or type(list.update) ~= "function"
        or type(list.draw) ~= "function" or type(list.onChoose) ~= "function"
        or not (optionEnabled(mod, BAG_POCKETS_OPTION, true)
          or optionEnabled(mod, GEN2_MENUS_OPTION, false)) then
      return list
    end
    if rawget(list, "_scottsTweaksPocketLayer") then return list end
    -- A lower-priority modern bag that deliberately publishes its own pocket
    -- controller remains the single owner rather than receiving a second set
    -- of Left/Right tabs.
    if type(rawget(list, "switchPocket")) == "function"
        or type(rawget(list, "__pocketIds")) == "table" then
      pocketStatus.reason = "existing_pocket_ui"
      return list
    end

    local goldEnabled = optionEnabled(mod, GEN2_MENUS_OPTION, false)
    local memory
    if goldEnabled and type(game) == "table" then
      memory = rawget(game, "_scottsTweaksGoldPackMemory")
      if type(memory) ~= "table" then
        memory = { pocket = 1, cursor = {}, scroll = {} }
        rawset(game, "_scottsTweaksGoldPackMemory", memory)
      end
      if type(memory.cursor) ~= "table" then memory.cursor = {} end
      if type(memory.scroll) ~= "table" then memory.scroll = {} end
    end
    local state = {
      pocket = memory and math.max(1,
        math.min(tonumber(memory.pocket) or 1, #BAG_POCKETS)) or 1,
      cursor = memory and memory.cursor or {},
      scroll = memory and memory.scroll or {},
      memory = memory,
      swapId = nil,
    }
    local baseUpdate = list.update
    local baseDraw = list.draw
    local baseChoose = list.onChoose
    local nativeRows = list.rows or 7

    local function currentId()
      local item = list.items and list.items[list.index]
      return item and item.value or nil
    end

    local function buildRows(pocketId)
      local rows = {}
      for _, id in ipairs(Bag.order(game.save)) do
        local count = game.save.inventory[id]
        local def = game.data.items[id]
        if count and pocketForItem(id, def, ItemEffects) == pocketId then
          rows[#rows + 1] = {
            value = id,
            label = def and def.name or id,
            right = "x" .. tostring(count),
          }
        end
      end
      return rows
    end

    local function rebuild(preferredId, restorePocket)
      local pocket = BAG_POCKETS[state.pocket]
      local oldId = preferredId
      if oldId == nil and not restorePocket then oldId = currentId() end
      list.items = buildRows(pocket.id)
      list.title = "< " .. pocket.label .. " >"
      list.rows = optionEnabled(mod, GEN2_MENUS_OPTION, false)
        and GOLD_PACK_VISIBLE_ROWS or nativeRows
      local nextIndex
      if oldId then
        for index, item in ipairs(list.items) do
          if item.value == oldId then nextIndex = index break end
        end
      end
      nextIndex = nextIndex or state.cursor[pocket.id] or 1
      list.index = math.max(1, math.min(nextIndex, math.max(1, #list.items)))
      local rows = list.rows or nativeRows
      local wantedScroll = restorePocket and (state.scroll[pocket.id] or 0)
        or (list.scroll or 0)
      list.scroll = math.max(0, math.min(wantedScroll,
        math.max(0, #list.items - rows)))
      if list.index - list.scroll > rows then
        list.scroll = list.index - rows
      elseif list.index - list.scroll < 1 then
        list.scroll = list.index - 1
      end
      state.cursor[pocket.id] = list.index
      state.scroll[pocket.id] = list.scroll
      if state.memory then
        state.memory.pocket = state.pocket
      end
    end

    local function finishSwap(secondId)
      local firstId = state.swapId
      state.swapId = nil
      list.swapIndex = nil
      if not firstId or not secondId then return false end
      local order = Bag.order(game.save)
      local firstIndex, secondIndex
      for index, id in ipairs(order) do
        if id == firstId then firstIndex = index end
        if id == secondId then secondIndex = index end
      end
      if firstIndex and secondIndex then
        order[firstIndex], order[secondIndex] = order[secondIndex], order[firstIndex]
        playMenuSound(game, "Swap")
        rebuild(secondId)
        return true
      end
      rebuild(secondId)
      return false
    end

    list.onSelectKey = function(item, current)
      if not item then return end
      if not state.swapId then
        state.swapId = item.value
        current.swapIndex = current.index
      else
        finishSwap(item.value)
      end
    end

    list.onChoose = function(item, ...)
      if state.swapId then
        finishSwap(item and item.value)
        return
      end
      if item and item.value == EXP_SHARE_ID then
        showUiMessage(game,
          "EXP.SHARE works when\nEXP. MODE is set to\nEXP.SHARE.")
        return
      end
      return baseChoose(item, ...)
    end

    list.update = function(self, dt)
      rebuild(currentId())
      local input = game.input
      local left = input and input.wasPressed and input:wasPressed("left")
      local right = input and input.wasPressed and input:wasPressed("right")
      if left or right then
        local pocket = BAG_POCKETS[state.pocket]
        state.cursor[pocket.id] = self.index
        state.scroll[pocket.id] = self.scroll or 0
        state.swapId = nil
        self.swapIndex = nil
        state.pocket = ((state.pocket - 1 + (right and 1 or -1))
          % #BAG_POCKETS) + 1
        if state.memory then state.memory.pocket = state.pocket end
        -- Do not carry the selected id from the old pocket into the new
        -- pocket.  Clearing the rendered rows lets rebuild restore that
        -- pocket's own remembered cursor instead.
        self.items = {}
        self.scroll = state.scroll[BAG_POCKETS[state.pocket].id] or 0
        rebuild(nil, true)
        playMenuSound(game)
        return
      end
      local result = pack(baseUpdate(self, dt))
      local active = BAG_POCKETS[state.pocket]
      state.cursor[active.id] = self.index
      state.scroll[active.id] = self.scroll or 0
      if state.memory then state.memory.pocket = state.pocket end
      return unpackValues(result, 1, result.n)
    end

    list.draw = function(self)
      rebuild(currentId())
      if optionEnabled(mod, GEN2_MENUS_OPTION, false)
          and not state.visualFailed then
        local drawn
        local ok, err = xpcall(function()
          drawn = drawGoldPack(game, self, BAG_POCKETS[state.pocket], state)
        end, traceback)
        if ok and drawn then return end
        if not ok then state.visualFailed = tostring(err) end
      end
      return baseDraw(self)
    end

    rawset(list, "_scottsTweaksPocketLayer", {
      owner = mod.id,
      version = RELEASE_VERSION,
      visual = goldEnabled and "crystal_pack" or "classic_pockets",
      state = state,
    })
    rebuild(nil, true)
    return list
  end

  mod.content.screens:override("BagMenu", {
    new = function(game, opts)
      return decorateBag(game, opts,
        constructScreen(priorBag, builtinBag, game, opts))
    end,
  })

  local priorShop = mod.content.screens:get("ShopMenu")
  local builtinShop = require("src.ui.ShopMenu")

  local function decorateBuyList(game, list)
    if type(list) ~= "table" or type(list.draw) ~= "function"
        or rawget(list, "_scottsTweaksOwnedCount") then return list end
    if list.title ~= "BUY" and list.kind ~= "BUY" then return list end
    local baseDraw = list.draw
    list.draw = function(self)
      local item = self.items and self.items[self.index]
      local count = item and game.save.inventory[item.value] or 0
      local oldTitle = self.title
      self.title = ("BUY BAG:%d"):format(tonumber(count) or 0)
      local result
      local ok, err = xpcall(function()
        result = pack(baseDraw(self))
      end, traceback)
      self.title = oldTitle
      if not ok then error(err, 0) end
      return unpackValues(result, 1, result.n)
    end
    rawset(list, "_scottsTweaksOwnedCount", {
      owner = mod.id,
      version = RELEASE_VERSION,
    })
    return list
  end

  local function decorateShop(game, menu)
    if type(menu) ~= "table" or type(menu.update) ~= "function"
        or rawget(menu, "_scottsTweaksShopLayer") then return menu end
    local baseUpdate = menu.update
    menu.update = function(self, dt)
      local before = game.stack and game.stack:top()
      local result
      local ok, err = xpcall(function()
        result = pack(baseUpdate(self, dt))
      end, traceback)
      if not ok then error(err, 0) end
      local after = game.stack and game.stack:top()
      if after and after ~= before then decorateBuyList(game, after) end
      return unpackValues(result, 1, result.n)
    end
    rawset(menu, "_scottsTweaksShopLayer", {
      owner = mod.id,
      version = RELEASE_VERSION,
    })
    return menu
  end

  mod.content.screens:override("ShopMenu", {
    new = function(game, stock, onQuit)
      local copied, seen = {}, false
      for _, id in ipairs(stock or {}) do
        copied[#copied + 1] = id
        if id == TRADE_STONE_ID then seen = true end
      end
      if not seen then copied[#copied + 1] = TRADE_STONE_ID end
      return decorateShop(game,
        constructScreen(priorShop, builtinShop, game, copied, onQuit))
    end,
  })
end

local function installExperienceModes(mod)
  local Bag = require("src.inventory.Bag")
  local state = {
    mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla"),
    item = EXP_SHARE_ID,
    itemUnlocked = false,
    pending = false,
    reason = "not_requested",
  }
  mod.exports.experience = state

  local function totalOwned(save)
    local bag = save and save.inventory and save.inventory[EXP_SHARE_ID] or 0
    local pc = save and save.pcItems and save.pcItems[EXP_SHARE_ID] or 0
    return (tonumber(bag) or 0) + (tonumber(pc) or 0)
  end

  local function ensureShareItem(save, data)
    state.mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla")
    if state.mode ~= "share" then
      state.reason = "mode_not_share"
      return false
    end
    if not (save and save.inventory and data and data.items
        and data.items[EXP_SHARE_ID]) then
      state.pending = true
      state.reason = "save_or_item_unavailable"
      return false
    end
    local bagCount = tonumber(save.inventory[EXP_SHARE_ID]) or 0
    local pcCount = save.pcItems and tonumber(save.pcItems[EXP_SHARE_ID]) or 0
    if bagCount > 0 then
      state.itemUnlocked = true
      state.pending = false
      state.reason = "in_bag"
      return true
    end
    -- SaveData may restore a disabled mod's item to the PC when the bag is
    -- full.  Move one existing copy back only after Bag.add succeeds, so a
    -- failed transfer cannot lose or duplicate it.
    if pcCount > 0 then
      if Bag.add(save, EXP_SHARE_ID, 1, data) then
        save.pcItems[EXP_SHARE_ID] = pcCount - 1
        if save.pcItems[EXP_SHARE_ID] <= 0 then
          save.pcItems[EXP_SHARE_ID] = nil
        end
        Bag.order(save)
        state.itemUnlocked = true
        state.pending = false
        state.reason = "moved_from_pc"
        return true
      end
      state.itemUnlocked = true
      state.pending = true
      state.reason = "in_pc_bag_full"
      return true
    end
    if totalOwned(save) > 0 then
      state.itemUnlocked = true
      state.pending = false
      state.reason = "owned"
      return true
    end
    if not Bag.add(save, EXP_SHARE_ID, 1, data) then
      state.pending = true
      state.reason = "bag_full"
      return false
    end
    -- v0.1.75 appended a new id once before Bag.order's defensive pass and
    -- once during it.  Calling order now normalizes that older representation.
    Bag.order(save)
    state.itemUnlocked = true
    state.pending = false
    state.reason = "granted"
    mod.log:info("EXP.SHARE unlocked in the item bag")
    return true
  end

  local function withExpAll(save, value, fn)
    local inventory = save and save.inventory
    if not inventory then return fn() end
    local existed = inventory.EXP_ALL ~= nil
    local previous = inventory.EXP_ALL
    inventory.EXP_ALL = value
    local result
    local ok, err = xpcall(function() result = pack(fn()) end, traceback)
    if existed then inventory.EXP_ALL = previous else inventory.EXP_ALL = nil end
    if not ok then error(err, 0) end
    return unpackValues(result, 1, result.n)
  end

  local function copiedAward(ctx, alive)
    local copy = {}
    for key, value in pairs(ctx) do copy[key] = value end
    copy.alive = alive
    copy.participants = 1
    return copy
  end

  mod.hooks:wrap("battle.exp_award", function(nextFn, ctx)
    local mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla")
    state.mode = mode
    if mode == "vanilla" or type(ctx) ~= "table"
        or type(ctx.applyShare) ~= "function" then
      return nextFn(ctx)
    end
    local battle = ctx.battle
    local game = battle and battle.game
    local save = game and game.save
    if not save then return nextFn(ctx) end

    if mode == "share" then
      ensureShareItem(save, game.data)
      return withExpAll(save, 1, function() return nextFn(ctx) end)
    end

    local alive = {}
    if mode == "lead" then
      local mon = battle.player and battle.player.mon
      if mon and (mon.hp or 0) > 0 then alive[1] = mon end
    elseif mode == "party" then
      for _, mon in ipairs(save.party or {}) do
        if (mon.hp or 0) > 0 then alive[#alive + 1] = mon end
      end
    else
      return nextFn(ctx)
    end
    return withExpAll(save, nil, function()
      return nextFn(copiedAward(ctx, alive))
    end)
  end, 1000)

  local function lifecycle(payload)
    if optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla") ~= "share" then
      state.mode = optionValue(mod, EXPERIENCE_MODE_OPTION, "vanilla")
      return
    end
    local game = payload and payload.game
    local save = payload and payload.save or (game and game.save) or Game.save
    local data = game and game.data or Game.data
    ensureShareItem(save, data)
  end

  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("game.ready", lifecycle)
    mod.events:on("save.created", lifecycle)
    mod.events:on("save.loaded", lifecycle)
    mod.events:on("map.entered", lifecycle)
    mod.events:on("mod.options_changed", function(payload)
      if payload and payload.mod == mod.id
          and payload.key == EXPERIENCE_MODE_OPTION then
        state.mode = payload.value
        lifecycle({ game = Game, save = Game.save })
      end
    end)
  end
end

-- POKEMON_FINAL and DRAMATIC_SHAPE deliberately publish a module loader for
-- companion adapters. This layer uses only that public seam and supplies its
-- own tiny procedural texture and mesh; no voxel source, map data, collision,
-- connection, or disk-cache input is copied or changed.
local function findGappedLandVoxel(mod)
  local ownId, ownHandle, ownLib = findOwnVoxel(mod)
  if ownId then return ownId, ownHandle, ownLib end
  local sawSupportedId = false
  for _, id in ipairs(GAPPED_LAND_VOXEL_IDS) do
    local handle = findMod(mod, id)
    if handle then
      sawSupportedId = true
      local lib = handle.exports and handle.exports.lib
      if type(lib) == "table" and type(lib.require) == "function" then
        return id, handle, lib
      end
    end
  end
  if sawSupportedId then
    return nil, nil, nil, "voxel_exports_missing_require"
  end
  return nil, nil, nil, "no_supported_voxel_mod"
end

local function releaseGpuObject(object)
  if object and type(object.release) == "function" then
    pcall(object.release, object)
  end
end

local function installGappedLand(mod)
  local status = {
    active = false,
    reason = "no_supported_voxel_mod",
    mode = "visual_apron",
  }
  status.restore = function() return false end
  mod.exports.gappedLand = status

  local voxelId, handle, lib, findReason = findGappedLandVoxel(mod)
  if not voxelId then
    status.reason = findReason
    return status
  end
  status.voxel = voxelId
  status.providerVersion = handle.version
    or (handle.exports and handle.exports.version)

  local okModules, VoxelScene, Voxel3D, Voxel, DayNight, Mat4 =
    pcall(function()
      return lib.require("VoxelScene"), lib.require("Voxel3D"),
        lib.require("VoxelState"), lib.require("DayNight"),
        lib.require("Mat4")
    end)
  if not okModules
      or type(VoxelScene) ~= "table"
      or type(VoxelScene.render) ~= "function"
      or type(Voxel3D) ~= "table"
      or type(Voxel3D.beginScene) ~= "function"
      or type(Voxel3D.newMesh) ~= "function"
      or type(Voxel3D.draw) ~= "function"
      or type(Voxel3D.invalidate) ~= "function"
      or type(Voxel3D.seams) ~= "function"
      or type(Voxel3D.glass) ~= "function"
      or type(Voxel) ~= "table"
      or type(Voxel.isFreeCam) ~= "function"
      or type(DayNight) ~= "table"
      or type(DayNight.isCanopy) ~= "function"
      or type(Mat4) ~= "table"
      or type(Mat4.translate) ~= "function" then
    status.reason = "exported_scene_modules_unavailable"
    return status
  end

  local existingScene = rawget(VoxelScene, GAPPED_LAND_RENDER_MARKER)
  local existingInvalidate = rawget(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER)
  if existingScene ~= nil or existingInvalidate ~= nil then
    local sameOwner = type(existingScene) == "table"
      and type(existingInvalidate) == "table"
      and existingScene.owner == mod.id
      and existingInvalidate.owner == mod.id
      and existingScene.controller ~= nil
      and existingScene.controller == existingInvalidate.controller
      and type(existingScene.controller.restore) == "function"
      and type(existingScene.wrapper) == "function"
      and type(existingInvalidate.wrapper) == "function"
    if not sameOwner then
      status.reason = "renderer_hook_owned_by_another_mod"
      return status
    end

    -- A hot reload may construct a fresh mod facade while exported voxel
    -- modules persist. Keep one wrapper and point its live option lookup and
    -- logging at the fresh facade instead of multiplying the draw.
    existingScene.controller.mod = mod
    status.active = true
    status.reason = "already_installed"
    status.restore = function()
      local changed = existingScene.controller.restore()
      if changed then
        status.active = false
        status.reason = "restored"
      end
      return changed
    end
    return status
  end

  local controller = {
    mod = mod,
    mesh = nil,
    texture = nil,
    warnedDraw = false,
    warnedBuild = false,
  }

  local function clearGpuObjects()
    local mesh, texture = controller.mesh, controller.texture
    controller.mesh, controller.texture = nil, nil
    if mesh ~= false then releaseGpuObject(mesh) end
    if texture ~= false then releaseGpuObject(texture) end
  end

  local function buildMesh()
    if controller.mesh ~= nil then return controller.mesh or nil end
    local verts, indices = {}, {}
    local radius, cell = GAPPED_LAND_RADIUS, GAPPED_LAND_CELL
    for x = -radius, radius - cell, cell do
      for z = -radius, radius - cell, cell do
        local base = #verts
        local u0, v0 = (x + radius) / cell, (z + radius) / cell
        local u1, v1 = u0 + 1, v0 + 1
        -- Four vertices per cell keep the quadratic world curve smooth all
        -- the way to the backdrop instead of bending one enormous quad.
        verts[#verts + 1] = { x, 0, z, u0, v0, 1 }
        verts[#verts + 1] = { x + cell, 0, z, u1, v0, 1 }
        verts[#verts + 1] = { x + cell, 0, z + cell, u1, v1, 1 }
        verts[#verts + 1] = { x, 0, z + cell, u0, v1, 1 }
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 2
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 4
      end
    end
    controller.mesh = Voxel3D.newMesh(verts, indices) or false
    return controller.mesh or nil
  end

  local function buildTexture()
    if controller.texture ~= nil then return controller.texture or nil end
    local imageApi = love and love.image
    local graphics = love and love.graphics
    if not (imageApi and type(imageApi.newImageData) == "function"
        and graphics and type(graphics.newImage) == "function") then
      controller.texture = false
      return nil
    end

    local data
    local ok, texture = pcall(function()
      data = imageApi.newImageData(8, 8)
      for y = 0, 7 do
        for x = 0, 7 do
          local light = (math.floor(x / 4) + math.floor(y / 4)) % 2 == 0
          local r, g, b = 0.30, 0.48, 0.18
          if light then r, g, b = 0.35, 0.55, 0.21 end
          -- A sparse third green keeps the procedural floor from reading as
          -- a flat debug colour while remaining quiet behind real terrain.
          if (x * 7 + y * 11) % 17 == 0 then
            r, g, b = 0.39, 0.59, 0.24
          end
          data:setPixel(x, y, r, g, b, 1)
        end
      end
      local image = graphics.newImage(data)
      if type(image.setFilter) == "function" then
        image:setFilter("nearest", "nearest")
      end
      if type(image.setWrap) == "function" then
        image:setWrap("repeat", "repeat")
      end
      return image
    end)
    releaseGpuObject(data)
    controller.texture = (ok and texture) or false
    return controller.texture or nil
  end

  local function eligible(state)
    local liveMod = controller.mod
    if not optionEnabled(liveMod, GAPPED_LAND_OPTION, true) then return false end
    local map = state and state.map
    local def = map and map.def
    if not def or GAPPED_LAND_SEA_MAPS[map.id] then return false end

    local tileset = def.tileset
    if not tileset and type(map.tileset) == "table" then
      tileset = map.tileset.id
    end
    if tileset == "SHIP_PORT" then return false end

    local okOutdoor, outdoor = pcall(Map.isOutdoor, def)
    if not okOutdoor or not outdoor then return false end
    local okCanopy, canopy = pcall(DayNight.isCanopy, map)
    if not okCanopy or canopy then return false end
    local okCamera, freeCamera = pcall(Voxel.isFreeCam)
    return okCamera and freeCamera == true
  end

  local function focusPoint(state)
    local focus = Voxel3D.focus
    local fx = type(focus) == "table" and finiteNumber(focus[1]) or nil
    local fz = type(focus) == "table" and finiteNumber(focus[3]) or nil
    if fx and fz then return fx, fz end

    local player = state and state.player
    local px = player and finiteNumber(player.px) or nil
    local pz = player and finiteNumber(player.py) or nil
    if px and pz then return px + 8, pz + 8 end

    local def = state and state.map and state.map.def
    return finiteNumber(def and def.width, 1) * 16,
      finiteNumber(def and def.height, 1) * 16
  end

  local function draw(state)
    if not eligible(state) then return end
    local mesh, texture = buildMesh(), buildTexture()
    if not (mesh and texture) then
      if not controller.warnedBuild then
        controller.warnedBuild = true
        controller.mod.log:warn("GAPPED LAND GPU objects are unavailable; leaving the native horizon unchanged")
      end
      return
    end

    local fx, fz = focusPoint(state)
    local cell = GAPPED_LAND_CELL
    local cx = math.floor(fx / cell) * cell
    local cz = math.floor(fz / cell) * cell

    -- This draw is deliberately before Backdrop/terrain. It writes ordinary
    -- depth at y=-40; the native y=-2..-37 apron, terrain and water rendered
    -- later therefore remain authoritative everywhere they exist.
    local okDraw, drawErr = xpcall(function()
      Voxel3D.seams(false)
      Voxel3D.glass(false)
      Voxel3D.draw(mesh, texture, Mat4.translate(cx, GAPPED_LAND_Y, cz))
    end, traceback)
    -- beginScene establishes seams/glass=true before this first draw. These
    -- setters normally cannot fail, but a provider/driver error must
    -- not leave later terrain sampling this procedural texture as glass or
    -- carrying its non-voxel wireframe state.
    pcall(Voxel3D.glass, true)
    pcall(Voxel3D.seams, true)
    if not okDraw then error(drawErr, 0) end
  end

  local originalRender = VoxelScene.render
  local originalInvalidate = Voxel3D.invalidate

  local function wrappedRender(state, ...)
    local renderArgs = pack(...)
    local innerBegin = Voxel3D.beginScene
    local wrappedBegin
    wrappedBegin = function(...)
      local beginArgs = pack(...)
      local began = pack(innerBegin(unpackValues(beginArgs, 1, beginArgs.n)))
      if began[1] then
        local okDraw, drawErr = xpcall(function() draw(state) end, traceback)
        if not okDraw and not controller.warnedDraw then
          controller.warnedDraw = true
          controller.mod.log:warn("GAPPED LAND skipped after a draw error: %s",
            tostring(drawErr))
        end
      end
      return unpackValues(began, 1, began.n)
    end

    rawset(Voxel3D, "beginScene", wrappedBegin)
    local rendered
    local okRender, renderErr = xpcall(function()
      rendered = pack(originalRender(state,
        unpackValues(renderArgs, 1, renderArgs.n)))
    end, traceback)
    -- Never leave a frame-local interception in the provider, and never
    -- overwrite a third party that deliberately replaced it during render.
    if rawget(Voxel3D, "beginScene") == wrappedBegin then
      rawset(Voxel3D, "beginScene", innerBegin)
    end
    if not okRender then error(renderErr, 0) end
    return unpackValues(rendered, 1, rendered.n)
  end

  local function wrappedInvalidate(...)
    local invalidateArgs = pack(...)
    local result
    local okInvalidate, invalidateErr = xpcall(function()
      result = pack(originalInvalidate(
        unpackValues(invalidateArgs, 1, invalidateArgs.n)))
    end, traceback)
    clearGpuObjects()
    if not okInvalidate then error(invalidateErr, 0) end
    return unpackValues(result, 1, result.n)
  end

  local sceneMarker = {
    owner = mod.id,
    version = RELEASE_VERSION,
    original = originalRender,
    wrapper = wrappedRender,
    controller = controller,
  }
  local invalidateMarker = {
    owner = mod.id,
    version = RELEASE_VERSION,
    original = originalInvalidate,
    wrapper = wrappedInvalidate,
    controller = controller,
  }

  controller.restore = function()
    -- Refuse a partial unhook if another adapter currently wraps either
    -- function outside ours. Its owner can restore first and this can be
    -- retried without severing anyone's call chain.
    if rawget(VoxelScene, GAPPED_LAND_RENDER_MARKER) ~= sceneMarker
        or rawget(VoxelScene, "render") ~= wrappedRender
        or rawget(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER) ~= invalidateMarker
        or rawget(Voxel3D, "invalidate") ~= wrappedInvalidate then
      return false
    end
    rawset(VoxelScene, "render", originalRender)
    rawset(VoxelScene, GAPPED_LAND_RENDER_MARKER, nil)
    rawset(Voxel3D, "invalidate", originalInvalidate)
    rawset(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER, nil)
    clearGpuObjects()
    return true
  end
  status.restore = function()
    local changed = controller.restore()
    if changed then
      status.active = false
      status.reason = "restored"
    end
    return changed
  end

  -- Shared-table writes are the final installation actions after all public
  -- capabilities and ownership markers have been checked.
  rawset(Voxel3D, "invalidate", wrappedInvalidate)
  rawset(Voxel3D, GAPPED_LAND_INVALIDATE_MARKER, invalidateMarker)
  rawset(VoxelScene, "render", wrappedRender)
  rawset(VoxelScene, GAPPED_LAND_RENDER_MARKER, sceneMarker)

  status.active = true
  status.reason = "attached"
  mod.log:info("GAPPED LAND visual apron attached to %s", voxelId)
  return status
end

local function installBadgeFreeFieldMoves(mod)
  -- Cut and Surf ask this hook again when the move is used. Calling next
  -- first preserves every vanilla or earlier-mod success; we only widen a
  -- rejected answer for one of the five badge-gated Gen 1 HMs.
  mod.hooks:wrap("fieldmove.eligibility",
    function(nextFn, wanted, ctx)
      local vanilla = nextFn(wanted, ctx)
      if vanilla ~= nil then return vanilla end
      if not optionEnabled(mod, "hm_without_badges", true)
          or HM_ACTIONS[wanted] == nil then
        return nil
      end
      local save = (ctx and ctx.save) or Game.save
      return partyMemberKnowing(save, wanted)
    end, 1000)

  -- Vanilla hides HM actions from the party submenu when the badge is
  -- missing. Add only those hidden rows, in the Pokemon's actual move order,
  -- while preserving terrain/context rules and entries supplied by other
  -- mods. Nothing is taught and no badge/save flag is changed.
  mod.hooks:wrap("ui.party.submenu",
    function(nextFn, game, items, mon, ctx)
      local downstream = nextFn(game, items, mon, ctx)
      if type(downstream) == "table" then items = downstream end
      if type(items) ~= "table"
          or not optionEnabled(mod, "hm_without_badges", true)
          or (ctx and ctx.battle)
          or not (ctx and ctx.overworld) then
        return items
      end

      local ow = ctx.overworld
      local outside = ow.map and ow.map.def and Map.isOutside(
        ow.map.def, FieldDefaults.field(game.data, "outsideTilesets")) or false
      local existing = {}
      local insertAt = #items + 1
      for index, item in ipairs(items) do
        if type(item) == "table" then
          if item.action then existing[item.action] = true end
          if insertAt == #items + 1
              and (item.action == "stats" or item.action == "switch") then
            insertAt = index
          end
        end
      end

      for _, move in ipairs((mon and mon.moves) or {}) do
        local id = moveId(move)
        local action = HM_ACTIONS[id]
        local contextAllows = action ~= nil
          and (id ~= "FLY" or outside)
          and (id ~= "FLASH" or ow.dark == true)
        if contextAllows and not existing[action] then
          table.insert(items, insertAt, { label = id, action = action })
          existing[action] = true
          insertAt = insertAt + 1
        end
      end
      return items
    end, 1000)

  mod.exports.hmWithoutBadges = function()
    return optionEnabled(mod, "hm_without_badges", true)
  end
end

-- Free Fly performs its takeoff and water-landing badge tests outside the
-- engine's fieldmove.eligibility hook. Feature-detect the public flight-state
-- export and the exact toggle in its registered option schema before applying
-- a live option overlay. No badge, move, story flag, or persisted Free Fly
-- preference is edited.
local function installFreeFlyImmediateFlight(mod)
  local state = {
    active = false,
    reason = "free_fly_not_active",
  }
  local activeLoader
  local activeBucketId
  local activeKey
  local activeHosted = false
  local priorSet = false
  local priorValue
  local priorBucketExisted = false

  local function findFreeFly()
    local host = mod.exports and mod.exports.vendorHost
    local bundled = host and host.loaded and host.loaded[FREE_FLY_ID]
    local handle = findMod(mod, FREE_FLY_ID)
    return handle, handle ~= nil and handle == bundled
  end

  local function compatible(handle, loader, hosted)
    local exports = handle and handle.exports
    if type(exports) ~= "table" or type(exports.isFlying) ~= "function" then
      return false, "flight_state_export_missing"
    end
    local schema
    if hosted then
      local host = mod.exports and mod.exports.vendorHost
      schema = host and host.schemas and host.schemas[FREE_FLY_ID]
    else
      local schemas = loader and loader.optionSchemas
      schema = schemas and schemas[FREE_FLY_ID]
    end
    if type(schema) ~= "table" then
      return false, "option_schema_missing"
    end
    for _, row in ipairs(schema) do
      if type(row) == "table" and row.key == FREE_FLY_BADGES_KEY
          and row.type == "toggle" then
        return true
      end
    end
    return false, "badges_toggle_missing"
  end

  local function restore()
    local loader = activeLoader
    local buckets = loader and loader.modOptions
    local bucket = buckets and activeBucketId and buckets[activeBucketId]
    if bucket then
      if priorSet then
        bucket[activeKey] = priorValue
      else
        bucket[activeKey] = nil
      end
      if not priorBucketExisted and next(bucket) == nil then
        buckets[activeBucketId] = nil
      end
    end
    activeLoader = nil
    activeBucketId = nil
    activeKey = nil
    activeHosted = false
    priorSet, priorValue, priorBucketExisted = false, nil, false
    state.active = false
    state.hosted = false
    state.reason = "disabled"
  end

  local function apply(loader)
    if not optionEnabled(mod, FREE_FLY_OPTION, true) then
      if activeLoader then restore() end
      state.reason = "disabled"
      return false
    end

    local handle, hosted = findFreeFly()
    if not handle then
      state.active = false
      state.reason = "free_fly_not_active"
      return false
    end
    if type(loader) ~= "table" then
      state.active = false
      state.reason = "loader_unavailable"
      return false
    end
    local isCompatible, compatibilityReason = compatible(handle, loader, hosted)
    if not isCompatible then
      state.active = false
      state.reason = "unsupported_free_fly_" .. tostring(compatibilityReason)
      mod.log:warn("Free Fly does not expose the supported badge-check adapter (%s)",
        tostring(compatibilityReason))
      return false
    end

    loader.modOptions = loader.modOptions or {}
    local bucketId = hosted and mod.id or FREE_FLY_ID
    local optionKey = hosted
      and (FREE_FLY_ID .. ":" .. FREE_FLY_BADGES_KEY)
      or FREE_FLY_BADGES_KEY
    local bucket = loader.modOptions[bucketId]
    if activeLoader ~= loader or activeBucketId ~= bucketId
        or activeKey ~= optionKey then
      if activeLoader then restore() end
      priorBucketExisted = bucket ~= nil
      bucket = bucket or {}
      loader.modOptions[bucketId] = bucket
      priorSet = bucket[optionKey] ~= nil
      priorValue = bucket[optionKey]
      activeLoader = loader
      activeBucketId = bucketId
      activeKey = optionKey
      activeHosted = hosted
    else
      bucket = bucket or {}
      loader.modOptions[bucketId] = bucket
    end
    bucket[optionKey] = false
    state.active = true
    state.reason = hosted and "hosted_badges_runtime_override"
      or "badges_runtime_override"
    state.version = handle.version
      or (handle.exports and handle.exports.version)
    state.hosted = hosted
    return true
  end

  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("mods.loaded", function(payload)
      apply(payload and payload.loader or Game.mods)
    end)
    mod.events:on("mod.options_changed", function(payload)
      if not payload then return end
      if payload.mod == mod.id and payload.key == FREE_FLY_OPTION then
        if payload.value == true then apply(Game.mods) else restore() end
      elseif state.active and ((not activeHosted
            and payload.mod == FREE_FLY_ID
            and payload.key == FREE_FLY_BADGES_KEY)
          or (activeHosted
            and ((payload.mod == mod.id
                  and payload.key == FREE_FLY_ID .. ":" .. FREE_FLY_BADGES_KEY)
              or (payload.mod == FREE_FLY_ID
                  and payload.key == FREE_FLY_BADGES_KEY)))) then
        -- Keep the player's latest Free Fly preference ready for restoration if
        -- Scott's override is later switched off, but hold the live answer
        -- false while the override remains enabled.
        priorSet = payload.value ~= nil
        priorValue = payload.value
        local buckets = activeLoader and activeLoader.modOptions
        local bucket = buckets and activeBucketId and buckets[activeBucketId]
        if bucket then bucket[activeKey] = false end
      end
    end)
  end

  apply(Game.mods)

  mod.exports.freeFlyBadgeBypass = function()
    return state.active, state.reason, state.version
  end
end

-- Free Fly 1.6.2 and the bundled 1.8.0 draw a second mount picture in render.hud
-- whenever Battle Art hides the player's world card for first person. Scott
-- prefers a clear first-person view. Keep this as a narrow presentation
-- adapter instead of editing Free Fly: its public isFlying export establishes
-- the flight state, and the voxel provider's published FirstPerson module
-- establishes whether the world card is hidden. During only the downstream
-- HUD chain, make that one query answer false so Free Fly omits its cockpit
-- picture. The 3D scene has already rendered by this point, so the actual
-- first-person player-card rule is unchanged; third person, movement, mount
-- state, collision and landing never pass through this adapter.
local function installFreeFlyCockpitControl(mod)
  local status = {
    active = false,
    reason = "free_fly_not_active",
  }
  mod.exports.freeFlyCockpitControl = status

  local handle = findMod(mod, FREE_FLY_ID)
  if not handle then return status end
  local exports = handle.exports
  if type(exports) ~= "table" or type(exports.isFlying) ~= "function" then
    status.reason = "flight_state_export_missing"
    return status
  end

  local version = handle.version or exports.version
  status.version = version
  -- These releases use the same verified hidePlayer-gated HUD implementation.
  -- A future Free Fly may publish its own cockpit option or change that draw
  -- gate; standing aside is safer than pretending an internal contract held.
  local supportedHud = version == "1.6.2" or version == "1.8.0"
  if not supportedHud then
    status.reason = "unsupported_free_fly_version"
    return status
  end

  local voxelId, _, lib = findVoxelMod(mod)
  if not voxelId or type(lib) ~= "table" or type(lib.require) ~= "function" then
    status.reason = "voxel_provider_unavailable"
    return status
  end
  local okFirstPerson, FirstPerson = pcall(lib.require, "FirstPerson")
  local originalHide = okFirstPerson and type(FirstPerson) == "table"
    and rawget(FirstPerson, "hidePlayer") or nil
  if type(originalHide) ~= "function" then
    status.reason = "first_person_visibility_api_missing"
    return status
  end

  local warnedReplacement = false
  mod.hooks:wrap("render.hud", function(nextFn, game, viewport)
    if optionEnabled(mod, FREE_FLY_COCKPIT_OPTION, false) then
      return nextFn(game, viewport)
    end

    local okFlying, isFlying = pcall(exports.isFlying)
    if not okFlying or isFlying ~= true then
      return nextFn(game, viewport)
    end
    if rawget(FirstPerson, "hidePlayer") ~= originalHide then
      status.active = false
      status.reason = "first_person_visibility_api_replaced"
      if not warnedReplacement then
        warnedReplacement = true
        mod.log:warn("FLY COCKPIT control stood aside after the FirstPerson visibility API changed")
      end
      return nextFn(game, viewport)
    end

    local okHidden, hidden = pcall(originalHide)
    if not okHidden or hidden ~= true then
      return nextFn(game, viewport)
    end

    local function cockpitSuppressed()
      return false
    end
    rawset(FirstPerson, "hidePlayer", cockpitSuppressed)
    local result
    local okHud, hudErr = xpcall(function()
      result = pack(nextFn(game, viewport))
    end, traceback)
    -- Restore only our own frame-local substitution. If another adapter
    -- deliberately replaced the function during the downstream call, never
    -- overwrite its newer ownership.
    if rawget(FirstPerson, "hidePlayer") == cockpitSuppressed then
      rawset(FirstPerson, "hidePlayer", originalHide)
    end
    if not okHud then error(hudErr, 0) end
    return unpackValues(result, 1, result.n)
  end, 10000)

  status.active = true
  status.reason = "first_person_hud_overlay_controlled"
  status.voxel = voxelId
  return status
end

local function resolvedFrames(player, onBike)
  local base = (onBike and player.bikeStepFrames) or player.stepFrames or 16
  base = math.max(1, math.floor(finiteNumber(base, 16)))

  local save = Game.save
  local value = Runtime.call(
    "movement.speed",
    function(frames) return frames end,
    base,
    {
      onBike = onBike,
      surfing = player.surfing and true or false,
      player = player,
      input = Game.input,
      save = save,
      freeMove = true,
      continuous = true,
    }
  )
  value = finiteNumber(value, base)
  return base, math.max(1, math.floor(value))
end

return function(mod)
  -- The fused renderer registers render pipelines and must be up before any
  -- option definition or feature module consults it.
  -- Integrity first: a half-copied install must say so in the log and the
  -- menu before anything downstream fails in stranger ways.
  do
    local check = loadOwn(mod, "modules/integrity.lua")
    if type(check) == "function" then pcall(check, mod) end
  end
  local vendorHost = newVendorHost(mod)
  installBattleArt(hostedHandle(mod, vendorHost))
  installVendoredMods(mod, vendorHost)
  defineOptions(mod, vendorHost)
  installFeatureModules(mod)
  -- These are ordinary bag/battle features and must remain available even
  -- when the player is using 2D mode or has no supported voxel renderer.
  installInventoryFeatures(mod)
  installExperienceModes(mod)
  installBadgeFreeFieldMoves(mod)
  installFreeFlyImmediateFlight(mod)
  installFreeFlyCockpitControl(mod)
  installPokemonFinalCacheCompatibility(mod)
  installGappedLand(mod)

  mod.exports.status = {
    active = false,
    reason = "no_supported_voxel_mod",
  }

  local voxelId, _, lib = findVoxelMod(mod)
  if not voxelId then
    mod.log:info("no supported voxel mod is active; bridge is idle")
    return
  end

  -- Running Shoes 0.2.2+ already carries its own integration for Dramatic
  -- Shape and Battle Art Voxel Fork. Let it remain the single owner there,
  -- otherwise the same multiplier would be applied twice.
  if lib._runningShoesHook then
    mod.exports.status = {
      active = false,
      voxel = voxelId,
      reason = "running_shoes_has_native_voxel_support",
    }
    mod.log:info("%s already has Running Shoes integration; bridge is idle", voxelId)
    return
  end

  local exportedBridge = lib._voxelRunBridgeHook
  if exportedBridge and not (type(exportedBridge) == "table"
      and exportedBridge.owner == mod.id
      and exportedBridge.dispatcher == true) then
    mod.exports.status = {
      active = false,
      voxel = voxelId,
      reason = "already_installed",
    }
    mod.log:info("%s is already bridged", voxelId)
    return
  end

  if type(lib.require) ~= "function" then
    mod.exports.status.reason = "voxel_exports_missing_require"
    mod.log:warn("%s does not export its module loader", voxelId)
    return
  end

  local okModule, FreeMove = pcall(lib.require, "FreeMove")
  if not okModule or type(FreeMove) ~= "table"
      or type(FreeMove.tick) ~= "function" then
    mod.exports.status.reason = "voxel_freemove_unavailable"
    mod.log:warn("%s does not expose a compatible FreeMove module", voxelId)
    return
  end

  local persistentBridge = rawget(FreeMove, VOXEL_BRIDGE_MARKER)
  if type(persistentBridge) == "table"
      and persistentBridge.owner == mod.id
      and persistentBridge.dispatcher == true then
    persistentBridge.mod = mod
    persistentBridge.voxel = voxelId
    persistentBridge.version = RELEASE_VERSION
    rawset(lib, "_voxelRunBridgeHook", persistentBridge)
    mod.exports.status = {
      active = true, voxel = voxelId, mode = "movement.speed",
      reason = "dispatcher_refreshed",
    }
    mod.log:info("%s movement.speed dispatcher refreshed", voxelId)
    return
  elseif persistentBridge then
    mod.exports.status = {
      active = false, voxel = voxelId, reason = "bridge_hook_owned",
    }
    mod.log:warn("%s FreeMove bridge is owned by another adapter", voxelId)
    return
  end

  -- Running Shoes 1.7+ publishes its native voxel wrapper on FreeMove
  -- itself, not on the exported library table used by older integrations.
  -- Trust the paired ownership markers even when another mod subsequently
  -- wraps tick outside it: the shoes' wrapper is still in that call chain,
  -- and adding ours would apply the movement multiplier twice.
  if runningShoesOwnsFreeMove(FreeMove) then
    mod.exports.status = {
      active = false,
      voxel = voxelId,
      reason = "running_shoes_has_native_voxel_support",
    }
    mod.log:info("%s FreeMove is already owned by Running Shoes; bridge is idle",
      voxelId)
    return
  end

  local innerTick = FreeMove.tick
  local bridge = {
    owner = mod.id, version = RELEASE_VERSION, dispatcher = true,
    original = innerTick, mod = mod, voxel = voxelId,
    warnedSpeedError = false, delegatedToNativeShoes = false,
  }

  local function bridgedTick(state)
    -- MadeinTaly Running Shoes 1.7 attaches its native wrapper lazily from
    -- input.step, so the ownership markers can appear after this bridge was
    -- installed. In that ordering its wrapper sits outside ours and has
    -- already scaled FreeMove; become a pass-through before sampling the
    -- movement.speed hook or the same run would be multiplied twice.
    if runningShoesOwnsFreeMove(FreeMove) then
      if not bridge.delegatedToNativeShoes then
        bridge.delegatedToNativeShoes = true
        bridge.mod.exports.status = {
          active = false,
          voxel = bridge.voxel,
          reason = "running_shoes_has_native_voxel_support",
        }
        bridge.mod.log:info("%s FreeMove gained native Running Shoes support; bridge is idle",
          bridge.voxel)
      end
      return innerTick(state)
    elseif bridge.delegatedToNativeShoes then
      bridge.delegatedToNativeShoes = false
      bridge.mod.exports.status = {
        active = true,
        voxel = bridge.voxel,
        mode = "movement.speed",
      }
      bridge.mod.log:info("%s native Running Shoes wrapper left; bridge resumed",
        bridge.voxel)
    end

    local player = state and state.player

    -- FreeMove itself stands aside during scripted movement. Do the same
    -- before consulting speed hooks, so cutscenes and NPC-controlled walks
    -- cannot inherit a held run button through this bridge.
    if not player or player.moving or player.inputLocked then
      return innerTick(state)
    end

    -- With no producer there is nothing to translate. This path is hit by
    -- players who installed the bridge before choosing a running mod.
    if not Runtime.wantsHook("movement.speed") then
      return innerTick(state)
    end

    local save = Game.save
    local onBike = save and save.onBike and true or false
    local speedKey = onBike and "BIKE" or "WALK"
    local speedBefore = FreeMove[speedKey]
    if finiteNumber(speedBefore) ~= speedBefore or speedBefore <= 0 then
      return innerTick(state)
    end

    local baseFrames, effectiveFrames
    local okSpeed, speedErr = pcall(function()
      baseFrames, effectiveFrames = resolvedFrames(player, onBike)
    end)

    if not okSpeed then
      if not bridge.warnedSpeedError then
        bridge.warnedSpeedError = true
        bridge.mod.log:warn("movement.speed bridge failed; using voxel default: %s",
          tostring(speedErr))
      end
      return innerTick(state)
    end

    local multiplier = baseFrames / effectiveFrames
    FreeMove[speedKey] = speedBefore * multiplier

    local result
    local okTick, tickErr = xpcall(function()
      result = pack(innerTick(state))
    end, traceback)

    -- Never leak a temporary speed into a later frame or another mod, even
    -- when the wrapped voxel tick throws.
    FreeMove[speedKey] = speedBefore

    if not okTick then error(tickErr, 0) end
    return unpackValues(result, 1, result.n)
  end

  mod.exports.status = {
    active = true,
    voxel = voxelId,
    mode = "movement.speed",
  }
  mod.log:info("bridging movement.speed into %s FreeMove", voxelId)

  -- These raw assignments are the final installation actions. Keeping all
  -- validation and logging above them avoids leaving half an adapter behind
  -- if setup fails.
  rawset(FreeMove, "tick", bridgedTick)
  bridge.wrapper = bridgedTick
  rawset(FreeMove, VOXEL_BRIDGE_MARKER, bridge)
  rawset(lib, "_voxelRunBridgeHook", bridge)
end
