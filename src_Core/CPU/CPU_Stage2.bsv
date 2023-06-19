// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved

//-
// RVFI_DII + CHERI modifications:
//     Copyright (c) 2018 Jack Deeley
//     Copyright (c) 2018-2019 Peter Rugg (RVFI_DII + CHERI)
//     All rights reserved.
//
//     This software was developed by SRI International and the University of
//     Cambridge Computer Laboratory (Department of Computer Science and
//     Technology) under DARPA contract HR0011-18-C-0016 ("ECATS"), as part of the
//     DARPA SSITH research programme.
//-

package CPU_Stage2;

// ================================================================
// This is Stage 2 of the CPU.
// It is the "DM" stage ("Data Memory"), which is the main function.

// However, this stage also contains all other (potentially) long-latency
// operations:
//    MBox ("M" extension ops, integer multiply/divide)
//    FDBox ("FD" extension ops, single and double precision floating point)

// This stage sends out Tandem Verifier information for pipelined instructions

// Note: $displays are indented by (stage num x 4) spaces.
// for traditional pipeline display
//     IF
//         DM
//             WB
// i.e., 8 spaces for this stage.

// ================================================================
// Exports

export
CPU_Stage2_IFC (..),
mkCPU_Stage2;

// ================================================================
// BSV library imports

import FIFOF        :: *;
import GetPut       :: *;
import ClientServer :: *;
import ConfigReg    :: *;

// ----------------
// BSV additional libs

import Cur_Cycle  :: *;

// ================================================================
// Project imports

import ISA_Decls     :: *;

`ifdef RVFI
import Verifier  :: *;
import RVFI_DII  :: *;
`endif
import TV_Info       :: *;

import CPU_Globals      :: *;
import Near_Mem_IFC     :: *;
import MMU_Cache_Common :: *;    // for CacheOp
import CSR_RegFile      :: *;    // For SATP, SSTATUS, MSTATUS

`ifdef SHIFT_SERIAL
import Shifter_Box  :: *;
`endif

`ifdef ISA_M
import RISCV_MBox  :: *;
`endif

`ifdef ISA_F
import FBox_Top    :: *;
import FBox_Core   :: *;   // For fv_nanbox function
`endif

`ifdef ISA_CHERI
import CHERICap :: *;
import CHERICC_Fat :: *;
`endif

// ================================================================
// Interface

interface CPU_Stage2_IFC;
   // ---- Reset
   interface Server #(Token, Token) server_reset;

   // ---- Output
   (* always_ready *)
   method Output_Stage2  out;

   (* always_ready *)
   method Action deq;

   // ---- Input
   (* always_ready *)
   method Action enq (Data_Stage1_to_Stage2 x, Bool valid);

   (* always_ready *)
   method Action set_full (Bool full);
endinterface

// ================================================================
// Implementation module

module mkCPU_Stage2 #(Bit #(4)         verbosity,
		      CSR_RegFile_IFC  csr_regfile,    // for SATP and SSTATUS: TODO carry in Data_Stage1_to_Stage2
		      DMem_IFC         dcache)
                    (CPU_Stage2_IFC);

   FIFOF #(Token) f_reset_reqs <- mkFIFOF;
   FIFOF #(Token) f_reset_rsps <- mkFIFOF;

   Reg #(Bool)                  rg_resetting  <- mkReg (False);
   Reg #(Bool)                  rg_full       <- mkReg (False);
   Reg #(Data_Stage1_to_Stage2) rg_stage2     <- mkRegU;    // From Stage 1
   Reg #(Bit#(5))               rg_f5         <- mkReg (0);

   // ----------------
   // Serial shifter box

`ifdef SHIFT_SERIAL
   Shifter_Box_IFC shifter_box <- mkShifter_Box;
`endif

   // ----------------
   // Integer multiply/divide box

`ifdef ISA_M
   RISCV_MBox_IFC mbox <- mkRISCV_MBox;
`endif

   // ----------------
   // Floating point box

