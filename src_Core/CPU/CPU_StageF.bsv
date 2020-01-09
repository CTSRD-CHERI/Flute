// Copyright (c) 2016-2019 Bluespec, Inc. All Rights Reserved

package CPU_StageF;

// ================================================================
// This is Stage F ("fetch") of the "Flute_V3" CPU.

// ================================================================
// Exports

export
CPU_StageF_IFC (..),
mkCPU_StageF;

// ================================================================
// BSV library imports

import FIFOF        :: *;
import GetPut       :: *;
import ClientServer :: *;

// ----------------
// BSV additional libs

import Cur_Cycle :: *;

// ================================================================
// Project imports

import ISA_Decls         :: *;
import CPU_Globals       :: *;
import Near_Mem_IFC      :: *;
import Branch_Predictor  :: *;

`ifdef RVFI_DII
import RVFI_DII          :: *;
`endif

`ifdef ISA_CHERI
import CHERICap          :: *;
import CHERICC_Fat       :: *;
`endif

// ================================================================
// Interface

interface CPU_StageF_IFC;
   // ---- Reset
   interface Server #(Token, Token) server_reset;

   // ---- Output
   (* always_ready *)
   method Output_StageF out;

   (* always_ready *)
   method Action deq;

   // ---- Input
   (* always_ready *)
   method Action enq (Epoch            epoch,
		      Maybe #(WordXL)  m_old_fetch_addr,
		      WordXL           fetch_addr,
`ifdef ISA_CHERI
                      Bool             refresh_pcc,
`endif
		      Priv_Mode        priv,
`ifdef RVFI_DII
                      Dii_Id   next_seq,
`endif
		      Bit #(1)         sstatus_SUM,
		      Bit #(1)         mstatus_MXR,
		      WordXL           satp);

   (* always_ready *)
   method Action set_full (Bool full);

endinterface

// ================================================================
// Implementation module

module mkCPU_StageF #(Bit #(4)  verbosity,
		      IMem_IFC  imem)
                    (CPU_StageF_IFC);

   FIFOF #(Token)  f_reset_reqs <- mkFIFOF;
   FIFOF #(Token)  f_reset_rsps <- mkFIFOF;

   Wire #(Bool)      dw_redirecting <- mkDWire (False);

   Reg #(Bool)       rg_full  <- mkReg (False);
`ifdef ISA_CHERI
   Reg #(Bool)       rg_refresh_pcc <- mkReg(False);
`endif
   Reg #(Epoch)      rg_epoch <- mkReg (0);               // Toggles on redirections
   Reg #(Priv_Mode)  rg_priv  <- mkRegU;

   Branch_Predictor_IFC branch_predictor <- mkBranch_Predictor;

   // ----------------------------------------------------------------
   // BEHAVIOR

   rule rl_reset;
      f_reset_reqs.deq;
      rg_full  <= False;
      rg_epoch <= 0;
`ifdef RVFI_DII
      branch_predictor.reset();
`endif
      f_reset_rsps.enq (?);
   endrule

   rule rl_commit;
      imem.commit; // always commit to imem, meaning OOB reads can happen over instr interface
   endrule

   // ----------------
   // Combinational output function

   function Output_StageF fv_out;
      let d = Data_StageF_to_StageD {fetch_addr:      imem.pc,
`ifdef ISA_CHERI
                                     refresh_pcc:     rg_refresh_pcc,
`endif
				     epoch:           rg_epoch,
				     priv:            rg_priv,
				     is_i32_not_i16:  imem.is_i32_not_i16,
				     exc:             imem.exc,
				     exc_code:        imem.exc_code,
				     tval:            imem.tval,
`ifdef RVFI_DII
				     instr:           tpl_1(imem.instr),
                                     instr_seq:       tpl_2(imem.instr),
`else
				     instr:           imem.instr,
`endif
				     pred_fetch_addr: branch_predictor.predict_rsp};

      let ostatus = (  (! rg_full) ? OSTATUS_EMPTY
		     : (  (! imem.valid) ? OSTATUS_BUSY
			: OSTATUS_PIPE));                    // instr or exception

      let output_stageF = Output_StageF {ostatus: ostatus, data_to_stageD: d};

      return output_stageF;
   endfunction: fv_out

   // ================================================================
   // INTERFACE

   // ---- Reset
   interface server_reset = toGPServer (f_reset_reqs, f_reset_rsps);

   // ---- Output
   method Output_StageF out;
      return fv_out;
   endmethod

   method Action deq ();
      noAction;
   endmethod

   // ---- Input
   method Action enq (Epoch            epoch,
		      Maybe #(WordXL)  m_old_fetch_addr,
                      WordXL           fetch_addr,
`ifdef ISA_CHERI
                      Bool             refresh_pcc,
`endif
		      Priv_Mode        priv,
`ifdef RVFI_DII
                      Dii_Id   next_seq,
`endif
		      Bit #(1)         sstatus_SUM,
		      Bit #(1)         mstatus_MXR,
		      WordXL           satp);
      if (verbosity > 1) begin
	 $write   ("    CPU_StageF.enq:  fetch_addr:0x%0h  epoch:%0d  priv:%0d", fetch_addr, epoch, priv);
	 $display ("  sstatus_SUM:%0d  mstatus_MXR:%0d  satp:0x%0h  m_old_addr:",
		   sstatus_SUM, mstatus_MXR, satp, fshow (m_old_fetch_addr));
      end

      imem.req (f3_LW, fetch_addr, priv, sstatus_SUM, mstatus_MXR, satp
`ifdef RVFI_DII
                                                                       , next_seq
`endif
                                                                       );
      branch_predictor.predict_req (fetch_addr, m_old_fetch_addr);    // TODO: ASID.VA vs PA?

      rg_epoch <= epoch;
      rg_priv  <= priv;
`ifdef ISA_CHERI
      rg_refresh_pcc <= refresh_pcc;
`endif
   endmethod

   method Action set_full (Bool full);
      rg_full <= full;
   endmethod
endmodule

// ================================================================

endpackage
