-- A saved icon-mode change happens after the Loader has frozen content.
-- The listener must never try to re-register icons at that point; the new art
-- and its matching true-color patch are installed together on the next boot.

local argv = rawget(_G, "arg") or {}
local sourceRoot = (argv[1] or "."):gsub("\\", "/"):gsub("/$", "")

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function eq(actual, expected, message)
  checks = checks + 1
  assert(actual == expected, ("%s: expected %s, got %s")
    :format(message, tostring(expected), tostring(actual)))
end

local oldVersionLoaded = package.loaded["src.core.GameVersion"]
local oldVersionPreload = package.preload["src.core.GameVersion"]
package.loaded["src.core.GameVersion"] = nil
package.preload["src.core.GameVersion"] = function()
  return { generation = function() return 1 end }
end

local listeners, logs = {}, {}
local frozen, overrides = false, 0
local icons = {
  get = function() return nil end,
  register = function()
    if frozen then error("icons: content is frozen after load") end
  end,
  override = function()
    if frozen then error("icons: content is frozen after load") end
    overrides = overrides + 1
  end,
}
local mod = {
  id = "unique_menu_icons",
  exports = {},
  content = { icons = icons },
  options = {
    define = function() end,
    get = function(_, key)
      if key == "icon_color_mode" then return "original" end
    end,
  },
  assets = { path = function(_, relative) return relative end },
  events = { on = function(_, name, callback) listeners[name] = callback end },
  log = { info = function(_, fmt, ...)
    logs[#logs + 1] = string.format(fmt, ...)
  end, warn = function() end },
}
function mod:read(relative) return "fixture:" .. tostring(relative) end

local install = assert(loadfile(sourceRoot .. "/vendor/unique_menu_icons/main.lua"))()
install(mod)
check(overrides > 0, "boot registers the selected icon paths")
check(type(listeners["mod.options_changed"]) == "function",
  "icon mode subscribes to saved option changes")

frozen = true
local before = overrides
local ok, err = pcall(listeners["mod.options_changed"], {
  mod = mod.id, key = "icon_color_mode", value = "unique_colors",
})
check(ok, "post-freeze icon option change does not touch frozen content: "
  .. tostring(err))
eq(overrides, before, "post-freeze option change registers no new icons")
check(logs[#logs] and logs[#logs]:find("restart to apply", 1, true),
  "the option change truthfully reports that a restart is required")
check(not logs[#logs]:find("applied live", 1, true),
  "the option change never claims that frozen content changed live")

local logCount = #logs
listeners["mod.options_changed"]({
  mod = "another_mod", key = "icon_color_mode", value = "gbc_red",
})
eq(#logs, logCount, "unrelated option events remain ignored")

package.loaded["src.core.GameVersion"] = oldVersionLoaded
package.preload["src.core.GameVersion"] = oldVersionPreload

io.stdout:write(("unique menu icon option lifecycle: %d checks passed\n")
  :format(checks))
