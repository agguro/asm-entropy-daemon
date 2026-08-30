# =============================================================================
# BARE-METAL IPC PRNG SERVICE ENGINE MAKEFILE (MULTIARCH)
# Author: agguro
# Date: August 2026
# =============================================================================

AS      := as
LD      := ld
CC      := gcc
STRIP   := strip

ARCH       ?= $(shell uname -m)
BUILD_TYPE ?= debug

# Project structure paths
PROJECT_ROOT := $(CURDIR)
INCLUDE_DIR  := $(PROJECT_ROOT)/include
ARCH_SRC_DIR := $(PROJECT_ROOT)/$(ARCH)
TESTU01_SRC  := $(PROJECT_ROOT)/external/TestU01-2009

# Output directory layout
ARCH_BUILD_DIR := $(PROJECT_ROOT)/build/$(ARCH)
BUILD_DIR      := $(ARCH_BUILD_DIR)/$(BUILD_TYPE)
OBJ_DIR        := $(BUILD_DIR)/obj
LST_DIR        := $(BUILD_DIR)/lists
MAP_DIR        := $(BUILD_DIR)/maps
LIB_DIR        := $(BUILD_DIR)/libs
TOP_LIB_DIR    := $(ARCH_BUILD_DIR)/libs

# TestU01 libraries
VERSION        := 1.2.3
ifeq ($(BUILD_TYPE),release)
    LIB_SUFFIX := .$(VERSION).a
else
    LIB_SUFFIX := .$(VERSION)-dbg.a
endif

LIBS := $(LIB_DIR)/libtestu01$(LIB_SUFFIX) $(LIB_DIR)/libprobdist$(LIB_SUFFIX) $(LIB_DIR)/libmylib$(LIB_SUFFIX)

# Architecture-specific flags
ifeq ($(ARCH),x86_64)
    ARCH_ASFLAGS := --64
else ifeq ($(ARCH),riscv64)
    ARCH_ASFLAGS := -march=rv64gc -mabi=lp64d
else ifeq ($(ARCH),aarch64)
    ARCH_ASFLAGS :=
endif

# Debug vs Release flags
BASE_CFLAGS := -Wall -Wextra \
               -I$(INCLUDE_DIR) \
               -I$(TESTU01_SRC)/include \
               -I$(TESTU01_SRC)/mylib \
               -I$(TESTU01_SRC)/probdist \
               -I$(TESTU01_SRC)/testu01

ifeq ($(BUILD_TYPE),release)
    ASFLAGS := $(ARCH_ASFLAGS) -I$(INCLUDE_DIR)
    LDFLAGS := -z noexecstack -s
    CFLAGS  := -O3 -march=native -DNDEBUG $(BASE_CFLAGS)
else
    ASFLAGS := $(ARCH_ASFLAGS) -g -I$(INCLUDE_DIR)
    LDFLAGS := -z noexecstack
    CFLAGS  := -O0 -g3 -march=native $(BASE_CFLAGS)
endif

# Target binaries and harnesses
BINARIES := $(BUILD_DIR)/chaos_engine $(BUILD_DIR)/chaos_logger $(BUILD_DIR)/chaos_monitor
HARNESS  := $(BUILD_DIR)/chaos_test_small $(BUILD_DIR)/chaos_test_crush $(BUILD_DIR)/chaos_test_big

.PHONY: all debug release clean clean-all directories libs stress_harness test info

all: directories libs $(BINARIES) stress_harness

debug:
	@$(MAKE) BUILD_TYPE=debug all

release:
	@$(MAKE) BUILD_TYPE=release all

info:
	@echo "[*] Architecture : $(ARCH)"
	@echo "[*] Build Type   : $(BUILD_TYPE)"
	@echo "[*] Output Path  : $(BUILD_DIR)"

directories:
	@mkdir -p $(BUILD_DIR) $(OBJ_DIR) $(LIB_DIR) $(TOP_LIB_DIR)
ifeq ($(BUILD_TYPE),debug)
	@mkdir -p $(LST_DIR) $(MAP_DIR)
endif

# -----------------------------------------------------------------------------
# Build external TestU01 static libraries within local build tree
# -----------------------------------------------------------------------------
libs: $(LIBS)

$(LIBS): | directories
	@echo "[!] Building TestU01 static libraries for $(ARCH) ($(BUILD_TYPE))..."
	$(MAKE) -C $(TESTU01_SRC) \
		ARCH=$(ARCH) \
		BUILD_TYPE=$(BUILD_TYPE) \
		BUILD_DIR=$(BUILD_DIR)/testu01 \
		LIB_DIR=$(LIB_DIR) \
		TOP_LIB_DIR=$(TOP_LIB_DIR)

# -----------------------------------------------------------------------------
# Assembly Engines & Tools
# -----------------------------------------------------------------------------
ifeq ($(BUILD_TYPE),debug)
$(BUILD_DIR)/chaos_engine: $(ARCH_SRC_DIR)/chaos_engine.s | directories
	$(AS) $(ASFLAGS) -a=$(LST_DIR)/chaos_engine.lst $< -o $(OBJ_DIR)/chaos_engine.o
	$(LD) $(LDFLAGS) -Map=$(MAP_DIR)/chaos_engine.map $(OBJ_DIR)/chaos_engine.o -o $@

$(BUILD_DIR)/chaos_logger: $(ARCH_SRC_DIR)/chaos_logger.s $(ARCH_SRC_DIR)/u64toa.s | directories
	$(AS) $(ASFLAGS) -a=$(LST_DIR)/chaos_logger.lst $(ARCH_SRC_DIR)/chaos_logger.s -o $(OBJ_DIR)/chaos_logger.o
	$(AS) $(ASFLAGS) -a=$(LST_DIR)/u64toa.lst $(ARCH_SRC_DIR)/u64toa.s -o $(OBJ_DIR)/u64toa.o
	$(LD) $(LDFLAGS) -Map=$(MAP_DIR)/chaos_logger.map $(OBJ_DIR)/chaos_logger.o $(OBJ_DIR)/u64toa.o -o $@

