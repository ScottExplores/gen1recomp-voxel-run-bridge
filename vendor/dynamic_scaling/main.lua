return function(mod)
  mod.log:info("Dynamic Level Scaling, Randomizer & Modular Difficulty Loaded")

  local BattleState = require("src.battle.BattleState")

  -- =====================================================================
  -- GLOBAL SETTINGS & OPTIONS MENU INTEGRATION
  -- =====================================================================
  local C = _G.__DYNAMIC_SCALING or {}
  _G.__DYNAMIC_SCALING = C

  local MODES = { off = true, normal = true, medium = true, hard = true }
  local MODE_KEYS = {
    trainer = "trainer_difficulty",
    boss = "boss_difficulty",
    wild = "wild_difficulty",
  }
  local MODE_FIELDS = {
    trainer = "trainerDifficulty",
    boss = "bossDifficulty",
    wild = "wildDifficulty",
  }

  local function modeValue(value)
    return MODES[value] and value or nil
  end

  local function optionValue(key)
    if not (mod.options and mod.options.get) then return nil end
    local ok, value = pcall(mod.options.get, mod.options, key)
    return ok and value or nil
  end

  -- Read the actual save/Loader buckets rather than treating a schema default
  -- as an explicitly chosen value.  That distinction is what lets an old
  -- `difficulty = medium` save seed all three new controls, even though each
  -- new schema row quite correctly defaults to OFF for a new installation.
  local function storedOption(game, key)
    if mod.options and type(mod.options.override) == "function" then
      local effective = mod.options:override(key, nil)
      if effective ~= nil then return effective, true end
    end
    local hosted = mod.options and mod.options.hosted
    local holders = {}
    local function add(holder)
      if type(holder) == "table" then holders[#holders + 1] = holder end
    end
    add(game and game.save and game.save.options)
    add(game and game.mods)
    add(game and game.mods and game.mods.loader)
    for _, holder in ipairs(holders) do
      local root = holder and holder.modOptions
      if type(root) == "table" then
        if type(hosted) == "table" then
          local bucket = root[hosted.hostId]
          local value = type(bucket) == "table"
            and bucket[(hosted.prefix or "") .. key] or nil
          if value ~= nil then return value, true end

          -- Standalone Dynamic Scaling used its own bucket.  Retaining this
          -- fallback makes a save portable into the fused Scott's Tweaks
          -- build without asking the player to recreate its settings.
          local legacy = root[hosted.vendorId]
          value = type(legacy) == "table" and legacy[key] or nil
          if value ~= nil then return value, true end
        else
          local bucket = root[mod.id]
          local value = type(bucket) == "table" and bucket[key] or nil
          if value ~= nil then return value, true end
        end
      end
    end
    return nil, false
  end

  local function liveGame()
    local ok, game = pcall(require, "src.core.Game")
    return ok and type(game) == "table" and game or nil
  end

  -- Capture values before define() installs the new OFF defaults.  On a fresh
  -- hosted load these calls can only see values that were really stored.
  local startup = {
    randomize = optionValue("randomize"),
    legacy = modeValue(optionValue("difficulty")),
  }
  for kind, key in pairs(MODE_KEYS) do
    startup[kind] = modeValue(optionValue(key))
  end

  if mod.options and mod.options.define then
    mod.options:define({
      {
        key = "randomize", type = "choice", label = "Trainer Randomizer",
        choices = {
          { "Off (Vanilla Teams)", "off" },
          { "Chaos (Any Pokemon)", "chaos" },
          { "Themed (Class-based)", "themed" }
        },
        default = "off"
      },
      {
        key = MODE_KEYS.trainer, type = "choice", label = "Trainer Difficulty",
        choices = {
          { "Off (Vanilla)", "off" },
          { "Normal (+2 Lvs)", "normal" },
          { "Medium (+5 Lvs, Max DVs)", "medium" },
          { "Hard (+10 Lvs, 6 Mons, Max EVs)", "hard" }
        },
        default = "off"
      },
      {
        key = MODE_KEYS.boss, type = "choice", label = "Boss Difficulty",
        choices = {
          { "Off (Vanilla)", "off" },
          { "Normal (+2 Lvs)", "normal" },
          { "Medium (+5 Lvs, Max DVs)", "medium" },
          { "Hard (+10 Lvs, 6 Mons, Max EVs)", "hard" }
        },
        default = "off"
      },
      {
        key = MODE_KEYS.wild, type = "choice", label = "Wild Pokemon Difficulty",
        choices = {
          { "Off (Vanilla)", "off" },
          { "Normal (+2 Lvs)", "normal" },
          { "Medium (+5 Lvs, Max DVs)", "medium" },
          { "Hard (+10 Lvs, Max EVs)", "hard" }
        },
        default = "off"
      }
    })
  end

  C.randomize = startup.randomize or C.randomize or "off"
  C.explicitModes = C.explicitModes or {}

  local function refreshOptions(game, migrate)
    game = game or liveGame()
    local legacy = storedOption(game, "difficulty")
    local standaloneStartupLegacy = not (mod.options and mod.options.hosted)
      and startup.legacy or nil
    legacy = modeValue(legacy) or standaloneStartupLegacy
    local hasLegacy = legacy ~= nil

    local missing = {}
    for kind, key in pairs(MODE_KEYS) do
      local value, explicit = storedOption(game, key)
      value = modeValue(value)
      if not explicit and not (mod.options and mod.options.hosted) then
        value = startup[kind]
        explicit = value ~= nil
      end
      local field = MODE_FIELDS[kind]
      C[field] = value or (hasLegacy and legacy) or "off"
      C.explicitModes[kind] = explicit
      if hasLegacy and not explicit then
        missing[#missing + 1] = { key = key, value = legacy }
      end
    end

    local randomize = optionValue("randomize")
    if randomize ~= nil then C.randomize = randomize end

    -- One fused write seeds every missing key.  Keeping the old key in place
    -- is intentional: if a player temporarily returns to an older release,
    -- its single control still has the exact behavior they previously chose.
    if migrate and #missing > 0 and type(game) == "table" then
      local ok, detail
      if mod.options and type(mod.options.writeMany) == "function" then
        ok, detail = mod.options:writeMany(game, missing)
      else
        -- Standalone fallback.  The fused handle always supplies writeMany,
        -- but upstream-style installs still receive a one-write transaction.
        local opts = game.save and game.save.options
        local loader = game.mods
        if opts then
          opts.modOptions = opts.modOptions or {}
          opts.modOptions[mod.id] = opts.modOptions[mod.id] or {}
        end
        if loader then
          loader.modOptions = loader.modOptions or {}
          loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
        end
        for _, change in ipairs(missing) do
          if opts then opts.modOptions[mod.id][change.key] = change.value end
          if loader then loader.modOptions[mod.id][change.key] = change.value end
        end
        if game.writeOptions then
          local called, result, err = pcall(game.writeOptions, game)
          ok = called and result ~= false
          detail = called and err or result
        else
          ok = true
        end
      end
      if ok then
        for kind, key in pairs(MODE_KEYS) do
          for _, change in ipairs(missing) do
            if change.key == key then C.explicitModes[kind] = true end
          end
        end
      elseif mod.log and mod.log.warn then
        mod.log:warn("could not migrate legacy difficulty controls: %s",
          tostring(detail or "options write rejected"))
      end
    end
  end
  refreshOptions(nil, false)

  local function lifecycle(payload)
    local game = type(payload) == "table" and payload.game or nil
    refreshOptions(game or liveGame(), true)
  end
  if mod.events and mod.events.on then
    mod.events:on("game.ready", lifecycle)
    mod.events:on("save.created", lifecycle)
    mod.events:on("save.loaded", lifecycle)
  end

  -- A hot reload can occur after game.ready.  Reconcile immediately only when
  -- a real save is already attached; otherwise the lifecycle hooks above own
  -- the first migration and cannot accidentally create an empty pre-load save.
  local currentGame = liveGame()
  if currentGame and currentGame.save and currentGame.save.options then
    refreshOptions(currentGame, true)
  end

  mod.events:on("mod.options_changed", function(p)
    if p and p.mod == mod.id then
      if mod.options and type(mod.options.override) == "function" then
        local effective = mod.options:override(p.key, nil)
        if effective ~= nil then
          refreshOptions(nil, false)
          return
        end
      end
      if p.key == "randomize" then C.randomize = p.value end
      for kind, key in pairs(MODE_KEYS) do
        if p.key == key and modeValue(p.value) then
          C[MODE_FIELDS[kind]] = p.value
          C.explicitModes[kind] = true
        end
      end
      -- Compatibility with an older standalone options page left open during
      -- a hot reload: only still-unseeded categories follow its legacy row.
      if p.key == "difficulty" and modeValue(p.value) then
        for kind, field in pairs(MODE_FIELDS) do
          if not C.explicitModes[kind] then C[field] = p.value end
        end
      end
    end
  end)

  local ROW_RNDM = { { "off", "OFF" }, { "chaos", "CHAOS" }, { "themed", "THEMED" } }
  local ROW_DIFF = { { "off", "OFF" }, { "normal", "NORMAL (+2)" }, { "medium", "MEDIUM (+5)" }, { "hard", "HARD (+10)" } }

  local function getModeIndex(val, list)
    for i, m in ipairs(list) do if m[1] == val then return i end end
    return 1
  end

  local function persistOpt(game, key, val)
    local id = mod.id
    local opts = game and game.save and game.save.options
    if opts then
      opts.modOptions = opts.modOptions or {}
      opts.modOptions[id] = opts.modOptions[id] or {}
      opts.modOptions[id][key] = val
    end
    local loader = game and game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[id] = loader.modOptions[id] or {}
      loader.modOptions[id][key] = val
    end
    if game and game.writeOptions then pcall(game.writeOptions, game) end
  end

  mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
    local out = nextFn(game, rows)
    if type(out) ~= "table" then return out end
    
    out[#out + 1] = {
      id = mod.id .. ":randomize",
      label = "TRAINERS",
      value = function() return ROW_RNDM[getModeIndex(C.randomize, ROW_RNDM)][2] end,
      step = function(g, dir) 
        local n = #ROW_RNDM
        local i = ((getModeIndex(C.randomize, ROW_RNDM) - 1 + dir) % n + n) % n + 1
        C.randomize = ROW_RNDM[i][1]
        persistOpt(g, "randomize", C.randomize)
        return true
      end,
    }

    local labels = {
      trainer = "TRAINER DIFFICULTY",
      boss = "BOSS DIFFICULTY",
      wild = "WILD DIFFICULTY",
    }
    for _, kind in ipairs({ "trainer", "boss", "wild" }) do
      local key, field = MODE_KEYS[kind], MODE_FIELDS[kind]
      out[#out + 1] = {
        id = mod.id .. ":" .. key,
        label = labels[kind],
        value = function()
          return ROW_DIFF[getModeIndex(C[field], ROW_DIFF)][2]
        end,
        step = function(g, dir)
          local n = #ROW_DIFF
          local i = ((getModeIndex(C[field], ROW_DIFF) - 1 + dir) % n + n) % n + 1
          C[field] = ROW_DIFF[i][1]
          C.explicitModes[kind] = true
          persistOpt(g, key, C[field])
          return true
        end,
      }
    end
    return out
  end)

  -- =====================================================================
  -- DICTIONARIES: THEMES, CLASSES & ULTIMATE MOVES
  -- =====================================================================
  local ULTIMATE_MOVES = {
    ARCANINE   = { "FLAMETHROWER", "FIRE_BLAST" },
    NINETALES  = { "FLAMETHROWER", "FIRE_SPIN" },
    RAICHU     = { "THUNDERBOLT", "THUNDER" },
    CLEFABLE   = { "METRONOME" },
    WIGGLYTUFF = { "METRONOME" },
    NIDOKING   = { "SLUDGE", "EARTHQUAKE" },
    NIDOQUEEN  = { "SLUDGE", "EARTHQUAKE" },
    EXEGGUTOR  = { "EGG_BOMB", "PSYCHIC_M", "PSYCHIC" }, 
    STARMIE    = { "HYDRO_PUMP", "PSYCHIC_M", "PSYCHIC" }
  }

  local THEME_POOLS = {
    BUG_FOREST = {"CATERPIE","WEEDLE","ODDISH","PARAS","VENONAT","BELLSPROUT","SCYTHER","PINSIR","TANGELA","BULBASAUR","EXEGGCUTE"},
    WATER_ICE = {"SQUIRTLE","PSYDUCK","POLIWAG","TENTACOOL","SLOWPOKE","SEEL","SHELLDER","KRABBY","HORSEA","GOLDEEN","STARYU","MAGIKARP","LAPRAS","OMANYTE","KABUTO","ARTICUNO"},
    ROCK_FIGHT = {"MANKEY","MACHOP","GEODUDE","ONIX","CUBONE","HITMONLEE","HITMONCHAN","RHYHORN","AERODACTYL"},
    FIRE_POISON = {"CHARMANDER","VULPIX","GROWLITHE","PONYTA","MAGMAR","MOLTRES","EKANS","NIDORAN_F","NIDORAN_M","ZUBAT","GRIMER","KOFFING"},
    ELEC_PSY_GHOST = {"PIKACHU","VOLTORB","ELECTABUZZ","ZAPDOS","MAGNEMITE","ABRA","DROWZEE","MR_MIME","JYNX","MEWTWO","MEW","GASTLY"},
    NORMAL_BIRD = {"PIDGEY","RATTATA","SPEAROW","CLEFAIRY","JIGGLYPUFF","MEOWTH","FARFETCHD","DODUO","LICKITUNG","CHANSEY","KANGASKHAN","TAUROS","DITTO","EEVEE","PORYGON","SNORLAX"}
  }

  local CLASS_THEMES = {
    BUG_CATCHER = "BUG_FOREST", JR_TRAINER_F = "BUG_FOREST", ERIKA = "BUG_FOREST",
    SAILOR = "WATER_ICE", FISHERMAN = "WATER_ICE", SWIMMER = "WATER_ICE", BEAUTY = "WATER_ICE", MISTY = "WATER_ICE", LORELEI = "WATER_ICE",
    HIKER = "ROCK_FIGHT", CUE_BALL = "ROCK_FIGHT", BLACKBELT = "ROCK_FIGHT", JR_TRAINER_M = "ROCK_FIGHT", BROCK = "ROCK_FIGHT", BRUNO = "ROCK_FIGHT", GIOVANNI = "ROCK_FIGHT",
    POKEMANIAC = "FIRE_POISON", SUPER_NERD = "FIRE_POISON", BIKER = "FIRE_POISON", BURGLAR = "FIRE_POISON", TAMER = "FIRE_POISON", SCIENTIST = "FIRE_POISON", KOGA = "FIRE_POISON", BLAINE = "FIRE_POISON",
    ENGINEER = "ELEC_PSY_GHOST", GAMER = "ELEC_PSY_GHOST", PSYCHIC_TR = "ELEC_PSY_GHOST", ROCKER = "ELEC_PSY_GHOST", JUGGLER = "ELEC_PSY_GHOST", CHANNELER = "ELEC_PSY_GHOST", LT_SURGE = "ELEC_PSY_GHOST", SABRINA = "ELEC_PSY_GHOST", AGATHA = "ELEC_PSY_GHOST",
    LASS = "NORMAL_BIRD", BIRD_KEEPER = "NORMAL_BIRD", LANCE = "NORMAL_BIRD"
  }

  -- =====================================================================
  -- ENGINE LOGIC (EVOLUTION, CACHES, AND LEVEL CAPS)
  -- =====================================================================
  local fullPokedexCache = nil
  local parentMapCache = nil

  -- Evaluates badge count to securely pull the Level Cap for offsetting
  local function getDynamicCap(game)
      local badgeCount = 0
      local vanilla = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", 
                        "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE" }
      for _, badge in ipairs(vanilla) do
          if game.save and game.save.inventory and game.save.inventory[badge] then 
              badgeCount = badgeCount + 1 
          end
      end
      local caps = { [0] = 15, [1] = 30, [2] = 45, [3] = 60, [4] = 75, [5] = 90, [6] = 105, [7] = 120, [8] = 255 }
      return caps[badgeCount] or 255
  end

  -- Automatically devolves a Pokemon back to its absolute base stage
  local function getBaseSpecies(game, species)
      if not parentMapCache then
          parentMapCache = {}
          for key, def in pairs(game.data.pokemon) do
              if def.evolutions then
                  for _, evo in ipairs(def.evolutions) do
                      local req = 30
                      if evo.method == "LEVEL" then req = evo.level or 30 end
                      parentMapCache[evo.species] = { parent = key, reqLevel = req }
                  end
              end
          end
      end
      
      local curr = species
      while parentMapCache[curr] do
          curr = parentMapCache[curr].parent
      end
      return curr
  end

  -- Evaluates if the Pokemon meets the level/item requirements to evolve
  local function getEvolvedSpecies(game, species, currentLevel)
    local def = game.data.pokemon[species]
    if not def or not def.evolutions then return species end
    for _, evo in ipairs(def.evolutions) do
      local req = 30 -- Trade and Stone evolutions natively require Lv 30
      if evo.method == "LEVEL" then req = evo.level or 30 end
      
      if currentLevel >= req then 
          return getEvolvedSpecies(game, evo.species, currentLevel) 
      end
    end
    return species
  end

  local BOSS_IDS = {
    BROCK = true, MISTY = true, LT_SURGE = true, ERIKA = true,
    KOGA = true, SABRINA = true, BLAINE = true, GIOVANNI = true,
    LORELEI = true, BRUNO = true, AGATHA = true, LANCE = true,
    RIVAL3 = true, PROF_OAK = true,
  }

  local function normalizedTrainerId(value)
    if type(value) ~= "string" then return value end
    return value:gsub("^OPP_", "")
  end

  local function isBoss(game, trainerId)
    local id = normalizedTrainerId(trainerId)
    if BOSS_IDS[id] then return true end
    local trainer = game and game.data and game.data.trainers
      and game.data.trainers[trainerId]
    if type(trainer) ~= "table" then return false end
    if trainer.boss or trainer.gymLeader or trainer.eliteFour or trainer.champion then
      return true
    end
    local name = type(trainer.name) == "string"
      and trainer.name:upper():gsub("[^A-Z0-9]+", "_") or nil
    return name ~= nil and BOSS_IDS[name] == true
  end

  local function difficultyForTrainer(game, trainerId)
    return isBoss(game, trainerId) and C.bossDifficulty
      or C.trainerDifficulty
  end

  local function difficultyParams(difficulty)
    if difficulty == "normal" then return 2, 0 end
    if difficulty == "medium" then return 5, 1 end
    if difficulty == "hard" then return 10, 0 end
    return 0, 0
  end

  local function playerBaseLevel(game)
    local totalLevel, count = 0, 0
    for _, mon in ipairs(game.save and game.save.party or {}) do
      local level = tonumber(mon and mon.level)
      if level then
        totalLevel = totalLevel + level
        count = count + 1
      end
    end
    local average = count > 0 and math.floor(totalLevel / count) or 5
    return math.min(average, getDynamicCap(game))
  end

  local function applyTierStats(game, mon, difficulty)
    if difficulty ~= "medium" and difficulty ~= "hard" then return end
    local Stats = require("src.pokemon.Stats")
    mon.dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
    if difficulty == "hard" then
      mon.statExp = {
        attack = 65535, defense = 65535, speed = 65535,
        special = 65535, hp = 65535,
      }
    end
    mon.stats = Stats.calc(game.data.pokemon[mon.species], mon.level,
      mon.dvs, mon.statExp)
    mon.hp = mon.stats.hp
  end

  -- newWild/newTrainer cache the active monster in several fields on every
  -- supported Gen1Recomp version.  Updating the Pokemon object alone leaves
  -- the HUD and turn resolver on different levels, so keep the complete
  -- 0.1.75-0.1.96 cache shape in lockstep.
  local function syncEnemy(game, battle, mon)
    if not (battle and battle.enemy and mon) then return end
    local enemy = battle.enemy
    local def = game.data and game.data.pokemon
      and game.data.pokemon[mon.species] or {}
    enemy.mon = mon
    enemy.species = mon.species
    enemy.name = mon.nickname or def.name or enemy.name
    enemy.level = mon.level
    enemy.curTypes = {}
    for index, value in ipairs(def.types or {}) do enemy.curTypes[index] = value end
    enemy.curMoves = {}
    for index, move in ipairs(mon.moves or {}) do
      enemy.curMoves[index] = { id = move.id, pp = move.pp }
    end
    enemy.stats = mon.stats
    enemy.curStats = mon.stats
    enemy.hp = mon.hp
    enemy.maxHP = mon.stats and mon.stats.hp or mon.hp
    enemy.shownHP = mon.hp
  end

  local function buildPokedex(game)
    if fullPokedexCache then return fullPokedexCache end
    fullPokedexCache = {}
    for key, def in pairs(game.data.pokemon or {}) do
      if type(def.dex) == "number" and def.dex >= 1 and def.dex <= 151 then
        fullPokedexCache[#fullPokedexCache + 1] = key
      end
    end
    return fullPokedexCache
  end

  local function scaleTrainer(game, battle, trainerId, difficulty)
    if not (battle and type(battle.enemyParty) == "table"
        and battle.enemyParty[1]) then return battle end
    difficulty = modeValue(difficulty) or "off"
    if difficulty == "off" and C.randomize == "off" then return battle end

    local offset, sizeBump = difficultyParams(difficulty)
    if difficulty == "hard" then
      battle.enemyAIMods = { 1, 2, 3 }
    end
    local baseLevel = playerBaseLevel(game)
    local originalMax = 0
    for _, mon in ipairs(battle.enemyParty) do
      originalMax = math.max(originalMax, tonumber(mon.level) or 0)
    end

    local pokedex = buildPokedex(game)
    local activePool = pokedex
    if C.randomize == "themed" then
      local theme = CLASS_THEMES[normalizedTrainerId(trainerId)]
      if theme and THEME_POOLS[theme] then activePool = THEME_POOLS[theme] end
    end

    local Pokemon = require("src.pokemon.Pokemon")
    local targetSize = #battle.enemyParty + sizeBump
    if difficulty == "hard" then targetSize = 6 end
    targetSize = math.min(6, targetSize)
    local rebuilt = {}

    for index = 1, targetSize do
      local filler = index > #battle.enemyParty
      local reference = battle.enemyParty[index]
        or battle.enemyParty[#battle.enemyParty]
      local level = reference.level
      if difficulty ~= "off" then
        local curveOffset = reference.level - originalMax
        level = math.min(255,
          math.max(2, baseLevel + offset + curveOffset))
      end

      local species
      if C.randomize == "chaos" or (filler and C.randomize ~= "themed") then
        species = pokedex[math.random(#pokedex)]
      elseif C.randomize == "themed" or filler then
        species = activePool[math.random(#activePool)]
      else
        species = reference.species
      end

      local baseSpecies = getBaseSpecies(game, species)
      local evolvedSpecies = getEvolvedSpecies(game, baseSpecies, level)
      local mon = Pokemon.new(game.data, evolvedSpecies, level)
      applyTierStats(game, mon, difficulty)

      for _, moveId in ipairs(ULTIMATE_MOVES[evolvedSpecies] or {}) do
        local moveDef = game.data.moves[moveId]
        if moveDef then
          local hasMove = false
          for _, move in ipairs(mon.moves or {}) do
            if move.id == moveId then hasMove = true break end
          end
          if not hasMove then
            table.insert(mon.moves, 1, { id = moveId, pp = moveDef.pp })
            if #mon.moves > 4 then table.remove(mon.moves) end
          end
        end
      end
      rebuilt[index] = mon
    end

    battle.enemyParty = rebuilt
    syncEnemy(game, battle, rebuilt[1])
    return battle
  end

  local function scaleWild(game, battle, species, difficulty)
    difficulty = modeValue(difficulty) or "off"
    if difficulty == "off" or not (battle and battle.enemy) then return battle end
    local original = battle.enemy.mon
    local speciesId = original and original.species or species
    if not (speciesId and game.data and game.data.pokemon
        and game.data.pokemon[speciesId]) then return battle end

    local offset = difficultyParams(difficulty)
    local level = math.min(255, math.max(2, playerBaseLevel(game) + offset))
    local Pokemon = require("src.pokemon.Pokemon")
    local mon = Pokemon.new(game.data, speciesId, level)
    applyTierStats(game, mon, difficulty)
    syncEnemy(game, battle, mon)
    if type(battle.enemyParty) == "table" and battle.enemyParty[1] then
      battle.enemyParty[1] = mon
    end
    return battle
  end

  -- A mutable dispatcher makes F5 safe.  New installs wrap each constructor
  -- once; reloads replace only these callbacks.  If 0.12.6's legacy trainer
  -- wrapper is already live, it remains the one scaler and this dispatcher
  -- temporarily feeds it the selected category instead of scaling twice.
  local patch = rawget(BattleState, "__scottsDynamicScalingPatch")
  if type(patch) ~= "table" then
    patch = {
      originalTrainer = BattleState.newTrainer,
      originalWild = BattleState.newWild,
      legacyTrainer = BattleState.__dynamic_scaling_wrapped == true,
    }
    patch.trainerWrapper = function(game, trainerId, partyIndex, ...)
      if patch.legacyTrainer then
        local previous = C.difficulty
        C.difficulty = difficultyForTrainer(game, trainerId)
        local ok, battle = pcall(patch.originalTrainer,
          game, trainerId, partyIndex, ...)
        C.difficulty = previous
        if not ok then error(battle, 0) end
        return battle
      end
      local battle = patch.originalTrainer(game, trainerId, partyIndex, ...)
      return patch.scaleTrainer(game, battle, trainerId,
        difficultyForTrainer(game, trainerId))
    end
    patch.wildWrapper = function(game, species, level, ...)
      local battle = patch.originalWild(game, species, level, ...)
      return patch.scaleWild(game, battle, species, C.wildDifficulty)
    end
    BattleState.newTrainer = patch.trainerWrapper
    if type(BattleState.newWild) == "function" then
      BattleState.newWild = patch.wildWrapper
    end
    rawset(BattleState, "__scottsDynamicScalingPatch", patch)
    BattleState.__dynamic_scaling_wrapped = true
  end
  patch.scaleTrainer = scaleTrainer
  patch.scaleWild = scaleWild

  mod.exports.dynamicScaling = {
    config = C,
    isBoss = isBoss,
    difficultyForTrainer = difficultyForTrainer,
    refreshOptions = refreshOptions,
    modeKeys = MODE_KEYS,
  }
end
