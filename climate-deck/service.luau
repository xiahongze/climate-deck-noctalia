local model = require("./model.luau")
local base, acKey, interval
local data, failures, lastUpdated = nil, 0, 0
local queue, busy, nextPoll, generation = {}, false, 0, 0

local function publish(message)
  noctalia.state.set("status", {data = data, online = lastUpdated > 0 and failures < 3,
    stale = failures > 0, configured = base ~= nil, updated = lastUpdated, error = message or ""})
end
local function configure()
  generation = generation + 1
  base = model.base(noctalia.getConfig("host"))
  acKey = noctalia.getConfig("aircon") or "ac1"
  interval = math.max(3, tonumber(noctalia.getConfig("interval")) or 10)
  data, failures, lastUpdated, queue, busy, nextPoll = nil, 0, 0, {}, false, 0
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
    if not ack or ack.ack ~= true then publish((ack and ack.reason) or "Command failed") end
    nextPoll = 0
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
    table.insert(queue, {path = cmd.path, body = {[acKey] = cmd.body}})
  elseif cmd.path == "setScene" or cmd.path == "runScene" or cmd.path == "setMySystem" then
    table.insert(queue, {path = cmd.path, body = cmd.body})
  else return end
  pump()
end)
configure()
noctalia.setUpdateInterval(1000)