`ifdef ISA_F
   FBox_Top_IFC fbox <- mkFBox_Top (0);
`endif

   // ----------------

`ifdef RVFI
   let info_RVFI_s1 = rg_stage2.info_RVFI_s1;
`endif

   let bypass_base = Bypass {bypass_state: BYPASS_RD_NONE,
			     rd:           rg_stage2.rd,
			     rd_val:       extract_cap(rg_stage2.val1)
			     };

`ifdef ISA_F
   let fbypass_base = FBypass {bypass_state: BYPASS_RD_NONE,
			       rd:           rg_stage2.rd,
			       rd_val:       rg_stage2.fval1
			       };
`endif

`ifdef RVFI
    let info_RVFI_s2_base = Data_RVFI_Stage2 {
                                    stage1:     info_RVFI_s1,
                                    mem_rmask:  0,
                                    mem_wmask:  0
                                };
`endif

   let data_to_stage3_base = Data_Stage2_to_Stage3 {
        priv:       rg_stage2.priv
`ifdef ISA_CHERI
      , pcc:        rg_stage2.pcc
`else
      , pc:         rg_stage2.pc
`endif
      , instr:      rg_stage2.instr
`ifdef RVFI_DII
      , instr_seq:  rg_stage2.instr_seq
`endif
`ifdef RVFI
      , info_RVFI_s2: info_RVFI_s2_base
`endif
      , rd_valid:   False
      , rd:         rg_stage2.rd
      , rd_val:     cast (rg_stage2.val1)
`ifdef ISA_F
						    , rd_in_fpr:  False,
						    upd_flags:  False,
						    fpr_flags:  0,
						    frd_val:    rg_stage2.fval1
`endif
`ifdef INCLUDE_TANDEM_VERIF
						    , trace_data: rg_stage2.trace_data
`endif
						    };

   let  trap_info_dmem = Trap_Info_Pipe {
				    exc_code: dcache.exc_code,
`ifdef ISA_CHERI
            cheri_exc_code: dcache.exc_code == exc_code_CHERI ? exc_code_CHERI_Length: exc_code_CHERI_None,
            cheri_exc_reg: ?, //TODO
            epcc: rg_stage2.pcc,
`else
            epc:  rg_stage2.pc,
`endif
				    tval: rg_stage2.addr };

`ifdef ISA_F
   // The FBox can only generate ILLEGAL Instruction exceptions
   let  trap_info_fbox = Trap_Info_Pipe {
`ifdef ISA_CHERI
            epcc:     rg_stage2.pcc,
            cheri_exc_code: ?,
            cheri_exc_reg: ?,
`else
            epc:      rg_stage2.pc,
`endif
				    exc_code: exc_code_ILLEGAL_INSTRUCTION,
				    tval:     0 };
`endif

   // ----------------------------------------------------------------
   // BEHAVIOR

   rule rl_reset_begin;
      f_reset_reqs.deq;
      rg_full <= False;
      rg_resetting <= True;
`ifdef ISA_F
      fbox.server_reset.request.put (?);
`endif
   endrule

   rule rl_reset_end (rg_resetting);
      rg_resetting <= False;

`ifdef ISA_F
      let res <- fbox.server_reset.response.get;
`endif

      f_reset_rsps.enq (?);
   endrule

   // ----------------
   // Combinational output function

   function Output_Stage2 fv_out;
      Output_Stage2 output_stage2 = ?;

`ifdef ISA_CHERI
     let check_enable = rg_full && rg_stage2.check_enable;
     let check_success =  rg_stage2.check_address_low >= getBase(rg_stage2.check_authority) &&
                         (rg_stage2.check_address_high <= getTop(rg_stage2.check_authority));
`endif

      // This stage is empty
      if (! rg_full) begin
	 output_stage2 = Output_Stage2 {ostatus         : OSTATUS_EMPTY,
					trap_info       : ?,
`ifdef PERFORMANCE_MONITORING
					perf            : unpack (0),
