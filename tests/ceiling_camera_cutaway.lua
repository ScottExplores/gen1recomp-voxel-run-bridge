-- Focused regression for the camera-aware interior cross-section.
-- Run from the mod root:
--   lua tests/ceiling_camera_cutaway.lua .
--   luajit tests/ceiling_camera_cutaway.lua .

local argv = rawget(_G, "arg") or {}
local root = argv[1] or "."

local checks = 0
local function check(value, label)
  checks = checks + 1
  if not value then error(label, 2) end
end
local function eq(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(
      label, tostring(expected), tostring(actual)), 2)
  end
end

local Voxel3D = { eye = { 88, 64, 152 } }
local modules = {
  Voxel3D = Voxel3D,
  TileShape = {},
  FirstPerson = { yaw = 0, blendEased = function() return 0 end },
  ThirdPerson = { showsPlayer = function() return false end },
  DayNight = { isCanopy = function() return false end },
  ModSetting = {
    new = function(_, _, values)
      return { get = function() return values[1] end }
    end,
  },
}
local V = {
  require = function(name)
    assert(modules[name], "unexpected Ceiling dependency: " .. tostring(name))
    return modules[name]
  end,
}

local Ceiling = assert(loadfile(root .. "/lib/Ceiling.lua"))(V)
local near = Ceiling.cameraNearCell
check(type(near) == "function", "camera cutaway predicate is published")

check(near(5, 5, 5, 6, 0, 1, 4),
  "south camera opens the nearby south wall")
check(not near(5, 5, 5, 4, 0, 1, 4),
  "south camera preserves the far north wall")
check(not near(5, 5, 6, 5, 0, 1, 4),
  "south camera preserves a side wall")
check(not near(5, 5, 5, 10, 0, 1, 4),
  "cutaway does not erase the distant room shell")
check(near(5, 5, 9, 5, 1, 0, 4),
  "east camera opens the inclusive-radius east wall")
check(not near(5, 5, 5, 9, 1, 0, 4),
  "turning east no longer leaves the old south cut active")
check(near(5, 5, 7, 7, 1, 1, 4),
  "diagonal camera opens its nearby corner")
check(not near(5, 5, 3, 3, 1, 1, 4),
  "diagonal camera preserves the opposite corner")

local state = { player = { cellX = 5, cellY = 5, px = 80, py = 80 } }
local x, z, key = Ceiling.cameraSide(state, 5, 5)
eq(x, 0, "camera side quantizes the centered south X bearing")
eq(z, 1, "camera side quantizes the south Z bearing")
eq(key, "0,1", "camera side cache key is stable")

Voxel3D.eye = { 152, 64, 88 }
x, z, key = Ceiling.cameraSide(state, 5, 5)
eq(x, 1, "camera side follows an east turn")
eq(z, 0, "east turn drops the stale south component")
eq(key, "1,0", "east bearing gets a distinct cache key")

Voxel3D.eye = { 140, 64, 140 }
x, z, key = Ceiling.cameraSide(state, 5, 5)
eq(x, 1, "diagonal bearing keeps its east component")
eq(z, 1, "diagonal bearing keeps its south component")
eq(key, "1,1", "diagonal bearing has one stable sector key")

Voxel3D.eye = { 140, 64, 136 }
local _, _, nearbyKey = Ceiling.cameraSide(state, 5, 5)
eq(nearbyKey, key, "small stick movement does not rebuild the room mesh")

Voxel3D.eye = nil
x, z, key = Ceiling.cameraSide(state, 5, 5)
eq(x, 0, "headless fallback keeps the original X bearing")
eq(z, 1, "headless fallback keeps the original south bearing")
eq(key, "0,1", "headless fallback remains cache-stable")

print(("ceiling camera cutaway: %d checks passed"):format(checks))
