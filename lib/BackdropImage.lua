-- Shared loader/cache for curated flat battle plates.

local V = ...
local BackdropImage = {}
local cache = {}

function BackdropImage.load(folder, file)
  if not file then return nil end
  local rel = ("assets/battle/front-static/%s/%s"):format(folder, file)
  if cache[rel] ~= nil then return cache[rel] or nil end
  local made
  local ok = pcall(function()
    -- The public asset facade owns path scoping and image construction. Raw
    -- love.filesystem access is unavailable to sandboxed mods going forward.
    made = V.mod.assets:image(rel)
    made:setFilter("linear", "linear")
    made:setWrap("clamp", "clamp")
  end)
  cache[rel] = (ok and made) or false
  return cache[rel] or nil
end

function BackdropImage.clear()
  for _, image in pairs(cache) do
    if image and image.release then pcall(image.release, image) end
  end
  cache = {}
end

return BackdropImage