`endif
					data_to_stage3  : ?,
					bypass          : no_bypass
`ifdef ISA_F
					, fbypass       : no_fbypass
`endif
					};
      end
      // This stage is just relaying ALU results from previous stage to next stage
      else
      if (rg_stage2.op_stage2 == OP_Stage2_ALU) begin
	 let data_to_stage3 = data_to_stage3_base;
	 data_to_stage3.rd_valid = True;

	 let bypass = bypass_base;
	 bypass.bypass_state = BYPASS_RD_RDVAL;

	 output_stage2 = Output_Stage2 {ostatus         : OSTATUS_PIPE,
					trap_info       : ?,
`ifdef PERFORMANCE_MONITORING
					perf            : unpack (0),
`endif
					data_to_stage3  : data_to_stage3,
					bypass          : bypass
`ifdef ISA_F
					, fbypass       : no_fbypass
`endif
					};
      end

`ifdef ISA_CHERI
      else if (   (rg_stage2.op_stage2 == OP_Stage2_TestSubset)) begin
          let ostatus = OSTATUS_PIPE;
          CapReg result = nullWithAddr(zeroExtend(pack(check_success)));
          let data_to_stage3 = data_to_stage3_base;
          data_to_stage3.rd_valid = True;
          data_to_stage3.rd_val = embed_cap(result);
          let bypass = bypass_base;
          bypass.bypass_state = BYPASS_RD;
`ifdef RVFI
          let info_RVFI_s2 = info_RVFI_s2_base;
          data_to_stage3.info_RVFI_s2 = info_RVFI_s2;
`endif
          output_stage2 = Output_Stage2 {ostatus:         ostatus,
                 trap_info:       trap_info_dmem,
`ifdef PERFORMANCE_MONITORING
                 perf            : unpack (0),
`endif
                 data_to_stage3:  data_to_stage3,
                 bypass:          bypass
`ifdef INCLUDE_TANDEM_VERIF
               , trace_data:      ?
`endif
                                        };
      end
`endif

      // This stage is doing a LOAD or AMO
      else if (   (rg_stage2.op_stage2 == OP_Stage2_LD)
`ifdef ISA_A
	       || (rg_stage2.op_stage2 == OP_Stage2_AMO)
`endif
	       )
	 begin
	    let ostatus = (  (! dcache.valid)
			   ? OSTATUS_BUSY
			   : (  dcache.exc
			      ? OSTATUS_NONPIPE
			      : OSTATUS_PIPE));
        match {.mem_tag, .mem_val} = dcache.word128;
`ifdef ISA_CHERI
        CapReg result = ?;
        if (rg_stage2.mem_tag_only) begin
          result = nullWithAddr(zeroExtend(pack(mem_tag)));
        end else if (rg_stage2.mem_width_code == w_SIZE_CAP) begin
          CapMem capMem = {pack(rg_stage2.mem_allow_cap && mem_tag), mem_val};
          result = cast(capMem);
        end else begin
          result = nullWithAddr(truncate(mem_val));
        end
`else
        WordXL result = truncate(mem_val);
`endif

        let funct3 = instr_funct3 (rg_stage2.instr);

	let data_to_stage3 = data_to_stage3_base;
	data_to_stage3.rd_valid = (ostatus == OSTATUS_PIPE);

`ifdef ISA_F
        data_to_stage3.rd_in_fpr = rg_stage2.rd_in_fpr;
        // A FPR load
        if (rg_stage2.rd_in_fpr) begin
`ifdef ISA_D
           // Both FLW and FLD are legal instructions
           // A FLW result
           if (funct3 == f3_FLW)
              // needs nan-boxing when destined for a DP register file
              data_to_stage3.frd_val = fv_nanbox (truncate(tpl_2(dcache.word128)));

           // A FLD result
           else
              data_to_stage3.frd_val = truncate (tpl_2(dcache.word128));
