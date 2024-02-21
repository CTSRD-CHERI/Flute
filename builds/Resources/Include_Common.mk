###  -*-Makefile-*-

# Copyright (c) 2018-2019 Bluespec, Inc. All Rights Reserved

# This file is not a standalone Makefile, but 'include'd by other Makefiles

# It contains common defs used by Makefiles generated for specific
# RISC-V implementations that differ in RISC-V architectural-feature
# choices, hardware implementation choices and simulator choices.

# ================================================================

.PHONY: help
help:
	@echo '    make  compile      Recompile Core (CPU, caches)'
	@echo '                           NOTE: needs Bluespec bsc compiler'
	@echo '                           For Bluesim: generates Bluesim intermediate files'
	@echo '                           For Verilog simulation: generates RTL'
	@echo '    make  simulator    Compiles and links intermediate files/RTL to create simulation executable'
	@echo '                           (Bluesim, verilator or iverilog)'
	@echo '    make  tagsparams   Generates the CHERI tag controller parameters source file'
	@echo '    make  all          = make  compile  simulator'
	@echo ''
	@echo '    make  run_example  Runs simulation executable on ELF given by EXAMPLE'
	@echo ''
	@echo '    make  test         Runs simulation executable on rv32ui-p-add or rv64ui-p-add'
	@echo '    make  isa_tests    Runs simulation executable on all relevant standard RISC-V ISA tests'
	@echo ''
	@echo '    make  clean        Remove intermediate build-files unnecessary for execution'
	@echo '    make  full_clean   Restore to pristine state (pre-building anything)'

.PHONY: all
all: compile  simulator

# ================================================================
# Near-mem (Cache and optional MMU for VM)
# WT = Write-through; WB = write-back
# L1 = L1 only; L1_L2 = L1 + coherent L2
# TCM = No caches, only TCM

CACHES ?= WT_L1
#CACHES ?= WB_L1_L2

ifeq ($(CACHES),WB_L1)
  NEAR_MEM_VM_DIR=Near_Mem_VM_WB_L1
else ifeq ($(CACHES),TCM)
  NEAR_MEM_VM_DIR=Near_Mem_TCM
else ifeq ($(CACHES),WB_L1_L2)
  NEAR_MEM_VM_DIR=Near_Mem_VM_WB_L1_L2
  # core size
  CORE_SIZE ?= SMALL
  # default 1 core
  CORE_NUM ?= 1
  # cache size
  CACHE_SIZE ?= LARGE

  BSC_COMPILATION_FLAGS += \
  	-D CORE_$(CORE_SIZE) \
  	-D NUM_CORES=$(CORE_NUM) \
  	-D CACHE_$(CACHE_SIZE) \

  LLCACHE_DIR   = $(REPO)/src_Core/Near_Mem_VM_WB_L1_L2/src_LLCache
  PROCS_LIB_DIR = $(LLCACHE_DIR)/procs/lib
  PROCS_OOO_DIR = $(LLCACHE_DIR)/procs/RV64G_OOO
  COHERENCE_DIR = $(LLCACHE_DIR)/coherence/src

  LLCACHE_DIRS = $(LLCACHE_DIR):$(PROCS_LIB_DIR):$(PROCS_OOO_DIR):$(COHERENCE_DIR)
else
  NEAR_MEM_VM_DIR=Near_Mem_VM_WT_L1
endif

# ================================================================
# CORE

SRC_CORE ?= $(REPO)/src_Core/Core
# SRC_CORE ?= $(REPO)/src_Core/Core_v2

# ================================================================
# Search path for bsc for .bsv files

CORE_DIRS = $(REPO)/src_Core/CPU:$(REPO)/src_Core/ISA:$(REPO)/src_Core/RegFiles:$(REPO)/src_Core/Core:$(REPO)/src_Core/Cache_Config:$(REPO)/src_Core/$(NEAR_MEM_VM_DIR):$(LLCACHE_DIRS):$(REPO)/src_Core/PLIC:$(REPO)/src_Core/Near_Mem_IO:$(REPO)/src_Core/Debug_Module:$(REPO)/src_Core/BSV_Additional_Libs

TESTBENCH_DIRS = $(REPO)/src_Testbench/Top:$(REPO)/src_Testbench/SoC

RVFI_DII_DIRS = $(REPO)/src_Verifier:$(REPO)/src_Verifier/BSV-RVFI-DII

RISCV_HPM_Events_DIR = $(REPO)/libs/RISCV_HPM_Events

CHERI_DIRS = $(REPO)/libs/cheri-cap-lib:$(REPO)/libs/TagController/TagController:$(REPO)/libs/TagController/TagController/CacheCore:$(REPO)/libs/BlueStuff/BlueUtils

