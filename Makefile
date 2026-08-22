# =============================================================================
# BARE-METAL IPC PRNG SERVICE ENGINE MAKEFILE
# Author: agguro
# Date: August 2026
# =============================================================================

AS      := as
LD      := ld
CC      := gcc

# Project structure paths
PROJECT_ROOT ?= .
INCLUDE_DIR  := $(PROJECT_ROOT)/include

# Default to debug
BUILD_TYPE ?= debug
BUILD_DIR  := build/x86_64/$(BUILD_TYPE)
LIB_DIR    := $(BUILD_DIR)/libs

# External sources
TESTU01_SRC := external/TestU01-2009
LIBS        := $(LIB_DIR)/libtestu01.a $(LIB_DIR)/libprobdist.a $(LIB_DIR)/libmylib.a

# Assembler flags
ASFLAGS := --64 -I$(INCLUDE_DIR)
LDFLAGS := -z noexecstack
CFLAGS  := -O3 -march=native -I./$(TESTU01_SRC)/include

.PHONY: all clean directories libs stress_harness test

all: directories libs $(BUILD_DIR)/chaos_engine $(BUILD_DIR)/chaos_logger $(BUILD_DIR)/chaos_monitor stress_harness

directories:
	@mkdir -p $(BUILD_DIR) $(LIB_DIR)

libs: $(LIBS)

$(LIBS):
	@echo "[!] Building TestU01 library for $(BUILD_TYPE)..."
	cd $(TESTU01_SRC) && ./configure && make
	cp $(TESTU01_SRC)/testu01/.libs/libtestu01.a $(LIB_DIR)/
	cp $(TESTU01_SRC)/probdist/.libs/libprobdist.a $(LIB_DIR)/
	cp $(TESTU01_SRC)/mylib/.libs/libmylib.a $(LIB_DIR)/

$(BUILD_DIR)/chaos_engine: x86_64/chaos_engine.s x86_64/print_hex64.s
	$(AS) $(ASFLAGS) x86_64/chaos_engine.s -o $(BUILD_DIR)/chaos_engine.o
	$(AS) $(ASFLAGS) x86_64/print_hex64.s -o $(BUILD_DIR)/print_hex64.o
	$(LD) $(LDFLAGS) $(BUILD_DIR)/chaos_engine.o $(BUILD_DIR)/print_hex64.o -o $@

$(BUILD_DIR)/chaos_logger: x86_64/chaos_logger.s x86_64/u64toa.s
	$(AS) $(ASFLAGS) x86_64/chaos_logger.s -o $(BUILD_DIR)/chaos_logger.o
	$(AS) $(ASFLAGS) x86_64/u64toa.s -o $(BUILD_DIR)/u64toa.o
	$(LD) $(LDFLAGS) $(BUILD_DIR)/chaos_logger.o $(BUILD_DIR)/u64toa.o -o $@

$(BUILD_DIR)/chaos_monitor: x86_64/chaos_monitor.s
	$(AS) $(ASFLAGS) $< -o $(BUILD_DIR)/chaos_monitor.o
	$(LD) $(LDFLAGS) $(BUILD_DIR)/chaos_monitor.o -o $@

stress_harness: $(TEST_BIN_SMALL) $(TEST_BIN_CRUSH) $(TEST_BIN_BIG)
	$(CC) $(CFLAGS) x86_64/test_bbattery_smallcrush.c -o $(BUILD_DIR)/chaos_test_small -L$(LIB_DIR) -ltestu01 -lprobdist -lmylib -lm
	$(CC) $(CFLAGS) x86_64/test_bbattery_crush.c       -o $(BUILD_DIR)/chaos_test_crush -L$(LIB_DIR) -ltestu01 -lprobdist -lmylib -lm
	$(CC) $(CFLAGS) x86_64/test_bbattery_bigcrush.c    -o $(BUILD_DIR)/chaos_test_big   -L$(LIB_DIR) -ltestu01 -lprobdist -lmylib -lm

test:
	$(MAKE) all BUILD_TYPE=debug
	@cd test && ./stress_test.sh
	@echo "results of tests can be found in test/results/"

clean:
	@echo "[!] Cleaning build artifacts and external libraries..."
	rm -rf build/
	if [ -f "$(TESTU01_SRC)/Makefile" ]; then \
		$(MAKE) -C $(TESTU01_SRC) clean; \
	fi
	rm -f $(TESTU01_SRC)/*.a
