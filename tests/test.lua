local model = assert(loadfile("climate-deck/model.luau"))()
assert(model.base("") == nil)
assert(model.base("192.0.2.1") == "http://192.0.2.1:2025")
assert(model.base("test:3000") == "http://test:3000")
assert(model.base("host/path") == nil)
local ac = {info = {setTemp = 22, myZone = 1}, zones = {
  z01 = {number = 1, type = 1, error = 0, measuredTemp = 20, setTemp = 24},
  z02 = {number = 2, type = 1, error = 1, measuredTemp = 30},
  z03 = {number = 3, type = 0, error = 0, measuredTemp = 29}}}
assert(model.average(ac) == 20)
assert(model.target(ac) == 24)
assert(model.targetPayload(ac, 40).zones.z01.setTemp == 32)
ac.info.myZone = 0
assert(model.targetPayload(ac, 0).info.setTemp == 16)
assert(#model.zones(ac) == 3)

local watchers, shared, requests = {}, {}, {}
local config = {host = "127.0.0.1:2025", aircon = "ac1", interval = 10}
local replyData = {aircons = {ac1 = ac}}
local time = 100
os.time = function() return time end
noctalia = {
  getConfig = function(k) return config[k] end,
  state = {set = function(k, v) shared[k] = v; if watchers[k] then watchers[k](v) end end,
    get = function(k) return shared[k] end,
    watch = function(k, f) watchers[k] = f end},
  setUpdateInterval = function(ms) assert(ms == 1000) end,
  http = function(req, cb) table.insert(requests, {req = req, cb = cb}); return true end,
  json = {encode = function(v) return "encoded" end, decode = function(v) if v == "good" then return replyData elseif v == "ack" then return {ack = true} end end},
  string = {urlEncode = function(v) return v end}
}
local realRequire = require
require = function(path) if path == "./model.luau" then return model end return realRequire(path) end
assert(loadfile("climate-deck/service.luau"))()
assert(shared.status.configured and not shared.status.online)
update()
assert(#requests == 1 and requests[1].req.url == "http://127.0.0.1:2025/getSystemData")
update(); assert(#requests == 1) -- one request at a time
requests[1].cb({ok = true, status = 200, body = "good"})
assert(shared.status.online and shared.status.data.aircons.ac1.info.myZone == 0)
shared.command = {path = "setAircon", body = {info = {state = "off"}}}
watchers.command(shared.command)
assert(#requests == 2 and requests[2].req.url:find("/setAircon?json=", 1, true))
watchers.command({path = "runScene", body = {id = "s10001"}})
assert(#requests == 2)
requests[2].cb({ok = true, status = 200, body = "ack"})
assert(#requests == 3 and requests[3].req.url:find("/runScene?json=", 1, true))
requests[3].cb({ok = true, status = 200, body = "ack"})
time = time + 2; update(); assert(#requests == 4) -- refresh after a write
requests[4].cb({ok = true, status = 200, body = "invalid"})
assert(shared.status.online and shared.status.stale and shared.status.data.aircons.ac1.info.myZone == 0)
for _ = 1, 2 do time = time + 10; update(); requests[#requests].cb({ok = false, status = 0}) end
assert(not shared.status.online and shared.status.data.aircons.ac1.info.myZone == 0)
local count = #requests
watchers.command({path = "setAircon", body = {info = {state = "on"}}})
assert(#requests == count) -- no controls while offline
config.host = ""; onConfigChanged(); assert(not shared.status.configured and not shared.status.data)
print("model and service: ok")
