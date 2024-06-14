.PHONY: test lint submodules
test: submodules
	nvim --clean -u tests/scripts/minimal_init.vim --headless -c "lua require('plenary.test_harness').test_directory('tests/')"

lint:
	luacheck lua/ --read-globals vim

submodules:
	@if git submodule status | grep -Eq '^[-+]'; then \
		git submodule update --init; \
	fi
