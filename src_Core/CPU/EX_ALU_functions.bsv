// Copyright (c) 2016-2019 Bluespec, Inc. All Rights Reserved

//-
// RVFI_DII + CHERI modifications:
//     Copyright (c) 2018 Jack Deeley (RVFI_DII)
//     Copyright (c) 2018 Peter Rugg (RVFI_DII + CHERI)
//     All rights reserved.
//
//     This software was developed by SRI International and the University of
//     Cambridge Computer Laboratory (Department of Computer Science and
//     Technology) under DARPA contract HR0011-18-C-0016 ("ECATS"), as part of the
//     DARPA SSITH research programme.
//-

package EX_ALU_functions;

// ================================================================
// These are the "ALU" functions in the EX stage of the "Piccolo" CPU.
// EX stands for "Execution".

// ================================================================
// Exports

export
ALU_Inputs (..),
ALU_Outputs (..),
Output_Select,
fv_ALU;

// ================================================================
// BSV library imports

import Vector :: *;

// ----------------
// BSV additional libs

// None

// ================================================================
// Project imports

import ISA_Decls   :: *;
import CPU_Globals :: *;
import TV_Info     :: *;
`ifdef ISA_CHERI
import CHERICap :: *;
import CHERICC_Fat :: *;
`endif

// ================================================================
// ALU inputs

typedef struct {
   Priv_Mode      cur_priv;
`ifdef ISA_CHERI
   PCC_T          pcc;
   CapPipe        ddc;
   Bit#(5)        rs1_idx;
   Bit#(5)        rs2_idx;
`endif
   Addr           pc;
   Bool           is_i32_not_i16;
   Instr          instr;
`ifdef ISA_C
   Instr          instr_or_instr_C;
`endif
   Decoded_Instr  decoded_instr;
   WordXL         rs1_val;
   WordXL         rs2_val;
   WordXL         mstatus;
`ifdef ISA_F
   Bit #(3)       frm;
   WordFL         frs1_val;
   WordFL         frs2_val;
   WordFL         frs3_val;
`ifdef INCLUDE_TANDEM_VERIF
   Bit #(5)       fflags;
`endif
`endif
`ifdef ISA_CHERI
   CapPipe        cap_rs1_val;
   CapPipe        cap_rs2_val;
`endif
   MISA           misa;
   } ALU_Inputs
deriving (Bits, FShow);

function Bool is_cap_mode (ALU_Inputs inputs);
   return getFlags(toCapPipe(inputs.pcc))[0] == 1;
endfunction

// ----------------
// These functions pick the instruction size and instruction bits to
// be sent in the trace to a tandem verifier

function ISize  fv_trace_isize (ALU_Inputs  inputs);
   return (inputs.is_i32_not_i16 ? ISIZE32BIT : ISIZE16BIT);
endfunction

function Bit #(32)  fv_trace_instr (ALU_Inputs  inputs);
`ifdef ISA_C
   return inputs.instr_or_instr_C;
`else
   return inputs.instr;
`endif
endfunction

// ================================================================
// ALU outputs

typedef struct {
   Control    control;
   Exc_Code   exc_code;        // Relevant if control == CONTROL_TRAP
`ifdef ISA_CHERI
   CHERI_Exc_Code cheri_exc_code; //Relevant if control == CONTROL_TRAP && exc_code == exc_code_CHERI
   Bit#(6)        cheri_exc_reg;
`endif

   Op_Stage2  op_stage2;
   RegName    rd;
   Addr       addr;           // Branch, jump: newPC
		              // Mem ops and AMOs: mem addr
   WordXL     val1;           // OP_Stage2_ALU: result for Rd (ALU ops: result, JAL/JALR: return PC)
                              // CSRRx: rs1_val
                              // OP_Stage2_M: arg1
                              // OP_Stage2_AMO: funct7

   WordXL     val2;           // Branch: branch target (for Tandem Verification)
		              // OP_Stage2_ST: store-val
                              // OP_Stage2_M: arg2
   WordXL     val1_fast;
   WordXL     val2_fast;

`ifdef ISA_F
   WordFL     fval1;          // OP_Stage2_FD: arg1
   WordFL     fval2;          // OP_Stage2_FD: arg2
   WordFL     fval3;          // OP_Stage2_FD: arg3
   Bool       rd_in_fpr;      // result to be written to fpr
   Bool       rs_frm_fpr;     // src register is in fpr (for stores)
   Bool       val1_frm_gpr;   // first operand is in gpr (for some FP instrns)
   Bit #(3)   rm;             // rounding mode
`endif

   Bit#(3) mem_width_code;
   Bool    mem_tag_only;
   Bool    mem_unsigned;

`ifdef ISA_CHERI
   Bool    mem_allow_cap; //Whether load/store is allowed to preserve cap tag

   PCC_T   pcc;
`endif

`ifdef ISA_CHERI
   CapPipe    cap_val1;
   CapPipe    cap_val2;
   Bool       val1_cap_not_int;
   Bool       val2_cap_not_int;

   Bool                check_enable;
   CapPipe             check_authority;
   Bit #(6)            check_authority_idx;
   Bit#(XLEN)          check_address_low;
   Bit#(TAdd#(XLEN,1)) check_address_high;
`ifdef PERFORMANCE_MONITORING
   Bool                set_offset_in_bounds;
   Bool                set_bounds_inexact;
`else
`endif

   CF_Info    cf_info;        // For redirection and branch predictor

`ifdef INCLUDE_TANDEM_VERIF
   Trace_Data trace_data;
`endif
   } ALU_Outputs
deriving (Bits, FShow);

CF_Info cf_info_base = CF_Info {cf_op       : CF_None,
				from_PC     : ?,
				taken       : ?,
				fallthru_PC : ?,
				taken_PC    : ?};

ALU_Outputs alu_outputs_base
= ALU_Outputs {control   : CONTROL_STRAIGHT,
	       exc_code  : exc_code_ILLEGAL_INSTRUCTION,
`ifdef ISA_CHERI
               cheri_exc_code: exc_code_CHERI_None,
               cheri_exc_reg:  ?,
`endif
               op_stage2 : ?,
               rd        : ?,
               addr      : ?,
               val1      : ?,
               val2      : ?,
	       val1_fast : ?,
	       val2_fast : ?,
`ifdef ISA_F
               fval1       : ?,
               fval2       : ?,
               fval3       : ?,
               rd_in_fpr   : False,
               rs_frm_fpr  : False,
               val1_frm_gpr: False,
               rm          : ?,
`endif
`ifdef ISA_CHERI
               cap_val1  : ?,
               cap_val2  : ?,
               val1_cap_not_int: False,
               val2_cap_not_int: False,

               pcc : ?,

               check_enable       : False,
               check_authority    : ?,
               check_authority_idx : ?,
               check_address_low  : ?,
               check_address_high : ?,
`ifdef PERFORMANCE_MONITORING
               set_bounds_inexact : False,
               set_offset_in_bounds : True,
`else
`endif

               mem_allow_cap      : False,
`endif

               mem_width_code     : ?,
               mem_tag_only       : False,
               mem_unsigned       : False,

               cf_info     : cf_info_base

`ifdef INCLUDE_TANDEM_VERIF
             , trace_data: ?
`endif
                            };

// ================================================================
// The fall-through PC is PC+4 for normal 32b instructions,
// and PC+2 for 'C' (16b compressed) instructions.

function Addr fall_through_pc_inc (ALU_Inputs inputs);
   Addr inc = 4;
`ifdef ISA_C
   if (! inputs.is_i32_not_i16)
      inc = 2;
`endif
   return inc;
endfunction

function Addr fall_through_pc (ALU_Inputs  inputs);
   return inputs.pc + fall_through_pc_inc(inputs);
endfunction

// ================================================================
// Alternate implementation of shifts using multiplication in DSPs

// ----------------------------------------------------------------
/* TODO: DELETE? 'factor' RegFile for shift ops

// ----------------------------------------------------------------
// The following is a lookup table of multiplication factors used by the "shift" ops
RegFile #(Bit #(TLog #(XLEN)), Bit #(XLEN))  rf_sh_factors <- mkRegFileFull;
// The following is used during reset to initialize rf_sh_factors
Reg #(Bool)                                  rg_resetting  <- mkReg (False);
Reg #(Bit #(TAdd #(1, TLog #(XLEN))))        rg_j          <- mkRegU;
Reg #(WordXL)                                rg_factor     <- mkRegU;
*/

// ----------------------------------------------------------------
// The following functions implement the 'shift' operators SHL, SHRL and SHRA
// using multiplication instead of actual shifts,
// thus using DSPs (multiplication) and LUTRAMs (rf_sh_factors) instead of LUTs

