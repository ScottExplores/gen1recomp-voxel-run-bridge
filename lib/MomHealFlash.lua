-- Mom's healing script in REDS_HOUSE_1F surrounds the heal jingle with the
-- Game Boy's fade-to-white / fade-from-white pair.  The engine faithfully
-- draws that overlay at 160x144, which only covers part of a modern 3D view.
--
-- Keep the shared fade command intact for transitions and every other map.
-- This wrapper skips only white fades while the player is in Red's house;
-- those are the two commands in Mom's healing script.

local MomHealFlash = {}

local function mapId(ctx)
  local map = ctx and ctx.overworld and ctx.overworld.map
  return map and (map.id or (map.def and map.def.id))
end

local function fadeColor(framesOrColor, colorOrFrames)
  if type(framesOrColor) == "string" then return framesOrColor end
  if type(colorOrFrames) == "string" then return colorOrFrames end
  return "black"
end

function MomHealFlash.shouldSuppress(ctx, framesOrColor, colorOrFrames)
  return mapId(ctx) == "REDS_HOUSE_1F"
    and fadeColor(framesOrColor, colorOrFrames) == "white"
end

function MomHealFlash.install()
  local Commands = require("src.script.Commands")
  if Commands.dramaticShapeMomHealFlashHook then return end

  local inner = Commands.fade
  function Commands.fade(ctx, dir, framesOrColor, colorOrFrames)
    if (dir == "out" or dir == "in")
        and MomHealFlash.shouldSuppress(ctx, framesOrColor, colorOrFrames) then
      return
    end
    return inner(ctx, dir, framesOrColor, colorOrFrames)
  end

  Commands.dramaticShapeMomHealFlashHook = true
end

return MomHealFlash