BLUESTUFFDIR = $(REPO)/libs/BlueStuff
include $(REPO)/libs/BlueStuff/bluestuff.inc.mk

BSC_PATH = $(CUSTOM_DIRS):$(CORE_DIRS):$(TESTBENCH_DIRS):$(BLUESTUFF_DIRS):$(RVFI_DII_DIRS):$(CHERI_DIRS):+

# ----------------
# Top-level file and module

TOPFILE   ?= $(REPO)/src_Testbench/Top/Top_HW_Side.bsv
TOPMODULE ?= mkTop_HW_Side

# ================================================================
# bsc compilation flags

BSC_COMPILATION_FLAGS += \
	-D CheriBusBytes=8 -D SMALL_TAG_CACHE \
	-D CheriMasterIDWidth=1 -D CheriTransactionIDWidth=5 \
	-D RISCV -D BLUESIM \
	-keep-fires -aggressive-conditions -no-warn-action-shadowing -no-show-timestamps -check-assert \
	-suppress-warnings G0020    \
	+RTS -K128M -RTS  -show-range-conflict

ifdef N_HLS
BSC_COMPILATION_FLAGS += -D N_HLS=$(N_HLS)
endif

ifdef HLS_CAP_CHECKER
BSC_COMPILATION_FLAGS += -D HLS_CAP_CHECKER
endif

ifdef CAPCHECKER_UNFORGIVING
BSC_COMPILATION_FLAGS += -D CAPCHECKER_UNFORGIVING
endif

# ================================================================
# Runs simulation executable on ELF given by EXAMPLE

EXAMPLE ?= PLEASE_DEFINE_EXAMPLE_PATH_TO_ELF

.PHONY: run_example
run_example:
	make -C  $(TESTS_DIR)/elf_to_hex
	$(TESTS_DIR)/elf_to_hex/elf_to_hex  $(EXAMPLE)  Mem.hex
	./exe_HW_sim  $(VERBOSITY)  +exit

# ================================================================
# Test: run the executable on the standard RISCV ISA test specified in TEST

TESTS_DIR ?= $(REPO)/Tests

VERBOSITY ?= +v1

.PHONY: test
test:
	make -C  $(TESTS_DIR)/elf_to_hex
	$(TESTS_DIR)/elf_to_hex/elf_to_hex  $(TESTS_DIR)/isa/$(TEST)  Mem.hex
	./exe_HW_sim  $(VERBOSITY)  +tohost

# ================================================================
# ISA Regression testing

.PHONY: isa_tests
isa_tests:
	make -C  $(TESTS_DIR)/elf_to_hex
	@echo "Running regressions on ISA tests; saving logs in Logs/"
	$(REPO)/Tests/Run_regression.py  ./exe_HW_sim  $(REPO)  ./Logs  $(ARCH)
	@echo "Finished running regressions; saved logs in Logs/"

# ================================================================
# Generate Bluespec CHERI tag controller source file

.PHONY: tagsparams
tagsparams: TagTableStructure.bsv
TagTableStructure.bsv: $(REPO)/libs/TagController/tagsparams.py
	@echo "INFO: Re-generating CHERI tag controller parameters"
	$^ -v -c $(CAPSIZE) -s $(TAGS_STRUCT:"%"=%) -a $(TAGS_ALIGN) --data-store-base-addr 0x80000000 -b $@ 0x3fffc000 0xbffff000
	@echo "INFO: Re-generated CHERI tag controller parameters"


.PHONY: generate_hpm_vector
generate_hpm_vector: GenerateHPMVector.bsv
GenerateHPMVector.bsv: $(RISCV_HPM_Events_DIR)/parse_counters.py
	@echo "INFO: Re-generating GenerateHPMVector bluespec file"
	$^ $(RISCV_HPM_Events_DIR)/counters.yaml -m ISA_Decls -b $@
	@echo "INFO: Re-generated GenerateHPMVector bluespec file"


.PHONY: stat_counters
stat_counters: StatCounters.bsv
StatCounters.bsv: $(RISCV_HPM_Events_DIR)/parse_counters.py
	@echo "INFO: Re-generating HPM events struct bluepsec file"
	$^ $(RISCV_HPM_Events_DIR)/counters.yaml -m ISA_Decls -s $@
	@echo "INFO: Re-generated HPM events struct bluespec file"


compile: tagsparams stat_counters generate_hpm_vector

# ================================================================

.PHONY: clean
clean:
	rm -r -f  *~  Makefile_*  symbol_table.txt  build_dir  obj_dir
	rm -f TagTableStructure.bsv StatCounters.bsv GenerateHPMVector.bsv

.PHONY: full_clean
full_clean: clean
	rm -r -f  $(SIM_EXE_FILE)*  *.log  *.vcd  *.hex  Logs/  worker_*

# ================================================================