// Shift-left
// Instead of '>>' operator, uses '*', using DSPs instead of LUTs.
// To SHL(n), do a multiplication by 2^n.
// The 2^n factor is looked up in a RegFile (used as a ROM), which uses a LUTRAM instead of LUTs
function WordXL fn_shl (WordXL x, Bit #(TLog #(XLEN)) shamt);
   IntXL  x_signed = unpack (x);

   // IntXL y_signed = unpack (rf_sh_factors.sub (shamt));
   IntXL  y_signed = unpack ('b1 << shamt);

   IntXL  z_signed = x_signed * y_signed;
   WordXL z        = pack (z_signed);
   return z;
endfunction

// Shift-right-arithmetic
// Instead of '>>' operator, uses '*', using DSPs instead of LUTs
// To SHR(n), do a 2*XLEN-wide multiplication by 2^(32-n), and take upper XLEN bits
// The 2^(32-n) factor is looked up in a RegFile (used as a ROM), which uses a LUTRAM instead of LUTs
function WordXL fn_shra (WordXL x, Bit #(TLog #(XLEN)) shamt);
   // Bit #(TAdd #(1, XLEN)) y = { reverseBits (rf_sh_factors.sub (shamt)), 1'b0 };
   Bit #(TAdd #(1, XLEN)) y = { reverseBits ('b1 << shamt), 1'b0 };

   Int #(XLEN_2) xx_signed = extend (unpack (x));
   Int #(XLEN_2) yy_signed = unpack (extend (y));
   Int #(XLEN_2) zz_signed = xx_signed * yy_signed;
   Bit #(XLEN_2) zz        = pack (zz_signed);
   WordXL        z         = truncateLSB (zz);
   return z;
endfunction

// Shift-right-logical
// Instead of '>>' operator, uses '*', using DSPs instead of LUTs
// To SHR(n), do a 2*XLEN-wide multiplication by 2^(32-n), and take upper XLEN bits
// The 2^(32-n) factor is looked up in a RegFile (used as a ROM), which uses a LUTRAM instead of LUTs
function WordXL fn_shrl (WordXL x, Bit #(TLog #(XLEN)) shamt);
   // Bit #(TAdd #(1, XLEN)) y = { reverseBits (rf_sh_factors.sub (shamt)), 1'b0 };
   Bit #(TAdd #(1, XLEN)) y = { reverseBits ('b1 << shamt), 1'b0 };

   Bit #(XLEN_2) xx = extend (x);
   Bit #(XLEN_2) yy = extend (y);
   Bit #(XLEN_2) zz = xx * yy;
   WordXL        z  = truncateLSB (zz);
   return z;
endfunction

// ================================================================
// BRANCH

function ALU_Outputs fv_BRANCH (ALU_Inputs inputs);
   let rs1_val = inputs.rs1_val;
   let rs2_val = inputs.rs2_val;

   // Signed versions of rs1_val and rs2_val
   IntXL s_rs1_val = unpack (inputs.rs1_val);
   IntXL s_rs2_val = unpack (inputs.rs2_val);

   IntXL offset        = extend (unpack (inputs.decoded_instr.imm13_SB));
   Addr  branch_target = pack (unpack (inputs.pc) + offset);
   Bool  branch_taken  = False;
   Bool  trap          = False;

   let funct3 = inputs.decoded_instr.funct3;
   if      (funct3 == f3_BEQ)  branch_taken = (rs1_val  == rs2_val);
   else if (funct3 == f3_BNE)  branch_taken = (rs1_val  != rs2_val);
   else if (funct3 == f3_BLT)  branch_taken = (s_rs1_val <  s_rs2_val);
   else if (funct3 == f3_BGE)  branch_taken = (s_rs1_val >= s_rs2_val);
   else if (funct3 == f3_BLTU) branch_taken = (rs1_val  <  rs2_val);
   else if (funct3 == f3_BGEU) branch_taken = (rs1_val  >= rs2_val);
   else                        trap = True;

   Bool misaligned_target = (branch_target [1] == 1'b1);
`ifdef ISA_C
   misaligned_target = False;
`endif

   Exc_Code exc_code = exc_code_ILLEGAL_INSTRUCTION;
   if ((! trap) && branch_taken && misaligned_target) begin
      trap = True;
      exc_code = exc_code_INSTR_ADDR_MISALIGNED;
   end

`ifdef ISA_CHERI
   let pcc_addr = getAddr(toCapPipe(inputs.pcc));
   let cf_info   = CF_Info {cf_op       : CF_BR,
			    from_PC     : pcc_addr,
			    taken       : branch_taken,
			    fallthru_PC : pcc_addr + fall_through_pc_inc(inputs),
			    taken_PC    : pack(unpack(pcc_addr) + offset) };
`else
   let cf_info   = CF_Info {cf_op       : CF_BR,
			    from_PC     : inputs.pc,
			    taken       : branch_taken,
			    fallthru_PC : fall_through_pc (inputs),
			    taken_PC    : branch_target };
`endif

   let alu_outputs = alu_outputs_base;
   let next_pc     = (branch_taken ? branch_target : fall_through_pc (inputs));
   alu_outputs.control   = (trap ? CONTROL_TRAP : (branch_taken ? CONTROL_BRANCH : CONTROL_STRAIGHT));
   alu_outputs.exc_code  = exc_code;
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = 0;
   // Gives a defined value when in verification mode.
   `ifdef RVFI
   alu_outputs.val1      = 0;
   `endif
   alu_outputs.addr      = next_pc;
   alu_outputs.val2      = extend (branch_target);    // For tandem verifier only

`ifdef ISA_CHERI
   alu_outputs = checkValidJump(alu_outputs, branch_taken, toCapPipe(inputs.pcc), getPCCBase(inputs.pcc), {1,scr_addr_PCC}, getPCCBase(inputs.pcc) + next_pc);
`endif

   alu_outputs.cf_info   = cf_info;
`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_OTHER (next_pc,
					   fv_trace_isize (inputs),
					   fv_trace_instr (inputs));
`endif
   return alu_outputs;
endfunction

// ----------------------------------------------------------------
// JAL

function ALU_Outputs fv_JAL (ALU_Inputs inputs);
   IntXL offset  = extend (unpack (inputs.decoded_instr.imm21_UJ));
   Addr  next_pc = pack (unpack (inputs.pc) + offset);
   Addr  ret_pc  = fall_through_pc (inputs);

   Bool misaligned_target = (next_pc [1] == 1'b1);
`ifdef ISA_C
   misaligned_target = False;
`endif

`ifdef ISA_CHERI
   let pcc_addr = getAddr(toCapPipe(inputs.pcc));
   let cf_info   = CF_Info {cf_op       : CF_JAL,
			    from_PC     : pcc_addr,
			    taken       : True,
			    fallthru_PC : pcc_addr + fall_through_pc_inc(inputs),
			    taken_PC    : pack(unpack(pcc_addr) + offset) };
`else
   let cf_info   = CF_Info {cf_op       : CF_JAL,
			    from_PC     : inputs.pc,
			    taken       : True,
			    fallthru_PC : ret_pc,
			    taken_PC    : next_pc };
`endif

   let alu_outputs = alu_outputs_base;
   alu_outputs.control   = (misaligned_target ? CONTROL_TRAP : CONTROL_BRANCH);
   alu_outputs.exc_code  = exc_code_INSTR_ADDR_MISALIGNED;
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.addr      = next_pc;
   alu_outputs.val1      = extend (ret_pc);
   alu_outputs.cf_info   = cf_info;

`ifdef ISA_CHERI
   alu_outputs = checkValidJump(alu_outputs, True, toCapPipe(inputs.pcc), getPCCBase(inputs.pcc), {1,scr_addr_PCC}, getPCCBase(inputs.pcc) + next_pc);
`endif

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (next_pc,
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  ret_pc);
`endif
   return alu_outputs;
endfunction

// ----------------------------------------------------------------
// JALR

function ALU_Outputs fv_JALR (ALU_Inputs inputs);
   let rs1_val = inputs.rs1_val;
   let rs2_val = inputs.rs2_val;

   // Signed versions of rs1_val and rs2_val
   IntXL s_rs1_val = unpack (rs1_val);
   IntXL s_rs2_val = unpack (rs2_val);
   IntXL offset    = extend (unpack (inputs.decoded_instr.imm12_I));
   Addr  next_pc   = pack (s_rs1_val + offset);
   Addr  ret_pc    = fall_through_pc (inputs);

   // next_pc [0] should be cleared
   next_pc [0] = 1'b0;

   Bool misaligned_target = (next_pc [1] == 1'b1);
`ifdef ISA_C
   misaligned_target = False;
`endif

`ifdef ISA_CHERI
   let pcc_addr = getAddr(toCapPipe(inputs.pcc));
   let target_addr = getPCCBase(inputs.pcc) + next_pc;
   let cf_info   = CF_Info {cf_op       : CF_JALR,
			    from_PC     : pcc_addr,
			    taken       : True,
			    fallthru_PC : pcc_addr + fall_through_pc_inc(inputs),
			    taken_PC    : target_addr };
`else
   let cf_info   = CF_Info {cf_op       : CF_JALR,
			    from_PC     : inputs.pc,
			    taken       : True,
			    fallthru_PC : ret_pc,
			    taken_PC    : next_pc };
`endif

   let alu_outputs = alu_outputs_base;
   alu_outputs.control   = (misaligned_target ? CONTROL_TRAP : CONTROL_BRANCH);
   alu_outputs.exc_code  = exc_code_INSTR_ADDR_MISALIGNED;
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.addr      = next_pc;
   alu_outputs.val1      = extend (ret_pc);
   alu_outputs.cf_info   = cf_info;

`ifdef ISA_CHERI
   alu_outputs = checkValidJump(alu_outputs, True, toCapPipe(inputs.pcc), getPCCBase(inputs.pcc), {1,scr_addr_PCC}, target_addr);
`endif

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (next_pc,
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  ret_pc);
`endif
   return alu_outputs;
endfunction

// ----------------------------------------------------------------
// Integer Register-Register and Register-Immediate Instructions

// ----------------
// Shifts (funct3 == f3_SLLI/ f3_SRLI/ f3_SRAI)

function ALU_Outputs fv_OP_and_OP_IMM_shifts (ALU_Inputs inputs);
   let rs1_val = inputs.rs1_val;
   let rs2_val = inputs.rs2_val;

   IntXL s_rs1_val = unpack (rs1_val);    // Signed version of rs1, for SRA

   Bit #(TLog #(XLEN)) shamt = (  (inputs.decoded_instr.opcode == op_OP_IMM)
				? truncate (inputs.decoded_instr.imm12_I)
				: truncate (rs2_val));
   WordXL   rd_val    = ?;
   let      funct3    = inputs.decoded_instr.funct3;
   Bit #(1) instr_b30 = inputs.instr [30];

`ifdef SHIFT_BARREL
   // Shifts implemented by Verilog synthesis,
   // mapping to barrel shifters
   if (funct3 == f3_SLLI)
      rd_val = (rs1_val << shamt);
   else begin // assert: (funct3 == f3_SRxI)
      if (instr_b30 == 1'b0)
	 // SRL/SRLI
	 rd_val = (rs1_val >> shamt);
      else
	 // SRA/SRAI
	 rd_val = pack (s_rs1_val >> shamt);
   end
`endif

`ifdef SHIFT_MULT
   // Shifts implemented using multiplication by 2^shamt,
   // mapping to DSPs in FPGA
   if (funct3 == f3_SLLI)
      rd_val = fn_shl (rs1_val, shamt);  // in LUTRAMs/DSPs
   else begin // assert: (funct3 == f3_SRxI)
      if (instr_b30 == 1'b0) 
	 // SRL/SRLI
	 rd_val = fn_shrl (rs1_val, shamt);  // in LUTRAMs/DSPs
      else
	 // SRA/SRAI
	 rd_val = fn_shra (rs1_val, shamt);     // in LUTRAMs/DSPs
   end
`endif

   // Trap in RV32 if shamt > 31, i.e., if imm12_I [5] is 1
   Bool trap = ((rv_version == RV32) && (inputs.decoded_instr.imm12_I [5] == 1));

   let alu_outputs       = alu_outputs_base;
   alu_outputs.control   = (trap ? CONTROL_TRAP : CONTROL_STRAIGHT);
   alu_outputs.rd        = inputs.decoded_instr.rd;

`ifndef SHIFT_SERIAL
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.val1      = rd_val;
`else
   // Will be executed in serial Shifter_Box later
   alu_outputs.op_stage2 = OP_Stage2_SH;
   alu_outputs.val1      = rs1_val;
   // Encode 'arith-shift' in bit [7] of val2
   WordXL val2 = extend (shamt);
   val2 = (val2 | { 0, instr_b30, 7'b0});
   alu_outputs.val2 = val2;
   alu_outputs.val1_fast = alu_outputs.val1;
   alu_outputs.val2_fast = alu_outputs.val2;
`endif

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  rd_val);
`endif
   return alu_outputs;
endfunction: fv_OP_and_OP_IMM_shifts

// ----------------
// Remaining OP and OP_IMM (excluding shifts, M ops MUL/DIV/REM)

function ALU_Outputs fv_OP_and_OP_IMM (ALU_Inputs inputs);
   let rs1_val = inputs.rs1_val;
   let rs2_val = inputs.rs2_val;

   // Signed versions of rs1_val and rs2_val
   IntXL  s_rs1_val = unpack (rs1_val);
   IntXL  s_rs2_val = unpack (rs2_val);

   IntXL  s_rs2_val_local = s_rs2_val;
   WordXL rs2_val_local   = rs2_val;

   Bit #(1) instr_b30  = inputs.instr [30];
   Bool     subtract   = ((inputs.decoded_instr.opcode == op_OP) && (instr_b30 == 1'b1));

   if (inputs.decoded_instr.opcode == op_OP_IMM) begin
      s_rs2_val_local = extend (unpack (inputs.decoded_instr.imm12_I));
      rs2_val_local   = pack (s_rs2_val_local);
   end

   let  funct3 = inputs.decoded_instr.funct3;
   Bool trap   = False;
   WordXL rd_val = ?;

   if      ((funct3 == f3_ADDI) && (! subtract)) rd_val = pack (s_rs1_val + s_rs2_val_local);
   else if ((funct3 == f3_ADDI) && (subtract))   rd_val = pack (s_rs1_val - s_rs2_val_local);

   else if (funct3 == f3_SLTI)  rd_val = ((s_rs1_val < s_rs2_val_local) ? 1 : 0);
   else if (funct3 == f3_SLTIU) rd_val = ((rs1_val  < rs2_val_local)  ? 1 : 0);
   else if (funct3 == f3_XORI)  rd_val = pack (s_rs1_val ^ s_rs2_val_local);
   else if (funct3 == f3_ORI)   rd_val = pack (s_rs1_val | s_rs2_val_local);
   else if (funct3 == f3_ANDI)  rd_val = pack (s_rs1_val & s_rs2_val_local);
   else
      trap = True;

   let alu_outputs       = alu_outputs_base;
   alu_outputs.control   = (trap ? CONTROL_TRAP : CONTROL_STRAIGHT);
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.val1      = rd_val;

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  rd_val);
`endif
   return alu_outputs;
endfunction: fv_OP_and_OP_IMM

// ----------------
// OP_IMM_32 (ADDIW, SLLIW, SRxIW)

function ALU_Outputs fv_OP_IMM_32 (ALU_Inputs inputs);
   WordXL   rs1_val     = inputs.rs1_val;
   IntXL    s_rs1_val   = unpack (rs1_val);

   Bit #(5) shamt       = truncate (inputs.decoded_instr.imm12_I);
   Bool     shamt5_is_0 = (inputs.instr [25] == 1'b0);

   let    funct3 = inputs.decoded_instr.funct3;
   Bool   trap   = False;
   WordXL rd_val = ?;

   if (funct3 == f3_ADDIW) begin
      IntXL  s_rs2_val = extend (unpack (inputs.decoded_instr.imm12_I));
      IntXL  sum       = s_rs1_val + s_rs2_val;
      WordXL tmp       = pack (sum);
      rd_val           = signExtend (tmp [31:0]);
   end
   else if ((funct3 == f3_SLLIW) && shamt5_is_0) begin
      Bit #(32) tmp = truncate (rs1_val);
      rd_val = signExtend (tmp << shamt);
   end
   else if ((funct3 == f3_SRxIW) && shamt5_is_0) begin
      Bit #(1) instr_b30 = inputs.instr [30];
      if (instr_b30 == 1'b0) begin
	 // SRLIW
	 Bit #(32) tmp = truncate (rs1_val);
	 rd_val = signExtend (tmp >> shamt);
      end
      else begin
	 // SRAIW
	 Int #(32) s_tmp = unpack (rs1_val [31:0]);
	 Bit #(32) tmp   = pack (s_tmp >> shamt);
	 rd_val = signExtend (tmp);
      end
   end
   else
      trap = True;

   let alu_outputs       = alu_outputs_base;
   alu_outputs.control   = (trap ? CONTROL_TRAP : CONTROL_STRAIGHT);
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.val1      = rd_val;

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  rd_val);
`endif
   return alu_outputs;
endfunction: fv_OP_IMM_32

// ----------------
// OP_32 (excluding 'M' ops: MULW/ DIVW/ DIVUW/ REMW/ REMUW)

function ALU_Outputs fv_OP_32 (ALU_Inputs inputs);
   Bit #(32) rs1_val = inputs.rs1_val [31:0];
   Bit #(32) rs2_val = inputs.rs2_val [31:0];

   // Signed version of rs1_val and rs2_val
   Int #(32) s_rs1_val = unpack (rs1_val);
   Int #(32) s_rs2_val = unpack (rs2_val);

   let    funct10 = inputs.decoded_instr.funct10;
   Bool   trap   = False;
   WordXL rd_val = ?;

   if      (funct10 == f10_ADDW) begin
      rd_val = pack (signExtend (s_rs1_val + s_rs2_val));
   end
   else if (funct10 == f10_SUBW) begin
      rd_val = pack (signExtend (s_rs1_val - s_rs2_val));
   end
   else if (funct10 == f10_SLLW) begin
      rd_val = pack (signExtend (rs1_val << (rs2_val [4:0])));
   end
   else if (funct10 == f10_SRLW) begin
      rd_val = pack (signExtend (rs1_val >> (rs2_val [4:0])));
   end
   else if (funct10 == f10_SRAW) begin
      rd_val = pack (signExtend (s_rs1_val >> (rs2_val [4:0])));
   end
   else
      trap = True;

   let alu_outputs       = alu_outputs_base;
   alu_outputs.control   = (trap ? CONTROL_TRAP : CONTROL_STRAIGHT);
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.val1      = rd_val;

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  rd_val);
`endif
   return alu_outputs;
endfunction: fv_OP_32

// ----------------------------------------------------------------
// Upper Immediates

function ALU_Outputs fv_LUI (ALU_Inputs inputs);
   Bit #(32)  v32    = { inputs.decoded_instr.imm20_U, 12'h0 };
   IntXL      iv     = extend (unpack (v32));
   let        rd_val = pack (iv);

   let alu_outputs       = alu_outputs_base;
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.val1      = rd_val;

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  rd_val);
`endif
   return alu_outputs;
endfunction

function ALU_Outputs fv_AUIPC (ALU_Inputs inputs);
   IntXL  iv     = extend (unpack ({ inputs.decoded_instr.imm20_U, 12'b0}));
   IntXL  pc_s   = unpack (inputs.pc);
   WordXL rd_val = pack (pc_s + iv);

   let alu_outputs       = alu_outputs_base;
   alu_outputs.op_stage2 = OP_Stage2_ALU;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.val1      = rd_val;

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
					  fv_trace_isize (inputs),
					  fv_trace_instr (inputs),
					  inputs.decoded_instr.rd,
					  rd_val);
`endif
   return alu_outputs;
endfunction

// ----------------------------------------------------------------
// LOAD

function ALU_Outputs fv_LD (ALU_Inputs inputs, Maybe#(Bit#(3)) size);
   // Signed versions of rs1_val and rs2_val
   let opcode = inputs.decoded_instr.opcode;
   IntXL s_rs1_val = unpack (inputs.rs1_val);
   IntXL s_rs2_val = unpack (inputs.rs2_val);

   IntXL  imm_s = extend (unpack (inputs.decoded_instr.imm12_I));
`ifdef ISA_CHERI
   if (valueOf(XLEN) == 32 && inputs.decoded_instr.funct3 == f3_LD) size = Valid(w_SIZE_D);

   Bool cap_mode = is_cap_mode(inputs);

   let authority = cap_mode ? inputs.cap_rs1_val : inputs.ddc;
   let authorityIdx = cap_mode ? {0,inputs.rs1_idx} : {1,scr_addr_DDC};
   WordXL eaddr = cap_mode ? getAddr(inputs.cap_rs1_val) + pack(imm_s) : getAddr(inputs.ddc) + inputs.rs1_val + pack(imm_s);
`else
   WordXL eaddr = pack (s_rs1_val + imm_s);
`endif

   let funct3 = inputs.decoded_instr.funct3;

   Bool legal_LD = (
           isValid(size)
        || (funct3 == f3_LB) || (funct3 == f3_LBU)
		    || (funct3 == f3_LH) || (funct3 == f3_LHU)
		    || (funct3 == f3_LW)
`ifdef RV64
		    || (funct3 == f3_LWU)
		    || (funct3 == f3_LD)
`endif
`ifdef ISA_F
		    || (funct3 == f3_FLW)
`endif
`ifdef ISA_D
		    || (funct3 == f3_FLD)
`endif
		    );

   // FP loads are not legal unless the MSTATUS.FS bit is set
   Bool legal_FP_LD = True;
`ifdef ISA_F
   if (opcode == op_LOAD_FP)
      legal_FP_LD = (fv_mstatus_fs (inputs.mstatus) != fs_xs_off);
`endif

   let alu_outputs = alu_outputs_base;

   let width_code = fromMaybe({0,funct3[1:0]}, size);

   alu_outputs.control   = ((legal_LD && legal_FP_LD) ? CONTROL_STRAIGHT
                                                      : CONTROL_TRAP);
   alu_outputs.op_stage2 = OP_Stage2_LD;
   alu_outputs.rd        = inputs.decoded_instr.rd;
   alu_outputs.addr      = eaddr;
   alu_outputs.mem_width_code = width_code;
   alu_outputs.mem_unsigned = unpack(funct3[2]);
`ifdef ISA_F
   // note that the destination register for this load is in the FPR
   alu_outputs.rd_in_fpr = (opcode == op_LOAD_FP);
`endif

`ifdef ISA_CHERI
   alu_outputs = checkValidDereference(alu_outputs, authority, authorityIdx, eaddr, width_code, False, True, ?);
`endif

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
`ifdef ISA_F
   if (alu_outputs.rd_in_fpr)
      alu_outputs.trace_data = mkTrace_F_LOAD (fall_through_pc (inputs),
					       fv_trace_isize (inputs),
					       fv_trace_instr (inputs),
					       inputs.decoded_instr.rd,
					       ?,
					       eaddr,
                                               inputs.mstatus);
   else
`endif
      alu_outputs.trace_data = mkTrace_I_LOAD (fall_through_pc (inputs),
					       fv_trace_isize (inputs),
					       fv_trace_instr (inputs),
					       inputs.decoded_instr.rd,
					       ?,
					       eaddr);
`endif
   return alu_outputs;
endfunction

// ----------------------------------------------------------------
// STORE

function ALU_Outputs fv_ST (ALU_Inputs inputs);
   // Signed version of rs1_val
   IntXL  s_rs1_val = unpack (inputs.rs1_val);
   IntXL  imm_s     = extend (unpack (inputs.decoded_instr.imm12_S));
`ifdef ISA_CHERI
   Bool cap_mode = is_cap_mode(inputs);

   let authority = cap_mode ? inputs.cap_rs1_val : inputs.ddc;
   let authorityIdx = cap_mode ? {0,inputs.rs1_idx} : {1,scr_addr_DDC};
   WordXL eaddr = cap_mode ? getAddr(inputs.cap_rs1_val) + pack(imm_s) : getAddr(inputs.ddc) + inputs.rs1_val + pack(imm_s);
`else
   WordXL eaddr = pack (s_rs1_val + imm_s);
`endif

   let opcode = inputs.decoded_instr.opcode;
   let funct3 = inputs.decoded_instr.funct3;
   Bool legal_ST = (   (funct3 == f3_SB)
		    || (funct3 == f3_SH)
		    || (funct3 == f3_SW)
`ifdef ISA_CHERI
`ifdef RV64
        || (funct3 == f3_SQ)
`else
        || (funct3 == f3_SD)
`endif
`endif
`ifdef RV64
		    || (funct3 == f3_SD)
`endif
`ifdef ISA_F
		    || (funct3 == f3_FSW)
`endif
`ifdef ISA_D
		    || (funct3 == f3_FSD)
`endif
		    );

   let alu_outputs = alu_outputs_base;

   // FP stores are not legal unless the MSTATUS.FS bit is set
   Bool legal_FP_ST = True;
`ifdef ISA_F
   if (opcode == op_STORE_FP) begin
      legal_FP_ST = (fv_mstatus_fs (inputs.mstatus) != fs_xs_off);

      // note that the source data register for this store is in the FPR
      alu_outputs.rs_frm_fpr = True;
   end
`endif

   let width_code = funct3;

   alu_outputs.control   = ((legal_ST && legal_FP_ST) ? CONTROL_STRAIGHT
                                                      : CONTROL_TRAP);
   alu_outputs.op_stage2 = OP_Stage2_ST;
   alu_outputs.addr      = eaddr;
   alu_outputs.mem_width_code = width_code;
   alu_outputs.mem_unsigned = False;

`ifdef ISA_CHERI
   alu_outputs = checkValidDereference(alu_outputs, authority, authorityIdx, eaddr, width_code, True, False, inputs.cap_rs2_val);
`endif

   alu_outputs.val2      = inputs.rs2_val;

`ifdef ISA_CHERI
   alu_outputs.cap_val2      = inputs.cap_rs2_val;
   alu_outputs.val2_cap_not_int = width_code == w_SIZE_CAP;
`endif

`ifdef ISA_F
   alu_outputs.fval2     = inputs.frs2_val;
`endif

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
`ifdef ISA_F
   if (opcode == op_STORE_FP)
      alu_outputs.trace_data = mkTrace_F_STORE (fall_through_pc (inputs),
						funct3,
						fv_trace_isize (inputs),
						fv_trace_instr (inputs),
						alu_outputs.fval2,
						eaddr);
   else
`endif
      alu_outputs.trace_data = mkTrace_I_STORE (fall_through_pc (inputs),
						funct3,
						fv_trace_isize (inputs),
						fv_trace_instr (inputs),
						(alu_outputs.val2),
						eaddr);
`endif
   return alu_outputs;
endfunction

// ----------------------------------------------------------------
// MISC_MEM (FENCE and FENCE.I)
// No-ops, for now

function ALU_Outputs fv_MISC_MEM (ALU_Inputs inputs);
`ifdef ISA_CHERI
   if (valueOf(XLEN) == 64 && inputs.decoded_instr.funct3 == f3_LQ) begin
       return fv_LD(inputs, Valid(w_SIZE_Q));
   end else
`endif
   begin
       let alu_outputs = alu_outputs_base;
       alu_outputs.control  = (  (inputs.decoded_instr.funct3 == f3_FENCE_I)
			       ? CONTROL_FENCE_I
			       : (  (inputs.decoded_instr.funct3 == f3_FENCE)
			          ? CONTROL_FENCE
			          : CONTROL_TRAP));

`ifdef INCLUDE_TANDEM_VERIF
       // Normal trace output (if no trap)
       alu_outputs.trace_data = mkTrace_OTHER (fall_through_pc (inputs),
					       fv_trace_isize (inputs),
					       fv_trace_instr (inputs));
`endif
       return alu_outputs;
   end
endfunction

// ----------------------------------------------------------------
// System instructions

function ALU_Outputs fv_SYSTEM (ALU_Inputs inputs);
   let funct3      = inputs.decoded_instr.funct3;
   let alu_outputs = alu_outputs_base;

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_OTHER (fall_through_pc (inputs),
					   fv_trace_isize (inputs),
					   fv_trace_instr (inputs));
`endif

   if (funct3  == f3_PRIV) begin
`ifdef ISA_PRIV_S
      // SFENCE.VMA instruction
      if (   (inputs.decoded_instr.rd  == 0)
	  && (   (inputs.cur_priv == m_Priv_Mode)
	      || (   (inputs.cur_priv == s_Priv_Mode)
		  && (inputs.mstatus [mstatus_tvm_bitpos] == 0)))
	  && (inputs.decoded_instr.funct7 == f7_SFENCE_VMA))
	 begin
	    alu_outputs.control = CONTROL_SFENCE_VMA;
	 end
      else
`endif
      if (   (inputs.decoded_instr.rd  == 0)
	  && (inputs.decoded_instr.rs1 == 0))
	 begin
	    // ECALL instructions
	    if (inputs.decoded_instr.imm12_I == f12_ECALL) begin
	       alu_outputs.control  = CONTROL_TRAP;
	       alu_outputs.exc_code = ((inputs.cur_priv == u_Priv_Mode)
				       ? exc_code_ECALL_FROM_U
				       : ((inputs.cur_priv == s_Priv_Mode)
					  ? exc_code_ECALL_FROM_S
					  : exc_code_ECALL_FROM_M));
	    end

	    // EBREAK instruction
	    else if (inputs.decoded_instr.imm12_I == f12_EBREAK) begin
	       alu_outputs.control  = CONTROL_TRAP;
	       alu_outputs.exc_code = exc_code_BREAKPOINT;
	    end

	    // MRET instruction
	    else if (   (inputs.cur_priv >= m_Priv_Mode)
		     && (inputs.decoded_instr.imm12_I == f12_MRET))
	       begin
                  if (getHardPerms(toCapPipe(inputs.pcc)).accessSysRegs) begin
                     alu_outputs.control = CONTROL_MRET;
                  end else begin
                     alu_outputs.control = CONTROL_TRAP;
                     alu_outputs.exc_code = exc_code_CHERI;
                     alu_outputs.cheri_exc_code = exc_code_CHERI_SysRegsPerm;
                     alu_outputs.cheri_exc_reg = {1'b1, scr_addr_PCC};
                  end
	       end

`ifdef ISA_PRIV_S
	    // SRET instruction
	    else if (   (   (inputs.cur_priv == m_Priv_Mode)
			 || (   (inputs.cur_priv == s_Priv_Mode)
			     && (inputs.mstatus [mstatus_tsr_bitpos] == 0)))
		     && (inputs.decoded_instr.imm12_I == f12_SRET))
	       begin
                  if (getHardPerms(toCapPipe(inputs.pcc)).accessSysRegs) begin
                     alu_outputs.control = CONTROL_SRET;
                  end else begin
                     alu_outputs.control = CONTROL_TRAP;
                     alu_outputs.exc_code = exc_code_CHERI;
                     alu_outputs.cheri_exc_code = exc_code_CHERI_SysRegsPerm;
                     alu_outputs.cheri_exc_reg = {1'b1, scr_addr_PCC};
                  end
	       end
`endif

	    /*
	    // URET instruction (future: Piccolo does not support 'N' extension)
	    else if (   (inputs.cur_priv >= u_Priv_Mode)
		     && (inputs.decoded_instr.imm12_I == f12_URET))
	       begin
		  alu_outputs.control = CONTROL_URET;
	       end
	    */

	    // WFI instruction
	    else if (   (   (inputs.cur_priv == m_Priv_Mode)
			 || (   (inputs.cur_priv == s_Priv_Mode)
			     && (inputs.mstatus [mstatus_tw_bitpos] == 0))
			 || (   (inputs.cur_priv == u_Priv_Mode)
			     && (inputs.misa.n == 1)))
		     && (inputs.decoded_instr.imm12_I == f12_WFI))
	       begin
		  alu_outputs.control = CONTROL_WFI;
	       end

	    else begin
	       alu_outputs.control = CONTROL_TRAP;
	    end
	 end

      else begin
	 alu_outputs.control = CONTROL_TRAP;
      end
   end    // funct3 is f3_PRIV

   // CSRRW, CSRRWI
   else if (f3_is_CSRR_W (funct3)) begin
      WordXL rs1_val = (  (funct3 [2] == 1)
			? extend (inputs.decoded_instr.rs1)    // Immediate zimm
			: inputs.rs1_val);                     // From rs1 reg

      alu_outputs.control   = CONTROL_CSRR_W;
      alu_outputs.val1      = rs1_val;
   end

   // CSRRS, CSRRSI, CSRRC, CSRRCI
   else if (f3_is_CSRR_S_or_C (funct3)) begin
      WordXL rs1_val = (  (funct3 [2] == 1)
			? extend (inputs.decoded_instr.rs1)    // Immediate zimm
			: inputs.rs1_val);                     // From rs1 reg

      alu_outputs.control   = CONTROL_CSRR_S_or_C;
      alu_outputs.val1      = rs1_val;
   end

   // funct3 is not f3_PRIV
   else begin // (funct3 == f3_SYSTEM_ILLEGAL)
      alu_outputs.control = CONTROL_TRAP;
   end

   return alu_outputs;
endfunction: fv_SYSTEM

// ----------------------------------------------------------------
// FP Ops
// Just pass through to the FP stage

`ifdef ISA_F
function ALU_Outputs fv_FP (ALU_Inputs inputs);
   let opcode = inputs.decoded_instr.opcode;
   let funct3 = inputs.decoded_instr.funct3;
   let funct7 = inputs.decoded_instr.funct7;
   let rs2    = inputs.decoded_instr.rs2;

   // Check instruction legality
   // Is the rounding mode legal
   match {.rm, .rm_is_legal} = fv_rmode_check  (funct3, inputs.frm);

   // Is the instruction legal -- if MSTATUS.FS = fs_xs_off, FP instructions
   // are always illegal
   let inst_is_legal = (  (fv_mstatus_fs (inputs.mstatus) == fs_xs_off)
			? False
			: fv_is_fp_instr_legal (funct7,
						rm,
						rs2,
						opcode));

   let alu_outputs         = alu_outputs_base;
   alu_outputs.control     = ((inst_is_legal && rm_is_legal) ? CONTROL_STRAIGHT
			                                     : CONTROL_TRAP);
   alu_outputs.op_stage2   = OP_Stage2_FD;
   alu_outputs.rd          = inputs.decoded_instr.rd;
   alu_outputs.rm          = rm;

   // Operand values
   // The first operand may be from the FPR or GPR
   alu_outputs.val1_frm_gpr= fv_fp_val1_from_gpr (opcode, funct7, rs2);

   // Just copy the rs1_val values from inputs to outputs this covers cases
   // whenever val1 is from GPR
   alu_outputs.val1     = inputs.rs1_val;
   alu_outputs.val1_fast = alu_outputs.val1;

   // Just copy the frs*_val values from inputs to outputs
   alu_outputs.fval1     = inputs.frs1_val;
   alu_outputs.fval2     = inputs.frs2_val;
   alu_outputs.fval3     = inputs.frs3_val;

   alu_outputs.rd_in_fpr = !fv_is_rd_in_GPR (funct7, rs2);

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   if (alu_outputs.rd_in_fpr)
      alu_outputs.trace_data = mkTrace_F_FRD (fall_through_pc (inputs),
					      fv_trace_isize (inputs),
					      fv_trace_instr (inputs),
					      inputs.decoded_instr.rd,
					      ?,
					      inputs.fflags,
					      inputs.mstatus);
   else
      alu_outputs.trace_data = mkTrace_F_GRD (fall_through_pc (inputs),
					      fv_trace_isize (inputs),
					      fv_trace_instr (inputs),
					      inputs.decoded_instr.rd,
					      ?,
					      inputs.fflags,
					      inputs.mstatus);
`endif
   return alu_outputs;
endfunction
`endif

// ----------------------------------------------------------------
// AMO
// Just pass through to the memory stage

`ifdef ISA_A
function ALU_Outputs fv_AMO (ALU_Inputs inputs);
   IntXL  s_rs1_val = unpack (inputs.rs1_val);
`ifdef ISA_CHERI
   Bool cap_mode = is_cap_mode(inputs);

   let authority = cap_mode ? inputs.cap_rs1_val : inputs.ddc;
   let authorityIdx = cap_mode ? {0,inputs.rs1_idx} : {1,scr_addr_DDC};
   WordXL eaddr = cap_mode ? getAddr(inputs.cap_rs1_val) : getAddr(inputs.ddc) + inputs.rs1_val;
`else
   WordXL eaddr = pack (s_rs1_val);
`endif

   let funct3 = inputs.decoded_instr.funct3;
   let funct5 = inputs.decoded_instr.funct5;
   let funct7 = inputs.decoded_instr.funct7;

   Bool legal_f5 = (   (funct5 == f5_AMO_LR)   || (funct5 == f5_AMO_SC)

		    || (funct5 == f5_AMO_ADD)
		    || (funct5 == f5_AMO_SWAP)

		    || (funct5 == f5_AMO_AND)  || (funct5 == f5_AMO_OR) || (funct5 == f5_AMO_XOR)

		    || (funct5 == f5_AMO_MIN)  || (funct5 == f5_AMO_MINU)
		    || (funct5 == f5_AMO_MAX)  || (funct5 == f5_AMO_MAXU));

   // TODO: Cap width
   Bool legal_width = (   (funct3 == f3_AMO_W)
`ifdef ISA_CHERI
                     || (((funct5 == f5_AMO_LR) || (funct5 == f5_AMO_SC) || (funct5 == f5_AMO_SWAP)) && (funct3 == f3_AMO_CAP))
                     || (((funct5 == f5_AMO_LR)   || (funct5 == f5_AMO_SC)) &&
                          (funct3 == f3_AMO_H
                       || (funct3 == f3_AMO_B)))
`endif
		       || ((xlen == 64) && (funct3 == f3_AMO_D)) );

   let alu_outputs = alu_outputs_base;

   let width_code = funct3;

   alu_outputs.control   = ((legal_f5 && legal_width) ? CONTROL_STRAIGHT : CONTROL_TRAP);
   alu_outputs.op_stage2 = OP_Stage2_AMO;
   alu_outputs.addr      = eaddr;
   alu_outputs.mem_width_code = width_code;
   alu_outputs.mem_unsigned = False;

   alu_outputs = checkValidDereference(alu_outputs, authority, authorityIdx, eaddr, width_code, funct5 != f5_AMO_LR, funct5 != f5_AMO_SC, inputs.cap_rs2_val);

   alu_outputs.val1      = zeroExtend (inputs.decoded_instr.funct7);

`ifdef ISA_CHERI
   alu_outputs.cap_val2      = inputs.cap_rs2_val;
   alu_outputs.val2_cap_not_int = width_code == w_SIZE_CAP;
`endif

   alu_outputs.val2      = inputs.rs2_val;

`ifdef INCLUDE_TANDEM_VERIF
   // Normal trace output (if no trap)
   alu_outputs.trace_data = mkTrace_AMO (fall_through_pc (inputs),
					 funct3,
					 fv_trace_isize (inputs),
					 fv_trace_instr (inputs),
					 inputs.decoded_instr.rd, ?,
					 inputs.rs2_val,
					 eaddr);
`endif
   return alu_outputs;
endfunction
`endif

// ----------------------------------------------------------------
// CHERI
// Capability operations

`ifdef ISA_CHERI

function ALU_Outputs fv_CHERI_exc(ALU_Outputs outputs, Bit#(6) regIdx, CHERI_Exc_Code exc_code);
  outputs.exc_code = exc_code_CHERI;
  outputs.cheri_exc_code = exc_code;
  outputs.cheri_exc_reg = regIdx;
  outputs.control = CONTROL_TRAP;
  return outputs;
endfunction

function ALU_Outputs checkValidDereference(ALU_Outputs alu_outputs, CapPipe authority, Bit#(6) authIdx, WordXL base, Bit#(3) widthCode, Bool isStore, Bool isLoad, CapPipe data);
   if (!isValidCap(authority)) begin
       alu_outputs = fv_CHERI_exc(alu_outputs, authIdx, exc_code_CHERI_Tag);
   end else if (getKind(authority) != UNSEALED) begin
       alu_outputs = fv_CHERI_exc(alu_outputs, authIdx, exc_code_CHERI_Seal);
   end else if (isLoad && !getHardPerms(authority).permitLoad) begin
       alu_outputs = fv_CHERI_exc(alu_outputs, authIdx, exc_code_CHERI_RPerm);
   end else if (isStore && !getHardPerms(authority).permitStore) begin
       alu_outputs = fv_CHERI_exc(alu_outputs, authIdx, exc_code_CHERI_WPerm);
   end else if (isStore && widthCode == w_SIZE_CAP && isValidCap(data) && !getHardPerms(authority).permitStoreCap) begin
       alu_outputs = fv_CHERI_exc(alu_outputs, authIdx, exc_code_CHERI_SCPerm);
   end else if (isStore && widthCode == w_SIZE_CAP && isValidCap(data) && !getHardPerms(data).global && !getHardPerms(authority).permitStoreLocalCap) begin
       alu_outputs = fv_CHERI_exc(alu_outputs, authIdx, exc_code_CHERI_SCLocalPerm);
   end
   alu_outputs.check_enable = True;
   alu_outputs.check_authority = authority;
   alu_outputs.check_authority_idx = authIdx;
   alu_outputs.check_address_low = base;
   alu_outputs.check_address_high = zeroExtend(base) + (1 << widthCode);

   //TODO check alignment?
   if (widthCode == w_SIZE_CAP && isLoad && getHardPerms(authority).permitLoadCap) begin
       alu_outputs.mem_allow_cap = True;
   end
   return alu_outputs;
endfunction

function ALU_Outputs checkValidJump(ALU_Outputs alu_outputs, Bool branchTaken, CapPipe authority, WordXL authority_base, Bit#(6) authIdx, WordXL target);
   //Note that we only check the first two bytes of the target instruction are in bounds in the jump.
`ifdef ISA_C
   Bool misaligned_target = authority_base[0] != 1'b0;
`else
   Bool misaligned_target = (target [1] == 1'b1) || (authority_base[1:0] != 2'b0);
`endif
   if (misaligned_target && branchTaken) begin
       alu_outputs.control = CONTROL_TRAP;
       alu_outputs.exc_code = exc_code_INSTR_ADDR_MISALIGNED;
   end
   alu_outputs.check_enable = branchTaken;
   alu_outputs.check_authority = authority;
   alu_outputs.check_authority_idx = authIdx;
   alu_outputs.check_address_low = target;
   alu_outputs.check_address_high = zeroExtend(target) + 2;
   return alu_outputs;
endfunction

function ALU_Outputs memCommon(ALU_Outputs alu_outputs, Bool isStoreNotLoad, Bool isUnsignedNotSigned, Bool useDDC, Bit#(3) widthCode, Bool tagOnly, CapPipe ddc, CapPipe addr, Bit#(5) addrIdx, CapPipe data, Bool is_amo, Bit#(7) amo_funct7);
   let eaddr = getAddr(addr) + (useDDC ? getAddr(ddc) : 0);
   let op_stage2 = isStoreNotLoad ? OP_Stage2_ST : OP_Stage2_LD;
`ifdef ISA_A
   if (is_amo) op_stage2 = OP_Stage2_AMO;
`endif

   //width code must be checked externally

   alu_outputs.op_stage2      = op_stage2;
   alu_outputs.addr           = eaddr;
   alu_outputs.mem_width_code = widthCode;
   alu_outputs.mem_tag_only   = tagOnly;
   alu_outputs.mem_unsigned   = isStoreNotLoad ? False : isUnsignedNotSigned;
   alu_outputs.val1           = zeroExtend(amo_funct7);
   alu_outputs.val2           = zeroExtend(getAddr(data)); //for stores
   alu_outputs.cap_val2       = data;
   alu_outputs.val2_cap_not_int = widthCode == w_SIZE_CAP && !tagOnly;

   let authority = useDDC ? ddc : addr;
   let authorityIdx = useDDC ? {1,scr_addr_DDC} : {0,addrIdx};

   alu_outputs = checkValidDereference(alu_outputs, authority, authorityIdx, eaddr, widthCode, isStoreNotLoad, !isStoreNotLoad, data);

   return alu_outputs;
endfunction

typedef enum {
  LITERAL,
  MODIFY_OFFSET,
  SET_BOUNDS,
  SET_ADDR,
  GET_PRECISION
  } Output_Select deriving (Bits, FShow, Eq);

function ALU_Outputs fv_CHERI (ALU_Inputs inputs, WordXL ddc_base);
    let funct3  = inputs.decoded_instr.funct3;
    let funct5rs2 = inputs.decoded_instr.funct5rs2;
    let funct5rd = inputs.decoded_instr.funct5rd;
    let funct7  = inputs.decoded_instr.funct7;

    let rs2_val = inputs.rs2_val;

    let cs1_val_immutable = inputs.cap_rs1_val;
    let cs1_val_mutable = setValidCap(cs1_val_immutable, isValidCap(cs1_val_immutable) && getKind(cs1_val_immutable) == UNSEALED);

    let ddc_val_immutable = inputs.ddc;
    let ddc_val_mutable = setValidCap(ddc_val_immutable, isValidCap(ddc_val_immutable) && getKind(ddc_val_immutable) == UNSEALED);

    let cs1_base = getBase(cs1_val_mutable);
    let cs1_offset = getOffset(cs1_val_mutable);

    let cs2_val = inputs.cap_rs2_val;

    let cs2_base = getBase(cs2_val);
    let cs2_top = getTop(cs2_val);
    Bool cs2_in_bounds = isInBounds(cs2_val, False);

    let alu_outputs = alu_outputs_base;
    alu_outputs.rd = inputs.decoded_instr.rd;
    alu_outputs.op_stage2 = OP_Stage2_ALU;

    Bool jalr_enable = False;
    Bool jalr_immediate = False;
    Bool jalr_cap_mode = False;

    Output_Select val1_source = LITERAL;

    // MODIFY_OFFSET signals
    CapPipe modify_offset_cap = ?;
    WordXL  modify_offset_off_or_inc = ?;
    Bool    modify_offset_inc_not_set = ?;
    Bool    modify_offset_seal_entry = False;

    // SET_BOUNDS signals
    WordXL  set_bounds_length = ?;
    Bool    set_bounds_exact = ?;

    // SET_ADDR signals
    WordXL  set_addr_addr = ?;

    // GET_PRECISION signals
    Bool get_precision_crrl_not_cram = ?;

    let check_cs1_tagged              = False;
    let check_cs2_tagged              = False;
    let check_cs1_sealed_with_type    = False;
    let check_cs2_sealed_with_type    = False;
    let check_cs1_unsealed_or_sentry  = False;
    let check_cs1_cs2_types_match     = False;
    let check_cs1_permit_ccall        = False;
    let check_cs2_permit_ccall        = False;
    let check_cs1_permit_x            = False;
    let check_cs1_unsealed_or_imm_0   = False;
    let check_cs2_no_permit_x         = False;

    if (inputs.decoded_instr.opcode == op_AUIPC) begin
        if (is_cap_mode(inputs)) begin
            val1_source = MODIFY_OFFSET;
            modify_offset_cap = toCapPipe(inputs.pcc);
            IntXL iv = extend (unpack ({ inputs.decoded_instr.imm20_U, 12'b0}));
            modify_offset_off_or_inc = pack(iv);
            modify_offset_inc_not_set = True;
        end else begin
            alu_outputs = fv_AUIPC (inputs);
        end
    end else if (inputs.decoded_instr.opcode == op_JAL) begin
        IntXL offset   = extend (unpack (inputs.decoded_instr.imm21_UJ));
        Addr  next_pc  = pack (unpack (inputs.pc) + offset);
        Addr  ret_pc   = fall_through_pc (inputs);
        Addr  pcc_addr = getAddr(toCapPipe(inputs.pcc));

        alu_outputs.control   = CONTROL_BRANCH;

        let cf_info   = CF_Info {cf_op       : CF_JAL,
                                 from_PC     : pcc_addr,
                                 taken       : True,
                                 fallthru_PC : pcc_addr + fall_through_pc_inc(inputs),
                                 taken_PC    : pack(unpack(pcc_addr) + offset) };

        alu_outputs.addr      = next_pc;
        alu_outputs.cf_info   = cf_info;

        val1_source = is_cap_mode(inputs) ? MODIFY_OFFSET : LITERAL;
        alu_outputs.val1 = extend (ret_pc);
        modify_offset_cap = toCapPipe(inputs.pcc);
        modify_offset_off_or_inc = fall_through_pc_inc(inputs);
        modify_offset_inc_not_set = True;
        modify_offset_seal_entry = True;
        alu_outputs = checkValidJump(alu_outputs, True, toCapPipe(inputs.pcc), getPCCBase(inputs.pcc), {1,scr_addr_PCC}, getPCCBase(inputs.pcc) + next_pc);
    end else if (inputs.decoded_instr.opcode == op_JALR) begin
        jalr_enable = True;
        jalr_immediate = True;
        jalr_cap_mode = is_cap_mode(inputs);
    end else begin
        case (funct3)
        f3_cap_CIncOffsetImmediate: begin
             val1_source = MODIFY_OFFSET;
             modify_offset_cap = cs1_val_mutable;
             modify_offset_off_or_inc = signExtend(inputs.decoded_instr.imm12_I);
             modify_offset_inc_not_set = True;
        end
        f3_cap_CSetBoundsImmediate: begin
            val1_source = SET_BOUNDS;
            set_bounds_length = zeroExtend(inputs.decoded_instr.imm12_I);
            set_bounds_exact = False;
        end
        f3_cap_ThreeOp: begin
            case (funct7)
            f7_cap_CSpecialRW: begin
                if (inputs.decoded_instr.rs2 == scr_addr_PCC && inputs.decoded_instr.rs1 == 0) begin
                    alu_outputs.cap_val1 = toCapPipe(inputs.pcc);
                    alu_outputs.val1_cap_not_int = True;
                end else if (inputs.decoded_instr.rs2 == scr_addr_DDC && inputs.decoded_instr.rs1 == 0) begin
                    alu_outputs.cap_val1 = ddc_val_immutable;
                    alu_outputs.val1_cap_not_int = True;
                end else begin
                    CapPipe rs1_val = inputs.cap_rs1_val;

                    alu_outputs.control   = CONTROL_SCR_W;
                    alu_outputs.cap_val1  = rs1_val;
                    alu_outputs.val1_cap_not_int = True;
                end
            end
            f7_cap_CSetBounds: begin
                val1_source = SET_BOUNDS;
                set_bounds_length = rs2_val;
                set_bounds_exact = False;
            end
            f7_cap_CSetBoundsExact: begin
                val1_source = SET_BOUNDS;
                set_bounds_length = rs2_val;
                set_bounds_exact = True;
            end
            f7_cap_CSetOffset: begin
                val1_source = MODIFY_OFFSET;
                modify_offset_cap = cs1_val_mutable;
                modify_offset_off_or_inc = rs2_val;
                modify_offset_inc_not_set = False;
            end
            f7_cap_CSetAddr: begin
                val1_source = SET_ADDR;
                set_addr_addr = rs2_val;
            end
            f7_cap_CIncOffset: begin
                val1_source = MODIFY_OFFSET;
                modify_offset_cap = cs1_val_mutable;
                modify_offset_off_or_inc = rs2_val;
                modify_offset_inc_not_set = True;
            end
            f7_cap_CSeal: begin
                CapPipe result = setKind(cs1_val_mutable, SEALED_WITH_TYPE(truncate(getAddr(cs2_val))));
                Bool permitted =    (isValidCap(cs2_val))
                                 && (getKind(cs2_val) == UNSEALED)
                                 && (getHardPerms(cs2_val).permitSeal)
                                 && (cs2_in_bounds)
                                 && (validAsType(cs2_val, truncate(getAddr(cs2_val))));
                alu_outputs.cap_val1 = setValidCap(result, isValidCap(result) && permitted);
                alu_outputs.val1_cap_not_int = True;
            end
            f7_cap_CCSeal: begin
                alu_outputs.val1_cap_not_int = True;
                if (   (! isValidCap(cs2_val))
                    || (getAddr(cs2_val) == otype_unsealed_ext)
                    || (getKind(cs1_val_mutable) != UNSEALED)
                    || (! cs2_in_bounds)) begin
                    alu_outputs.cap_val1 = cs1_val_immutable;
                end else begin
                    CapPipe result = setKind(cs1_val_mutable, SEALED_WITH_TYPE(truncate(getAddr(cs2_val))));
                    Bool permitted =    (getKind(cs2_val) == UNSEALED)
                                     && (getHardPerms(cs2_val).permitSeal)
                                     && (validAsType(cs2_val, truncate(getAddr(cs2_val))));
                    alu_outputs.cap_val1 = setValidCap(result, isValidCap(result) && permitted);
                end
            end
            f7_cap_TwoSrc: begin
                case (inputs.decoded_instr.rd)
                    rd_cap_CCall: begin
                        check_cs1_tagged = True;
                        check_cs2_tagged = True;
                        check_cs1_sealed_with_type = True;
                        check_cs2_sealed_with_type = True;
                        check_cs1_cs2_types_match = True;
                        check_cs1_permit_x = True;
                        check_cs2_no_permit_x = True;
                        check_cs1_permit_ccall = True;
                        check_cs2_permit_ccall = True;
                        alu_outputs.val1_cap_not_int = True;
                        alu_outputs.cap_val1 = setKind(cs2_val, UNSEALED);
                        alu_outputs.rd = cCallRD;
                        alu_outputs.pcc = fromCapPipe(maskAddr(setKind(cs1_val_immutable, UNSEALED), signExtend(2'b10)));
                        alu_outputs.control = CONTROL_CAPBRANCH;
                        let target = {truncateLSB(getAddr(cs1_val_immutable)), 1'b0};
                        alu_outputs = checkValidJump(alu_outputs, True, cs1_val_immutable, cs1_base, zeroExtend(inputs.rs1_idx), target);
                    end
                    default: alu_outputs.control = CONTROL_TRAP;
                endcase
            end
            f7_cap_CUnseal: begin
                CapPipe result = setKind(cs1_val_mutable, UNSEALED);
                let perms = getHardPerms(cs1_val_mutable);
                perms.global = perms.global && getHardPerms(cs2_val).global;
                result = setHardPerms(result, perms);
                Bool permitted =    (isValidCap(cs2_val))
                                 && (getKind(cs2_val) == UNSEALED)
                                 && (getKind(cs1_val_mutable) matches tagged SEALED_WITH_TYPE ._ ? True : False)
                                 && (getAddr(cs2_val) == zeroExtend(getKind(cs1_val_mutable).SEALED_WITH_TYPE))
                                 && (getHardPerms(cs2_val).permitUnseal)
                                 && (cs2_in_bounds);
                alu_outputs.cap_val1 = setValidCap(result, isValidCap(result) && permitted);
                alu_outputs.val1_cap_not_int = True;
            end
            f7_cap_CTestSubset: begin
                let local_cs1_val = inputs.rs1_idx == 0 ? ddc_val_immutable : cs1_val_immutable;
                if (isValidCap(local_cs1_val) == isValidCap(cs2_val) &&
                    ((getPerms(cs2_val) & getPerms(local_cs1_val)) == getPerms(cs2_val)) ) begin
                    alu_outputs.check_enable = False; // We do not require the check to pass to avoid a trap
                    alu_outputs.check_authority = local_cs1_val;
                    alu_outputs.check_address_low = cs2_base;
                    alu_outputs.check_address_high = cs2_top;
                    alu_outputs.op_stage2 = OP_Stage2_TestSubset;
                end else begin
                    alu_outputs.val1 = zeroExtend(pack(False));
                end
            end
            f7_cap_CSetEqualExact: begin
                alu_outputs.val1 = zeroExtend(pack(toMem(cs1_val_immutable) == toMem(cs2_val)));
            end
            f7_cap_CCopyType: begin
                case (getKind(cs2_val)) matches
                    tagged UNSEALED: begin
                        alu_outputs.val1 = otype_unsealed_ext;
                    end
                    tagged SENTRY: begin
                        alu_outputs.val1 = otype_sentry_ext;
                    end
                    tagged RES0: begin
                        alu_outputs.val1 = otype_res0_ext;
                    end
                    tagged RES1: begin
                        alu_outputs.val1 = otype_res1_ext;
                    end
                    tagged SEALED_WITH_TYPE .otype: begin
                        val1_source = SET_ADDR;
                        set_addr_addr = zeroExtend(otype);
                    end
                endcase
            end
            f7_cap_CAndPerm: begin
                alu_outputs.cap_val1 = setPerms(cs1_val_mutable, pack(getPerms(cs1_val_mutable)) & truncate(rs2_val));
                alu_outputs.val1_cap_not_int = True;
            end
            f7_cap_CSetFlags: begin
                alu_outputs.cap_val1 = setFlags(cs1_val_mutable, truncate(rs2_val));
                alu_outputs.val1_cap_not_int = True;
            end
            f7_cap_CToPtr: begin
                if (isValidCap(cs1_val_mutable) && isValidCap(inputs.rs2_idx == 0 ? ddc_val_immutable : cs2_val)) begin
                    alu_outputs.val1 = zeroExtend(getAddr(cs1_val_mutable) - (inputs.rs2_idx == 0 ? ddc_base : cs2_base));
                end else begin
                    alu_outputs.val1 = 0;
                end
            end
            f7_cap_CFromPtr: begin
                if (rs2_val == 0) begin
                    alu_outputs.val1 = 0;
                end else begin
                    val1_source = MODIFY_OFFSET;
                    modify_offset_cap = inputs.rs1_idx == 0 ? ddc_val_mutable : cs1_val_mutable;
                    modify_offset_off_or_inc = rs2_val;
                    modify_offset_inc_not_set = False;
                end
            end
            f7_cap_CSub: begin
                alu_outputs.val1 = zeroExtend(getAddr(cs1_val_mutable) - getAddr(cs2_val));
            end
            f7_cap_CBuildCap: begin
                let auth = inputs.rs1_idx == 0 ? ddc_val_mutable : cs1_val_mutable;

                Bool perm_subset = (getPerms(auth) & getPerms(cs2_val)) == getPerms(cs2_val);
                Bool bound_subset = cs2_base >= getBase(auth) && cs2_top <= getTop(auth);

                let result = setValidCap(cs2_val, isValidCap(auth) && isDerivable(cs2_val) && perm_subset && bound_subset);
                alu_outputs.cap_val1 = setKind(result, getKind(cs2_val) == SENTRY ? SENTRY : UNSEALED); // Preserve sentries
                alu_outputs.val1_cap_not_int = True;
            end
            f7_cap_Loads: begin
                Bit#(3) widthCode = zeroExtend(funct5rs2[1:0]);
                Bool is_lr = False;
                Bool is_unsigned = funct5rs2[2] == cap_mem_unsigned && funct5rs2[4] == 1'b0;
                Bool illegal = False;
                if (funct5rs2[4] == 1'b1) begin
                    if (funct5rs2[2:0] == 3'b111) begin
                        widthCode = w_SIZE_Q;
                    end else begin
`ifdef ISA_A
                        is_lr = True;
                        widthCode = funct5rs2[2:0];
`else
                        illegal = True;
`endif
                    end
                end
                if ((widthCode > w_SIZE_MAX) || (is_unsigned && widthCode >= w_SIZE_INT_MAX)) illegal = True;
                if (illegal) begin
                    // exc_code defaults to exc_code_ILLEGAL_INSTRUCTION
                    alu_outputs.control = CONTROL_TRAP;
                end else begin
                    alu_outputs = memCommon(alu_outputs, False, is_unsigned, funct5rs2[3] == cap_mem_ddc, widthCode, False, inputs.ddc, cs1_val_immutable, inputs.rs1_idx, ?, is_lr, {f5_AMO_LR, 2'b0});
                end
            end
            f7_cap_Stores: begin
                let widthCode = funct5rd[2:0];
                Bool is_sc = funct5rd[4] == 1'b1;
                Bool illegal = False;
                if (is_sc) begin
`ifdef ISA_A
                    alu_outputs.rd = inputs.rs2_idx;
`else
                    illegal = True;
`endif
                end
                if (widthCode > w_SIZE_MAX) illegal = True;
                if (illegal) begin
                    // exc_code defaults to exc_code_ILLEGAL_INSTRUCTION
                    alu_outputs.control = CONTROL_TRAP;
                end else begin
                    alu_outputs = memCommon(alu_outputs, True, ?, funct5rd[3] == cap_mem_ddc, widthCode, False, inputs.ddc, cs1_val_immutable, inputs.rs1_idx, cs2_val, is_sc, {f5_AMO_SC, 2'b0});
                end
            end
            f7_cap_TwoOp: begin
                case (funct5rs2)
                f5rs2_cap_CGetLen: begin
                    Bit#(XLEN) length = truncate(getLength(cs1_val_mutable));
                    alu_outputs.val1 = zeroExtend(length);
                end
                f5rs2_cap_CGetBase: begin
                    alu_outputs.val1 = zeroExtend(cs1_base);
                end
                f5rs2_cap_CGetTag: begin
                    alu_outputs.val1 = zeroExtend(pack(isValidCap(cs1_val_immutable)));
                end
                f5rs2_cap_CGetSealed: begin
                    alu_outputs.val1 = zeroExtend(pack(getKind(cs1_val_mutable) != UNSEALED));
                end
                f5rs2_cap_CRRL: begin
                    val1_source = GET_PRECISION;
                    get_precision_crrl_not_cram = True;
                end
                f5rs2_cap_CRAM: begin
                    val1_source = GET_PRECISION;
                    get_precision_crrl_not_cram = False;
                end
                f5rs2_cap_CMove: begin
                    alu_outputs.cap_val1 = cs1_val_immutable;
                    alu_outputs.val1_cap_not_int = True;
                end
                f5rs2_cap_CClearTag: begin
                    alu_outputs.cap_val1 = setValidCap(cs1_val_mutable, False);
                    alu_outputs.val1_cap_not_int = True;
                end
                f5rs2_cap_CGetAddr: begin
                    alu_outputs.val1 = zeroExtend(getAddr(cs1_val_mutable));
                end
                f5rs2_cap_CSealEntry: begin
                    alu_outputs.cap_val1 = setKind(cs1_val_mutable, SENTRY);
                    alu_outputs.val1_cap_not_int = True;
                end
                f5rs2_cap_CLoadTags: begin
                    // XXX Implement a single-tag cloadtags
                    alu_outputs = memCommon(alu_outputs, False, True, False, w_SIZE_CAP, True, ?, cs1_val_immutable, inputs.rs1_idx, ?, False, ?);
                end
                f5rs2_cap_CGetOffset: begin
                    alu_outputs.val1 = zeroExtend(cs1_offset);
                end
                f5rs2_cap_CGetFlags: begin
                    alu_outputs.val1 = zeroExtend(getFlags(cs1_val_mutable));
                end
                f5rs2_cap_CGetPerm: begin
                    alu_outputs.val1 = zeroExtend(getPerms(cs1_val_mutable));
                end
                f5rs2_cap_JALR_CAP: begin
                    jalr_enable = True;
                    jalr_cap_mode = True;
                    jalr_immediate = False;
                end
                f5rs2_cap_JALR_PCC: begin
                    jalr_enable = True;
                    jalr_cap_mode = False;
                    jalr_immediate = False;
                end
                f5rs2_cap_CGetType: begin
                    case (getKind(cs1_val_mutable)) matches
                        tagged UNSEALED: begin
                            alu_outputs.val1 = otype_unsealed_ext;
                        end
                        tagged SENTRY: begin
                            alu_outputs.val1 = otype_sentry_ext;
                        end
                        tagged RES0: begin
                            alu_outputs.val1 = otype_res0_ext;
                        end
                        tagged RES1: begin
                            alu_outputs.val1 = otype_res1_ext;
                        end
                        tagged SEALED_WITH_TYPE .otype: begin
                            alu_outputs.val1 = zeroExtend(otype);
                        end
                    endcase
                end
                default: alu_outputs.control = CONTROL_TRAP;
                endcase
            end
            default: alu_outputs.control = CONTROL_TRAP;
            endcase
        end
        default: alu_outputs.control = CONTROL_TRAP;
        endcase
    end

    if (jalr_enable) begin
        // Signed version of rs1_val
        IntXL s_rs1_val = unpack (inputs.rs1_val);
        IntXL offset    = jalr_immediate ? extend (unpack (inputs.decoded_instr.imm12_I)) : 0;
        Addr  next_pc   = pack (s_rs1_val + offset);
        Addr  ret_pc    = fall_through_pc (inputs);
        Addr  pcc_addr  = getAddr(toCapPipe(inputs.pcc));

        WordXL auth_base = getPCCBase(inputs.pcc);
        Bit#(6) auth_idx = {1,scr_addr_PCC};
        CapPipe auth_cap = toCapPipe(inputs.pcc);
        CapPipe maskedTarget = setKind(maskAddr(setAddrUnsafe(cs1_val_immutable, getAddr(cs1_val_immutable) + pack(offset)), signExtend(2'b10)), UNSEALED);

        alu_outputs.val1 = extend (ret_pc);
        alu_outputs.pcc = fromCapPipe(maskedTarget);

        modify_offset_cap = toCapPipe(inputs.pcc);
        modify_offset_off_or_inc = fall_through_pc_inc(inputs);
        modify_offset_inc_not_set = True;
        modify_offset_seal_entry = True;

        if (jalr_cap_mode) begin
            check_cs1_tagged = True;
            check_cs1_unsealed_or_sentry = True;
            check_cs1_permit_x = True;
            check_cs1_unsealed_or_imm_0 = jalr_immediate;

            alu_outputs.control = CONTROL_CAPBRANCH;

            val1_source = MODIFY_OFFSET;

            next_pc   = cs1_offset + pack(offset);
            auth_base = cs1_base;
            auth_idx  = {0,inputs.rs1_idx};
            auth_cap  = cs1_val_immutable;
        end else begin
            alu_outputs.control = CONTROL_BRANCH;

            val1_source = LITERAL;
        end

        next_pc [0] = 1'b0;
        alu_outputs.addr      = next_pc;

        let cf_info   = CF_Info {cf_op       : CF_JALR,
                                 from_PC     : pcc_addr,
                                 taken       : True,
                                 fallthru_PC : pcc_addr + fall_through_pc_inc(inputs),
                                 taken_PC    : getAddr(maskedTarget) };
        alu_outputs.cf_info   = cf_info;

        alu_outputs = checkValidJump(alu_outputs, True, auth_cap, auth_base, auth_idx, auth_base + next_pc);
    end

    case(val1_source)
    MODIFY_OFFSET: begin
        let result = modifyOffset(modify_offset_cap, modify_offset_off_or_inc, modify_offset_inc_not_set);
        if (modify_offset_seal_entry) begin
            result.value = setKind(result.value, SENTRY);
        end
        alu_outputs.cap_val1 = result.value;
        alu_outputs.val1_cap_not_int = True;
`ifdef PERFORMANCE_MONITORING
        alu_outputs.set_offset_in_bounds = result.exact;
`endif
    end
    SET_BOUNDS: begin
        let result = setBounds(cs1_val_mutable, set_bounds_length);
        Bool in_bounds = getAddr(cs1_val_mutable) >= cs1_base
                      && zeroExtend(getAddr(cs1_val_mutable)) + zeroExtend(set_bounds_length) <= getTop(cs1_val_mutable);
        alu_outputs.cap_val1 = setValidCap(result.value, isValidCap(result.value) && (!set_bounds_exact || result.exact) && in_bounds);
        alu_outputs.val1_cap_not_int = True;
`ifdef PERFORMANCE_MONITORING
        alu_outputs.set_bounds_inexact = !result.exact;
`endif
    end
    GET_PRECISION: begin
        CapReg nullCapReg = nullCap;
        let result = getRepresentableAlignmentMask(nullCapReg, inputs.rs1_val);
        if (get_precision_crrl_not_cram) begin
            result = (inputs.rs1_val + ~result) & result;
        end
        alu_outputs.val1 = result;
    end
    SET_ADDR: begin
        let result = setAddr(cs1_val_mutable, set_addr_addr);
        alu_outputs.cap_val1 = result.value;
        alu_outputs.val1_cap_not_int = True;
    end
    endcase

    if      (check_cs1_tagged             && !isValidCap(cs1_val_immutable))
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs1_idx), exc_code_CHERI_Tag);
    else if (check_cs2_tagged             && !isValidCap(cs2_val))
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs2_idx), exc_code_CHERI_Tag);
    else if (check_cs1_sealed_with_type   && (getKind(cs1_val_mutable) matches tagged SEALED_WITH_TYPE ._ ? False : True))
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs1_idx), exc_code_CHERI_Seal);
    else if (check_cs2_sealed_with_type   && (getKind(cs2_val) matches tagged SEALED_WITH_TYPE ._ ? False : True))
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs2_idx), exc_code_CHERI_Seal);
    else if (check_cs1_unsealed_or_sentry && isValidCap(cs1_val_immutable) && getKind(cs1_val_mutable) != UNSEALED && getKind(cs1_val_mutable) != SENTRY)
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs1_idx), exc_code_CHERI_Seal);
    else if (check_cs1_cs2_types_match    && getKind(cs1_val_mutable).SEALED_WITH_TYPE != getKind(cs2_val).SEALED_WITH_TYPE) // Already checked SEALED_WITH_TYPE
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs1_idx), exc_code_CHERI_Type);
    else if (check_cs1_permit_ccall       && !getHardPerms(cs1_val_mutable).permitCCall)
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs1_idx), exc_code_CHERI_CCallPerm);
    else if (check_cs2_permit_ccall       && !getHardPerms(cs2_val).permitCCall)
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs2_idx), exc_code_CHERI_CCallPerm);
    else if (check_cs1_permit_x           && !getHardPerms(cs1_val_mutable).permitExecute)
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs1_idx), exc_code_CHERI_XPerm);
    else if (check_cs1_unsealed_or_imm_0  && (getKind(cs1_val_mutable) != UNSEALED && inputs.decoded_instr.imm12_I != 0))
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs1_idx), exc_code_CHERI_Seal);
    else if (check_cs2_no_permit_x        && getHardPerms(cs2_val).permitExecute)
        alu_outputs = fv_CHERI_exc(alu_outputs, zeroExtend(inputs.rs2_idx), exc_code_CHERI_XPerm);

    // Normal trace output (if no trap)
    //alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
					//  fv_trace_isize (inputs),
					//  fv_trace_instr (inputs),
					//  inputs.decoded_instr.rd,
					//  getAddr(rd_val));
   return alu_outputs;
endfunction
`endif

// ----------------------------------------------------------------
// Top-level ALU function

function ALU_Outputs fv_ALU (ALU_Inputs inputs);
   let alu_outputs = alu_outputs_base;

   let ddc_base = getBase(inputs.ddc);

   if (inputs.decoded_instr.opcode == op_BRANCH)
      alu_outputs = fv_BRANCH (inputs);

`ifndef ISA_CHERI
   // If we are in CHERI, we might need to do a CJAL(R), so moved to fv_CHERI
   else if (inputs.decoded_instr.opcode == op_JAL)
      alu_outputs = fv_JAL (inputs);

   else if (inputs.decoded_instr.opcode == op_JALR)
      alu_outputs = fv_JALR (inputs);
`endif

`ifdef ISA_M
   // OP 'M' ops MUL/ MULH/ MULHSU/ MULHU/ DIV/ DIVU/ REM/ REMU
   else if (   (inputs.decoded_instr.opcode == op_OP)
	    && f7_is_OP_MUL_DIV_REM (inputs.decoded_instr.funct7))
      begin
	 // Will be executed in MBox in next stage
	 alu_outputs.op_stage2 = OP_Stage2_M;
	 alu_outputs.rd        = inputs.decoded_instr.rd;
	 alu_outputs.val1      = inputs.rs1_val;
	 alu_outputs.val2      = inputs.rs2_val;
         alu_outputs.val1_fast = alu_outputs.val1;
         alu_outputs.val2_fast = alu_outputs.val2;

`ifdef INCLUDE_TANDEM_VERIF
	 // Normal trace output (if no trap)
	 alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
						fv_trace_isize (inputs),
						fv_trace_instr (inputs),
						inputs.decoded_instr.rd,
						?);
`endif
      end

`ifdef RV64
   // OP 'M' ops MULW/ DIVW/ DIVUW/ REMW/ REMUW
   else if (   (inputs.decoded_instr.opcode == op_OP_32)
	    && f7_is_OP_MUL_DIV_REM (inputs.decoded_instr.funct7))
      begin
	 // Will be executed in MBox in next stage
	 alu_outputs.op_stage2 = OP_Stage2_M;
	 alu_outputs.rd        = inputs.decoded_instr.rd;
	 alu_outputs.val1      = inputs.rs1_val;
	 alu_outputs.val2      = inputs.rs2_val;
         alu_outputs.val1_fast = alu_outputs.val1;
         alu_outputs.val2_fast = alu_outputs.val2;

`ifdef INCLUDE_TANDEM_VERIF
	 // Normal trace output (if no trap)
	 alu_outputs.trace_data = mkTrace_I_RD (fall_through_pc (inputs),
						fv_trace_isize (inputs),
						fv_trace_instr (inputs),
						inputs.decoded_instr.rd,
						?);
`endif
      end
`endif
`endif

   // OP_IMM and OP (shifts)
   else if (   (   (inputs.decoded_instr.opcode == op_OP_IMM)
		|| (inputs.decoded_instr.opcode == op_OP))
	    && (   (inputs.decoded_instr.funct3 == f3_SLLI)
		|| (inputs.decoded_instr.funct3 == f3_SRLI)
		|| (inputs.decoded_instr.funct3 == f3_SRAI)))
      alu_outputs = fv_OP_and_OP_IMM_shifts (inputs);

   // Remaining OP_IMM and OP (excluding shifts and 'M' ops MUL/DIV/REM)
   else if (   (inputs.decoded_instr.opcode == op_OP_IMM)
	    || (inputs.decoded_instr.opcode == op_OP))
      alu_outputs = fv_OP_and_OP_IMM (inputs);

`ifdef RV64
   else if (inputs.decoded_instr.opcode == op_OP_IMM_32)
      alu_outputs = fv_OP_IMM_32 (inputs);

   // Remaining op_OP_32 (excluding 'M' ops)
   else if (inputs.decoded_instr.opcode == op_OP_32)
      alu_outputs = fv_OP_32 (inputs);
`endif

   else if (inputs.decoded_instr.opcode == op_LUI)
      alu_outputs = fv_LUI (inputs);

`ifndef ISA_CHERI
   // If we are in CHERI, we might need to do a setOffset for AUIPCC, so moved to fv_CHERI
   else if (inputs.decoded_instr.opcode == op_AUIPC)
      alu_outputs = fv_AUIPC (inputs);
`endif

   else if (inputs.decoded_instr.opcode == op_LOAD)
      alu_outputs = fv_LD (inputs, Invalid);

   else if (inputs.decoded_instr.opcode == op_STORE)
      alu_outputs = fv_ST (inputs);

   else if (inputs.decoded_instr.opcode == op_MISC_MEM)
      alu_outputs = fv_MISC_MEM (inputs);

   else if (inputs.decoded_instr.opcode == op_SYSTEM)
      alu_outputs = fv_SYSTEM (inputs);

`ifdef ISA_A
   else if (inputs.decoded_instr.opcode == op_AMO)
      alu_outputs = fv_AMO (inputs);
`endif

`ifdef ISA_F
   else if (   (inputs.decoded_instr.opcode == op_LOAD_FP))
      alu_outputs = fv_LD (inputs, Invalid);

   else if (   (inputs.decoded_instr.opcode == op_STORE_FP))
      alu_outputs = fv_ST (inputs);

   else if (   (inputs.decoded_instr.opcode == op_FP)
            || (inputs.decoded_instr.opcode == op_FMADD)
            || (inputs.decoded_instr.opcode == op_FMSUB)
            || (inputs.decoded_instr.opcode == op_FNMSUB)
            || (inputs.decoded_instr.opcode == op_FNMADD))
      alu_outputs = fv_FP (inputs);
`endif

`ifdef ISA_CHERI
   else if (   (inputs.decoded_instr.opcode == op_cap_Manip)
            || (inputs.decoded_instr.opcode == op_AUIPC)
            || (inputs.decoded_instr.opcode == op_JALR)
            || (inputs.decoded_instr.opcode == op_JAL))
      alu_outputs = fv_CHERI (inputs, ddc_base);
`endif

   else begin
      alu_outputs.control = CONTROL_TRAP;

`ifdef INCLUDE_TANDEM_VERIF
      // Normal trace output (if no trap)
      alu_outputs.trace_data = mkTrace_TRAP (fall_through_pc (inputs),
					     fv_trace_isize (inputs),
					     fv_trace_instr (inputs),
					     ?,
					     ?,
					     ?,
					     ?,
					     ?);
`endif
   end

   return alu_outputs;
endfunction

// ================================================================

endpackage
