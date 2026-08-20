# =============================================================================
# BARE-METAL IPC PRNG SERVICE ENGINE MAKEFILE
# =============================================================================

AS      := as
LD      := ld
CC      := gcc

# Default to debug
BUILD_TYPE ?= debug
BUILD_DIR  := build/x86_64/$(BUILD_TYPE)
LIB_DIR    := $(BUILD_DIR)/libs

# Externe bronnen
TESTU01_SRC := external/TestU01-2009
LIBS        := $(LIB_DIR)/libtestu01.a $(LIB_DIR)/libprobdist.a $(LIB_DIR)/libmylib.a

ASFLAGS := --64
LDFLAGS := -z noexecstack
CFLAGS  := -O3 -march=native -I./$(TESTU01_SRC)/include

.PHONY: all clean directories libs stress_harness test

all: directories libs $(BUILD_DIR)/chaos_service $(BUILD_DIR)/chaos_client stress_harness

directories:
	@mkdir -p $(BUILD_DIR) $(LIB_DIR)

# Alleen bouwen als de libs er nog niet zijn in de specifieke BUILD_DIR
libs: $(LIBS)

$(LIBS):
	@echo "[!] Building TestU01 library for $(BUILD_TYPE)..."
	cd $(TESTU01_SRC) && ./configure && make
	cp $(TESTU01_SRC)/testu01/.libs/libtestu01.a $(LIB_DIR)/
	cp $(TESTU01_SRC)/probdist/.libs/libprobdist.a $(LIB_DIR)/
	cp $(TESTU01_SRC)/mylib/.libs/libmylib.a $(LIB_DIR)/

$(BUILD_DIR)/chaos_service: x86_64/chaos_service.s x86_64/print_hex64.s
	$(AS) $(ASFLAGS) x86_64/chaos_service.s -o $(BUILD_DIR)/chaos_service.o
	$(AS) $(ASFLAGS) x86_64/print_hex64.s -o $(BUILD_DIR)/print_hex64.o
	$(LD) $(LDFLAGS) $(BUILD_DIR)/chaos_service.o $(BUILD_DIR)/print_hex64.o -o $@

$(BUILD_DIR)/chaos_client: x86_64/chaos_client.s
	$(AS) $(ASFLAGS) $< -o $(BUILD_DIR)/chaos_client.o
	$(LD) $(LDFLAGS) $(BUILD_DIR)/chaos_client.o -o $@

stress_harness:
	$(CC) $(CFLAGS) x86_64/test_bbattery_smallcrush.c -o $(BUILD_DIR)/chaos_test_small -L$(LIB_DIR) -ltestu01 -lprobdist -lmylib -lm
	$(CC) $(CFLAGS) x86_64/test_bbattery_crush.c      -o $(BUILD_DIR)/chaos_test_crush -L$(LIB_DIR) -ltestu01 -lprobdist -lmylib -lm
	$(CC) $(CFLAGS) x86_64/test_bbattery_bigcrush.c   -o $(BUILD_DIR)/chaos_test_big -L$(LIB_DIR) -ltestu01 -lprobdist -lmylib -lm

test:
	$(MAKE) all BUILD_TYPE=debug
	@if [ -f "test/stress_test.sh" ]; then \
		chmod +x stress_test/stress_test.sh && ./test/stress_test.sh; \
	else \
		echo "ERROR: stress_test/stress_test.sh not found!"; \
		exit 1; \
	fi

clean:
	@echo "[!] Cleaning build artifacts and external libraries..."
	rm -rf build/
	# Als TestU01 een lokale make clean ondersteunt, roepen we die ook aan:
	if [ -f "$(TESTU01_SRC)/Makefile" ]; then \
		$(MAKE) -C $(TESTU01_SRC) clean; \
	fi
	# Verwijder eventuele overgebleven .a files in de submodule root
	rm -f $(TESTU01_SRC)/*.a
