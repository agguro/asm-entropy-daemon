# =============================================================================
# BARE-METAL IPC PRNG SERVICE ENGINE MAKEFILE
# =============================================================================

AS      := as
LD      := ld
CC      := gcc

# Default to debug, usage: make BUILD_TYPE=release
BUILD_TYPE ?= debug
BUILD_DIR  := build/$(BUILD_TYPE)/x86_64
BIN_DIR    := bin/$(BUILD_TYPE)/x86_64

# Flags
ASFLAGS := --64
LDFLAGS := -z noexecstack
CFLAGS  := -O3 -march=native -I./external/TestU01-2009/include

.PHONY: all clean directories

all: directories $(BIN_DIR)/chaos_service $(BIN_DIR)/chaos_client

directories:
	@mkdir -p $(BUILD_DIR) $(BIN_DIR)

$(BIN_DIR)/chaos_service: src/x86_64/service/chaos_service.s src/x86_64/common/print_hex64.s
	$(AS) $(ASFLAGS) src/x86_64/service/chaos_service.s -o $(BUILD_DIR)/chaos_service.o
	$(AS) $(ASFLAGS) src/x86_64/common/print_hex64.s -o $(BUILD_DIR)/print_hex64.o
	$(LD) $(LDFLAGS) $(BUILD_DIR)/chaos_service.o $(BUILD_DIR)/print_hex64.o -o $@

$(BIN_DIR)/chaos_client: src/x86_64/client/chaos_client.s
	$(AS) $(ASFLAGS) $< -o $(BUILD_DIR)/chaos_client.o
	$(LD) $(LDFLAGS) $(BUILD_DIR)/chaos_client.o -o $@

clean:
	@echo "[CLEAN] Purging all build structures..."
	rm -rf bin/ build/