`else
           // Only FLW is a legal instruction
           data_to_stage3.frd_val = truncate (tpl_2(dcache.word128));
`endif
        end
`endif
        // GPR loads
	data_to_stage3.rd_val   = embed_cap(result);

        // Update the bypass channel, if not trapping (NONPIPE)
	let bypass = bypass_base;
`ifdef ISA_F
        // In a system with FD, the LD result may be meant for FPR or GPR
        // Check before updating the appropriate bypass channel
	let fbypass = fbypass_base;
`endif

`ifdef ISA_F
            // Bypassing FPR value.
            if (rg_stage2.rd_in_fpr) begin
	       // Choose one of the following two options

	       // Option 1: longer critical path, since the data is bypassed back into previous stage.
	       // We use data_to_stage3.rd_val since nanboxing has been done.
	       // fbypass.bypass_state = ((ostatus == OSTATUS_PIPE) ? BYPASS_RD_RDVAL : BYPASS_RD);
	       // fbypass.rd_val       = data_to_stage3.frd_val;

	       // Option 2: shorter critical path, since the data is not bypassed into previous stage,
	       // (the bypassing is effectively delayed until the next stage).
	        fbypass.bypass_state = BYPASS_RD;
            end
`endif

            // Bypassing GPR values
            if (rg_stage2.rd != 0) begin    // TODO: is this test necessary?
	       // Choose one of the following two options

	       // Option 1: longer critical path, since the data is bypassed back into previous stage.
	       // We use data_to_stage3.rd_val since nanboxing has been done.
	       // bypass.bypass_state = ((ostatus == OSTATUS_PIPE) ? BYPASS_RD_RDVAL : BYPASS_RD);
	       // bypass.rd_val       = result;

	       // Option 2: shorter critical path, since the data is not bypassed into previous stage,
	       // (the bypassing is effectively delayed until the next stage).
	        bypass.bypass_state = BYPASS_RD;
	    end

`ifdef INCLUDE_TANDEM_VERIF
	    let trace_data = rg_stage2.trace_data;
`ifdef ISA_F
            if (rg_stage2.rd_in_fpr) begin
               trace_data.word5 = data_to_stage3.frd_val;

               // Update MSTATUS.FS in trace packet
	       let new_mstatus = csr_regfile.mv_update_mstatus_fs (fs_xs_dirty);
               trace_data = fv_trace_update_mstatus_fs (trace_data, new_mstatus);
            end else
`endif
               trace_data.word1 = data_to_stage3.rd_val;

            data_to_stage3.trace_data = trace_data;
`elsif RVFI
	    let info_RVFI_s2 = info_RVFI_s2_base;
        // If we're doing a load or AMO other than SC, we need to set the read mask.
        if((rg_stage2.op_stage2 == OP_Stage2_LD)
`ifdef ISA_A
            ||((rg_stage2.op_stage2 == OP_Stage2_AMO) && (rg_f5 != f5_AMO_SC))
`endif
        ) begin
            info_RVFI_s2.mem_rmask = getMemMask({0,rg_stage2.mem_width_code},rg_stage2.addr);
        end
`ifdef ISA_A
`ifdef ISA_CHERI
        WordXL int_ret_val = getAddr(result);
`else
        WordXL int_ret_val = result;
