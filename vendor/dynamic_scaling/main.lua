return function(mod)
  mod.log:info("Dynamic Level Scaling, Randomizer & Modular Difficulty Loaded")

  local BattleState = require("src.battle.BattleState")

  -- =====================================================================
  -- GLOBAL SETTINGS & OPTIONS MENU INTEGRATION
  -- =====================================================================
  local C = _G.__DYNAMIC_SCALING or {}
  _G.__DYNAMIC_SCALING = C
  C.randomize = C.randomize or "off"
  C.difficulty = C.difficulty or "off"

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
        key = "difficulty", type = "choice", label = "Difficulty Mode",
        choices = {
          { "Off (Vanilla)", "off" },
          { "Normal (+2 Lvs)", "normal" },
          { "Medium (+5 Lvs, Max DVs)", "medium" },
          { "Hard (+10 Lvs, 6 Mons, Max EVs)", "hard" }
        },
        default = "off"
      }
    })
  end

  local function refreshOptions()
    if mod.options and mod.options.get then
      pcall(function() C.randomize = mod.options:get("randomize") or "off" end)
      pcall(function() C.difficulty = mod.options:get("difficulty") or "off" end)
    end
  end
  refreshOptions()

  mod.events:on("mod.options_changed", function(p)
    if p and p.mod == mod.id then
      if p.key == "randomize" then C.randomize = p.value end
      if p.key == "difficulty" then C.difficulty = p.value end
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

    out[#out + 1] = {
      id = mod.id .. ":difficulty",
      label = "DIFFICULTY",
      value = function() return ROW_DIFF[getModeIndex(C.difficulty, ROW_DIFF)][2] end,
      step = function(g, dir) 
        local n = #ROW_DIFF
        local i = ((getModeIndex(C.difficulty, ROW_DIFF) - 1 + dir) % n + n) % n + 1
        C.difficulty = ROW_DIFF[i][1]
        persistOpt(g, "difficulty", C.difficulty)
        return true
      end,
    }
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

  if not BattleState.__dynamic_scaling_wrapped then
    BattleState.__dynamic_scaling_wrapped = true
    local orig_newTrainer = BattleState.newTrainer
    
    BattleState.newTrainer = function(game, trainerId, partyIndex, ...)

      -- 1. Let the engine create the base battle to preserve hooks!
      local battle = orig_newTrainer(game, trainerId, partyIndex, ...)
      
      if not battle or not battle.enemyParty then return battle end
      if C.difficulty == "off" and C.randomize == "off" then return battle end

      -- 2. Difficulty Parameters
      local offset = 0
      local sizeBump = 0
      if C.difficulty == "normal" then 
          offset = 2 
      elseif C.difficulty == "medium" then 
          offset = 5
          sizeBump = 1
      elseif C.difficulty == "hard" then 
          offset = 10
          battle.enemyAIMods = {1, 2, 3} -- Boss AI
      end

      -- 3. Calculate Player Party Average and limit it to the Level Cap
      local totalLevel, count = 0, 0
      if game.save and game.save.party then
        for _, mon in ipairs(game.save.party) do
          totalLevel = totalLevel + mon.level
          count = count + 1
        end
      end
      local avgLevel = count > 0 and math.floor(totalLevel / count) or 5
      local cap = getDynamicCap(game)
      
      -- If player is overleveled, trainers clamp to the cap before adding the offset!
      local baseLevel = math.min(avgLevel, cap)

      -- 4. Calculate Original Max Level to preserve boss balance curves
      local origMax = 0
      for _, mon in ipairs(battle.enemyParty) do
        if mon.level > origMax then origMax = mon.level end
      end

      -- 5. Build Pokedex Cache
      if not fullPokedexCache then
        fullPokedexCache = {}
        for key, def in pairs(game.data.pokemon) do
          if type(def.dex) == "number" and def.dex >= 1 and def.dex <= 151 then
            table.insert(fullPokedexCache, key)
          end
        end
      end

      -- 6. Determine active Randomizer Pool
      local activePool = fullPokedexCache
      if C.randomize == "themed" then
         local themeName = CLASS_THEMES[trainerId]
         if themeName and THEME_POOLS[themeName] then
            activePool = THEME_POOLS[themeName]
         end
      end

      -- 7. Dynamically rebuild the enemy party!
      local Pokemon = require("src.pokemon.Pokemon")
      local Stats = require("src.pokemon.Stats")
      
      local targetSize = #battle.enemyParty + sizeBump
      if C.difficulty == "hard" then targetSize = 6 end
      targetSize = math.min(6, targetSize)

      local newEnemyParty = {}

      for i = 1, targetSize do
        local isFiller = (i > #battle.enemyParty)
        local referenceMon = battle.enemyParty[i] or battle.enemyParty[#battle.enemyParty]
        
        -- Scale Level
        local newLevel = referenceMon.level
        if C.difficulty ~= "off" then
            local curveOffset = referenceMon.level - origMax
            newLevel = math.min(255, math.max(2, (baseLevel + offset) + curveOffset))
        end

        -- Determine Species
        local chosenSpecies
        if C.randomize == "chaos" or (isFiller and C.randomize ~= "themed") then
            chosenSpecies = fullPokedexCache[math.random(#fullPokedexCache)]
        elseif C.randomize == "themed" or isFiller then
            chosenSpecies = activePool[math.random(#activePool)]
        else
            chosenSpecies = referenceMon.species
        end

        -- Devolution & Evolution Check!
        -- Strips over-evolved randomizer pulls down to base stage, then safely evolves up to current level.
        local safeBaseSpecies = getBaseSpecies(game, chosenSpecies)
        local correctStageSpecies = getEvolvedSpecies(game, safeBaseSpecies, newLevel)

        -- Generate fresh Pokemon object
        local newMon = Pokemon.new(game.data, correctStageSpecies, newLevel)

        -- Inject Modular Stats
        if C.difficulty == "medium" then
          newMon.dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
          newMon.stats = Stats.calc(game.data.pokemon[correctStageSpecies], newLevel, newMon.dvs, newMon.statExp)
          newMon.hp = newMon.stats.hp
        elseif C.difficulty == "hard" then
          newMon.dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
          newMon.statExp = { attack = 65535, defense = 65535, speed = 65535, special = 65535, hp = 65535 }
          newMon.stats = Stats.calc(game.data.pokemon[correctStageSpecies], newLevel, newMon.dvs, newMon.statExp)
          newMon.hp = newMon.stats.hp
        end

        -- Inject Ultimate Moves
        if ULTIMATE_MOVES[correctStageSpecies] then
          for _, moveId in ipairs(ULTIMATE_MOVES[correctStageSpecies]) do
            local mdef = game.data.moves[moveId]
            if mdef then
              local hasMove = false
              for _, m in ipairs(newMon.moves) do 
                  if m.id == moveId then hasMove = true end 
              end
              if not hasMove then
                table.insert(newMon.moves, 1, { id = moveId, pp = mdef.pp })
                if #newMon.moves > 4 then table.remove(newMon.moves) end
              end
            end
          end
        end

        newEnemyParty[i] = newMon
      end

      -- 8. Apply the new scaled party back to the battle
      battle.enemyParty = newEnemyParty
      
      -- 9. Sync ALL cached battle variables for the new lead Pokemon
      if battle.enemy and newEnemyParty[1] then
        local lead = newEnemyParty[1]
        local def = game.data.pokemon[lead.species]
        
        battle.enemy.mon = lead
        battle.enemy.species = lead.species
        battle.enemy.name = lead.nickname or def.name
        battle.enemy.level = lead.level
        
        battle.enemy.curTypes = {}
        if def.types then
            for idx, t in ipairs(def.types) do battle.enemy.curTypes[idx] = t end
        end
        
        battle.enemy.curMoves = {}
        if lead.moves then
            for idx, m in ipairs(lead.moves) do battle.enemy.curMoves[idx] = { id = m.id, pp = m.pp } end
        end
        
        battle.enemy.stats = lead.stats
        battle.enemy.curStats = lead.stats
        battle.enemy.hp = lead.hp
        battle.enemy.maxHP = lead.stats.hp
        battle.enemy.shownHP = lead.hp
      end

      return battle
    end
  end
end