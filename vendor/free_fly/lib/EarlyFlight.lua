-- Scott's optional, earned early-flight rule. This is a read-only predicate:
-- it never teaches FLY, grants an HM/badge, creates a partner or edits a save.
-- Vanilla FLY and its other field actions continue to use the original rules.
local EarlyFlight = {}

function EarlyFlight.eligible(game, mon, enabled, generation)
  if enabled ~= true or generation ~= 1 then return false end
  local inventory = game and game.save and game.save.inventory
  if type(inventory) ~= "table" or not inventory.BOULDERBADGE then return false end
  if type(mon) ~= "table" then return false end
  if type(mon.hp) ~= "number" or mon.hp ~= mon.hp
      or mon.hp == math.huge or mon.hp <= 0 then return false end
  -- Only an actual party member is a mount, not a preview or PC descriptor.
  local inParty = false
  for _, partner in ipairs(game.save.party or {}) do
    if partner == mon then inParty = true break end
  end
  if not inParty then return false end
  local pokemon = game.data and game.data.pokemon
  local def = pokemon and pokemon[mon.species]
  for _, move in ipairs((def and def.tmhm) or {}) do
    if move == "FLY" then return true end
  end
  return false
end

return EarlyFlight