`endif
        // If we're doing an AMO that's not an LR, we need to set the write mask as well.
        if (rg_stage2.op_stage2 == OP_Stage2_AMO && rg_f5 != f5_AMO_LR) begin
            // For most AMOs we can just go ahead and do it
            if (rg_f5 != f5_AMO_SC) begin
                info_RVFI_s2.mem_wmask = getMemMask(rg_stage2.mem_width_code,rg_stage2.addr);
                match {.res_tag, .res_data} = toMem (result);
                match {.new_ld_val,
                       .new_st_val} = fn_amo_op (rg_stage2.mem_width_code,
                                                 rg_f5,
                                                 rg_stage2.addr & ~(~0 << rg_stage2.mem_width_code), // force aligned address as return from memory is already sliced appropriately (a 0 addr would just work)
                                                 // put tag and data in bottom bits due to alignment on the line above
                                                 tuple2 (zeroExtend (pack (res_tag)), zeroExtend (res_data)),
                                                 tuple2(False, zeroExtend(rg_stage2.info_RVFI_s1.mem_wdata))
                                                );
                info_RVFI_s2.stage1.mem_wdata = truncate(pack(tpl_2(new_st_val)));
            // For SC however we do need to check that it was successful, otherwise we've not written.
            end else begin
                info_RVFI_s2.mem_wmask = ((int_ret_val != 0) ? getMemMask(rg_stage2.mem_width_code,rg_stage2.addr) : 0);
            end
        end
        data_to_stage3.info_RVFI_s2 = info_RVFI_s2;
`endif
`endif

`ifdef PERFORMANCE_MONITORING
	 Output_Stage2_Perf perf = unpack (0);
`ifdef ISA_A
	 if (   (rg_stage2.op_stage2 == OP_Stage2_AMO) && (rg_f5 == f5_AMO_SC)   )
`ifdef ISA_CHERI
	    perf.sc_success = (getAddr (result) == 0);
`else
	    perf.sc_success = (result == 0);
`endif
`endif // ISA_A
`ifdef ISA_CHERI
	 perf.ld_cap = (rg_stage2.mem_width_code == w_SIZE_CAP && !rg_stage2.mem_tag_only);
	 // Note: 'ld_cap_tag_set' will only count when 'mem_allow_cap' is set
	 // To count 'mem_tag' set, regardless of 'mem_allow_cap', use caps loaded from L1
	 perf.ld_cap_tag_set = (rg_stage2.mem_width_code == w_SIZE_CAP) && mem_tag && rg_stage2.mem_allow_cap && !rg_stage2.mem_tag_only;
`endif
	 perf.ld_wait = (! dcache.valid);
`endif

            output_stage2 = Output_Stage2 {ostatus         : ostatus,
					   trap_info       : trap_info_dmem,
`ifdef PERFORMANCE_MONITORING
					   perf            : perf,
`endif
					   data_to_stage3  : data_to_stage3,
					   bypass          : bypass
`ifdef ISA_F
					   , fbypass       : fbypass
`endif
					   };
	 end

      // This stage is doing a STORE
      else if (rg_stage2.op_stage2 == OP_Stage2_ST) begin
	 let ostatus = (  (! dcache.valid)
			     ? OSTATUS_BUSY
			     : (  dcache.exc
				? OSTATUS_NONPIPE
				: OSTATUS_PIPE));

	 let data_to_stage3 = data_to_stage3_base;
	 data_to_stage3.rd_valid = (ostatus == OSTATUS_PIPE);
	 data_to_stage3.rd       = 0;

`ifdef RVFI
`ifdef ISA_CHERI
	 data_to_stage3.rd_val   = embed_cap(nullCap);
`else
	 data_to_stage3.rd_val   = 0;
`endif
	 let info_RVFI_s2 = info_RVFI_s2_base;
	 info_RVFI_s2.mem_wmask = getMemMask(rg_stage2.mem_width_code,rg_stage2.addr);
	 data_to_stage3.info_RVFI_s2 = info_RVFI_s2;
`else
	 data_to_stage3.rd_val   = ?;
`endif

`ifdef PERFORMANCE_MONITORING
	 Output_Stage2_Perf perf = unpack (0);
	 perf.st_wait = (! dcache.valid);
`endif

	 output_stage2 = Output_Stage2 {ostatus         : ostatus,
					trap_info       : trap_info_dmem,
`ifdef PERFORMANCE_MONITORING
					perf            : perf,
`endif
					data_to_stage3  : data_to_stage3,
					bypass          : no_bypass
`ifdef ISA_F
					, fbypass       : no_fbypass
`endif
					};
      end

