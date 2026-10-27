local model = require("./model.luau")
local function render(s)
  local ac = s and s.data and s.data.aircons and s.data.aircons[noctalia.getConfig("aircon")]
  barWidget.setGlyph("temperature")
  barWidget.setText(ac and model.temperature(model.average(ac)) or "Climate")
  barWidget.setTooltip(s and (s.error ~= "" and s.error or (s.online and "Climate Deck · connected" or "Climate Deck · offline")) or "Climate Deck")
end
noctalia.state.watch("status", render)
function update() render(noctalia.state.get("status")) end
function onClick() noctalia.togglePanel("xiahongze/climate-deck:panel") end
