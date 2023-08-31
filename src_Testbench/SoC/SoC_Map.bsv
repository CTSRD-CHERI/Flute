// Copyright (c) 2013-2020 Bluespec, Inc. All Rights Reserved

//-
// RVFI_DII + CHERI modifications:
//     Copyright (c) 2018-19 Peter Rugg
// AXI (user fields) modifications:
//     Copyright (c) 2019 Alexandre Joannou
//     Copyright (c) 2019 Peter Rugg
//     Copyright (c) 2019 Jonathan Woodruff
//     All rights reserved.
//
//     This software was developed by SRI International and the University of
//     Cambridge Computer Laboratory (Department of Computer Science and
//     Technology) under DARPA contract HR0011-18-C-0016 ("ECATS"), as part of the
//     DARPA SSITH research programme.
//-

package SoC_Map;

// ================================================================
// This module defines the overall 'address map' of the SoC, showing
// the addresses serviced by each slave IP, and which addresses are
// memory vs. I/O.

// ***** WARNING! WARNING! WARNING! *****

// During system integration, this address map should be identical to
// the system interconnect settings (e.g., routing of requests between
// masters and slaves).  This map is also needed by software so that
// it knows how to address various IPs.

// This module contains no state; it just has constants, and so can be
// freely instantiated at multiple places in the SoC module hierarchy
// at no hardware cost.  It allows this map to be defined in one
// place and shared across the SoC.

// ================================================================
// Exports

export  SoC_Map_IFC (..), mkSoC_Map;

// export  fn_addr_in_range;

export  Num_Masters;
export  imem_master_num;
export  dmem_master_num;
export  hls_master_num;

export  Num_Slaves;
export  Wd_SId;
export  boot_rom_slave_num;
export  mem0_controller_slave_num;
export  uart0_slave_num;
export  hls_slave_num;

export  N_External_Interrupt_Sources;
export  n_external_interrupt_sources;
export  irq_num_uart0;
export  irq_num_hls;

// ================================================================
// Bluespec library imports

import Routable :: *; // For Range

// ================================================================
// Project imports

import Fabric_Defs :: *;    // Only for type Fabric_Addr

`ifdef ISA_CHERI
import CHERICap     :: *;
import CHERICC_Fat  :: *;
`endif

`ifdef RVFI_DII
import RVFI_DII     :: *;
`endif

import ISA_Decls :: *;

// ================================================================
// Interface and module for the address map

interface SoC_Map_IFC;
   (* always_ready *)   method  Range#(Wd_Addr)  m_near_mem_io_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_plic_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_uart0_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_boot_rom_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_hls_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_mem0_controller_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_tcm_addr_range;

   (* always_ready *)
   method  Bool  m_is_mem_addr (Fabric_Addr addr);

   (* always_ready *)
   method  Bool  m_is_IO_addr (Fabric_Addr addr);

   (* always_ready *)
   method  Bool  m_is_near_mem_IO_addr (Fabric_Addr addr);

   (* always_ready *)   method  Bit #(XLEN)  m_pc_reset_value;
   (* always_ready *)   method  Bit #(XLEN)  m_mtvec_reset_value;

   // Non-maskable interrupt vector
   (* always_ready *)   method  Bit #(XLEN)  m_nmivec_reset_value;
`ifdef ISA_CHERI
   (* always_ready *)   method  CapReg  m_pcc_reset_value;
   (* always_ready *)   method  CapReg  m_ddc_reset_value;
   (* always_ready *)   method  CapReg  m_mtcc_reset_value;
   (* always_ready *)   method  CapReg  m_mepcc_reset_value;
`endif
endinterface

// ================================================================

(* synthesize *)
module mkSoC_Map (SoC_Map_IFC);

   // ----------------------------------------------------------------
   // Near_Mem_IO (including CLINT, the core-local interruptor)

   let near_mem_io_addr_range = Range {
      base: 'h_0200_0000,
      size: 'h_0000_C000    // 48K
   };

   // ----------------------------------------------------------------
   // PLIC

   let plic_addr_range = Range {
      base: 'h0C00_0000,
      size: 'h0040_0000     // 4M
   };

   // ----------------------------------------------------------------
   // UART 0

   let uart0_addr_range = Range {
      base: 'hC000_0000,
      size: 'h0000_0080     // 128
   };

   // ----------------------------------------------------------------
   // ACCEL 0

   let hls_addr_range = Range {
      base: 'hC000_2000,
      size: 'h0000_1000
   };

   // ----------------------------------------------------------------
   // Boot ROM

   let boot_rom_addr_range = Range {
      base: 'h_0000_1000,
      size: 'h_0000_1000    // 4K
   };

   // ----------------------------------------------------------------
   // Main Mem Controller 0

   let mem0_controller_addr_range = Range {
      base: 'h_8000_0000,
      size: 'h_4000_0000    // 1 GB
   };

   // ----------------------------------------------------------------
   // Tightly-coupled memory ('TCM'; optional)

`ifdef Near_Mem_TCM
// Integer kB_per_TCM = 'h4;         // 4KB
// Integer kB_per_TCM = 'h40;     // 64KB
// Integer kB_per_TCM = 'h80;     // 128KB
// Integer kB_per_TCM = 'h400;    // 1 MB
   Integer kB_per_TCM = 'h4000;    // 16 MB
`else
   Integer kB_per_TCM = 0;
