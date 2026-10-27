import pathlib
import tomllib
root = pathlib.Path(__file__).resolve().parent.parent
manifest = tomllib.loads((root / "climate-deck/plugin.toml").read_text())
catalog = tomllib.loads((root / "catalog.toml").read_text())["plugin"][0]
for key in ("id", "name", "version", "plugin_api"):
    assert manifest[key] == catalog[key], key
for kind in ("service", "widget", "desktop_widget", "panel"):
    for entry in manifest.get(kind, []):
        assert (root / "climate-deck" / entry["entry"]).is_file(), entry
print("manifest and catalog: ok")
