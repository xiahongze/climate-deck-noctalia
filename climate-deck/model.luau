-- Pure MyPlace helpers; adapted from Climate Deck, MIT licensed.
local M = {}
function M.base(host)
  local h = tostring(host or ""):match("^%s*(.-)%s*$"):gsub("^https?://", ""):gsub("/+$", "")
  if h == "" or h:find("[/@?#%s]") then return nil end
  if not h:find(":", 1, true) then h = h .. ":2025" end
  return "http://" .. h
end
function M.zones(ac)
  local out = {}
  for key, z in pairs((ac and ac.zones) or {}) do
    if type(z) == "table" then
      table.insert(out, {key = key, number = tonumber(z.number) or tonumber(key:sub(2)), name = z.name or key,
        temp = tonumber(z.measuredTemp), target = tonumber(z.setTemp), value = tonumber(z.value) or 0,
        sensor = tonumber(z.type) ~= 0, error = (tonumber(z.error) or 0) ~= 0, open = z.state == "open"})
    end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end
function M.average(ac)
  local sum, count = 0, 0
  for _, z in ipairs(M.zones(ac)) do
    if z.sensor and not z.error and z.temp and z.temp > 0 then sum, count = sum + z.temp, count + 1 end
  end
  return count > 0 and sum / count or nil
end
function M.target(ac)
  if not ac or not ac.info then return nil end
  local n = tonumber(ac.info.myZone) or 0
  local z = n >= 1 and n <= 10 and (ac.zones or {})[string.format("z%02d", n)] or nil
  return tonumber(z and z.setTemp or ac.info.setTemp)
end
function M.targetPayload(ac, temp)
  temp = math.max(16, math.min(32, math.floor(temp + 0.5)))
  local n = tonumber(ac.info.myZone) or 0
  if n >= 1 and n <= 10 then return {zones = {[string.format("z%02d", n)] = {setTemp = temp}}} end
  return {info = {setTemp = temp}}
end
function M.temperature(t)
  return t and string.format("%.1f°", t) or "—"
end
function M.copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = M.copy(v) end
  return out
end
function M.validName(name)
  if type(name) ~= "string" then return false end
  name = name:match("^%s*(.-)%s*$")
  -- The tablet rejects long names and mishandles backslashes.
  local ok, length = pcall(function()
    local units = 0
    for _, cp in utf8.codes(name) do units = units + (cp > 65535 and 2 or 1) end
    return units
  end)
  return ok and length > 0 and length <= 12 and not name:find("\\", 1, true)
end
function M.validRange(heat, cool)
  return type(heat) == "number" and type(cool) == "number" and heat % 1 == 0 and cool % 1 == 0
    and heat >= 16 and heat <= 28 and cool >= 20 and cool <= 32 and cool - heat >= 4
end
function M.nextSceneId(system)
  local scenes = ((system or {}).myScenes or {}).scenes or {}
  for n = 1, 12 do
    local id = string.format("s1%04d", n)
    if not scenes[id] then return id end
  end
  return nil
end
function M.sceneDraft(id, name, ac, acKey)
  local info = ac.info or {}
  local selectedInfo, selectedZones = {}, {}
  for _, key in ipairs({"uid", "name", "mode", "fan", "setTemp", "myZone", "freshAirStatus"}) do
    selectedInfo[key] = info[key]
  end
  selectedInfo.state = "on"
  for key, zone in pairs(ac.zones or {}) do
    local item = {}
    for _, field in ipairs({"number", "state", "value", "setTemp", "motionConfig"}) do item[field] = zone[field] end
    selectedZones[key] = item
  end
  return {id = id, name = name or "", timerEnabled = false, activeDays = 127, startTime = 420,
    airconStopTimeEnabled = false, airconStopTime = 540, myTimeEnabled = false,
    aircons = {[acKey] = {info = selectedInfo, zones = selectedZones}}}
end
function M.scenePayload(draft, acKey)
  local out = {}
  for _, key in ipairs({"id", "name", "timerEnabled", "activeDays", "startTime", "airconStopTimeEnabled", "airconStopTime", "myTimeEnabled"}) do
    out[key] = draft[key]
  end
  local sceneAc = draft.aircons and draft.aircons[acKey]
  if sceneAc then out.aircons = M.copy(draft.aircons) end
  return out
end
function M.contains(actual, expected)
  if type(expected) ~= "table" then return actual == expected or (actual ~= nil and tostring(actual) == tostring(expected)) end
  if type(actual) ~= "table" then return false end
  for k, value in pairs(expected) do if not M.contains(actual[k], value) then return false end end
  return true
end
return M