`endif
   Integer bytes_per_TCM = kB_per_TCM * 'h400;

   let tcm_addr_range = Range {
      base: 'h_0000_0000,
      size: fromInteger (bytes_per_TCM)
   };

`ifdef RVFI_DII
  let rvfi_cached = Range {
      base: 'h_8000_0000,
      size: fromInteger(valueOf(RVFI_DII_Mem_Size))
   };
   function Bool fn_is_mem_addr (Fabric_Addr addr);
       return (inRange(rvfi_cached, addr));
   endfunction
   function Bool fn_is_IO_addr (Fabric_Addr addr);
       return False;
   endfunction
`else
   // ----------------------------------------------------------------
   // Memory address predicate
   // Identifies memory addresses in the Fabric.
   // (Caches need this information to cache these addresses.)

   function Bool fn_is_mem_addr (Fabric_Addr addr);
       return (  inRange(boot_rom_addr_range, addr)
	      || inRange(mem0_controller_addr_range, addr)
	      || inRange(tcm_addr_range, addr)
	      );
   endfunction

   // ----------------------------------------------------------------
   // I/O address predicate
   // Identifies I/O addresses in the Fabric.
   // (Caches need this information to avoid cacheing these addresses.)

   function Bool fn_is_IO_addr (Fabric_Addr addr);
      return (   inRange(near_mem_io_addr_range, addr)
              || inRange(plic_addr_range, addr)
              || inRange(uart0_addr_range, addr)
              || inRange(hls_addr_range, addr));
   endfunction
`endif
   // ----------------------------------------------------------------
   // PC, MTVEC and NMIVEC reset values

`ifdef RVFI_DII
   Bit #(XLEN) pc_reset_value     = 'h8000_0000;
   Bit #(XLEN) mtvec_reset_value  = 'h0000;
`else
   Bit #(XLEN) pc_reset_value     = rangeBase(boot_rom_addr_range);
   Bit #(XLEN) mtvec_reset_value  = 'h1000;    // TODO
`endif
   // Non-maskable interrupt vector
   Bit #(XLEN) nmivec_reset_value = ?;         // TODO

`ifdef ISA_CHERI
   CapPipe almightyPipe = almightyCap;
   CapReg pcc_reset_value  = cast(setOffset(almightyPipe, pc_reset_value).value);
   CapReg ddc_reset_value = almightyCap;
   CapReg mtcc_reset_value = cast(setOffset(almightyPipe, mtvec_reset_value).value);
   CapReg mepcc_reset_value = almightyCap;
`endif

   // ================================================================
   // INTERFACE

   method  Range#(Wd_Addr)  m_near_mem_io_addr_range = near_mem_io_addr_range;
   method  Range#(Wd_Addr)  m_plic_addr_range = plic_addr_range;
   method  Range#(Wd_Addr)  m_uart0_addr_range = uart0_addr_range;
   method  Range#(Wd_Addr)  m_boot_rom_addr_range = boot_rom_addr_range;
   method  Range#(Wd_Addr)  m_hls_addr_range = hls_addr_range;

   method  Range#(Wd_Addr)  m_mem0_controller_addr_range = mem0_controller_addr_range;

   method  Range#(Wd_Addr)  m_tcm_addr_range = tcm_addr_range;

   method  Bool  m_is_mem_addr (Fabric_Addr addr) = fn_is_mem_addr (addr);

   method  Bool  m_is_IO_addr (Fabric_Addr addr) = fn_is_IO_addr (addr);

   method  Bool  m_is_near_mem_IO_addr (Fabric_Addr addr) = inRange (near_mem_io_addr_range, addr);

   method  Bit #(XLEN)  m_pc_reset_value     = pc_reset_value;
   method  Bit #(XLEN)  m_mtvec_reset_value  = mtvec_reset_value;

   // Non-maskable interrupt vector
   method  Bit #(XLEN)  m_nmivec_reset_value = nmivec_reset_value;

`ifdef ISA_CHERI
   method  CapReg  m_pcc_reset_value   = pcc_reset_value;
   method  CapReg  m_ddc_reset_value   = ddc_reset_value;
   method  CapReg  m_mtcc_reset_value  = mtcc_reset_value;
   method  CapReg  m_mepcc_reset_value = mepcc_reset_value;
`endif
endmodule

// ================================================================
// Count and master-numbers of masters in the fabric.

Integer imem_master_num   = 0;
Integer dmem_master_num   = 1;
Integer hls_master_num = 2;

typedef 3 Num_Masters;

// ================================================================
// Count and slave-numbers of slaves in the fabric.

typedef 4 Num_Slaves;


Integer boot_rom_slave_num        = 0;
Integer mem0_controller_slave_num = 1;
Integer uart0_slave_num           = 2;
Integer hls_slave_num             = 3;

// ================================================================
// Width of fabric 'id' buses
typedef TAdd#(Wd_MId_ext, TLog#(Num_Masters)) Wd_SId;

// ================================================================
// Interrupt request numbers (== index in to vector of
// interrupt-request lines in Core)

typedef  16  N_External_Interrupt_Sources;
Integer  n_external_interrupt_sources = valueOf (N_External_Interrupt_Sources);

Integer irq_num_uart0  = 0;
Integer irq_num_hls = 1;

// ================================================================

endpackage
