local model = require("./model.luau")
local sceneEditor = require("./scene_editor.luau")
local status, page, serial = nil, "climate", 0
local sceneDraft, sceneIsNew, sceneSaving, sceneError, deleteConfirm = nil, false, nil, "", nil
local setupError, renameDrafts = "", {}
local render
local function send(path, body, token)
  if not status or not status.online then return end
  serial = serial + 1
  noctalia.state.set("command", {path = path, body = body, serial = serial, time = os.time(), token = token})
end
local function ac() return status and status.data and status.data.aircons and status.data.aircons[noctalia.getConfig("aircon")] end
local function button(text, callback, selected, enabled, stretch)
  return ui.button({text = text, variant = selected and "primary" or "outline", selected = selected == true, controlSize = "sm", enabled = enabled ~= false, onClick = callback, flexGrow = stretch and 1 or nil})
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
        end, tonumber(info.myZone) == zone.number, online, true))
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
      label("MODE", 11, "on_surface/0.65"), row(modeButtons), label("FAN", 11, "on_surface/0.65"), row(fanButtons), row(timer)})
  }
  if #zoneChoices > 0 then
    table.insert(result, label("MYZONE", 11, "on_surface/0.65"))
    for first = 1, #zoneChoices, 3 do
      local choices = {}
      for i = first, math.min(first + 2, #zoneChoices) do table.insert(choices, zoneChoices[i]) end
      table.insert(result, row(choices))
    end
  end
  for _, z in ipairs(zoneCards) do table.insert(result, z) end
  return result
end
local function scenes()
  local section = status.data and status.data.myScenes or {}
  local scenes = section.scenes or {}
  if sceneDraft then
    return sceneEditor.render({draft = sceneDraft, acKey = noctalia.getConfig("aircon"), live = ac(),
      online = status.online, saving = sceneSaving ~= nil, isNew = sceneIsNew, error = sceneError,
      redraw = function() render() end,
      cancel = function() sceneDraft = nil; sceneError = ""; render() end,
      save = function()
        if not status.online or sceneSaving then return end
        local name = (sceneDraft.name or ""):match("^%s*(.-)%s*$")
        if not model.validName(name) then sceneError = "Use a name of 1–12 characters without a backslash."; render(); return end
        sceneDraft.name = name
        local key = noctalia.getConfig("aircon")
        local payload = model.scenePayload(sceneDraft, key)
        if not payload.aircons then sceneError = "No aircon settings in this scene."; render(); return end
        local token = tostring(os.time()) .. ":scene:" .. tostring(serial + 1)
        sceneSaving = {token = token, payload = payload, polls = 0, lastSequence = status.pollSequence or 0, acknowledged = false}
        sceneError = ""
        send("setScene", payload, token)
        render()
      end})
  end
  local ids, seen = {}, {}
  for _, id in ipairs(section.scenesOrder or {}) do
    if scenes[id] and id:match("^s1%x%x%x%x$") and not seen[id] then table.insert(ids, id); seen[id] = true end
  end
  local rest = {}
  for id in pairs(scenes) do if id:match("^s1%x%x%x%x$") and not seen[id] then table.insert(rest, id) end end
  table.sort(rest); for _, id in ipairs(rest) do table.insert(ids, id) end
  local newId = model.nextSceneId(status.data)
  local list = {row({label("Scenes on your tablet", 18), ui.spacer({flexGrow = 1}),
    button("+ New", function()
      local id = model.nextSceneId(status.data)
      if not id or not status.online then return end
      sceneDraft = model.sceneDraft(id, "", ac(), noctalia.getConfig("aircon"))
      sceneIsNew = true; sceneError = ""; deleteConfirm = nil; render()
    end, false, status.online and newId ~= nil)})}
  if not newId then table.insert(list, label("The tablet holds up to 12 scenes.", 12, "on_surface/0.65")) end
  if #ids == 0 then table.insert(list, label("No saved scenes.", 13, "on_surface/0.65")) end
  for _, id in ipairs(ids) do
    local scene = scenes[id]
    table.insert(list, card({row({label(scene.name or id, 15), ui.spacer({flexGrow = 1}), label(scene.timerEnabled and "AUTO" or "MANUAL", 11, "primary"),
      ui.toggle({checked = scene.timerEnabled == true, enabled = status.online, onChange = function(v) send("setScene", {id = id, timerEnabled = v == "true"}) end})}),
      label(scene.summary or "", 12, "on_surface/0.65"), row({
        button("Run now", function() send("runScene", {id = id}) end, false, status.online),
        button("Edit", function()
          if not status.online then return end
          sceneDraft = model.copy(scene)
          local key = noctalia.getConfig("aircon")
          sceneDraft.aircons = sceneDraft.aircons or {}
          if not sceneDraft.aircons[key] then sceneDraft.aircons[key] = model.sceneDraft(id, scene.name, ac(), key).aircons[key] end
          sceneDraft.aircons[key].info = sceneDraft.aircons[key].info or {}
          sceneDraft.aircons[key].zones = sceneDraft.aircons[key].zones or {}
          sceneIsNew = false; sceneError = ""; deleteConfirm = nil; render()
        end, false, status.online),
        button(deleteConfirm == id and "Confirm delete" or "Delete", function()
          if not status.online then return end
          if deleteConfirm == id then send("setScene", {id = id, name = ""}); deleteConfirm = nil
          else deleteConfirm = id end
          render()
        end, false, status.online)
      })}))
  end
  return list
end
local function setup(a)
  local i = a.info or {}
  local online = status.online
  local nodes = {label("Names", 18)}
  if setupError ~= "" then table.insert(nodes, label(setupError, 12, "error")) end
  local function nameRow(title, key, current, save)
    local initial = current or ""
    return row({label(title, 13), ui.input({key = "rename-" .. key, value = initial, placeholder = "Up to 12 characters", enabled = online, flexGrow = 1,
      onChange = function(v) renameDrafts[key] = v end}),
      button("Save", function()
        local value = (renameDrafts[key] or initial):match("^%s*(.-)%s*$")
        if not model.validName(value) then setupError = "Use a name of 1–12 characters without a backslash."; render(); return end
        setupError = ""
        if value ~= initial then save(value) end
        render()
      end, false, online)})
  end
  local names = {nameRow("Aircon", "aircon", i.name, function(v) commandInfo("name", v) end)}
  for _, z in ipairs(model.zones(a)) do
    local zone = z
    table.insert(names, nameRow("Zone " .. tostring(zone.number or zone.key), zone.key, zone.name, function(v) commandZone(zone.key, "name", v) end))
  end
  table.insert(nodes, card(names))
  local function setting(title, key)
    return row({label(title, 14), ui.spacer({flexGrow = 1}), ui.toggle({checked = i[key] == true, enabled = online, onChange = function(v) commandInfo(key, v == "true") end})})
  end
  table.insert(nodes, label("MyComfort", 18))
  local heat = tonumber(i.myAutoHeatTargetTemp) or 20
  local cool = tonumber(i.myAutoCoolTargetTemp) or 24
  if heat <= 0 then heat = 20 end
  if cool <= 0 then cool = 24 end
  local function setRange(h, c)
    if model.validRange(h, c) and online then send("setAircon", {info = {myAutoHeatTargetTemp = h, myAutoCoolTargetTemp = c}}) end
  end
  table.insert(nodes, card({setting("MySleep$aver", "quietNightModeEnabled"), setting("MyFan speed", "aaAutoFanModeEnabled"),
    label("Temperature control", 14), row({
      button("MyZone", function() send("setAircon", {info = {climateControlModeEnabled = false, myAutoModeEnabled = false}}) end, not i.climateControlModeEnabled and not i.myAutoModeEnabled, online),
      button("MyTemp", function() send("setAircon", {info = {climateControlModeEnabled = true, myAutoModeEnabled = false}}) end, i.climateControlModeEnabled == true and not i.myAutoModeEnabled, online),
      button("MyAuto", function() send("setAircon", {info = {climateControlModeEnabled = false, myAutoModeEnabled = true}}) end, i.myAutoModeEnabled == true, online)}),
    label("MyAuto range · at least 4° apart", 13), row({label("Heat"),
      button("−", function() setRange(heat - 1, cool) end, false, online and model.validRange(heat - 1, cool)), label(tostring(heat) .. "°"),
      button("+", function() setRange(heat + 1, cool) end, false, online and model.validRange(heat + 1, cool)), ui.spacer({flexGrow = 1}), label("Cool"),
      button("−", function() setRange(heat, cool - 1) end, false, online and model.validRange(heat, cool - 1)), label(tostring(cool) .. "°"),
      button("+", function() setRange(heat, cool + 1) end, false, online and model.validRange(heat, cool + 1))})}))
  local system = status.data and status.data.system or {}
  table.insert(nodes, card({row({label("Show actual temperature"), ui.spacer({flexGrow = 1}),
    ui.toggle({checked = system.showMeasuredTemp == true, enabled = online, onChange = function(v) send("setMySystem", {showMeasuredTemp = v == "true"}) end})})}))
  return nodes
end
render = function()
  local s = status or {online = false, error = "Connecting…"}
  local a = ac()
  local contents = {}
  if not a then
    contents = {card({label(s.error ~= "" and s.error or "Waiting for the tablet…", 14), button("Open plugin settings", function() noctalia.runAsync({"noctalia", "msg", "settings-open-plugin", "xiahongze/climate-deck"}) end)})}
  elseif page == "climate" then contents = climate(a)
  elseif page == "scenes" then contents = scenes()
  else contents = setup(a) end
  if s.error and s.error ~= "" and a then table.insert(contents, 1, label(s.error, 12, "error")) end
  panel.render(ui.column({gap = 12, padding = 16, flexGrow = 1}, {
    statusRow(s), row({button("Climate", function() if sceneSaving then return end; sceneDraft = nil; page = "climate"; render() end, page == "climate"), button("Scenes", function() page = "scenes"; render() end, page == "scenes"), button("Setup", function() if sceneSaving then return end; sceneDraft = nil; page = "setup"; render() end, page == "setup")}),
    ui.scroll({gap = 10, flexGrow = 1}, contents)
  }))
end
noctalia.state.watch("commandResult", function(result)
  if not sceneSaving or not result or result.token ~= sceneSaving.token then return end
  if result.ok then
    sceneSaving.acknowledged = true
    sceneSaving.lastSequence = status and status.pollSequence or 0
  else
    sceneError = "The tablet refused the scene: " .. (result.reason or "Unknown error")
    sceneSaving = nil
  end
  render()
end)
noctalia.state.watch("status", function(s)
  status = s
  if sceneSaving and sceneSaving.acknowledged and s and s.data and (s.pollSequence or 0) > sceneSaving.lastSequence then
    sceneSaving.lastSequence = s.pollSequence
    sceneSaving.polls = sceneSaving.polls + 1
    local scenes = (s.data.myScenes or {}).scenes or {}
    if model.contains(scenes[sceneSaving.payload.id], sceneSaving.payload) then
      sceneDraft = nil; sceneSaving = nil; sceneError = ""
    elseif sceneSaving.polls >= 2 then
      sceneSaving = nil; sceneError = "The tablet did not confirm the save. Please try again."
    end
  end
  render()
end)
function onOpen() status = noctalia.state.get("status"); render() end
