-- The fused build's optional first-person jump button.
--
-- Press Space (keyboard) or Y (pad) in free roam while facing a ledge to hop
-- two cells across it from either side.  Facing anything else makes a small
-- cosmetic hop in place.  Movement still goes through the engine's stock
-- script commands, collision checks and ledge animation.

local DX = { up = 0, down = 0, left = -1, right = 1 }
local DY = { up = -1, down = 1, left = 0, right = 0 }

return function(mod)
  mod.commands:register("scott_ledge_leap_arc", function(ctx)
    local player = ctx.overworld and ctx.overworld.player
    if player then player.hopFrames, player.hopTotal = 32, 32 end
  end)

  local scriptRunning = false
  mod.events:on("script.started", function() scriptRunning = true end)
  mod.events:on("script.ended", function() scriptRunning = false end)

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
    for _, ledge in ipairs(game.data.field.ledges or {}) do
      if (ledge.tileset or "OVERWORLD") == tileset
          and ledge.ledgeTile == frontTile then
        return true, direction, frontX, frontY
      end
    end
    return false
  end

  local function tryJump(game)
    local overworld = game.overworld
    if not overworld or game.stack:top() ~= overworld then return end
    local player = overworld.player
    if not player or player.moving or scriptRunning then return end
    if (player.hopFrames or 0) > 0 or player.surfing then return end

    local isLedge, direction, frontX, frontY =
      facingLedge(game, overworld, player)

    -- Leave a face-button press to ordinary interaction when an NPC occupies
    -- the cell ahead; talking wins over a cosmetic bounce.
    if not isLedge and occupied(overworld.entities,
        player.cellX + DX[player.facing], player.cellY + DY[player.facing],
        player) then
      return
    end

    if isLedge then
      local landX = frontX + DX[direction]
      local landY = frontY + DY[direction]
      if overworld.map:inBounds(landX, landY)
          and overworld.map:isWalkableCell(landX, landY)
          and not occupied(overworld.entities, landX, landY, player) then
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
