// Copyright (c) 2013-2020 Bluespec, Inc. All Rights Reserved

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
export  irq_num_uart;
export  irq_num_key;
export  irq_num_timer;

// ================================================================
// Bluespec library imports

// None

// ================================================================
// Project imports

import Fabric_Defs :: *;    // Only for type Fabric_Addr

// ================================================================
// Interface and module for the address map

interface SoC_Map_IFC;
   (* always_ready *)   method  Fabric_Addr  m_plic_addr_base;
   (* always_ready *)   method  Fabric_Addr  m_plic_addr_size;
   (* always_ready *)   method  Fabric_Addr  m_plic_addr_lim;

   (* always_ready *)   method  Fabric_Addr  m_near_mem_io_addr_base;
   (* always_ready *)   method  Fabric_Addr  m_near_mem_io_addr_size;
   (* always_ready *)   method  Fabric_Addr  m_near_mem_io_addr_lim;

   (* always_ready *)   method  Fabric_Addr  m_periph_addr_base;
   (* always_ready *)   method  Fabric_Addr  m_periph_addr_size;
   (* always_ready *)   method  Fabric_Addr  m_periph_addr_lim;

   (* always_ready *)   method  Fabric_Addr  m_sdram_addr_base;
   (* always_ready *)   method  Fabric_Addr  m_sdram_addr_size;
   (* always_ready *)   method  Fabric_Addr  m_sdram_addr_lim;

   (* always_ready *)
   method  Bool  m_is_mem_addr (Fabric_Addr addr);

   (* always_ready *)
   method  Bool  m_is_IO_addr (Fabric_Addr addr);

   (* always_ready *)
   method  Bool  m_is_near_mem_IO_addr (Fabric_Addr addr);

   (* always_ready *)   method  Bit #(64)  m_pc_reset_value;
   (* always_ready *)   method  Bit #(64)  m_mtvec_reset_value;
   (* always_ready *)   method  Bit #(64)  m_nmivec_reset_value;
endinterface

// ================================================================

(* synthesize *)
module mkSoC_Map (SoC_Map_IFC);

   // ----------------------------------------------------------------
   // PLIC

   Fabric_Addr plic_addr_base = 'h_0C00_0000;
   Fabric_Addr plic_addr_size = 'h_0040_0000;    // 4M
   Fabric_Addr plic_addr_lim  = plic_addr_base + plic_addr_size;

   function Bool fn_is_plic_addr (Fabric_Addr addr);
      return ((plic_addr_base <= addr) && (addr < plic_addr_lim));
   endfunction

   // ----------------------------------------------------------------
   // Near_Mem_IO (CLINT)

   Fabric_Addr near_mem_io_addr_base = 'h_1000_0000;
   Fabric_Addr near_mem_io_addr_size = 'h_0001_0000;    // 64K
   Fabric_Addr near_mem_io_addr_lim  = near_mem_io_addr_base + near_mem_io_addr_size;

   function Bool fn_is_near_mem_io_addr (Fabric_Addr addr);
      return ((near_mem_io_addr_base <= addr) && (addr < near_mem_io_addr_lim));
   endfunction

   // ----------------------------------------------------------------
   // Various peripherals

   Fabric_Addr periph_addr_base = 'h_0402_0000;
   Fabric_Addr periph_addr_size = 'h_0004_0000;
   Fabric_Addr periph_addr_lim  = periph_addr_base + periph_addr_size;

   function Bool fn_is_periph_addr (Fabric_Addr addr);
      return ((periph_addr_base <= addr) && (addr < periph_addr_lim));
   endfunction

   // ----------------------------------------------------------------
   // SDRAM cached

   Fabric_Addr sdram_addr_base = 'h_0000_0000;
   Fabric_Addr sdram_addr_size = 'h_0400_0000;    // 64M
   Fabric_Addr sdram_addr_lim  = sdram_addr_base + sdram_addr_size;

   function Bool fn_is_sdram_addr (Fabric_Addr addr);
      return ((sdram_addr_base <= addr) && (addr < sdram_addr_lim));
   endfunction

   // ----------------------------------------------------------------
   // Memory address predicate
   // Identifies memory addresses in the Fabric.
   // (Caches needs this information to cache these addresses.)

   function Bool fn_is_mem_addr (Fabric_Addr addr);
      return (   fn_is_sdram_addr (addr)
	      );
   endfunction

   // ----------------------------------------------------------------
   // I/O address predicate
   // Identifies I/O addresses in the Fabric.
   // (Caches needs this information to avoid cacheing these addresses.)

   function Bool fn_is_IO_addr (Fabric_Addr addr);
      return (   fn_is_plic_addr (addr)
	      || fn_is_near_mem_io_addr (addr)
              || fn_is_periph_addr (addr)
	      );
   endfunction

   // ----------------------------------------------------------------
   // PC, MTVEC and NMIVEC reset values

   Bit #(64) pc_reset_value     = periph_addr_base;
   Bit #(64) mtvec_reset_value  = periph_addr_base;
   Bit #(64) nmivec_reset_value = periph_addr_base;

   // ================================================================
   // INTERFACE

   method  Fabric_Addr  m_plic_addr_base = plic_addr_base;
   method  Fabric_Addr  m_plic_addr_size = plic_addr_size;
   method  Fabric_Addr  m_plic_addr_lim  = plic_addr_lim;

   method  Fabric_Addr  m_near_mem_io_addr_base = near_mem_io_addr_base;
   method  Fabric_Addr  m_near_mem_io_addr_size = near_mem_io_addr_size;
   method  Fabric_Addr  m_near_mem_io_addr_lim  = near_mem_io_addr_lim;

   method  Fabric_Addr  m_periph_addr_base = periph_addr_base;
   method  Fabric_Addr  m_periph_addr_size = periph_addr_size;
   method  Fabric_Addr  m_periph_addr_lim  = periph_addr_lim;

   method  Fabric_Addr  m_sdram_addr_base = sdram_addr_base;
   method  Fabric_Addr  m_sdram_addr_size = sdram_addr_size;
   method  Fabric_Addr  m_sdram_addr_lim  = sdram_addr_lim;

   method  Bool  m_is_mem_addr (Fabric_Addr addr) = fn_is_mem_addr (addr);

   method  Bool  m_is_IO_addr (Fabric_Addr addr) = fn_is_IO_addr (addr);

   method  Bool  m_is_near_mem_IO_addr (Fabric_Addr addr) = fn_is_near_mem_io_addr (addr);

   method  Bit #(64)  m_pc_reset_value     = pc_reset_value;
   method  Bit #(64)  m_mtvec_reset_value  = mtvec_reset_value;
   method  Bit #(64)  m_nmivec_reset_value = nmivec_reset_value;
endmodule

// ================================================================
// Interrupt request numbers (== index in to vector of
// interrupt-request lines in Core)

typedef  16  N_External_Interrupt_Sources;
Integer  n_external_interrupt_sources = valueOf (N_External_Interrupt_Sources);

Integer irq_num_uart = 1;
Integer irq_num_key = 0;
Integer irq_num_timer = 2;

// ================================================================

endpackage
