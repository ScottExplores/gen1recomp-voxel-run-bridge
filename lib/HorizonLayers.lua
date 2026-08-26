-- Order the three outdoor background layers without changing the established
-- painted-panorama path.
--
-- PIXEL HILLS is screen-space and depth-free: atmospheric SkyLayer art must
-- go down first so stars/clouds cannot appear over opaque land, then the hills,
-- then the depth-writing underlay. Painted cylinder panoramas keep their
-- original underlay -> backdrop -> atmosphere order exactly.

local HorizonLayers = {}

function HorizonLayers.draw(Backdrop, SkyLayer, WorldUnderlay,
                            state, cx, cy, underlayColor)
  local okPixel, pixel = false, false
  if type(Backdrop.usesPixelHills) == "function" then
    okPixel, pixel = pcall(Backdrop.usesPixelHills, state)
  end
  pixel = okPixel and pixel == true
  if pixel then
    pcall(SkyLayer.draw, state)
    pcall(Backdrop.draw, state)
    WorldUnderlay.draw(state, cx, cy, underlayColor)
    return "PIXEL_HILLS"
  end

  WorldUnderlay.draw(state, cx, cy, underlayColor)
  pcall(Backdrop.draw, state)
  pcall(SkyLayer.draw, state)
  return "PANORAMA"
end

return HorizonLayers
