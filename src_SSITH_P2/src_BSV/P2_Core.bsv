// Copyright (c) 2018-2020 Bluespec, Inc. All Rights Reserved.

package P2_Core;

// ================================================================
// This package defines the interface and implementation of the 'P2 Core'
// for the DARPA SSITH project.
// This P2 core contains:
//    - Flute CPU, including
//        - Near_Mem (ICache and DCache)
//        - Near_Mem_IO (Timer, Software-interrupt, and other mem-mapped-locations)
//        - External interrupt request lines
//        - 2 x AXI4 Master interfaces (from DM and ICache, and from DCache)
//    - RISC-V Debug Module (DM)
//    - JTAG TAP interface for DM
//    - Optional Tandem Verification trace stream output interface

// ================================================================
// BSV library imports

import Vector        :: *;
import FIFO          :: *;
import GetPut        :: *;
import ClientServer  :: *;
import Connectable   :: *;
import Bus           :: *;

// ----------------
// BSV additional libs

import GetPut_Aux :: *;
import Semi_FIFOF :: *;

// ================================================================
// Project imports

import SoC_Map  :: *;

// The basic core
import Core_IFC :: *;
import Core     :: *;
import Near_Mem_IFC :: *;    // For Wd_{Id,Addr,Data,User}_Dma

// External interrupt request interface
import PLIC :: *;    // for PLIC_Source_IFC type which is exposed at P2_Core interface

// Main Fabric
import AXI4_Types   :: *;
import AXI4_Fabric  :: *;
import Fabric_Defs  :: *;

`ifdef INCLUDE_DMEM_SLAVE
import AXI4_Lite_Types :: *;
`endif

// ================================================================
// The P2_Core interface

interface P2_Core_IFC;

   // ----------------------------------------------------------------
   // Core CPU interfaces

   // CPU IMem to Fabric master interface
   interface AXI4_Master_IFC #(Wd_Id, Wd_Addr, Wd_Data, Wd_User) master0;

   // CPU DMem (incl. I/O) to Fabric master interface
   interface AXI4_Master_IFC #(Wd_Id, Wd_Addr, Wd_Data, Wd_User) master1;

   // External interrupt sources
   (* always_ready, always_enabled, prefix="" *)
   method  Action interrupt_reqs ((* port="cpu_external_interrupt_req" *) Bit #(N_External_Interrupt_Sources)  reqs);
endinterface

// ================================================================

(* synthesize *)
module mkP2_Core (P2_Core_IFC);

   // Core: CPU + Near_Mem_IO (CLINT) + PLIC + Debug module (optional) + TV (optional)
   Core_IFC::Core_IFC #(N_External_Interrupt_Sources)  core <- mkCore;

   // ================================================================
   // Tie-offs (not used in SSITH GFE)

   // Tie-offs
   rule rl_always (True);
      // Non-maskable interrupt request.
      core.nmi_req (False);
   endrule

   AXI4_Master_IFC #(Wd_Id_Dma, Wd_Addr_Dma, Wd_Data_Dma, Wd_User_Dma)
   dummy = dummy_AXI4_Master_ifc;
   mkConnection (dummy, core.dma_server);

   // ================================================================
   // Reset on startup, and also on NDM reset from Debug Module
   // (NDM reset from Debug Module = "non-debug-module-reset" = reset all except Debug Module)

   Reg #(Bool)          rg_once      <- mkReg (False);
   Reg #(Maybe #(Bool)) rg_ndm_reset <- mkReg (tagged Invalid);

   rule rl_once (! rg_once);
      Bool running = True;
      if (rg_ndm_reset matches tagged Valid False)
	 running = False;
      core.cpu_reset_server.request.put (running);
      core.ma_ddr4_ready;
      rg_once <= True;
   endrule

   rule rl_reset_response;
      let running <- core.cpu_reset_server.response.get;

   endrule

   // ----------------
   // Also do a reset if requested from Debug Module (NDM = Non-Debug-Module reset)

   rule rl_ndmreset (rg_once);
      rg_once <= False;
   endrule

   // ================================================================
   // INTERFACE

   // CPU IMem to Fabric master interface
   interface AXI4_Master_IFC master0 = core.cpu_imem_master;

   // CPU DMem to Fabric master interface
   interface AXI4_Master_IFC master1 = core.core_mem_master;

   // External interrupts
   method  Action interrupt_reqs (Bit #(N_External_Interrupt_Sources) reqs);
      for (Integer j = 0; j < valueOf (N_External_Interrupt_Sources); j = j + 1) begin
	 Bool req_j = unpack (reqs [j]);
	 core.core_external_interrupt_sources [j].m_interrupt_req (req_j);
      end
   endmethod
endmodule

// ================================================================

endpackage
