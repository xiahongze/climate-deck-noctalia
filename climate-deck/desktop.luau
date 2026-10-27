local model = require("./model.luau")
local function render(s)
  local ac = s and s.data and s.data.aircons and s.data.aircons[noctalia.getConfig("aircon")]
  local info = ac and ac.info or {}
  desktopWidget.render(ui.column({padding = 16, gap = 8, fill = "surface", radius = 18}, {
    ui.row({align = "center", gap = 8}, {ui.glyph({name = "temperature", color = "primary", size = 22}), ui.label({text = "CLIMATE DECK", fontWeight = "bold", fontSize = 13}), ui.spacer({flexGrow = 1}), ui.label({text = s and s.online and "LIVE" or "OFFLINE", color = "primary", fontSize = 11})}),
    ui.label({text = ac and model.temperature(model.average(ac)) or "—", fontSize = 40, fontWeight = "bold"}),
    ui.label({text = ac and ((info.state == "on" and (info.mode or "On") or "Off") .. "  ·  Target " .. model.temperature(model.target(ac))) or (s and s.error or "Connecting…"), color = "on_surface/0.65"}),
    ui.button({text = "Open controls", variant = "secondary", onClick = "openControls"})
  }))
end
noctalia.state.watch("status", render)
function update() render(noctalia.state.get("status")) end
function openControls() noctalia.runAsync({"noctalia", "msg", "panel-toggle", "xiahongze/climate-deck:panel"}) end
