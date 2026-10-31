local model = require("./model.luau")
local M = {}
local function label(text, size, color)
  return ui.label({text = tostring(text or ""), fontSize = size or 13, color = color or "on_surface"})
end
local function row(children) return ui.row({gap = 6, align = "center"}, children) end
local function button(text, action, selected, enabled, stretch)
  return ui.button({text = text, variant = selected and "primary" or "outline", selected = selected == true, controlSize = "sm", enabled = enabled ~= false, onClick = action, flexGrow = stretch and 1 or nil})
end
local function toggle(value, action, enabled)
  return ui.toggle({checked = value == true, enabled = enabled ~= false, onChange = function(v) action(v == "true") end})
end
local function step(labelText, value, minimum, maximum, stepSize, update, enabled, suffix)
  local v = tonumber(value) or minimum
  return row({label(labelText, 13), ui.spacer({flexGrow = 1}),
    button("−", function() update(math.max(minimum, v - stepSize)) end, false, enabled and v > minimum),
    label(tostring(v) .. (suffix or ""), 14),
    button("+", function() update(math.min(maximum, v + stepSize)) end, false, enabled and v < maximum)})
end
local function timeString(minutes)
  local n = math.floor(tonumber(minutes) or 0) % 1440
  return string.format("%02d:%02d", math.floor(n / 60), n % 60)