`ifdef SHIFT_SERIAL
      // This stage is doing a serial shift
      else if (rg_stage2.op_stage2 == OP_Stage2_SH) begin
	 let ostatus = ((! shifter_box.valid) ? OSTATUS_BUSY : OSTATUS_PIPE);

	 let result = shifter_box.word;

	 let data_to_stage3 = data_to_stage3_base;
	 data_to_stage3.rd_valid = (ostatus == OSTATUS_PIPE);
	 data_to_stage3.rd_val   = embed_int(result);

	 let bypass = bypass_base;
	 bypass.bypass_state = ((ostatus == OSTATUS_PIPE) ? BYPASS_RD_RDVAL : BYPASS_RD);
	 bypass.rd_val       = nullWithAddr(result);

`ifdef INCLUDE_TANDEM_VERIF
	 let trace_data            = rg_stage2.trace_data;
	 trace_data.word1          = result;
	 data_to_stage3.trace_data = trace_data;
`elsif RVFI
	 // No memory op, so very simple.
	 let info_RVFI_s2 = info_RVFI_s2_base;
	 data_to_stage3.info_RVFI_s2 = info_RVFI_s2;
`endif

	 output_stage2 = Output_Stage2 {ostatus         : ostatus,
					trap_info       : ?,
`ifdef PERFORMANCE_MONITORING
					perf            : unpack (0),
`endif
					data_to_stage3  : data_to_stage3,
					bypass          : bypass
`ifdef ISA_F
					, fbypass         : no_fbypass
`endif
					};
      end
`endif

`ifdef ISA_M
      // This stage is doing an integer multiply/divide
      else if (rg_stage2.op_stage2 == OP_Stage2_M) begin
	 let ostatus = ((! mbox.valid) ? OSTATUS_BUSY : OSTATUS_PIPE);

	 let result = mbox.word;

	 let data_to_stage3 = data_to_stage3_base;
	 data_to_stage3.rd_valid = (ostatus == OSTATUS_PIPE);
	 data_to_stage3.rd_val   = embed_int(result);

	 let bypass = bypass_base;
	 bypass.bypass_state = ((ostatus == OSTATUS_PIPE) ? BYPASS_RD_RDVAL : BYPASS_RD);
`ifdef ISA_CHERI
	 bypass.rd_val       = nullWithAddr(result);
`else
	 bypass.rd_val       = result;
`endif

`ifdef INCLUDE_TANDEM_VERIF
	 let trace_data            = rg_stage2.trace_data;
	 trace_data.word1          = result;
	 data_to_stage3.trace_data = trace_data;
`elsif RVFI
	 // No memory op, so very simple.
	 let info_RVFI_s2 = info_RVFI_s2_base;
	 data_to_stage3.info_RVFI_s2 = info_RVFI_s2;
`endif

	 output_stage2 = Output_Stage2 {ostatus         : ostatus,
					trap_info       : ?,
`ifdef PERFORMANCE_MONITORING
					perf            : unpack (0),
`endif
					data_to_stage3  : data_to_stage3,
					bypass          : bypass
`ifdef ISA_F
					, fbypass         : no_fbypass
`endif
					};
      end
`endif

`ifdef ISA_F
      // This stage is doing a floating point op
      else if (rg_stage2.op_stage2 == OP_Stage2_FD) begin
	 let ostatus = ((! fbox.valid) ? OSTATUS_BUSY : OSTATUS_PIPE);

         // Extract fields from FBOX result
	 match {.value, .fflags} = fbox.word;

	 let data_to_stage3      = data_to_stage3_base;
	 data_to_stage3.rd_valid = (ostatus == OSTATUS_PIPE);
`ifdef ISA_D
	 data_to_stage3.frd_val  = value;
`else
	 data_to_stage3.frd_val  = truncate (value);
