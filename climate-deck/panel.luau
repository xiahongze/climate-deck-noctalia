local model = require("./model.luau")
local status, page, serial = nil, "climate", 0
local function send(path, body)
  if not status or not status.online then return end
  serial = serial + 1
  noctalia.state.set("command", {path = path, body = body, serial = serial, time = os.time()})
end
local function ac() return status and status.data and status.data.aircons and status.data.aircons[noctalia.getConfig("aircon")] end
local function button(text, callback, selected, enabled)
  return ui.button({text = text, variant = selected and "primary" or "secondary", controlSize = "sm", enabled = enabled ~= false, onClick = callback})
end
local function label(text, size, color)
  return ui.label({text = tostring(text or ""), fontSize = size or 13, color = color or "on_surface"})
end
local function row(children) return ui.row({gap = 8, align = "center"}, children) end
local function card(children) return ui.column({gap = 10, padding = 14, radius = 16, fill = "surface_variant"}, children) end
local function commandInfo(key, value) send("setAircon", {info = {[key] = value}}) end
local function commandZone(key, field, value) send("setAircon", {zones = {[key] = {[field] = value}}}) end
local function statusRow(s)
  return row({ui.glyph({name = "temperature", size = 20, color = "primary"}), label("CLIMATE DECK", 15), ui.spacer({flexGrow = 1}), label(s.online and (s.stale and "RETRYING" or "LIVE") or "OFFLINE", 11, "primary")})
