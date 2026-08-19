-- Derive two small sky-animation frames from battle pictures generated from
-- the player's own imported ROM.  No Pokemon sprite is distributed in this
-- private mod; the asset transform runs locally after import.

local COMMON = { "pidgey", "pidgeotto", "spearow", "fearow", "zubat",
                 "golbat", "butterfree", "venomoth", "farfetchd" }
local RARE = { "articuno", "zapdos", "moltres", "aerodactyl", "dragonite" }
local SQUEEZE = 0.62

return function(ctx)
  local derived = 0

  local function derive(name)
    local sourcePath = "battle/front/" .. name .. ".png"
    if not ctx.exists(sourcePath) then return end
    local ok, source = pcall(ctx.readImage, sourcePath)
    if not (ok and source) then return end
    local width, height = source:getWidth(), source:getHeight()
    if width < 8 or height < 8 then return end

    ctx.writeImage(source, "birds/" .. name .. "_a.png")
    local okFrame, frame = pcall(function()
      local out = ctx.blank(width, height)
      local newHeight = math.max(2, math.floor(height * SQUEEZE))
      local top = math.floor((height - newHeight) / 2)
      for y = 0, newHeight - 1 do
        local sourceY = math.min(height - 1, math.floor(y / SQUEEZE))
        for x = 0, width - 1 do
          local r, g, b, a = source:getPixel(x, sourceY)
          if a and a > 0 then out:setPixel(x, top + y, r, g, b, a) end
        end
      end
      return out
    end)
    ctx.writeImage((okFrame and frame) or source,
                   "birds/" .. name .. "_b.png")
    derived = derived + 1
  end

  for _, name in ipairs(COMMON) do derive(name) end
  for _, name in ipairs(RARE) do derive(name) end
  return derived
end
