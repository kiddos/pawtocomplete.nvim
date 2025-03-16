TESTS_INIT=tests/init.lua
TESTS_DIR=tests/

all:
	cmake -B build -DCMAKE_BUILD_TYPE=Release
	make -C build

clean:
	make -C build clean

test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

.PHONY: all clean test