end
function M.render(ctx)
  local d, key, live, redraw = ctx.draft, ctx.acKey, ctx.live, ctx.redraw
  local active = ctx.online and not ctx.saving
  local sceneAc = d.aircons[key]
  local info = sceneAc.info
  local zones = sceneAc.zones
  local nodes = {
    row({label(ctx.isNew and "New scene" or "Edit scene", 18), ui.spacer({flexGrow = 1}),
      button("Cancel", ctx.cancel, false, not ctx.saving), ui.button({text = ctx.saving and "Saving…" or "Save", variant = "primary", controlSize = "sm", enabled = active, onClick = ctx.save})}),
  }
  if ctx.error ~= "" then table.insert(nodes, label(ctx.error, 12, "error")) end
  table.insert(nodes, ui.input({key = "scene-name-" .. d.id, value = d.name or "", placeholder = "Scene name (up to 12 characters)", enabled = active, onChange = function(v) d.name = v end}))
  table.insert(nodes, label("WHEN", 11, "on_surface/0.65"))
  local days = {{"M", 2}, {"T", 4}, {"W", 8}, {"T", 16}, {"F", 32}, {"S", 64}, {"S", 1}}
  local dayButtons = {}
  for _, day in ipairs(days) do
    local bit = day[2]
    local mask = tonumber(d.activeDays) or 0
    local selected = math.floor(mask / bit) % 2 == 1
    table.insert(dayButtons, button(day[1], function() d.activeDays = selected and mask - bit or mask + bit; redraw() end, selected, active, true))
  end
  table.insert(nodes, row(dayButtons))
  local presets = {}
  for _, preset in ipairs({{"Every day", 127}, {"Weekdays", 62}, {"Weekend", 65}}) do
    local mask = preset[2]
    table.insert(presets, button(preset[1], function() d.activeDays = mask; redraw() end, d.activeDays == mask, active))
  end
  table.insert(nodes, row(presets))
  table.insert(nodes, row({label("Run automatically"), ui.spacer({flexGrow = 1}), toggle(d.timerEnabled, function(v) d.timerEnabled = v; redraw() end, active)}))
  local function timeRow(title, keyName, enabled)
    local v = tonumber(d[keyName]) or 0
    return row({label(title), ui.spacer({flexGrow = 1}), button("−15m", function() d[keyName] = (v - 15) % 1440; redraw() end, false, enabled),
      label(timeString(v), 15), button("+15m", function() d[keyName] = (v + 15) % 1440; redraw() end, false, enabled)})
  end
  table.insert(nodes, timeRow("Starts at", "startTime", active))
  table.insert(nodes, row({label("Turn aircon off later"), ui.spacer({flexGrow = 1}), toggle(d.airconStopTimeEnabled, function(v) d.airconStopTimeEnabled = v; redraw() end, active)}))
  table.insert(nodes, timeRow("Off at", "airconStopTime", active and d.airconStopTimeEnabled))
  table.insert(nodes, label("AIRCON", 11, "on_surface/0.65"))
  table.insert(nodes, row({button("On", function() info.state = "on"; redraw() end, info.state == "on", active), button("Off", function() info.state = "off"; redraw() end, info.state == "off", active)}))
  local modes = {{"Cool", "cool"}, {"Heat", "heat"}, {"Fan", "vent"}, {"Dry", "dry"}}
  if live.info and live.info.myAutoModeEnabled then table.insert(modes, {"MyAuto", "myauto"}) end
  local modeButtons = {}
  for _, mode in ipairs(modes) do
    local v = mode[2]; table.insert(modeButtons, button(mode[1], function() info.mode = v; redraw() end, info.mode == v, active))
  end
  table.insert(nodes, row(modeButtons))
  local fanButtons = {}
  for _, fan in ipairs({{"Low", "low"}, {"Med", "medium"}, {"High", "high"}, {"Auto", live.info.aaAutoFanModeEnabled and "autoAA" or "auto"}}) do
    local v = fan[2]
    table.insert(fanButtons, button(fan[1], function() info.fan = v; redraw() end, info.fan == v or (fan[1] == "Auto" and (info.fan == "auto" or info.fan == "autoAA")), active))
  end
  table.insert(nodes, row(fanButtons))
  local target = model.target(sceneAc)
  if target then table.insert(nodes, step("Target", target, 16, 32, 1, function(v)
    local edit = model.targetPayload(sceneAc, v)
    if edit.info then info.setTemp = edit.info.setTemp
    else for zoneKey, values in pairs(edit.zones) do
      zones[zoneKey] = zones[zoneKey] or {number = tonumber(zoneKey:sub(2))}
      zones[zoneKey].setTemp = values.setTemp
    end end
    redraw()
  end, active, "°")) end
  local liveZones = model.zones(live)
  local choices = {}
  if (tonumber(info.myZone) or 0) > 0 then
    for _, z in ipairs(liveZones) do
      local zone = z
      if zone.sensor and not zone.error and zone.number then
        table.insert(choices, button(zone.name, function()
          info.myZone = zone.number
          zones[zone.key] = zones[zone.key] or {number = zone.number}
          zones[zone.key].state = "open"
          redraw()
        end, tonumber(info.myZone) == zone.number, active, true))
      end
    end
  end
  if #choices > 0 then
    table.insert(nodes, label("MYZONE", 11, "on_surface/0.65"))
    for first = 1, #choices, 3 do
      local cells = {}; for i = first, math.min(first + 2, #choices) do table.insert(cells, choices[i]) end
      table.insert(nodes, row(cells))
    end
  end
  table.insert(nodes, label("ZONES", 11, "on_surface/0.65"))
  for _, z in ipairs(liveZones) do
    local zone = z
    local sceneZone = zones[zone.key] or {number = zone.number}
    do
      local isMyZone = zone.number == tonumber(info.myZone)
      table.insert(nodes, row({label(zone.name .. (isMyZone and " ★" or "")), ui.spacer({flexGrow = 1}),
        toggle(sceneZone.state == "open", function(v) zones[zone.key] = sceneZone; sceneZone.state = v and "open" or "close"; redraw() end, active and not isMyZone)}))
      local field = zone.sensor and "setTemp" or "value"
      local value = tonumber(sceneZone[field])
      if value then table.insert(nodes, step(zone.sensor and "Target" or "Opening", value, zone.sensor and 16 or 5, zone.sensor and 32 or 100, zone.sensor and 1 or 5,
        function(v) zones[zone.key] = sceneZone; sceneZone[field] = v; redraw() end, active, zone.sensor and "°" or "%")) end
    end
  end
  return nodes
end
return M
