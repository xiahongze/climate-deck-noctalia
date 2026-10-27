.PHONY: test lint package

test:
	lua tests/test.lua
	python3 tests/test_package.py
lint:
	noctalia plugins lint climate-deck
	@for f in climate-deck/*.luau; do luac -p "$$f"; done
package:
	./scripts/package.sh
