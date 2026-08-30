# ==============================================================================
# Makefile for TestU01-2009 (Multiarch, Semantic Versioning, Maps & Symlinks)
# Version : 1.2.3
# Author  : agguro
# ==============================================================================

CC      ?= gcc
AR      ?= ar
RANLIB  ?= ranlib
LD      ?= ld

VERSION    := 1.2.3
ARCH       ?= $(shell uname -m)
BUILD_TYPE ?= debug

SRC_ROOT   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ARCH_DIR   := $(SRC_ROOT)/build/$(ARCH)
BUILD_DIR  ?= $(ARCH_DIR)/$(BUILD_TYPE)
OBJ_DIR    := $(BUILD_DIR)/obj
LIB_DIR    := $(BUILD_DIR)/libs
TOP_LIB_DIR:= $(ARCH_DIR)/libs

# Debug-specifieke directories
LST_DIR    := $(BUILD_DIR)/lists
ASM_DIR    := $(BUILD_DIR)/S
MAP_DIR    := $(BUILD_DIR)/maps

# Headers & Flags
CPPFLAGS   := -I$(SRC_ROOT)/include -I$(SRC_ROOT)/mylib -I$(SRC_ROOT)/probdist -I$(SRC_ROOT)/testu01
BASE_FLAGS := -fPIC -Wall -Wextra -Wno-unused-parameter -Wno-unused-result -Wno-implicit-function-declaration -Wno-stringop-truncation

ifeq ($(BUILD_TYPE),release)
    CFLAGS     ?= -O3 -DNDEBUG $(BASE_FLAGS)
    LIB_SUFFIX := .$(VERSION).a
else
    CFLAGS     ?= -O0 -g3 $(BASE_FLAGS)
    LIB_SUFFIX := .$(VERSION)-dbg.a
endif

# Bronbestanden
MYLIB_SRCS    := $(wildcard $(SRC_ROOT)/mylib/*.c)
PROBDIST_SRCS := $(wildcard $(SRC_ROOT)/probdist/*.c)
TESTU01_SRCS  := $(wildcard $(SRC_ROOT)/testu01/*.c)

# Objecten
MYLIB_OBJS    := $(patsubst $(SRC_ROOT)/mylib/%.c,$(OBJ_DIR)/mylib_%.o,$(MYLIB_SRCS))
PROBDIST_OBJS := $(patsubst $(SRC_ROOT)/probdist/%.c,$(OBJ_DIR)/probdist_%.o,$(PROBDIST_SRCS))
TESTU01_OBJS  := $(patsubst $(SRC_ROOT)/testu01/%.c,$(OBJ_DIR)/testu01_%.o,$(TESTU01_SRCS))

# Versioneerde library targets
TARGET_MYLIB    := $(LIB_DIR)/libmylib$(LIB_SUFFIX)
TARGET_PROBDIST := $(LIB_DIR)/libprobdist$(LIB_SUFFIX)
TARGET_TESTU01  := $(LIB_DIR)/libtestu01$(LIB_SUFFIX)
LIBS            := $(TARGET_MYLIB) $(TARGET_PROBDIST) $(TARGET_TESTU01)

.PHONY: all debug release clean clean-all directories symlinks

all: directories $(LIBS) symlinks

debug:
	@$(MAKE) BUILD_TYPE=debug all

release:
	@$(MAKE) BUILD_TYPE=release all

directories:
	@mkdir -p $(OBJ_DIR) $(LIB_DIR) $(TOP_LIB_DIR)
ifeq ($(BUILD_TYPE),debug)
	@mkdir -p $(LST_DIR) $(ASM_DIR) $(MAP_DIR)
endif

# Bibliotheek creatie + optionele generatie van linker map
$(TARGET_MYLIB): $(MYLIB_OBJS)
	$(AR) rcs $@ $^
	$(RANLIB) $@
ifeq ($(BUILD_TYPE),debug)
	@$(LD) -r --print-map $^ > $(MAP_DIR)/libmylib.map 2>/dev/null || true
endif

$(TARGET_PROBDIST): $(PROBDIST_OBJS)
	$(AR) rcs $@ $^
	$(RANLIB) $@
ifeq ($(BUILD_TYPE),debug)
	@$(LD) -r --print-map $^ > $(MAP_DIR)/libprobdist.map 2>/dev/null || true
endif

$(TARGET_TESTU01): $(TESTU01_OBJS)
	$(AR) rcs $@ $^
	$(RANLIB) $@
ifeq ($(BUILD_TYPE),debug)
	@$(LD) -r --print-map $^ > $(MAP_DIR)/libtestu01.map 2>/dev/null || true
endif

# Symlinks aanmaken in build/$(ARCH)/libs/ die wijzen naar de actieve build
symlinks: $(LIBS)
	@ln -sf ../$(BUILD_TYPE)/libs/libmylib$(LIB_SUFFIX) $(TOP_LIB_DIR)/libmylib.a
	@ln -sf ../$(BUILD_TYPE)/libs/libprobdist$(LIB_SUFFIX) $(TOP_LIB_DIR)/libprobdist.a
	@ln -sf ../$(BUILD_TYPE)/libs/libtestu01$(LIB_SUFFIX) $(TOP_LIB_DIR)/libtestu01.a

# Compilatieregels
ifeq ($(BUILD_TYPE),release)
$(OBJ_DIR)/mylib_%.o: $(SRC_ROOT)/mylib/%.c | directories
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/probdist_%.o: $(SRC_ROOT)/probdist/%.c | directories
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/testu01_%.o: $(SRC_ROOT)/testu01/%.c | directories
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
else
$(OBJ_DIR)/mylib_%.o: $(SRC_ROOT)/mylib/%.c | directories
	$(CC) $(CPPFLAGS) $(CFLAGS) -S -fverbose-asm $< -o $(ASM_DIR)/mylib_$*.s
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wa,-adhlns=$(LST_DIR)/mylib_$*.lst -c $< -o $@

$(OBJ_DIR)/probdist_%.o: $(SRC_ROOT)/probdist/%.c | directories
	$(CC) $(CPPFLAGS) $(CFLAGS) -S -fverbose-asm $< -o $(ASM_DIR)/probdist_$*.s
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wa,-adhlns=$(LST_DIR)/probdist_$*.lst -c $< -o $@

$(OBJ_DIR)/testu01_%.o: $(SRC_ROOT)/testu01/%.c | directories
	$(CC) $(CPPFLAGS) $(CFLAGS) -S -fverbose-asm $< -o $(ASM_DIR)/testu01_$*.s
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wa,-adhlns=$(LST_DIR)/testu01_$*.lst -c $< -o $@
endif

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(TOP_LIB_DIR)/*
	rm -f $(SRC_ROOT)/*.lst $(SRC_ROOT)/*.s
	rm -f $(SRC_ROOT)/mylib/*.o $(SRC_ROOT)/probdist/*.o $(SRC_ROOT)/testu01/*.o

clean-all:
	rm -rf $(SRC_ROOT)/build
	rm -f $(SRC_ROOT)/*.lst $(SRC_ROOT)/*.s
	rm -f $(SRC_ROOT)/mylib/*.o $(SRC_ROOT)/probdist/*.o $(SRC_ROOT)/testu01/*.o
