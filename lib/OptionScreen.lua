-- Compact OptionRows screen adapted from Scott's Sprite Menu 0.2.2.
--
-- Copyright (c) 2026 Scott and contributors. Used under the MIT License;
-- see THIRD_PARTY_NOTICES.md. This is UI/controller code only and contains
-- no Pokemon, trainer, menu-icon, font, or other art assets.

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
  return setmetatable({
    game = game,
    rows = rows,
    index = 1,
    scroll = 0,
    title = opts.title,
    onCancel = opts.onCancel,
    isOpaque = true,
  }, OptionScreen)
end

local function close(self)
  self.game.stack:pop()
  if self.onCancel then self.onCancel(self.game) end
end

function OptionScreen:update(_)
  local input = self.game.input
  local cancel = #self.rows + 1
  local changed = false

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
      changed = row.step(self.game, direction) and true or false
    elseif pressedA then
      close(self)
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    close(self)
  end

  -- Pipeline rows persist in the stock OptionsMenu at this layer. Other
  -- rows already write immediately; a second unchanged write is harmless.
  if changed and self.game.writeOptions then
    pcall(self.game.writeOptions, self.game)
  end
  self.scroll = OptionRows.clampScroll(
    self.index, self.scroll or 0, #self.rows, cancel)
end

function OptionScreen:draw()
  OptionRows.draw(self.game, self.rows, self.index, self.scroll or 0,
                  "BACK", #self.rows + 1)
end

return OptionScreen
