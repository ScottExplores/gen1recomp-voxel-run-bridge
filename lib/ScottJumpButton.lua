-- The fused build's optional manual jump button, including first-person roam.
--
-- Press Space (keyboard) or Y (pad) in free roam while facing a ledge to hop
-- two cells across it from either side when LEDGE HOPS is enabled. Facing
-- anything else makes a small cosmetic hop in place. This is not a wall
-- noclip: only authored ledge tiles qualify, and a clear, walkable landing
-- plus the live movement.collision chain must approve the route. The stock
-- script commands animate movement; they do not validate that route for us.

local DX = { up = 0, down = 0, left = -1, right = 1 }
local DY = { up = -1, down = 1, left = 0, right = 0 }
local KEYS = { space = true, j = true, lctrl = true, off = true }
local PADS = { y = true, x = true, off = true }

return function(mod)
  mod.commands:register("scott_ledge_leap_arc", function(ctx)
    local player = ctx.overworld and ctx.overworld.player
    if player then player.hopFrames, player.hopTotal = 32, 32 end
  end)

  local scriptDepth, inBattle = 0, false
  local function foreground(event)
    local runner = event and event.ctx and event.ctx.runner
    return not (runner and runner.parallel)
  end
  mod.events:on("script.started", function(event)
    if foreground(event) then scriptDepth = scriptDepth + 1 end
  end)
  mod.events:on("script.ended", function(event)
    if foreground(event) then scriptDepth = math.max(0, scriptDepth - 1) end
  end)
  mod.events:on("battle.started", function() inBattle = true end)
  mod.events:on("battle.ended", function() inBattle = false end)
  mod.events:on("save.loaded", function() scriptDepth, inBattle = 0, false end)

  local function occupied(entities, cellX, cellY, ignore)
    for _, entity in ipairs(entities or {}) do
      if entity ~= ignore and not entity.passable then
        if (entity.cellX == cellX and entity.cellY == cellY)
            or (entity.targetX == cellX and entity.targetY == cellY) then
          return true
        end
      end
    end
    return false
  end

  local function facingLedge(game, overworld, player)
    local map, direction = overworld.map, player.facing
    local frontX = player.cellX + DX[direction]
    local frontY = player.cellY + DY[direction]
    if not map:inBounds(frontX, frontY) then return false end
    local frontTile = map:cellTile(frontX, frontY)
    local tileset = map.def.tileset
    local field = game.data and game.data.field
    for _, ledge in ipairs(field and field.ledges or {}) do
      if (ledge.tileset or "OVERWORLD") == tileset
          and ledge.ledgeTile == frontTile then
        return true, direction, frontX, frontY
      end
    end
    return false
  end

  local function landingAllowed(game, overworld, player, direction,
      frontX, frontY, landX, landY)
    local map = overworld.map
    if not map:inBounds(landX, landY)
        or not map:isWalkableCell(landX, landY)
        or occupied(overworld.entities, frontX, frontY, player)
        or occupied(overworld.entities, landX, landY, player) then
      return false
    end

    -- Match the engine's tile-pair protection at the destination. The ledge
    -- itself is deliberately crossed, but a different elevation barrier on
    -- the far side is not permission to bypass a cave/forest wall.
    local field = game.data and game.data.field
    local pairs = field and field.tilePairs and field.tilePairs.land
    local fromTile = map:cellTile(player.cellX, player.cellY)
    local landTile = map:cellTile(landX, landY)
    for _, pair in ipairs(pairs or {}) do
      if pair.tileset == map.def.tileset
          and ((pair.a == fromTile and pair.b == landTile)
            or (pair.b == fromTile and pair.a == landTile)) then
        return false
      end
    end

    -- Do not use Collision.canMove with a copied/fake mover: other mods need
    -- the real player identity. Present each leg to the documented hook,
    -- without mutating player.cellX/cellY or letting a permissive hook undo
    -- the hard bounds/tile/occupancy checks above. Missing/broken compatibility
    -- fails closed to an in-place hop rather than an unchecked scripted walk.
    local ok, allowed = pcall(function()
      local Runtime = require("src.mods.Runtime")
      if not Runtime.wantsHook("movement.collision") then return true end
      local function passthrough(value) return value end
      for _, leg in ipairs({
        { player.cellX, player.cellY, frontX, frontY },
        { frontX, frontY, landX, landY },
      }) do
        local ctx = { map = map, mover = player, dir = direction,
          fromX = leg[1], fromY = leg[2], toX = leg[3], toY = leg[4] }
        if Runtime.call("movement.collision", passthrough, true, ctx) ~= true then
          return false
        end
      end
      return true
    end)
    return ok and allowed == true
  end

  local function tryJump(game)
    if not game or not game.stack or type(game.stack.top) ~= "function" then
      return
    end
    local overworld = game.overworld
    if not overworld or game.stack:top() ~= overworld then return end
    local player = overworld.player
    if not player or player.moving or player.inputLocked or scriptDepth > 0
        or inBattle or player.freeFlying or player.surfing or player.onBike
        or (game.save and game.save.onBike) then return end
    if overworld.transitioning or overworld.engaging or overworld.emote
        or overworld.teleportOut or overworld.flyAnim or overworld.flyArrive
        or (overworld.scriptMoves and #overworld.scriptMoves > 0)
        or (overworld.pendingScripts and #overworld.pendingScripts > 0) then
      return
    end
    if overworld.runner and type(overworld.runner.isRunning) == "function"
        and overworld.runner:isRunning() then return end
    if type(player.hopFrames) == "number" and player.hopFrames > 0 then return end

    local map, direction = overworld.map, player.facing
    if not map or not map.def or type(map.inBounds) ~= "function"
        or type(map.cellTile) ~= "function"
        or type(map.isWalkableCell) ~= "function"
        or not DX[direction] or not DY[direction]
        or type(player.cellX) ~= "number" or player.cellX % 1 ~= 0
        or type(player.cellY) ~= "number" or player.cellY % 1 ~= 0
        or not map:inBounds(player.cellX, player.cellY) then return end

    local isLedge, direction, frontX, frontY =
      facingLedge(game, overworld, player)

    -- Leave a face-button press to ordinary interaction when an NPC occupies
    -- the cell ahead; talking wins, even if that NPC stands on a ledge.
    if occupied(overworld.entities,
        player.cellX + DX[player.facing], player.cellY + DY[player.facing],
        player) then
      return
    end

    if isLedge and mod.options:get("ledge_hops") ~= false then
      local landX = frontX + DX[direction]
      local landY = frontY + DY[direction]
      if landingAllowed(game, overworld, player, direction,
          frontX, frontY, landX, landY)
          and mod.world and type(mod.world.queueScript) == "function" then
        mod.world:queueScript({
          { "scott_ledge_leap_arc" },
          { "play_sound", "Ledge" },
          { "move_player", direction, 2 },
        })
        return
      end
    end

    player.hopFrames, player.hopTotal = 16, 16
  end

  -- Edge latches are local to this feature, so a held button makes one jump.
  local keyboardHeld, padHeld = false, false
  mod.hooks:wrap("input.step", function(next, game, dt)
    local key = mod.options:get("jumpkey") or "space"
    local pad = mod.options:get("jumppad") or "y"
    if not KEYS[key] then key = "off" end
    if not PADS[pad] then pad = "off" end

    local keyboardDown = false
    if key ~= "off" and love and love.keyboard then
      keyboardDown = love.keyboard.isDown(key)
    end

    local padDown = false
    if pad ~= "off" and love and love.joystick then
      for _, joystick in ipairs(love.joystick.getJoysticks()) do
        -- Select+face belongs to the engine's display-control chord.
        if joystick:isGamepad() and joystick:isGamepadDown(pad)
            and not joystick:isGamepadDown("back") then
          padDown = true
          break
        end
      end
    end

    local pressed = (keyboardDown and not keyboardHeld)
      or (padDown and not padHeld)
    keyboardHeld, padHeld = keyboardDown, padDown
    if pressed then tryJump(game) end
    return next(game, dt)
  end)
end
