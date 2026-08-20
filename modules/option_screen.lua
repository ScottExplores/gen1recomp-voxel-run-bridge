-- Small reusable OptionRows screen.  Every row is a normal Gen1Recomp row
-- descriptor, so presentation mods and the dual-screen compositor see the
-- same UI surface as the built-in Options menu.
-- Incorporated from Scott's Sprite Menu (MIT). See THIRD_PARTY_NOTICES.md.

local OptionRows = require("src.ui.OptionRows")
local PaletteFX = require("src.render.PaletteFX")

local OptionScreen = {}
OptionScreen.__index = OptionScreen
OptionScreen.isOpaque = true

function OptionScreen:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

function OptionScreen.new(game, opts)
  opts = opts or {}
  local rows = opts.rows
  if type(rows) == "function" then rows = rows(game) end
  if type(rows) ~= "table" then rows = {} end
  local title = tostring(opts.title or "")
  local footer = opts.footer
  if footer == nil then
    footer = title ~= "" and ("BACK: " .. title):sub(1, 18) or "BACK"
  end
  return setmetatable({
    game = game,
    rows = rows,
    index = 1,
    scroll = 0,
    title = opts.title,
    footer = footer,
    onCancel = opts.onCancel,
    isOpaque = true,
  }, OptionScreen)
end

local function close(self)
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function OptionScreen:update(_)
  local input = self.game.input
  local cancel = #self.rows + 1

  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or cancel
  elseif input:wasPressed("down") then
    self.index = self.index < cancel and self.index + 1 or 1
  elseif input:wasPressed("left") or input:wasPressed("right")
      or input:wasPressed("a") then
    local row = self.rows[self.index]
    local pressedA = input:wasPressed("a")
    if row and row.activate then
      if pressedA then row.activate(self.game) end
    elseif row and row.step then
      local direction = input:wasPressed("left") and -1 or 1
      row.step(self.game, direction)
    elseif pressedA then
      close(self)
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    close(self)
  end

  self.scroll = OptionRows.clampScroll(
    self.index, self.scroll or 0, #self.rows, cancel)
end

function OptionScreen:draw()
  OptionRows.draw(self.game, self.rows, self.index, self.scroll or 0,
                  self.footer or "BACK", #self.rows + 1)
end

return OptionScreen