`endif
         data_to_stage3.rd_in_fpr= rg_stage2.rd_in_fpr;
         data_to_stage3.upd_flags= True;
         data_to_stage3.fpr_flags= fflags;

         // result is meant for a FPR
	 let bypass              = bypass_base;
         let fbypass             = fbypass_base;
         if (rg_stage2.rd_in_fpr) begin
            fbypass.bypass_state    = ((ostatus==OSTATUS_PIPE) ? BYPASS_RD_RDVAL
                                                               : BYPASS_RD);
`ifdef ISA_D
            fbypass.rd_val          = value;
`else
            fbypass.rd_val          = truncate(value);
`endif
         end

         // result is meant for a GPR
         else begin
            bypass.bypass_state     = ((ostatus==OSTATUS_PIPE) ? BYPASS_RD_RDVAL
                                                               : BYPASS_RD);
`ifdef RV64
            bypass.rd_val           = nullWithAddr(value);
            data_to_stage3.rd_val   = embed_int(value);
`else
            bypass.rd_val           = nullWithAddr(truncate(value));
            data_to_stage3.rd_val   = embed_int(truncate(value));
`endif
         end

         // -----
`ifdef INCLUDE_TANDEM_VERIF
	 let trace_data = rg_stage2.trace_data;

         if (rg_stage2.rd_in_fpr) begin
            trace_data.word5 = data_to_stage3.frd_val;
         end else begin
            trace_data.word1 = data_to_stage3.rd_val;
         end

	 data_to_stage3.trace_data = trace_data;
`elsif RVFI
	 // No memory op, so very simple.
	 let info_RVFI_s2 = info_RVFI_s2_base;
	 data_to_stage3.info_RVFI_s2 = info_RVFI_s2;
`endif

	 output_stage2 = Output_Stage2 {ostatus         : ostatus,
					trap_info       : trap_info_fbox,
`ifdef PERFORMANCE_MONITORING
					perf            : unpack (0),
`endif
					data_to_stage3  : data_to_stage3,
					bypass          : bypass
`ifdef ISA_F
					, fbypass       : fbypass
`endif
         };
      end
`endif
`ifdef ISA_CHERI
      let  trap_info_capbounds = Trap_Info_Pipe {epcc:    rg_stage2.pcc,
                                                 exc_code: exc_code_CHERI,
                                                 cheri_exc_code: check_success ? exc_code_CHERI_Precision : exc_code_CHERI_Length,
                                                 cheri_exc_reg: rg_stage2.check_authority_idx,
                                                 tval: rg_stage2.check_address_low };
      output_stage2.check_success = check_enable && check_success;
      if (check_enable && !check_success) begin
         output_stage2.ostatus = OSTATUS_NONPIPE;
         output_stage2.trap_info = trap_info_capbounds;
      end
`endif
      return output_stage2;
   endfunction

   // ----------------
   // Initiate DM, Shifter box, MBox or FBox op

   function Action fa_enq (Data_Stage1_to_Stage2 x, Bool valid);
      action
	 if (valid) rg_stage2  <= x;

	 let funct3 = instr_funct3 (x.instr);

	 // If DMem access, initiate it
`ifdef ISA_A
	 Bool op_stage2_amo = (x.op_stage2 == OP_Stage2_AMO);
`ifdef ISA_CHERI
	 Bit #(5) amo_funct5 = getAddr(extract_cap(x.val1)) [6:2];
	 Bit #(7) amo_funct7 = getAddr(extract_cap(x.val1)) [6:0];
`else
	 Bit #(5) amo_funct5 = pack(x.val1) [6:2];
	 Bit #(7) amo_funct7 = pack(x.val1) [6:0];
`endif
         if (valid) rg_f5 <= amo_funct5;
`else
	 Bool op_stage2_amo = False;
	 Bit #(5) amo_funct5 = 0;
	 Bit #(7) amo_funct7 = 0;
`endif
	 if ((x.op_stage2 == OP_Stage2_LD) || (x.op_stage2 == OP_Stage2_ST) || op_stage2_amo) begin
	    WordXL   mstatus     = csr_regfile.read_mstatus;
`ifdef ISA_PRIV_S
	    Bit #(1) sstatus_SUM = (csr_regfile.read_sstatus) [18];