$(BUILD_DIR)/chaos_monitor: $(ARCH_SRC_DIR)/chaos_monitor.s | directories
	$(AS) $(ASFLAGS) -a=$(LST_DIR)/chaos_monitor.lst $< -o $(OBJ_DIR)/chaos_monitor.o
	$(LD) $(LDFLAGS) -Map=$(MAP_DIR)/chaos_monitor.map $(OBJ_DIR)/chaos_monitor.o -o $@
else
$(BUILD_DIR)/chaos_engine: $(ARCH_SRC_DIR)/chaos_engine.s | directories
	$(AS) $(ASFLAGS) $< -o $(OBJ_DIR)/chaos_engine.o
	$(LD) $(LDFLAGS) $(OBJ_DIR)/chaos_engine.o -o $@

$(BUILD_DIR)/chaos_logger: $(ARCH_SRC_DIR)/chaos_logger.s $(ARCH_SRC_DIR)/u64toa.s | directories
	$(AS) $(ASFLAGS) $(ARCH_SRC_DIR)/chaos_logger.s -o $(OBJ_DIR)/chaos_logger.o
	$(AS) $(ASFLAGS) $(ARCH_SRC_DIR)/u64toa.s -o $(OBJ_DIR)/u64toa.o
	$(LD) $(LDFLAGS) $(OBJ_DIR)/chaos_logger.o $(OBJ_DIR)/u64toa.o -o $@

$(BUILD_DIR)/chaos_monitor: $(ARCH_SRC_DIR)/chaos_monitor.s | directories
	$(AS) $(ASFLAGS) $< -o $(OBJ_DIR)/chaos_monitor.o
	$(LD) $(LDFLAGS) $(OBJ_DIR)/chaos_monitor.o -o $@
endif

# -----------------------------------------------------------------------------
# C Test Harnesses (Linked against TestU01)
# -----------------------------------------------------------------------------
stress_harness: $(HARNESS)

ifeq ($(BUILD_TYPE),debug)
$(BUILD_DIR)/chaos_test_small: $(ARCH_SRC_DIR)/test_bbattery_smallcrush.c $(LIBS)
	$(CC) $(CFLAGS) $< -o $@ -L$(LIB_DIR) -ltestu01$(LIB_SUFFIX:.a=) -lprobdist$(LIB_SUFFIX:.a=) -lmylib$(LIB_SUFFIX:.a=) -lm -Wl,-Map=$(MAP_DIR)/chaos_test_small.map

$(BUILD_DIR)/chaos_test_crush: $(ARCH_SRC_DIR)/test_bbattery_crush.c $(LIBS)
	$(CC) $(CFLAGS) $< -o $@ -L$(LIB_DIR) -ltestu01$(LIB_SUFFIX:.a=) -lprobdist$(LIB_SUFFIX:.a=) -lmylib$(LIB_SUFFIX:.a=) -lm -Wl,-Map=$(MAP_DIR)/chaos_test_crush.map

$(BUILD_DIR)/chaos_test_big: $(ARCH_SRC_DIR)/test_bbattery_bigcrush.c $(LIBS)
	$(CC) $(CFLAGS) $< -o $@ -L$(LIB_DIR) -ltestu01$(LIB_SUFFIX:.a=) -lprobdist$(LIB_SUFFIX:.a=) -lmylib$(LIB_SUFFIX:.a=) -lm -Wl,-Map=$(MAP_DIR)/chaos_test_big.map
else
$(BUILD_DIR)/chaos_test_small: $(ARCH_SRC_DIR)/test_bbattery_smallcrush.c $(LIBS)
	$(CC) $(CFLAGS) $< -o $@ -L$(LIB_DIR) -ltestu01$(LIB_SUFFIX:.a=) -lprobdist$(LIB_SUFFIX:.a=) -lmylib$(LIB_SUFFIX:.a=) -lm

$(BUILD_DIR)/chaos_test_crush: $(ARCH_SRC_DIR)/test_bbattery_crush.c $(LIBS)
	$(CC) $(CFLAGS) $< -o $@ -L$(LIB_DIR) -ltestu01$(LIB_SUFFIX:.a=) -lprobdist$(LIB_SUFFIX:.a=) -lmylib$(LIB_SUFFIX:.a=) -lm

$(BUILD_DIR)/chaos_test_big: $(ARCH_SRC_DIR)/test_bbattery_bigcrush.c $(LIBS)
	$(CC) $(CFLAGS) $< -o $@ -L$(LIB_DIR) -ltestu01$(LIB_SUFFIX:.a=) -lprobdist$(LIB_SUFFIX:.a=) -lmylib$(LIB_SUFFIX:.a=) -lm
endif

# -----------------------------------------------------------------------------
# Test Target
# -----------------------------------------------------------------------------
test:
	$(MAKE) all BUILD_TYPE=debug
	@cd test && ./stress_test.sh
	@echo "[*] Results of tests can be found in test/results/"

# -----------------------------------------------------------------------------
# Clean Targets
# -----------------------------------------------------------------------------
clean:
	@echo "[!] Cleaning build artifacts for $(ARCH) ($(BUILD_TYPE))..."
	rm -rf $(BUILD_DIR)
	@rm -f $(TOP_LIB_DIR)/*

clean-all:
	@echo "[!] Cleaning all build directories..."
	rm -rf $(PROJECT_ROOT)/build
