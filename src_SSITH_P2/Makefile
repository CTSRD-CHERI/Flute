###  -*-Makefile-*-

# ================================================================

.PHONY: help
help:
	@echo '    make  compile      Recompile Core (CPU, caches) into Verilog_RTL'
	@echo '                           NOTE: needs Bluespec bsc compiler'
	@echo '    make  tagsparams   Generates the CHERI tag controller parameters source file'
	@echo ''
	@echo '    make  clean        Remove intermediate build-files'
	@echo '    make  full_clean   Restore this directory to pristine state'

.PHONY: all
all: compile

# ================================================================

REPO ?= ..
ARCH ?= RV64ACDFIMSUxCHERI

# ================================================================
# CORE implementation options
#   Use 'Core_v2' with WB_L1_L2 cache, otherwise use 'Core'
#   XXX no cherification work has happened in Core_v2 XXX

SRC_CORE ?= $(REPO)/src_Core/Core
#SRC_CORE ?= $(REPO)/src_Core/Core_v2

# ================================================================
# RISC-V config macros passed into Bluespec 'bsc' compiler

BSC_COMPILATION_FLAGS += \
	-D RV64 \
	-D ISA_PRIV_M  -D ISA_PRIV_U  -D ISA_PRIV_S  \
	-D SV39 \
	-D RISCV \
	-D CapWidth=128 -D CheriBusBytes=8 -D SMALL_TAG_CACHE \
	-D CheriMasterIDWidth=1 -D CheriTransactionIDWidth=5 \
	-D ISA_CHERI \
	-D PERFORMANCE_MONITORING \
	-D ISA_PRIV_M  -D ISA_PRIV_S  -D ISA_PRIV_U  \
	-D ISA_I  -D ISA_M  -D ISA_A  -D ISA_C  \
	-D ISA_F -D ISA_D -D INCLUDE_FDIV  -D INCLUDE_FSQRT \
	-D SHIFT_BARREL    \
	-D MULT_SYNTH     \
	-D Near_Mem_Caches    \
	-D FABRIC64    \
	-D INCLUDE_GDB_CONTROL \
	-D BRVF_TRACE \
	-D XILINX_BSCAN  -D XILINX_XCVU9P  -D JTAG_TAP

ifdef N_HLS
BSC_COMPILATION_FLAGS += -D N_HLS=$(N_HLS)
endif

ifdef HLS_CAP_CHECKER
BSC_COMPILATION_FLAGS += -D HLS_CAP_CHECKER
endif

# CHERI paramters
CAPSIZE = 128
TAGS_STRUCT = 0 64
TAGS_ALIGN = 32
#================================================================
# For LLCache

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

CUSTOM_DIRS = $(LLCACHE_DIR):$(PROCS_LIB_DIR):$(PROCS_OOO_DIR):$(COHERENCE_DIR)

# ================================================================
# bsc compilation flags

BSC_COMPILATION_FLAGS += \
	-keep-fires -aggressive-conditions -no-warn-action-shadowing -no-show-timestamps -check-assert \
	-suppress-warnings G0020    \
	+RTS -K128M -RTS  -show-range-conflict

# ================================================================
# Search path for bsc for .bsv files

# ================================================================
# Near-mem (Cache and optional MMU for VM)
# WT = Write-through; WB = write-back
# L1 = L1 only; L1_L2 = L1 + coherent L2

CACHES ?= WT_L1

ifeq ($(CACHES),WB_L1)
  NEAR_MEM_VM_DIR=Near_Mem_VM_WB_L1
else ifeq ($(CACHES),WB_L1_L2)
  NEAR_MEM_VM_DIR=Near_Mem_VM_WB_L1_L2
else
  NEAR_MEM_VM_DIR=Near_Mem_VM_WT_L1
endif

SRC_CORE ?= $(REPO)/src_Core/Core

CONTRIB_DIRS = %/Libraries/Bus
CORE_DIRS = $(REPO)/src_Core/CPU:$(REPO)/src_Core/ISA:$(REPO)/src_Core/RegFiles:$(SRC_CORE):$(REPO)/src_Core/Cache_Config:$(REPO)/src_Core/$(NEAR_MEM_VM_DIR):$(REPO)/src_Core/PLIC:$(REPO)/src_Core/Near_Mem_IO:$(REPO)/src_Core/Debug_Module:$(REPO)/src_Core/BSV_Additional_Libs

CHERI_DIRS = $(REPO)/libs/cheri-cap-lib:$(REPO)/libs/TagController/TagController:$(REPO)/libs/TagController/TagController/CacheCore:$(REPO)/libs/BlueStuff/BlueUtils

BLUESTUFFDIR = $(REPO)/libs/BlueStuff
include $(REPO)/libs/BlueStuff/bluestuff.inc.mk

BSC_PATH = $(CONTRIB_DIRS):$(CUSTOM_DIRS):src_BSV:$(CORE_DIRS):$(TESTBENCH_DIRS):$(BLUESTUFF_DIRS):$(RVFI_DII_DIRS):$(CHERI_DIRS):+

RISCV_HPM_Events_DIR = $(REPO)/libs/RISCV_HPM_Events

# ----------------
# Top-level file and module

TOPFILE   = src_BSV/P2_Core.bsv
TOPMODULE = mkP2_Core

# ================================================================
# bsc compilation flags

BSC_COMPILATION_FLAGS += \
	-keep-fires -aggressive-conditions -no-warn-action-shadowing -no-show-timestamps \
	-suppress-warnings G0020    \
	+RTS -K128M -RTS  -show-range-conflict \
        -unspecified-to X -opt-undetermined-vals

# ================================================================
# Generate Bluespec CHERI tag controller source file

.PHONY: tagsparams
tagsparams: src_BSV/TagTableStructure.bsv
src_BSV/TagTableStructure.bsv: $(REPO)/libs/TagController/tagsparams.py
	@echo "INFO: Re-generating CHERI tag controller parameters"
	$^ -v -c $(CAPSIZE) -s $(TAGS_STRUCT:"%"=%) -a $(TAGS_ALIGN) --data-store-base-addr 0xc0000000  -b $@ 0x3fffc000 0xfffff000
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

# ================================================================
# Generate Verilog RTL from BSV sources (needs Bluespec 'bsc' compiler)

RTL_GEN_DIRS = -vdir Verilog_RTL  -bdir build_dir  -info-dir build_dir

build_dir:
	mkdir -p $@

Verilog_RTL:
	mkdir -p $@

.PHONY: compile
compile:  build_dir tagsparams stat_counters generate_hpm_vector Verilog_RTL
	@echo  "INFO: Generating RTL into Verilog_RTL ..."
	bsc -u -elab -verilog  $(RTL_GEN_DIRS)  $(BSC_COMPILATION_FLAGS)  -p $(BSC_PATH)  $(TOPFILE)
	@echo  "INFO: Generated RTL into Verilog_RTL"

# ================================================================

.PHONY: clean
clean:
	rm -r -f  *~  Makefile_*  build_dir
	rm -f src_BSV/TagTableStructure.bsv

.PHONY: full_clean
full_clean: clean
	rm -r -f  *.log  Verilog_RTL

# ================================================================
