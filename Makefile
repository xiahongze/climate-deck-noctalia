.PHONY: test lint package

test:
	lua tests/test.lua
	lua tests/test_panel.lua
	lua tests/test_scenes_setup.lua
	lua tests/test_bar.lua
	python3 tests/test_package.py
	python3 tests/test_fake_tablet.py
lint:
	noctalia plugins lint climate-deck
	@set -e; for f in climate-deck/*.luau; do luac -p "$$f"; done
package:
	./scripts/package.sh
