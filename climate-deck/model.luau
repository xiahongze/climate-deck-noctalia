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
return M
