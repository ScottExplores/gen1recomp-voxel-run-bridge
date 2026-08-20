-- ROM-free contracts for Scott's Tweaks' built-in PACK + Crystal POKeGEAR.

local root = arg and arg[1] or "."
local checks = 0

local function check(value, message)
  checks = checks + 1
  if not value then error(message or ("check " .. checks .. " failed"), 2) end
end

local function eq(actual, expected, message)
  checks = checks + 1
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function contains(text, needle, message)
  checks = checks + 1
  if not tostring(text or ""):find(needle, 1, true) then
    error((message or "text missing") .. ": " .. tostring(needle)
      .. " not in " .. tostring(text), 2)
  end
end

local draws = { text = {}, code = {}, rectangle = {}, color = {}, line = {},
  circle = {}, polygon = {}, systemText = {}, shaderSet = {}, shaderNew = {} }

local function clearDraws()
  for _, rows in pairs(draws) do
    for index = #rows, 1, -1 do rows[index] = nil end
  end
end

local baselineShader = { id = "baseline" }
local graphics = {
  shader = baselineShader,
  colorValue = { 0.2, 0.3, 0.4, 0.5 },
}
function graphics.setColor(...)
  graphics.colorValue = { ... }
  draws.color[#draws.color + 1] = { ... }
end
function graphics.getColor()
  local c = graphics.colorValue
  return c[1], c[2], c[3], c[4]
end
function graphics.newShader(source)
  local shader = { id = "pokegear-ink", source = source }
  draws.shaderNew[#draws.shaderNew + 1] = shader
  return shader
end
function graphics.setShader(shader)
  graphics.shader = shader
  draws.shaderSet[#draws.shaderSet + 1] = shader or false
end
function graphics.getShader() return graphics.shader end
function graphics.print(text, x, y)
  draws.systemText[#draws.systemText + 1] = {
    text = tostring(text), x = x, y = y, shader = graphics.shader,
    color = graphics.colorValue,
  }
end
function graphics.rectangle(...)
  draws.rectangle[#draws.rectangle + 1] = { ... }
end
function graphics.line(...)
  draws.line[#draws.line + 1] = { ... }
end
function graphics.circle(...)
  draws.circle[#draws.circle + 1] = { ... }
end
function graphics.polygon(...)
  draws.polygon[#draws.polygon + 1] = { ... }
end
love = { graphics = graphics }

local fakeFont = {}
function fakeFont.draw(text, x, y)
  if fakeFont.failText == text then error("fixture font draw failure") end
  local active = love.graphics
  draws.text[#draws.text + 1] = {
    text = text, x = x, y = y, shader = active.shader,
    color = active.colorValue,
  }
  return #tostring(text) * 8
end
function fakeFont.drawCode(code, x, y)
  local active = love.graphics
  draws.code[#draws.code + 1] = {
    code = code, x = x, y = y, shader = active.shader,
    color = active.colorValue,
  }
end

local fakeTheme = { cursor = 0xED }
local soundCalls = {}
local fakeSound = {
  play = function(data, name)
    soundCalls[#soundCalls + 1] = { data = data, name = name }
    return true
  end,
}
local musicCalls, restoreCalls = {}, 0
local fakeMusic = {
  -- This deliberately has only the two methods available to this screen on
  -- engine .75. It proves the implementation does not rely on .88's current,
  -- mapSong or setMapSong additions.
  play = function(data, song, loop, ctx)
    musicCalls[#musicCalls + 1] = {
      data = data, song = song, loop = loop, ctx = ctx,
    }
    return true
  end,
  restoreMap = function(_data)
    restoreCalls = restoreCalls + 1
    return true
  end,
}

package.loaded["src.render.Font"] = nil
package.loaded["src.ui.Theme"] = nil
package.loaded["src.core.Sound"] = nil
package.loaded["src.core.Music"] = nil
package.preload["src.render.Font"] = function() return fakeFont end
package.preload["src.ui.Theme"] = function() return fakeTheme end
package.preload["src.core.Sound"] = function() return fakeSound end
package.preload["src.core.Music"] = function() return fakeMusic end

local pushed = {}

local function newInput()
  local input = { pressed = {} }
  function input:press(key) self.pressed[key] = true end
  function input:wasPressed(key)
    local value = self.pressed[key] == true
    self.pressed[key] = nil
    return value
  end
  return input
end

local function newHarness(initial, opts)
  opts = opts or {}
  local values = {
    gen2_menus = initial == true,
    trainer_rematches = opts.rematches ~= false,
  }
  local saveValues = opts.saveValues or {
    trainer_memory = {
      format = 1,
      trainers = {
        route3_youngster = {
          trainerClass = "OPP_YOUNGSTER", mapId = "ROUTE_3",
          battles = 2, wins = 1, losses = 1, rematches = 1,
          lastResult = "win", lastSequence = 4,
        },
        rock_tunnel_pokemaniac = {
          trainerClass = "OPP_POKEMANIAC", mapId = "ROCK_TUNNEL_1F",
          battles = 3, wins = 2, losses = 0, rematches = 0,
          lastResult = opts.recentResult or "forfeit", lastSequence = 9,
        },
      },
    },
  }
  local registered = {}
  local hooks = {}
  local saveWrites = 0
  local mod = {
    id = "voxel_run_bridge",
    exports = {},
    datetime = {
      time = function(_, _game, _stamp) return "5:07 PM" end,
    },
    save = {
      get = function(_, key) return saveValues[key] end,
      set = function() saveWrites = saveWrites + 1 end,
    },
    ui = {
      push = function(game, id)
        pushed[#pushed + 1] = { game = game, id = id }
        return true
      end,
    },
    content = {
      screens = {
        get = function(_, id) return registered[id] end,
        register = function(_, id, factory)
          check(registered[id] == nil, "screen registered only once")
          registered[id] = factory
        end,
        override = function(_, id, factory)
          check(registered[id] ~= nil, "screen override has prior factory")
          registered[id] = factory
        end,
      },
    },
    hooks = {
      wrap = function(_, name, callback, priority)
        hooks[#hooks + 1] = {
          name = name, callback = callback, priority = priority,
        }
      end,
    },
  }
  local context = {
    settings = {
      get = function(_, key, fallback)
        local value = values[key]
        if value == nil then return fallback end
        return value
      end,
    },
  }
  return mod, context, values, saveValues, registered, hooks,
    function() return saveWrites end
end

local function newGame(opts)
  opts = opts or {}
  local input = newInput()
  local game = {
    input = input,
    save = { party = { { species = "PIKACHU" } } },
    data = {
      trainers = {
        OPP_YOUNGSTER = { name = "YOUNGSTER" },
        OPP_POKEMANIAC = { name = "POKéMANIAC" },
      },
      audio = {
        songs = opts.songs or {
          Music_MeetProfOak = {}, Music_Pokecenter = {},
          Music_JigglypuffSong = {}, Music_Cities1 = {},
        },
      },
      field = {
        townMap = {
          locations = {
            PALLET_TOWN = { x = 2, y = 9, name = "PALLET TOWN" },
            ROUTE_3 = { x = 8, y = 2, name = "ROUTE 3" },
            CERULEAN_CITY = { x = 12, y = 4, name = "CERULEAN CITY" },
          },
        },
      },
    },
    overworld = { map = { id = "ROUTE_3", def = { id = "ROUTE_3" } } },
  }
  local stack = { states = {}, pops = 0 }
  function stack:top() return self.states[#self.states] end
  function stack:pop()
    local state = table.remove(self.states)
    self.pops = self.pops + 1
    if state and state.exit then state:exit() end
    return state
  end
  game.stack = stack
  return game
end

local function drawnText()
  local out = {}
  for _, row in ipairs(draws.text) do out[#out + 1] = tostring(row.text) end
  return table.concat(out, "\n")
end

local installer = assert(dofile(root .. "/modules/gen2_ui.lua"))
local mod, context, values, saveValues, registered, hooks, saveWriteCount =
  newHarness(false)
local api = installer(mod, context)

eq(api.apiVersion, 3, "Pokegear API version")
eq(api.optionKey, "gen2_menus", "legacy option key is retained")
eq(api.getEnabled(), false, "option defaults off")
eq(api.getStatus().romImport, false, "feature has no ROM import")
eq(api.getStatus().ready, true, "built-in feature is always ready")
eq(api.getStatus().style, "crystal_inspired_native_160x144",
  "status names the ROM-free Crystal-inspired presentation")
eq(#api.getStatus().cards, 4, "status exposes four Pokegear cards")
eq(api.getStatus().limitations.phone,
  "trainer_rematch_history_not_gen2_phone_scripts",
  "status tells clients the honest Red phone boundary")
eq(#hooks, 1, "one Start-menu hook")
eq(hooks[1].name, "ui.start_menu.items", "Start hook name")
eq(hooks[1].priority, 100, "Pokegear stays outside Modern grouping")
check(registered.ScottsPokegear ~= nil, "Pokegear screen registered")

local itemCallback = function() return "bag" end
local base = {
  { label = "POKéMON" },
  { label = "ITEM", onSelect = itemCallback, custom = "preserved" },
  { label = "MODS" },
}
local nextCalls = 0
local function nextFn(_game, rows)
  nextCalls = nextCalls + 1
  return rows
end
local menuGame = { id = "red" }

local off = hooks[1].callback(nextFn, menuGame, base)
eq(off, base, "option-off preserves exact prior list")
eq(base[2].label, "ITEM", "option-off does not rename ITEM")
eq(nextCalls, 1, "downstream hook called once")

values.gen2_menus = true
local on = hooks[1].callback(nextFn, menuGame, base)
eq(#on, 4, "one Pokegear row added")
eq(on[2].label, "PACK", "ITEM is presented as PACK")
eq(on[2].onSelect, itemCallback, "PACK keeps exact Red bag callback")
eq(on[2].custom, "preserved", "PACK keeps custom descriptor fields")
eq(on[3].id, "scotts_tweaks.pokegear", "stable Pokegear row id")
eq(on[3].label, "POKéGEAR", "Pokegear follows PACK")
eq(on[3].desc[1], "Clock Map", "Start description advertises first cards")
eq(on[3].desc[2], "Phone Radio", "Start description advertises later cards")
eq(base[2].label, "ITEM", "source descriptor is never mutated")
on[3].onSelect()
eq(pushed[#pushed].id, "ScottsPokegear", "Pokegear row opens screen")

for _, alias in ipairs({ "ITEMS", "PACK" }) do
  local aliasRows = hooks[1].callback(nextFn, menuGame,
    { { label = alias, onSelect = itemCallback } })
  eq(aliasRows[1].label, "PACK", alias .. " presents as PACK")
  eq(aliasRows[1].onSelect, itemCallback, alias .. " callback preserved")
  eq(aliasRows[2].label, "POKéGEAR", alias .. " gets Pokegear after it")
end

local idRows = hooks[1].callback(nextFn, menuGame,
  { { id = "items", label = "BAG", onSelect = itemCallback } })
eq(idRows[1].label, "PACK", "items id is recognized independent of label")
eq(idRows[2].label, "POKéGEAR", "id-based PACK gets Pokegear after it")

local existing = hooks[1].callback(nextFn, menuGame, {
  { label = "ITEM" },
  { id = "scotts_tweaks.pokegear", label = "POKéGEAR" },
})
eq(#existing, 2, "existing Pokegear row is not duplicated")

local game = newGame()
local gear = registered.ScottsPokegear.new(game)
game.stack.states[1] = gear
eq(gear.screenId, "ScottsPokegear", "screen identity is stable")
eq(gear.isOpaque, true, "Pokegear owns the full 160x144 panel")
eq(gear:wantsFillScale(), true, "Pokegear asks for crisp native scaling")
eq(#gear.cards, 4, "Clock Map Phone Radio are present on old Red saves")
eq(gear.cards[1].id, "clock", "Crystal card order starts with Clock")
eq(gear.cards[2].id, "map", "Crystal card order continues with Map")
eq(gear.cards[3].id, "phone", "Crystal card order continues with Phone")
eq(gear.cards[4].id, "radio", "Crystal card order ends with Radio")
eq(gear.items, gear.cards, "public item introspection follows card list")
eq(#gear.contacts, 2, "trainer journey records become phone contacts")
eq(gear.contacts[1].name, "POKéMANIAC", "most recent contact is first")
eq(gear.contacts[1].lastResult, "forfeit",
  "lowercase journey result remains normalized")
eq(gear.contacts[2].name, "YOUNGSTER", "trainer class data supplies names")
eq(#gear.stations, 4, "four Crystal-style frequencies are exposed")
eq(api.getStatus(game).phoneContacts, 2, "status counts existing contacts")
eq(api.getStatus(game).radioStations, 4, "status counts playable stations")
eq(api.getStatus(game).capabilities.radio, true,
  "two-method .75 Music surface enables radio")
eq(saveWriteCount(), 0, "opening Pokegear never mutates old save data")

clearDraws()
gear:draw()
local foundCanvas = false
for _, row in ipairs(draws.rectangle) do
  if row[1] == "fill" and row[2] == 0 and row[3] == 0
      and row[4] == 160 and row[5] == 144 then
    foundCanvas = true
  end
end
check(foundCanvas, "draw paints an opaque native 160x144 canvas")
contains(drawnText(), "CLOCK", "Clock card labels its selected strip tab")
contains(drawnText(), "5:07 PM", "Clock card follows engine time preference")
check(#draws.polygon > 0, "selected card has a mode indicator arrow")
eq(#draws.shaderNew, 1, "one ink-recolor shader is compiled and cached")
contains(draws.shaderNew[1].source, "vec4(color.rgb",
  "ink shader replaces black cartridge RGB with requested color")
contains(draws.shaderNew[1].source, "source.a * color.a",
  "ink shader preserves cartridge glyph coverage")
local header, switchHint
for _, row in ipairs(draws.text) do
  if row.text == "CLOCK" and row.y == 4 then header = row end
  if row.text == "L/R" and row.y == 4 then switchHint = row end
end
check(header and header.shader and header.shader.id == "pokegear-ink",
  "black cartridge header glyphs draw through ink-recolor shader")
eq(header.color[1], 248 / 255, "selected card title is cream, not black")
eq(header.color[2], 248 / 255, "selected card title keeps cream green")
eq(header.color[3], 216 / 255, "selected card title keeps cream blue")
check(switchHint and switchHint.shader
    and switchHint.shader.id == "pokegear-ink",
  "switch hint also uses recolored cartridge glyphs")
eq(switchHint.color[1], 88 / 255, "switch hint receives cyan ink")
eq(switchHint.color[2], 184 / 255, "switch hint cyan is visible on black")
eq(graphics.shader, baselineShader,
  "successful recolor restores the exact prior graphics shader")

-- If the cartridge-font draw itself rejects the shader, the temporary shader
-- is still restored and a visible system-font label is used on the dark strip.
fakeFont.failText = "CLOCK"
clearDraws()
graphics.shader = baselineShader
gear:draw()
fakeFont.failText = nil
local fallbackHeader
for _, row in ipairs(draws.systemText) do
  if row.text == "CLOCK" then fallbackHeader = row end
end
check(fallbackHeader ~= nil,
  "shader draw failure falls back to visible system header text")
eq(fallbackHeader.shader, nil,
  "system-font fallback is isolated from the prior world shader")
eq(fallbackHeader.color[1], 248 / 255,
  "system-font fallback keeps requested cream ink")
eq(graphics.shader, baselineShader,
  "failed shader draw restores the exact prior graphics shader")

-- Shader compilation can also be absent on a minimal renderer. A fresh
-- graphics context gets one failed attempt, uses system text, and restores its
-- pre-existing pipeline rather than retrying or leaking state.
local failedBaseline = { id = "failed-context-baseline" }
local failedGraphics = {
  shader = failedBaseline,
  colorValue = { 0.6, 0.5, 0.4, 0.3 },
}
function failedGraphics.setColor(...)
  failedGraphics.colorValue = { ... }
  draws.color[#draws.color + 1] = { ... }
end
function failedGraphics.getColor()
  local c = failedGraphics.colorValue
  return c[1], c[2], c[3], c[4]
end
function failedGraphics.newShader(_source)
  failedGraphics.compileAttempts = (failedGraphics.compileAttempts or 0) + 1
  error("fixture shader compile failure")
end
function failedGraphics.setShader(shader) failedGraphics.shader = shader end
function failedGraphics.getShader() return failedGraphics.shader end
function failedGraphics.print(text, x, y)
  draws.systemText[#draws.systemText + 1] = {
    text = tostring(text), x = x, y = y, shader = failedGraphics.shader,
    color = failedGraphics.colorValue,
  }
end
function failedGraphics.rectangle(...) draws.rectangle[#draws.rectangle + 1] = { ... } end
function failedGraphics.line(...) draws.line[#draws.line + 1] = { ... } end
function failedGraphics.circle(...) draws.circle[#draws.circle + 1] = { ... } end
function failedGraphics.polygon(...) draws.polygon[#draws.polygon + 1] = { ... } end
love.graphics = failedGraphics
clearDraws()
gear:draw()
local compileFallback
for _, row in ipairs(draws.systemText) do
  if row.text == "CLOCK" then compileFallback = row end
end
eq(failedGraphics.compileAttempts, 1,
  "failed shader compilation is attempted only once per graphics context")
check(compileFallback ~= nil,
  "compile failure still renders the selected title")
eq(compileFallback.shader, nil,
  "compile fallback clears unrelated shader while printing")
eq(failedGraphics.shader, failedBaseline,
  "compile fallback restores the prior shader")
love.graphics = graphics

-- Map is a live card, and A opens the unchanged native Kanto TownMap over it.
game.input:press("right")
gear:update(0)
eq(gear:card().id, "map", "Right pages from Clock to Map")
clearDraws()
gear:draw()
contains(drawnText(), "ROUTE 3", "Map card names the current Red map")
check(#draws.rectangle > 15, "Map card plots extracted Kanto locations")
game.input:press("a")
gear:update(0)
eq(pushed[#pushed].id, "TownMap", "Map A uses Red's native TownMap")
eq(game.stack:top(), gear, "TownMap opens over rather than replacing Pokegear")

-- Phone is useful without pretending Red has Gold's phone-script VM.
game.input:press("right")
gear:update(0)
eq(gear:card().id, "phone", "Right pages from Map to Phone")
game.input:press("a")
gear:update(0)
eq(gear.phoneDetail, true, "Phone A opens the selected journey contact")
contains(gear:phoneMessage(), "NO BACKING OUT NEXT TIME",
  "latest forfeit wording wins even when the trainer has older wins")
clearDraws()
gear:draw()
contains(drawnText(), "CALLING POKéMANIAC", "Phone detail names the contact")
contains(drawnText(), "BATTLES 3", "Phone detail exposes real battle history")
game.input:press("b")
gear:update(0)
eq(gear.phoneDetail, false, "B hangs up before closing Pokegear")
eq(game.stack:top(), gear, "hanging up keeps Pokegear open")
game.input:press("down")
gear:update(0)
eq(gear.phoneIndex, 2, "Phone list moves without wrapping")
game.input:press("a")
gear:update(0)
contains(gear:phoneMessage(), "COME FIND ME FOR A REMATCH",
  "won trainer contact reports useful rematch guidance")
game.input:press("b")
gear:update(0)

-- Radio only calls the .75-compatible play/restoreMap pair, and only for
-- labels the active Red cache owns.
game.input:press("right")
gear:update(0)
eq(gear:card().id, "radio", "Right pages from Phone to Radio")
game.input:press("a")
gear:update(0)
eq(gear.radioPlaying, true, "Radio A starts an available station")
eq(#musicCalls, 1, "one music request starts the station")
eq(musicCalls[1].song, "Music_MeetProfOak", "Oak station uses owned Red song")
eq(musicCalls[1].loop, true, "radio station loops")
eq(musicCalls[1].ctx.reason, "radio", "radio playback is attributed")
game.input:press("up")
gear:update(0)
eq(gear.radioIndex, 2, "Radio Up tunes toward the next frequency")
eq(restoreCalls, 1, "retuning restores the map before replacing station")
eq(#musicCalls, 2, "live retune starts the new station")
eq(musicCalls[2].song, "Music_Pokecenter", "new frequency resolves owned song")
game.input:press("left")
gear:update(0)
eq(gear:card().id, "phone", "Left pages back from Radio")
eq(gear.radioPlaying, false, "leaving Radio stops its station")
eq(restoreCalls, 2, "leaving Radio restores map music")

-- B closes this opaque screen and reconstructs StartMenu, matching the former
-- Menu.onCancel behavior instead of dropping the player into the world.
game.input:press("b")
gear:update(0)
eq(game.stack.pops, 1, "Pokegear B pops exactly itself")
eq(pushed[#pushed].id, "StartMenu", "Pokegear B reopens StartMenu")
eq(saveWriteCount(), 0, "using all cards still writes no migration state")

-- Empty legacy journey memory remains a usable Phone card with guidance.
local emptyMod, emptyContext, _, _, emptyRegistered = newHarness(true, {
  saveValues = {},
})
installer(emptyMod, emptyContext)
local emptyGear = emptyRegistered.ScottsPokegear.new(newGame())
emptyGear.cardIndex = 3
eq(#emptyGear.contacts, 0, "old save without journey memory has no fake contact")
contains(emptyGear:phoneMessage(), "NO NUMBERS STORED",
  "empty Phone explains how contacts appear")
clearDraws()
emptyGear:draw()
contains(drawnText(), "NO NUMBERS", "empty Phone card is visibly intentional")

-- A false-returning playback seam must not claim ON AIR and must not restore
-- music later, because nothing started.
local falseMusic = {
  play = function() return false end,
  restoreMap = function() error("restore must not run for failed play") end,
}
package.loaded["src.core.Music"] = falseMusic
local falseInstaller = assert(dofile(root .. "/modules/gen2_ui.lua"))
local falseMod, falseContext, _, _, falseRegistered = newHarness(true)
falseInstaller(falseMod, falseContext)
local falseGear = falseRegistered.ScottsPokegear.new(newGame())
falseGear.cardIndex = 4
eq(falseGear:toggleRadio(), false, "explicit playback refusal is failure")
eq(falseGear.radioPlaying, false, "failed playback never reports ON AIR")
contains(falseGear.radioMessage, "COULDN'T START",
  "failed playback has a useful status")
falseGear:switch(-1)
eq(falseGear.radioPlaying, false, "failed station needs no restoration")

-- With neither song data nor a callable Music API the RADIO card stays visible
-- and safely explains the missing capability.
package.loaded["src.core.Music"] = {}
local unavailableInstaller = assert(dofile(root .. "/modules/gen2_ui.lua"))
local unavailableMod, unavailableContext, _, _, unavailableRegistered =
  newHarness(true)
unavailableInstaller(unavailableMod, unavailableContext)
local unavailableGame = newGame({ songs = {} })
local unavailableGear = unavailableRegistered.ScottsPokegear.new(unavailableGame)
unavailableGear.cardIndex = 4
eq(unavailableGear.capabilities.radio, false,
  "empty cache and missing API disable radio capability")
eq(unavailableGear:toggleRadio(), false, "unavailable Radio A is a safe no-op")
contains(unavailableGear.radioMessage, "ISN'T AVAILABLE",
  "unavailable Radio explains itself")
clearDraws()
unavailableGear:draw()
contains(drawnText(), "RADIO", "unavailable card remains discoverable")
contains(drawnText(), "AVAILABLE IN THIS",
  "unavailable state is rendered rather than decorative")

-- A second real entry updates the registered factory rather than failing or
-- adding a process-global resource owner.
package.loaded["src.core.Music"] = fakeMusic
local api2 = installer(mod, context)
eq(api2.apiVersion, 3, "second entry stays valid")
eq(#hooks, 2, "fresh Loader facade receives one fresh hook")
eq(registered.ScottsPokegear.new(game).screenId, "ScottsPokegear",
  "second entry replaces the screen factory safely")

-- Source-level cross-version contract: .75 provides only play/restoreMap;
-- avoid newer read/write helpers and all Gen2 cache modules.
local sourceFile = assert(io.open(root .. "/modules/gen2_ui.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
check(not source:find("Music.current", 1, true),
  "Pokegear does not require .88 Music.current")
check(not source:find("Music.mapSong", 1, true),
  "Pokegear does not require .88 Music.mapSong")
check(not source:find("Music.setMapSong", 1, true),
  "Pokegear does not overwrite remembered map music")
check(not source:find("src.ui.gen2", 1, true),
  "Red Pokegear does not require Gen2 engine/cache modules")
check(not source:find("mod.save:set", 1, true),
  "Pokegear requires no new saved field")

local manifestFile = assert(io.open(root .. "/manifest.json", "rb"))
local manifest = manifestFile:read("*a")
manifestFile:close()
check(not manifest:find("optional_imports", 1, true),
  "manifest has no imported-ROM contract")
check(not manifest:lower():find("pokemon gold rom", 1, true),
  "manifest does not ask for Pokemon Gold")

io.write(("gen2_ui: %d checks passed\n"):format(checks))