`else
	    Bit #(1) sstatus_SUM = 0;
`endif
	    Bit #(1) mstatus_MXR = mstatus [19];
	    Priv_Mode  mem_priv = x.priv;
	    if (mstatus [17] == 1'b1) begin
	       mem_priv = mstatus [12:11];
	       // $display ("    S2.fa_enq: mem_priv %0d => %0d (mstatus.MPP) due to mstatus.MPRV", x.priv, mem_priv);
	    end

	    CacheOp cache_op = ?;
	    if      (x.op_stage2 == OP_Stage2_LD)  cache_op = CACHE_LD;
	    else if (x.op_stage2 == OP_Stage2_ST)  cache_op = CACHE_ST;
`ifdef ISA_A
	    else if (x.op_stage2 == OP_Stage2_AMO) cache_op = CACHE_AMO;
`endif

`ifdef ISA_CHERI
        CapReg capReg = cast(extract_cap(x.val2));
        CapMem capMem = cast(capReg);
        Bit#(TSub#(SizeOf#(CapMem),1)) tagless = truncate(capMem);
`endif

        dcache.req (cache_op,
			x.mem_width_code,
            x.mem_unsigned,
`ifdef ISA_A
			amo_funct5,
`endif
			x.addr,
`ifdef ISA_F
			x.rs_frm_fpr ? tuple2(False,zeroExtend(x.fval2)) :
`endif
`ifdef ISA_CHERI
      tuple2(x.mem_width_code == w_SIZE_CAP && isValidCap(capMem), zeroExtend(tagless)),
`else
      tuple2(False, zeroExtend(x.val2)),
`endif
			mem_priv,
			sstatus_SUM,
			mstatus_MXR,
			csr_regfile.read_satp);
	 end

`ifdef SHIFT_SERIAL
	 // If Shifter box op, initiate it
	 else if (x.op_stage2 == OP_Stage2_SH)
	    shifter_box.req (unpack (funct3 [2]), x.val1_fast, x.val2_fast);
`endif

`ifdef ISA_M
	 // If MBox op, initiate it
	 else if (x.op_stage2 == OP_Stage2_M) begin
            // Instr fields required for decode for F/D opcodes
	    Bool is_OP_not_OP_32 = (x.instr [3] == 1'b0);
            mbox.req (is_OP_not_OP_32, funct3, x.val1_fast, x.val2_fast);
	 end
`endif

`ifdef ISA_F
	 // If FBox op, initiate it
	 else if (x.op_stage2 == OP_Stage2_FD) begin
	    // Instr fields required for decode for F/D opcodes
            let opcode = instr_opcode (x.instr);
	    let funct7 = instr_funct7 (x.instr);
            let rs2    = instr_rs2    (x.instr);
            Bit #(64) val1 = x.val1_frm_gpr ? extend(x.val1_fast)
                                            : extend (x.fval1);

	    fbox.req (opcode,
		      funct7,
		      x.rounding_mode,   // rm
		      rs2,
		      val1,
		      extend (x.fval2),
		      extend (x.fval3),
		      valid);
         end
`endif
      endaction
   endfunction

   // ----------------------------------------------------------------
   // INTERFACE

   // ---- Reset
   interface server_reset = toGPServer (f_reset_reqs, f_reset_rsps);

   // ---- Output
   method Output_Stage2  out;
      return fv_out;
   endmethod

   method Action deq ();
      noAction;
   endmethod

   // ---- Input
   method Action enq (Data_Stage1_to_Stage2 x, Bool valid);
      fa_enq (x, valid);

      if (verbosity > 1 && valid)
	 $display ("%0t    CPU_Stage2.enq (Data_Stage1_to_Stage2) ", $time, fshow(x));
   endmethod

   method Action set_full (Bool full);
      rg_full <= full;
   endmethod
endmodule

// ================================================================

endpackage
