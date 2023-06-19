// Copyright (c) 2013-2020 Bluespec, Inc. All Rights Reserved

//-
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
// This version of SoC_Map is for the DARPA SSITH GFE

// Our "Near_Mem_IO" corresponds to "CLINT" in Rocket

// ================================================================
// Exports

export  SoC_Map_IFC (..), mkSoC_Map;

export  N_External_Interrupt_Sources;
export  n_external_interrupt_sources;

// ================================================================
// Bluespec library imports

import Routable :: *;

// ================================================================
// Project imports

import Fabric_Defs :: *;    // Only for type Fabric_Addr

`ifdef ISA_CHERI
import CHERICap     :: *;
import CHERICC_Fat  :: *;
`endif

import ISA_Decls :: *;

// ================================================================
// Interface and module for the address map

interface SoC_Map_IFC;
   (* always_ready *)   method  Range#(Wd_Addr)  m_plic_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_near_mem_io_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_periph_addr_range;
   (* always_ready *)   method  Range#(Wd_Addr)  m_sdram_addr_range;

   (* always_ready *)
   method  Bool  m_is_mem_addr (Fabric_Addr addr);

   (* always_ready *)
   method  Bool  m_is_IO_addr (Fabric_Addr addr);

   (* always_ready *)
   method  Bool  m_is_near_mem_IO_addr (Fabric_Addr addr);

   (* always_ready *)   method  Bit #(XLEN)  m_pc_reset_value;
`ifdef ISA_CHERI
   (* always_ready *)   method  CapReg  m_pcc_reset_value;
   (* always_ready *)   method  CapReg  m_ddc_reset_value;
   (* always_ready *)   method  CapReg  m_mtcc_reset_value;
   (* always_ready *)   method  CapReg  m_mepcc_reset_value;
`endif
   (* always_ready *)   method  Bit #(XLEN)  m_mtvec_reset_value;
   (* always_ready *)   method  Bit #(XLEN)  m_nmivec_reset_value;
endinterface

// ================================================================

(* synthesize *)
module mkSoC_Map (SoC_Map_IFC);

   // ----------------------------------------------------------------
   // PLIC

   let plic_addr_range = Range {
      base: 'h_0C00_0000,
      size: 'h_0040_0000    // 4M
   };

   // ----------------------------------------------------------------
   // Near_Mem_IO (CLINT)

   let near_mem_io_addr_range = Range {
      base: 'h_1000_0000,
      size: 'h_0001_0000    // 64K
   };

   // ----------------------------------------------------------------
   // Various memory mapped peripherals

   let periph_addr_range = Range {
      base: 'h_0402_0000,
      size: 'h_0004_0000
   };

   // ----------------------------------------------------------------
   // cached sdram

   let sdram_addr_range = Range {
      base: 'h_0000_0000,
      size: 'h_0400_0000
   };

   // ----------------------------------------------------------------
   // Memory address predicate
   // Identifies memory addresses in the Fabric.
   // (Caches needs this information to cache these addresses.)

   function Bool fn_is_mem_addr (Fabric_Addr addr);
      return inRange (sdram_addr_range, addr);
   endfunction

   // ----------------------------------------------------------------
   // I/O address predicate
   // Identifies I/O addresses in the Fabric.
   // (Caches needs this information to avoid cacheing these addresses.)

   function Bool fn_is_IO_addr (Fabric_Addr addr);
      return (   inRange (plic_addr_range, addr)
	      || inRange (near_mem_io_addr_range, addr)
	      || inRange (periph_addr_range, addr)
	      );
   endfunction

   // ----------------------------------------------------------------
   // PC, MTVEC and NMIVEC reset values

   Bit #(XLEN) pc_reset_value     = rangeBase(periph_addr_range);
   Bit #(XLEN) mtvec_reset_value  = pc_reset_value;    // TODO
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

   method  Range#(Wd_Addr)  m_plic_addr_range = plic_addr_range;
   method  Range#(Wd_Addr)  m_near_mem_io_addr_range = near_mem_io_addr_range;

   /* REMOVED?
   method  Fabric_Addr  m_pcie_ecam_slave_bridge_addr_base = pcie_ecam_slave_bridge_addr_base;
   method  Fabric_Addr  m_pcie_ecam_slave_bridge_addr_size = pcie_ecam_slave_bridge_addr_size;
   method  Fabric_Addr  m_pcie_ecam_slave_bridge_addr_lim  = pcie_ecam_slave_bridge_addr_lim;
   */

   /* REMOVED?
   method  Fabric_Addr  m_pcie_block_registers_addr_base = pcie_block_registers_addr_base;
   method  Fabric_Addr  m_pcie_block_registers_addr_size = pcie_block_registers_addr_size;
   method  Fabric_Addr  m_pcie_block_registers_addr_lim  = pcie_block_registers_addr_lim;
   */

   method  Range#(Wd_Addr)  m_periph_addr_range = periph_addr_range;
   method  Range#(Wd_Addr)  m_sdram_addr_range = sdram_addr_range;

   method  Bool  m_is_mem_addr (Fabric_Addr addr) = fn_is_mem_addr (addr);

   method  Bool  m_is_IO_addr (Fabric_Addr addr) = fn_is_IO_addr (addr);

   method  Bool  m_is_near_mem_IO_addr (Fabric_Addr addr) = inRange(near_mem_io_addr_range, addr);

   method  Bit #(XLEN)  m_pc_reset_value     = pc_reset_value;
   method  Bit #(XLEN)  m_mtvec_reset_value  = mtvec_reset_value;
   method  Bit #(XLEN)  m_nmivec_reset_value = nmivec_reset_value;

`ifdef ISA_CHERI
   method  CapReg  m_pcc_reset_value   = pcc_reset_value;
   method  CapReg  m_ddc_reset_value   = ddc_reset_value;
   method  CapReg  m_mtcc_reset_value  = mtcc_reset_value;
   method  CapReg  m_mepcc_reset_value = mepcc_reset_value;
`endif
endmodule

// ================================================================
// Interrupt request numbers (== index in to vector of
// interrupt-request lines in Core)

typedef  16  N_External_Interrupt_Sources;
Integer  n_external_interrupt_sources = valueOf (N_External_Interrupt_Sources);

// ================================================================

endpackage
