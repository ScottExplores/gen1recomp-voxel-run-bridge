-- Minimal engine compatibility used by Scott's Gen-2 terrain cache.
--
-- This terrain-only package needs exactly two host services: the engine-owned
-- persistence filesystem and a platform name for cache-yield tuning. It does
-- not expose upstream file pickers, external-file staging, shell access, ROM
-- import helpers, or any other host capability.
local V = ...

local Compat = {}
local cachedFs

local function req(name)
  local ok, value = pcall(require, name)
  if ok and type(value) == "table" then return value end
  return nil
end

function Compat.fs()
  if cachedFs then return cachedFs end

  -- Current engine-owned persistence routing. This returns the same backend
  -- Gold saves/options use (portable mode included) without touching raw host
  -- paths or bypassing the mod sandbox.
  local SaveData = req("src.core.SaveData")
  if SaveData and type(SaveData.persistenceFs) == "function" then
    local ok, filesystem = pcall(SaveData.persistenceFs)
    if ok and type(filesystem) == "table" then
      cachedFs = filesystem
      return filesystem
    end
  end

  -- Older pre-sandbox releases exposed the LOVE persistence facade directly.
  -- Keep that narrow fallback for cache data only.
  local ok, filesystem = pcall(function()
    return love and love.filesystem
  end)
  if ok and type(filesystem) == "table" then
    cachedFs = filesystem
    return filesystem
  end
  return nil
end

function Compat.osName()
  local Platform = req("src.core.Platform")
  if Platform and type(Platform.detect) == "function" then
    local ok, info = pcall(Platform.detect)
    if ok and type(info) == "table" and type(info.os) == "string" then
      return info.os
    end
  end

  local ok, name = pcall(function()
    local system = love and love.system
    return system and system.getOS and system.getOS()
  end)
  if ok and type(name) == "string" then return name end
  return "Unknown"
end

return Compat
