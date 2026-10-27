local model = assert(loadfile("climate-deck/model.luau"))()
local originalRequire = require
require = function(path) if path == "./model.luau" then return model end return originalRequire(path) end
local state = {status = {online = true, data = {aircons = {ac1 = {
  info = {name = "Home", state = "on", mode = "heat", fan = "low", myZone = 1},
  zones = {z01 = {number = 1, name = "Living", type = 1, error = 0, measuredTemp = 21, setTemp = 23, state = "open"},
    z02 = {number = 2, name = "Study", type = 1, error = 0, measuredTemp = 20, setTemp = 22, state = "close"}}
}}, myScenes = {scenes = {s10001 = {name = "Evening", timerEnabled = false}}}}}}
for n = 3, 6 do
  state.status.data.aircons.ac1.zones[string.format("z%02d", n)] = {number = n, name = "Zone " .. n, type = 1, error = 0, measuredTemp = 20, setTemp = 22, state = "open"}
end
local watchers, tree = {}, nil
noctalia = {getConfig = function() return "ac1" end, runAsync = function() end,
  state = {get = function(k) return state[k] end, set = function(k, v) state[k] = v end,
    watch = function(k, f) watchers[k] = f end}}
ui = setmetatable({}, {__index = function(_, kind) return function(props, children) return {kind = kind, props = props or {}, children = children or {}} end end})
panel = {render = function(t) tree = t end, close = function() end}
assert(loadfile("climate-deck/panel.luau"))()
onOpen()
local function find(node, text)
  if node.props.text == text then return node end
  for _, child in ipairs(node.children) do local found = find(child, text); if found then return found end end
end
assert(find(tree, "CLIMATE DECK"))
assert(find(tree, "Living"))
assert(not find(tree, "Close") and not find(tree, "ZONES"))
local function parentOf(node, text)
  for _, child in ipairs(node.children) do
    if child.props.text == text then return node end
    local parent = parentOf(child, text); if parent then return parent end
  end
end
local firstRow, secondRow = parentOf(tree, "Living"), parentOf(tree, "Zone 4")
assert(firstRow.kind == "row" and #firstRow.children == 3)
assert(secondRow.kind == "row" and #secondRow.children == 3)
assert(firstRow.children[1].props.flexGrow == 1)
state.status.data.aircons.ac1.zones.z07 = {number = 7, name = "Zone 7", type = 1, error = 0, measuredTemp = 20, setTemp = 22, state = "open"}
watchers.status(state.status)
assert(#parentOf(tree, "Zone 7").children == 1)
find(tree, "Turn off").props.onClick()
assert(state.command.path == "setAircon" and state.command.body.info.state == "off")
find(tree, "Study").props.onClick()
assert(state.command.body.zones.z02.state == "open")
find(tree, "Scenes").props.onClick()
assert(find(tree, "Evening"))
find(tree, "Run now").props.onClick()
assert(state.command.path == "runScene" and state.command.body.id == "s10001")
find(tree, "Setup").props.onClick()
find(tree, "MyAuto").props.onClick()
assert(state.command.body.info.myAutoModeEnabled == true and state.command.body.info.climateControlModeEnabled == false)
state.status.online = false; watchers.status(state.status)
local old = state.command
find(tree, "MyTemp").props.onClick()
assert(state.command == old)
print("panel interactions: ok")