end
local function climate(a)
  local info, online = a.info or {}, status.online
  local target = model.target(a)
  local modes = {{"Cool", "cool"}, {"Heat", "heat"}, {"Fan", "vent"}, {"Dry", "dry"}}
  if info.myAutoModeEnabled then table.insert(modes, {"MyAuto", "myauto"}) end
  local modeButtons = {}
  for _, mode in ipairs(modes) do
    local val = mode[2]
    table.insert(modeButtons, button(mode[1], function() commandInfo("mode", val) end, info.mode == val, online))
  end
  local fanButtons = {}
  for _, fan in ipairs({{"Low", "low"}, {"Med", "medium"}, {"High", "high"}, {"Auto", info.aaAutoFanModeEnabled and "autoAA" or "auto"}}) do
    local val = fan[2]
    table.insert(fanButtons, button(fan[1], function() commandInfo("fan", val) end, info.fan == val or (fan[1] == "Auto" and (info.fan == "auto" or info.fan == "autoAA")), online))
  end
  local zoneCards = {}
  for _, z in ipairs(model.zones(a)) do
    local zone = z
    local value = zone.sensor and zone.target or zone.value
    local step = zone.sensor and 1 or 5
    local lo, hi, field = zone.sensor and 16 or 5, zone.sensor and 32 or 100, zone.sensor and "setTemp" or "value"
    local measure = zone.sensor and (zone.error and "Sensor error" or model.temperature(zone.temp)) or "Damper"
    local suffix = zone.sensor and "°" or "%"
    table.insert(zoneCards, card({row({label(zone.name, 15), ui.spacer({flexGrow = 1}), label(measure, 14, "primary"), ui.toggle({checked = zone.open, enabled = online, onChange = function(v) commandZone(zone.key, "state", v == "true" and "open" or "close") end})}),
      row({label((tonumber(info.myZone) == zone.number and "MYZONE · " or "") .. (zone.sensor and "Target" or "Opening"), 11, "on_surface/0.65"), ui.spacer({flexGrow = 1}),
        button("−", function() commandZone(zone.key, field, math.max(lo, (value or lo) - step)) end, false, online and value ~= nil), label(value and (tostring(value) .. suffix) or "—", 14), button("+", function() commandZone(zone.key, field, math.min(hi, (value or lo) + step)) end, false, online and value ~= nil)})}))
  end
  local zoneChoices = {}
  if (tonumber(info.myZone) or 0) > 0 and not info.quietNightModeIsRunning then
    for _, z in ipairs(model.zones(a)) do
      local zone = z
      if zone.sensor and not zone.error and zone.number then
        table.insert(zoneChoices, button(zone.name, function()
          commandInfo("myZone", zone.number)
          if not zone.open then commandZone(zone.key, "state", "open") end
        end, tonumber(info.myZone) == zone.number, online))
      end
    end
  end
  local timerField = info.state == "on" and "countDownToOff" or "countDownToOn"
  local mins = tonumber(info[timerField]) or 0
  local timer = {label(info.state == "on" and "TURN OFF IN" or "TURN ON IN", 11, "on_surface/0.65")}
  if mins > 0 then
    table.insert(timer, label(tostring(mins) .. " min", 13))
    table.insert(timer, button("+30m", function() commandInfo(timerField, math.min(720, mins + 30)) end, false, online))
    table.insert(timer, button("Cancel", function() commandInfo(timerField, 0) end, false, online))
  else
    for _, m in ipairs({30, 60, 120, 240}) do
      local minutes = m
      table.insert(timer, button(m < 60 and "30m" or string.format("%dh", m / 60), function() commandInfo(timerField, minutes) end, false, online))
    end
  end
  local result = {
    card({row({ui.column({gap = 2}, {label("INSIDE", 11, "on_surface/0.65"), label(model.temperature(model.average(a)), 36)}), ui.spacer({flexGrow = 1}), ui.column({gap = 4, align = "end"}, {label("TARGET", 11, "on_surface/0.65"), row({button("−", function() if target then send("setAircon", model.targetPayload(a, target - 1)) end end, false, online and target ~= nil), label(target and string.format("%.0f°", target) or "—", 24), button("+", function() if target then send("setAircon", model.targetPayload(a, target + 1)) end end, false, online and target ~= nil)})})}),
      row({label(info.name or "Air conditioner", 13), ui.spacer({flexGrow = 1}), button(info.state == "on" and "Turn off" or "Turn on", function() commandInfo("state", info.state == "on" and "off" or "on") end, info.state == "on", online)}),
      label("MODE", 11, "on_surface/0.65"), row(modeButtons), label("FAN", 11, "on_surface/0.65"), row(fanButtons), row(timer)}),
    row({label("ZONES", 12, "on_surface/0.65"), ui.spacer({flexGrow = 1}), label(tostring(#zoneCards), 12, "on_surface/0.65")})
  }
  if #zoneChoices > 0 then
    table.insert(result, label("MYZONE", 11, "on_surface/0.65"))
    for _, choice in ipairs(zoneChoices) do table.insert(result, choice) end
  end
  for _, z in ipairs(zoneCards) do table.insert(result, z) end
  return result
end
local function scenes()
  local section = status.data and status.data.myScenes or {}
  local scenes = section.scenes or {}
  local ids = {}
  for id in pairs(scenes) do if id:match("^s1%x%x%x%x$") then table.insert(ids, id) end end
  table.sort(ids)
  local list = {label("Scenes on your tablet", 18)}
  if #ids == 0 then table.insert(list, label("No saved scenes.", 13, "on_surface/0.65")) end
  for _, id in ipairs(ids) do
    local scene = scenes[id]
    table.insert(list, card({row({label(scene.name or id, 15), ui.spacer({flexGrow = 1}), label(scene.timerEnabled and "AUTO" or "MANUAL", 11, "primary"), ui.toggle({checked = scene.timerEnabled == true, enabled = status.online, onChange = function(v) send("setScene", {id = id, timerEnabled = v == "true"}) end})}),
      label(scene.summary or "", 12, "on_surface/0.65"), row({button("Run now", function() send("runScene", {id = id}) end, false, status.online)})}))
  end
  return list
end
local function setup(a)
  local i = a.info or {}
  local function setting(title, key)
    return row({label(title, 14), ui.spacer({flexGrow = 1}), ui.toggle({checked = i[key] == true, enabled = status.online, onChange = function(v) commandInfo(key, v == "true") end})})
  end
  return {label("MyComfort", 18), card({setting("MySleep$aver", "quietNightModeEnabled"), setting("MyFan speed", "aaAutoFanModeEnabled"),
    label("Temperature control", 14), row({
      button("MyZone", function() send("setAircon", {info = {climateControlModeEnabled = false, myAutoModeEnabled = false}}) end, not i.climateControlModeEnabled and not i.myAutoModeEnabled, status.online),
      button("MyTemp", function() send("setAircon", {info = {climateControlModeEnabled = true, myAutoModeEnabled = false}}) end, i.climateControlModeEnabled == true and not i.myAutoModeEnabled, status.online),
      button("MyAuto", function() send("setAircon", {info = {climateControlModeEnabled = false, myAutoModeEnabled = true}}) end, i.myAutoModeEnabled == true, status.online)})}),
    label("Connection settings are available in Noctalia’s plugin settings.", 12, "on_surface/0.65"),
    button("Open plugin settings", function() noctalia.runAsync({"noctalia", "msg", "settings-open-plugin", "xiahongze/climate-deck"}) end)}
end
local function render()
  local s = status or {online = false, error = "Connecting…"}
  local a = ac()
  local contents = {}
  if not a then
    contents = {card({label(s.error ~= "" and s.error or "Waiting for the tablet…", 14), button("Open plugin settings", function() noctalia.runAsync({"noctalia", "msg", "settings-open-plugin", "xiahongze/climate-deck"}) end)})}
  elseif page == "climate" then contents = climate(a)
  elseif page == "scenes" then contents = scenes()
  else contents = setup(a) end
  panel.render(ui.column({gap = 12, padding = 16, flexGrow = 1}, {
    statusRow(s), row({button("Climate", function() page = "climate"; render() end, page == "climate"), button("Scenes", function() page = "scenes"; render() end, page == "scenes"), button("Setup", function() page = "setup"; render() end, page == "setup"), ui.spacer({flexGrow = 1}), button("Close", function() panel.close() end)}),
    ui.scroll({gap = 10, flexGrow = 1}, contents)
  }))
end
noctalia.state.watch("status", function(s) status = s; render() end)
function onOpen() status = noctalia.state.get("status"); render() end
