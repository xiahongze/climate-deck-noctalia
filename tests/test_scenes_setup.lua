local model = assert(loadfile("climate-deck/model.luau"))()
local originalRequire = require
require = function(path)
  if path == "./model.luau" then return model end
  if path == "./scene_editor.luau" then return assert(loadfile("climate-deck/scene_editor.luau"))() end
  return originalRequire(path)
end
local ac = {info = {uid = "unit-1", name = "Home", state = "off", mode = "heat", fan = "low", setTemp = 23, myZone = 1},
  zones = {z01 = {number = 1, name = "Living", type = 1, error = 0, state = "open", measuredTemp = 21, setTemp = 23, value = 100},
           z02 = {number = 2, name = "Study", type = 1, error = 0, state = "close", measuredTemp = 20, setTemp = 22, value = 100}}}
local state = {status = {online = true, pollSequence = 1, data = {aircons = {ac1 = ac}, myScenes = {scenes = {}, scenesOrder = {}}}}}
local watchers, tree = {}, nil
noctalia = {getConfig = function() return "ac1" end, runAsync = function() end,
 state = {get = function(k) return state[k] end, set = function(k, v) state[k] = v end, watch = function(k, f) watchers[k] = f end}}
ui = setmetatable({}, {__index = function(_, kind) return function(props, children) return {kind = kind, props = props or {}, children = children or {}} end end})
panel = {render = function(t) tree = t end, close = function() end}
assert(loadfile("climate-deck/panel.luau"))(); onOpen()
local function find(node, pred)
  if pred(node) then return node end
  for _, child in ipairs(node.children) do local v = find(child, pred); if v then return v end end
end
local function named(text) return assert(find(tree, function(n) return n.props.text == text end), "missing " .. text) end
local function input(key) return assert(find(tree, function(n) return n.kind == "input" and n.props.key == key end), "missing input " .. key) end
local function update(sequence)
  state.status.pollSequence = sequence; watchers.status(state.status)
end
named("Scenes").props.onClick(); named("+ New").props.onClick()
assert(input("scene-name-s10001"))
named("Save").props.onClick(); assert(named("Use a name of 1–12 characters without a backslash."))
input("scene-name-s10001").props.onChange("Morning")
named("Weekdays").props.onClick()
named("+15m").props.onClick()
named("Cool").props.onClick()
named("High").props.onClick()
named("Study").props.onClick()
named("+").props.onClick()
local function parentWithText(node, text)
  for _, child in ipairs(node.children) do
    if child.props.text == text then return node end
    local p = parentWithText(child, text); if p then return p end
  end
end
local myZoneRow = parentWithText(tree, "Study ★")
assert(myZoneRow and find(myZoneRow, function(n) return n.kind == "toggle" end).props.enabled == false)
named("Save").props.onClick()
local cmd = state.command
assert(cmd.path == "setScene" and cmd.body.id == "s10001" and cmd.body.name == "Morning")
assert(cmd.body.activeDays == 62 and cmd.body.startTime == 435 and cmd.body.aircons.ac1.info.uid == "unit-1")
assert(cmd.body.aircons.ac1.info.mode == "cool" and cmd.body.aircons.ac1.info.fan == "high")
assert(cmd.body.aircons.ac1.info.myZone == 2 and cmd.body.aircons.ac1.zones.z02.state == "open" and cmd.body.aircons.ac1.zones.z02.setTemp == 23)
watchers.commandResult({token = cmd.token, ok = true})
update(2); assert(named("Saving…")) -- ack alone is not confirmation
state.status.data.myScenes.scenes.s10001 = model.copy(cmd.body)
update(3); assert(named("Morning") and named("Edit"))
-- Editing preserves other aircons and unrelated scene fields on the tablet.
local scene = state.status.data.myScenes.scenes.s10001
scene.aircons.ac2 = {info = {name = "Other"}, zones = {z01 = {number = 1, state = "open"}}}
scene.lights = {group = {state = "on"}}
named("Edit").props.onClick(); input("scene-name-s10001").props.onChange("Evening"); named("Save").props.onClick()
cmd = state.command
assert(cmd.body.name == "Evening" and cmd.body.aircons.ac2.info.name == "Other" and cmd.body.lights == nil)
watchers.commandResult({token = cmd.token, ok = false, reason = "Rejected"})
assert(named("The tablet refused the scene: Rejected"))
named("Save").props.onClick(); cmd = state.command; watchers.commandResult({token = cmd.token, ok = true})
update(4); update(5); assert(named("The tablet did not confirm the save. Please try again."))
named("Cancel").props.onClick(); named("Setup").props.onClick()
input("rename-aircon").props.onChange("New name")
local function parentOf(node, key)
  for _, child in ipairs(node.children) do
    if child.props.key == key then return node end
    local p = parentOf(child, key); if p then return p end
  end
end
local nameRow = parentOf(tree, "rename-aircon")
local save = find(nameRow, function(n) return n.props.text == "Save" end)
save.props.onClick(); assert(state.command.body.info.name == "New name")
input("rename-z02").props.onChange("Study 2")
local zoneRow = parentOf(tree, "rename-z02")
find(zoneRow, function(n) return n.props.text == "Save" end).props.onClick()
assert(state.command.body.zones.z02.name == "Study 2")
input("rename-z02").props.onChange("bad\\name")
find(zoneRow, function(n) return n.props.text == "Save" end).props.onClick()
assert(named("Use a name of 1–12 characters without a backslash."))
local function rowWith(node, a, b)
 if node.kind == "row" and find(node, function(n) return n.props.text == a end) and find(node, function(n) return n.props.text == b end) then return node end
 for _, child in ipairs(node.children) do local r = rowWith(child, a, b); if r then return r end end
end
local range = assert(rowWith(tree, "Heat", "Cool"))
assert(range.children[4].props.enabled == false) -- 20 → 21 would leave less than 4°
range.children[2].props.onClick() -- heat 20 → 19
assert(state.command.body.info.myAutoHeatTargetTemp == 19 and state.command.body.info.myAutoCoolTargetTemp == 24)
assert(model.validRange(16, 20) and not model.validRange(21, 24) and not model.validRange(16, 33))
assert(model.validName("空调") and model.validName("😀😀😀😀😀😀") and not model.validName("😀😀😀😀😀😀😀") and not model.validName("bad\\name"))
print("scene editing and setup: ok")
