local model = require("./model.luau")
local base, acKey, interval
local data, failures, lastUpdated, pollSequence = nil, 0, 0, 0
local queue, busy, nextPoll, generation = {}, false, 0, 0
local pending = {}
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end
local function leaves(value, path, out)
  for key, val in pairs(value) do
    local nextPath = copy(path); table.insert(nextPath, key)
    if type(val) == "table" then leaves(val, nextPath, out)
    else table.insert(out, {path = nextPath, value = val, expires = os.time() + 12}) end
  end
end
local function pathValue(obj, path)
  for _, key in ipairs(path) do if type(obj) ~= "table" then return nil end; obj = obj[key] end
  return obj
end
local function apply(obj, path, val)
  for i = 1, #path - 1 do
    local key = path[i]
    if type(obj[key]) ~= "table" then obj[key] = {} end
    obj = obj[key]
  end
  obj[path[#path]] = val
end
local function visibleData()
  if not data then return nil end
  local result = copy(data)
  local current = result.aircons and result.aircons[acKey]
  if current then for _, item in ipairs(pending) do apply(current, item.path, item.value) end end
  return result
end
local function reconcile()
  local current = data and data.aircons and data.aircons[acKey]
  local remaining = {}
  for _, item in ipairs(pending) do
    if os.time() < item.expires and pathValue(current, item.path) ~= item.value then table.insert(remaining, item) end
  end
  pending = remaining
end

local function publish(message)
  noctalia.state.set("status", {data = visibleData(), online = lastUpdated > 0 and failures < 3,
    stale = failures > 0, configured = base ~= nil, updated = lastUpdated, pollSequence = pollSequence, error = message or ""})
end
local function configure()
  generation = generation + 1
  base = model.base(noctalia.getConfig("host"))
  acKey = noctalia.getConfig("aircon") or "ac1"
  interval = math.max(3, tonumber(noctalia.getConfig("interval")) or 10)
  data, failures, lastUpdated, queue, busy, nextPoll, pending, pollSequence = nil, 0, 0, {}, false, 0, {}, 0
  publish(base and "Connecting…" or "Set the tablet address in plugin settings")
end
local function request(url, done)
  busy = true
  local g = generation
  local accepted = noctalia.http({url = url, headers = {"User-Agent: ClimateDeck-Noctalia/0.1"}}, function(res)
    if g ~= generation then return end
    busy = false
    done(res)
  end)
  if not accepted then busy = false; done({ok = false, status = 0}) end
end
local function pump()
  if busy or not base or #queue == 0 then return end
  local item = table.remove(queue, 1)
  local body = noctalia.json.encode(item.body)
  if not body then publish("Could not encode command"); return end
  request(base .. "/" .. item.path .. "?json=" .. noctalia.string.urlEncode(body), function(res)
    local ack = res.ok and res.status == 200 and noctalia.json.decode(res.body or "") or nil
    local ok = ack and ack.ack == true
    local reason = ok and "" or ((ack and ack.reason) or "Command failed")
    if not ok then
      pending = {}
      publish(reason)
    end
    if item.token then noctalia.state.set("commandResult", {token = item.token, ok = ok == true, reason = reason}) end
    nextPoll = os.time() + 2
    pump()
  end)
end
function update()
  if not base or busy then return end
  if #queue > 0 then pump(); return end
  local now = os.time()
  if now < nextPoll then return end
  nextPoll = now + interval
  request(base .. "/getSystemData", function(res)
    local reply = res.ok and res.status == 200 and noctalia.json.decode(res.body or "") or nil
    if type(reply) == "table" and type(reply.aircons) == "table" and next(reply.aircons) then
      data, failures, lastUpdated = reply, 0, os.time()
      pollSequence = pollSequence + 1
      reconcile()
      publish("")
    else
      failures = failures + 1
      publish("Tablet not reachable or returned invalid data")
    end
    pump()
  end)
end
function onConfigChanged() configure() end
noctalia.state.watch("command", function(cmd)
  if not cmd or not base or lastUpdated == 0 or failures >= 3 then return end
  if cmd.path == "setAircon" then
    local updates = {}; leaves(cmd.body, {}, updates)
    for _, item in ipairs(updates) do
      local rest = {}
      for _, old in ipairs(pending) do
        local same = #old.path == #item.path
        if same then for i = 1, #item.path do if old.path[i] ~= item.path[i] then same = false; break end end end
        if not same then table.insert(rest, old) end
      end
      pending = rest; table.insert(pending, item)
    end
    publish("")
    table.insert(queue, {path = cmd.path, body = {[acKey] = cmd.body}, token = cmd.token})
  elseif cmd.path == "setScene" or cmd.path == "runScene" or cmd.path == "setMySystem" then
    table.insert(queue, {path = cmd.path, body = cmd.body, token = cmd.token})
  else return end
  pump()
end)
configure()
noctalia.setUpdateInterval(1000)
