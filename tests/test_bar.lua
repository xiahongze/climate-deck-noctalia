local model = assert(loadfile("climate-deck/model.luau"))()
local oldRequire = require
require = function(path) if path == "./model.luau" then return model end return oldRequire(path) end
local opened
noctalia = {togglePanel = function(id) opened = id end, state = {watch = function() end, get = function() end}, getConfig = function() return "ac1" end}
barWidget = {setGlyph = function() end, setText = function() end, setTooltip = function() end}
assert(loadfile("climate-deck/bar.luau"))()
onClick()
assert(opened == "xiahongze/climate-deck:panel")
print("bar click: ok")
