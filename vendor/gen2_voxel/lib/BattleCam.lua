-- Deliberate no-battle stub for Scott's Tweaks' terrain-only Gen-2 port.
local BattleCam = { steerable = false, ZOOM_STEP = 1.1 }
function BattleCam.stepZoom() return false end
function BattleCam.stickOrbit() end
function BattleCam.stickPitch() end
function BattleCam.mouseOrbit() end
function BattleCam.mousePitch() end
function BattleCam.dragOrbit() end
function BattleCam.dragPitch() end
return BattleCam
