# ==============================================================================
# BARE-METAL IPC PRNG SERVICE ENGINE MAKEFILE
# ==============================================================================

AS      := as
LD      := ld

# Sizing and Linking
ASFLAGS := --64
# -no-pie is not needed for ld (it's a gcc flag), 
# -z noexecstack ensures your security-hardened stack stays secure
LDFLAGS := -z noexecstack

# Tree Directories
SRC_DIR   := src/x86_64
BUILD_DIR := build/x86_64
BIN_DIR   := bin/x86_64

# Targets
SERVICE_BIN := $(BIN_DIR)/chaos_service
CLIENT_BIN  := $(BIN_DIR)/chaos_client

# Object Maps
COMMON_OBJ  := $(BUILD_DIR)/print_hex64.o
SERVICE_OBJ := $(BUILD_DIR)/chaos_service.o
CLIENT_OBJ  := $(BUILD_DIR)/chaos_client.o

.PHONY: all clean directories

all: directories $(SERVICE_BIN) $(CLIENT_BIN)

directories:
	@mkdir -p $(BUILD_DIR) $(BIN_DIR)

# Assemble Common Objects
$(COMMON_OBJ): $(SRC_DIR)/common/print_hex64.s
	@echo "[ASM] Compiling Shared Artifacts..."
	$(AS) $(ASFLAGS) $< -o $@

# Assemble Service Object
$(SERVICE_OBJ): $(SRC_DIR)/service/chaos_service.s
	@echo "[ASM] Compiling Chaos Master Daemon..."
	$(AS) $(ASFLAGS) $< -o $@

# Assemble Client Object
$(CLIENT_OBJ): $(SRC_DIR)/client/chaos_client.s
	@echo "[ASM] Compiling Chaos Interfacing Client..."
	$(AS) $(ASFLAGS) $< -o $@

# Link Service Executable
$(SERVICE_BIN): $(SERVICE_OBJ) $(COMMON_OBJ)
	@echo "[LINK] Forging chaos_service..."
	$(LD) $(LDFLAGS) $^ -o $@

# Link Client Executable
$(CLIENT_BIN): $(CLIENT_OBJ) $(COMMON_OBJ)
	@echo "[LINK] Forging chaos_client..."
	$(LD) $(LDFLAGS) $^ -o $@

clean:
	@echo "[CLEAN] Purging runtime output structures..."
	rm -rf bin/ build/
	rm -f *.dat *.log
