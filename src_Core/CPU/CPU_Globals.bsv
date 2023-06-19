// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved

package CPU_Globals;

// ================================================================
// Types common to multiple CPU stages,
// including types communicated from stage to stage.

// ================================================================
// BSV library imports

// None

// ----------------
// BSV additional libs

// None

// ================================================================
// Project imports

import ISA_Decls :: *;

`ifdef ISA_CHERI
import CHERICap :: *;
import CHERICC_Fat :: *;
`endif

`ifdef RVFI_DII
`define RVFI
`endif

import TV_Info   :: *;

// ================================================================
// Output status of each stage

// EMPTY:   Stage has nothing in its input register
// BUSY:    Stage has input, but output is not ready
// PIPE:    Stage has input; driving normal output for pipeline
// NONPIPE: (In some stages) Stage has input; driving output is handled specially
//                (such as traps, CSR access, ...)

typedef enum {OSTATUS_EMPTY,
	      OSTATUS_BUSY,
	      OSTATUS_PIPE,
	      OSTATUS_NONPIPE
   } Stage_OStatus
deriving (Eq, Bits, FShow);

// ================================================================
// Branch-prediction info

// ----------------
// Epoch is a wrap-around counter that ticks every time there is a
// control-flow redirection due (e.g., due to a mispredict).
// Number of bits should be large enough to accommodate wrap-around.

typedef Bit #(2)  Epoch;

// ----------------
// CF_Info ("control flow information") is sent from the execute stage
// on all control-flow instructions and is used by the fetch stage to
// improve branch prediction.

// cf. RISC-V Unprivileged ISA Spec Section 2.5 on JAL/JALR for
// interpretation of the 'link' fields below.

typedef enum {CF_BR,
	      CF_JAL,
	      CF_JALR,
	      // TODO: extend to ECALL/traps and xRET?
	      CF_None
   } CF_Op
deriving (Eq, Bits, FShow);

typedef struct {
   CF_Op   cf_op;
   WordXL  from_PC;
   Bool    taken;            // Relevant for BR
   WordXL  fallthru_PC;      // for BR; return-PC for JAL/JALR
   WordXL  taken_PC;         // target PC for taken BR and for JAL/JALR
   } CF_Info
deriving (Bits);

CF_Info cf_info_none = CF_Info{cf_op:       CF_None,
			       from_PC:     ?,
			       taken:       ?,
			       fallthru_PC: ?,
			       taken_PC:    ?};

instance FShow #(CF_Info);
   function Fmt fshow (CF_Info x);
      Fmt fmt = $format ("{");

      if (x.cf_op == CF_None)
	 fmt = fmt + $format ("CF_None");
      else if (x.cf_op == CF_BR) begin
	 fmt = fmt + $format ("BR ");
	 fmt = fmt + $format (x.taken ? "taken " : "fallthru ");
	 fmt = fmt + $format ("[%h->%h %h]", x.from_PC, x.fallthru_PC, x.taken_PC);
      end
      else if (x.cf_op == CF_JAL)
	 fmt = fmt + $format ("JAL [%h->%h/%h]", x.from_PC, x.taken_PC, x.fallthru_PC);
      else if (x.cf_op == CF_JALR)
	 fmt = fmt + $format ("JALR [%h->%h/%h]", x.from_PC, x.taken_PC, x.fallthru_PC);

      fmt = fmt + $format ("}");
      return fmt;
   endfunction
endinstance

// ================================================================
// Bypass information
// From later to earlier stages.

// For an instruction's Rd (output GPR), a stage may:
// - have no Rd output
// - have Rd output, Rd is known but RdVal unknown
// - have Rd output, Rd is known and RdVal is known
// Note: a bypass has to stall if Rd matches and RdVal is unknown

typedef enum { BYPASS_RD_NONE, BYPASS_RD, BYPASS_RD_RDVAL } Bypass_State
deriving (Eq, Bits, FShow);

// We do not bypass CSR values, since we stall on CSRRxy insructions.

typedef struct {
   Bypass_State  bypass_state;
   RegName       rd;
`ifdef ISA_CHERI
   CapPipe       rd_val;
`else
   Word          rd_val;
`endif
   } Bypass
deriving (Bits);

instance FShow #(Bypass);
   function Fmt fshow (Bypass x);
      let fmt0 = $format ("Bypass {");
      let fmt1 = ((x.bypass_state == BYPASS_RD_NONE)
		  ? $format ("Rd -")
		  : $format ("Rd %0d ", x.rd) + ((x.bypass_state == BYPASS_RD)
						 ? $format ("-")
						 : $format ("rd_val:", fshow(x.rd_val))));
      let fmt2 = $format ("}");
      return fmt0 + fmt1 + fmt2;
   endfunction
endinstance

`ifdef ISA_F
typedef struct {
   Bypass_State  bypass_state;
   RegName       rd;
   WordFL        rd_val;
   } FBypass
deriving (Bits);

instance FShow #(FBypass);
   function Fmt fshow (FBypass x);
      let fmt0 = $format ("FBypass {");
      let fmt1 = ((x.bypass_state == BYPASS_RD_NONE)
		  ? $format ("FRd -")
		  : $format ("FRd %0d ", x.rd) + ((x.bypass_state == BYPASS_RD)
						 ? $format ("-")
						 : $format ("frd_val:%h", x.rd_val)));
      let fmt2 = $format ("}");
      return fmt0 + fmt1 + fmt2;
   endfunction
endinstance
`endif

// ----------------
// Baseline bypass info

Bypass no_bypass = Bypass {bypass_state: BYPASS_RD_NONE,
			   rd: ?,
			   rd_val: ? };

`ifdef ISA_F
FBypass no_fbypass = FBypass {bypass_state: BYPASS_RD_NONE,
			      rd: ?,
			      rd_val: ? };
`endif

// ----------------
// Bypass functions for GPRs
// Returns '(busy, val)'
// 'busy' means that the RegName is valid and matches, but the value is not available yet

`ifdef ISA_CHERI
function Tuple2 #(Bool, CapPipe) fn_gpr_bypass (Bypass bypass, RegName rd, CapPipe rd_val);
`else
function Tuple2 #(Bool, Word) fn_gpr_bypass (Bypass bypass, RegName rd, Word rd_val);
`endif
   Bool busy = ((bypass.bypass_state == BYPASS_RD) && (bypass.rd == rd));
   let val = (  ((bypass.bypass_state == BYPASS_RD_RDVAL) && (bypass.rd == rd))
		 ? bypass.rd_val
		 : rd_val);
   return tuple2 (busy, val);
endfunction

`ifdef ISA_F
// FBypass functions for FPRs
// Returns '(busy, val)'
// 'busy' means that the RegName is valid and matches, but the value is not available yet

function Tuple2 #(Bool, WordFL) fn_fpr_bypass (FBypass bypass, RegName rd, WordFL rd_val);
   Bool busy = ((bypass.bypass_state == BYPASS_RD) && (bypass.rd == rd));
   WordFL val= (  ((bypass.bypass_state == BYPASS_RD_RDVAL) && (bypass.rd == rd))
		? bypass.rd_val
		: rd_val);
   return tuple2 (busy, val);
endfunction
`endif

`ifdef ISA_CHERI
typeclass PCC#(type t);
    function Exact#(t) setPC (t oldPCC, Addr newPC);
    function Addr getPC (t pcc);
    function Addr getPCCBase (t pcc);
    function Bool checkPreValid (t pcc);
    function Maybe#(CHERI_Exc_Code) checkValid (t pcc, Bit#(TAdd#(XLEN,1)) top, Bool is_i32_not_i16);
    function t fromCapPipe(CapPipe pcc);
    function CapPipe toCapPipe(t pcc);
endtypeclass

typedef Tuple2#(CapPipe,Bit#(XLEN)) PCC_T;

instance PCC#(PCC_T);
    function Exact#(PCC_T) setPC (PCC_T oldPCC, Addr newPC);
        let setOffsetResult = setOffset(tpl_1(oldPCC), newPC);
        return Exact {exact: setOffsetResult.exact, value: tuple2(setOffsetResult.value, tpl_2(oldPCC))};
    endfunction
    function Addr getPC (PCC_T pcc);
        return getOffset(tpl_1(pcc));
    endfunction
    function Addr getPCCBase (PCC_T pcc);
        return tpl_2(pcc);
    endfunction
    // Check if a PCC dereference is valid before the instruction len is known
    function Bool checkPreValid (PCC_T pcc);
        //TODO alignment checks?
        return  isValidCap(tpl_1(pcc))
             && getKind(tpl_1(pcc)) == UNSEALED
             && getHardPerms(tpl_1(pcc)).permitExecute
             && isInBounds(tpl_1(pcc), False);
    endfunction
    function Maybe#(CHERI_Exc_Code) checkValid (PCC_T pcc, Bit#(TAdd#(XLEN,1)) top, Bool is_i32_not_i16);
        let toRet = Invalid;
        //TODO alignment checks?
        CapPipe ac = almightyCap;
        if (!isValidCap(tpl_1(pcc)))
            toRet = Valid(exc_code_CHERI_Tag);
        else if (getKind(tpl_1(pcc)) != UNSEALED)
            toRet = Valid(exc_code_CHERI_Seal);
        else if (!getHardPerms(tpl_1(pcc)).permitExecute)
            toRet = Valid(exc_code_CHERI_XPerm);
        else if (!isInBounds(tpl_1(pcc), False) || !isInBounds(setAddrUnsafe(tpl_1(pcc), getAddr(tpl_1(pcc)) + (is_i32_not_i16 ? 4 : 2)), True))
            toRet = Valid(exc_code_CHERI_Length);
        return toRet;
    endfunction
    function PCC_T fromCapPipe(CapPipe pcc);
        return tuple2(pcc, getBase(pcc));
    endfunction
    function CapPipe toCapPipe(PCC_T pcc);
        return tpl_1(pcc);
    endfunction
endinstance

`endif

// ================================================================
// Trap information

typedef struct {
`ifdef ISA_CHERI
   PCC_T epcc;
   CHERI_Exc_Code cheri_exc_code;
   Bit#(6) cheri_exc_reg;
`else
   Addr      epc;
`endif
   Exc_Code  exc_code;
   Addr      tval;
   } Trap_Info_Pipe
deriving (Bits, FShow);

// ================================================================
// Output from Stage F

typedef struct {
   Stage_OStatus          ostatus;

   // feedforward data
   Data_StageF_to_StageD  data_to_stageD;
   } Output_StageF
deriving (Bits);

instance FShow #(Output_StageF);
   function Fmt fshow (Output_StageF x);
      Fmt fmt = $format ("Output_StageF");
      if (x.ostatus == OSTATUS_EMPTY)
	 fmt = fmt + $format (" EMPTY");
      else if (x.ostatus == OSTATUS_BUSY)
	 fmt = fmt + $format (" BUSY: fetch_addr:%h", x.data_to_stageD.fetch_addr);
      else if (x.ostatus == OSTATUS_NONPIPE)
	 fmt = fmt + $format (" NONPIPE: fetch_addr:%h [***** IMPOSSIBLE! *****]", x.data_to_stageD.fetch_addr);
      else
	 fmt = fmt + $format (" PIPE: ", fshow (x.data_to_stageD));
      return fmt;
   endfunction
endinstance
// ----------------
// Data_StageF_to_StageD

typedef struct {
   Addr       fetch_addr;
   Bool       is_cap_mode;
`ifdef ISA_CHERI
   Bool       refresh_pcc;
`endif
`ifdef RVFI_DII
   Dii_Id instr_seq;
`endif
   Epoch      epoch;              // Branch prediction epoch
   Priv_Mode  priv;               // Priv at which instr was fetched
   Bool       is_i32_not_i16;     // True if a regular 32b instr, not a compressed (16b) instr
   Bool       exc;                // True if exc in icache access
   Exc_Code   exc_code;
   WordXL     tval;               // Trap value; can be different from PC, with 'C' extension
   Instr      instr;              // Valid if no exception
   WordXL     pred_fetch_addr;    // Predicted next pc
   Bool       pred_is_cap_mode;   // Predicted encoding mode (cap or integer)
   } Data_StageF_to_StageD
deriving (Bits);

instance FShow #(Data_StageF_to_StageD);
   function Fmt fshow (Data_StageF_to_StageD x);
      Fmt fmt = $format ("data_to_StageD {fetch_addr:%h is_cap_mode:%b  priv:%0d  epoch:%0d", x.fetch_addr, x.is_cap_mode, x.priv, x.epoch);
      if (x.exc)
	 fmt = fmt + $format ("  ", fshow_trap_Exc_Code (x.exc_code));
      else
	 fmt = fmt + $format ("  instr:%h  pred_fetch_addr:%h  pred_is_cap_mode:%b", x.instr, x.pred_fetch_addr, x.pred_is_cap_mode);
      fmt = fmt + $format ("}");
      return fmt;
   endfunction
endinstance

// ================================================================
// Output from Stage D
// Just adds decoded instr info

typedef struct {
   Stage_OStatus          ostatus;

   // feedforward data
   Data_StageD_to_Stage1  data_to_stage1;
   } Output_StageD
deriving (Bits);

instance FShow #(Output_StageD);
   function Fmt fshow (Output_StageD x);
      Fmt fmt = $format ("Output_StageD");
      if (x.ostatus == OSTATUS_EMPTY)
	 fmt = fmt + $format (" EMPTY");
      else if (x.ostatus == OSTATUS_BUSY)
	 fmt = fmt + $format (" BUSY: fetch_addr:%h is_cap_mode:%b", x.data_to_stage1.fetch_addr, x.data_to_stage1.is_cap_mode);
      else if (x.ostatus == OSTATUS_NONPIPE)
	 fmt = fmt + $format (" NONPIPE: fetch_addr:%h [***** IMPOSSIBLE! *****]", x.data_to_stage1.fetch_addr);
      else
	 fmt = fmt + $format (" PIPE: ", fshow (x.data_to_stage1));
      return fmt;
   endfunction
endinstance

// ----------------
// Data_StageD_to_Stage1

typedef struct {
   Addr           fetch_addr;
   Bool           is_cap_mode;
`ifdef ISA_CHERI
   Bool           refresh_pcc;
`endif
`ifdef RVFI_DII
   Dii_Id instr_seq;
`endif
   Priv_Mode      priv;               // Priv at which instr was fetched
   Epoch          epoch;              // Branch prediction epoch

   Bool           is_i32_not_i16;     // True if a regular 32b instr, not a compressed (16b) instr

   Bool           exc;                // True if exc in icache access
   Exc_Code       exc_code;
   WordXL         tval;               // Trap value; can be different from PC, with 'C' extension

   Instr          instr;              // Valid if no exception
   Instr          instr_or_instr_C;   // Valid if no exception; original (possibly compressed) instruction
   WordXL         pred_fetch_addr;    // Predicted next pc
   Bool           pred_is_cap_mode;   // Predicted encoding mode (cap or integer)
   Decoded_Instr  decoded_instr;
   } Data_StageD_to_Stage1
deriving (Bits);

instance FShow #(Data_StageD_to_Stage1);
   function Fmt fshow (Data_StageD_to_Stage1 x);
      Fmt fmt = $format ("data_to_Stage1 {pc:%0h cap_mode:%b  priv:%0d  epoch:%0d", x.fetch_addr, x.is_cap_mode, x.priv, x.epoch);
      if (x.exc)
	 fmt = fmt + $format ("  ", fshow_trap_Exc_Code (x.exc_code), " tval %0h", x.tval);
      else begin
	 if (!x.is_i32_not_i16)
	    fmt = fmt + $format ("  instr_C:%0h", x.instr_or_instr_C);
	 fmt = fmt + $format ("  instr:%0h  pred_fetch_addr:%0h  pred_is_cap_mode:%b", x.instr, x.pred_fetch_addr, x.pred_is_cap_mode);
      end
      fmt = fmt + $format ("}");
      return fmt;
   endfunction
endinstance

// ================================================================
// Output from Stage 1

// Outputs from Stage1 to pipeline control
typedef enum {  CONTROL_DISCARD
	      , CONTROL_STRAIGHT
	      , CONTROL_BRANCH
	      , CONTROL_CSRR_W
`ifdef ISA_CHERI
        , CONTROL_CAPBRANCH
	      , CONTROL_SCR_W
`endif
	      , CONTROL_CSRR_S_or_C
	      , CONTROL_FENCE
	      , CONTROL_FENCE_I
	      , CONTROL_SFENCE_VMA
	      , CONTROL_MRET
	      , CONTROL_SRET
	      , CONTROL_URET
	      , CONTROL_WFI
	      , CONTROL_TRAP
   } Control
deriving (Eq, Bits, FShow);

typedef struct {
   Stage_OStatus          ostatus;

   Control                control;

   Trap_Info_Pipe         trap_info;

   // feedback
   Bool                   redirect;
`ifdef ISA_CHERI
   PCC_T                  next_pcc;
`else
   WordXL                 next_pc;
`endif
   CF_Info                cf_info;

   // feedforward data
   Data_Stage1_to_Stage2  data_to_stage2;
   } Output_Stage1
deriving (Bits);

instance FShow #(Output_Stage1);
   function Fmt fshow (Output_Stage1 x);
`ifdef ISA_CHERI
      let pc = getPC(x.data_to_stage2.pcc);
`else
      let pc = x.data_to_stage2.pc;
`endif
      Fmt fmt = $format ("Output_Stage1");
      if (x.ostatus == OSTATUS_EMPTY)
	 fmt = fmt + $format (" EMPTY");
      else if (x.ostatus == OSTATUS_BUSY)
	 fmt = fmt + $format (" BUSY pc:%h", pc);
      else begin
	 if (x.ostatus == OSTATUS_NONPIPE) begin
	    fmt = fmt + $format (" NONPIPE: pc:%h", pc);
	    fmt = fmt + $format (" ", fshow (x.control));
	    fmt = fmt + $format (" ", fshow (x.trap_info));
	 end
	 else begin
	    fmt = fmt + $format (" PIPE: ", fshow (x.control), " ", fshow (x.cf_info), fshow (x.data_to_stage2));
	 end

	 if (x.redirect)
	    fmt = fmt + $format ("\n        redirect next_pc:%h", getPC(x.next_pcc));
      end
      return fmt;
   endfunction
endinstance

// ================================================================
// Data_Stage1_to_Stage2: Data output from Stage1 stage, input to DM stage

// Stage1 stage forwards, to DM, one of these 'opcodes'
// - ALU result (all non-mem, M and FD insructions)
// - DM request (Data Memory LD/ST/...)
// - Shifter Box request (SLL/SLLI, SRL/SRLI, SRA/SRAI)
// - MBox request (integer multiply/divide)
// - FDBox request (floating point ops)

typedef enum {  OP_Stage2_ALU         // Pass-through (non mem, M, FD, AMO)
	      , OP_Stage2_LD
	      , OP_Stage2_ST

`ifdef SHIFT_SERIAL
	      , OP_Stage2_SH
`endif

`ifdef ISA_M
	      , OP_Stage2_M
`endif

`ifdef ISA_A
	      , OP_Stage2_AMO
`endif

`ifdef ISA_F
	      , OP_Stage2_FD
`endif
`ifdef ISA_CHERI
              , OP_Stage2_TestSubset
`endif
   } Op_Stage2
deriving (Eq, Bits, FShow);

typedef struct {
`ifdef ISA_CHERI
    capType val;
`else
    WordXL val;
`endif
   } Pipeline_Val#(type capType) deriving (Bits, FShow);

instance Cast#(Pipeline_Val#(a), Pipeline_Val#(b)) provisos (Cast#(a,b));
   function Pipeline_Val#(b) cast (Pipeline_Val#(a) src);
`ifdef ISA_CHERI
    return Pipeline_Val{val:cast(src.val)};
`else
    return Pipeline_Val{val:src.val};
`endif
   endfunction
endinstance



`ifdef ISA_CHERI
    function Pipeline_Val#(t) embed_cap(t cap) provisos(CHERICap#(t,a,b,XLEN,d,e)) = Pipeline_Val{val: cap};
    function t extract_cap(Pipeline_Val#(t) val) = val.val;
    function Pipeline_Val#(t) embed_int(WordXL num) provisos(CHERICap#(t,a,b,XLEN,d,e)) = Pipeline_Val{val: nullWithAddr(num)};
    function WordXL extract_int(Pipeline_Val#(t) val)  provisos(CHERICap#(t,a,b,XLEN,d,e)) = getAddr(val.val);
`else
    function Pipeline_Val#(t) embed_int(WordXL num) = Pipeline_Val{val: num};
    function WordXL extract_int(Pipeline_Val#(t) val) = val.val;
`endif

typedef struct {
   Priv_Mode  priv;
`ifdef ISA_CHERI
   PCC_T      pcc;
`else
   Addr       pc;
`endif
   Instr      instr;             // For debugging. Just funct3, funct7 are
                                 // enough for functionality.
`ifdef RVFI_DII
   Dii_Id instr_seq;
`endif
   Op_Stage2  op_stage2;
   RegName    rd;
   Addr       addr;     // Branch, jump: newPC
                        // Mem ops and AMOs: mem addr

   Pipeline_Val#(CapPipe) val1;  // OP_Stage2_ALU: rd_val
                       // OP_Stage2_M and OP_Stage2_FD: arg1

   Pipeline_Val#(CapPipe) val2;  // OP_Stage2_ST: store-val;
                       // OP_Stage2_M and OP_Stage2_FD: arg2

`ifdef ISA_D
   WordFL     val1_fast; // Timing optimisation: vals for putting into the fbox/mbox where it is known the result doesn't depend on cap arithmetic
   WordFL     val2_fast;
`else
   WordXL     val1_fast;
   WordXL     val2_fast;
`endif

`ifdef ISA_CHERI
   // Bounds check: if check_enable, will test
   // address_low >= authority.base && address_high <= authority.top
   // TODO behaviour if address_low > address_high?
   // Does not check that authority is tagged, so only generates
   // Bounds exceptions
   CapPipe    check_authority;
   Bit#(6)    check_authority_idx;
   Bit#(XLEN)     check_address_low;
   Bit#(TAdd#(XLEN,1))     check_address_high;
   Bool       check_enable;
`ifdef PERFORMANCE_MONITORING
   Bool set_bounds_inexact;
   Bool set_offset_in_bounds;
`endif

   Bool       mem_allow_cap;
`endif

   Bit#(3)    mem_width_code;
   Bool       mem_tag_only;
   Bool       mem_unsigned;

`ifdef ISA_F
   // Floating point fields
   WordFL     fval1;             // OP_Stage2_FD: arg1
   WordFL     fval2;             // OP_Stage2_FD: arg2
   WordFL     fval3;             // OP_Stage2_FD: arg3
   Bool       rd_in_fpr;         // The rd should update into FPR
   Bool       rs_frm_fpr;        // The rs is from FPR (FP stores)
   Bool       val1_frm_gpr;      // The val1 is from GPR for a FP instruction
   Bit #(3)   rounding_mode;     // rounding mode from fcsr_frm or instr.rm
`endif

`ifdef INCLUDE_TANDEM_VERIF
   Trace_Data  trace_data;
`endif
`ifdef RVFI
   Data_RVFI_Stage1 info_RVFI_s1;
`endif
   } Data_Stage1_to_Stage2
deriving (Bits);

`ifdef RVFI

typedef struct {
    Bit#(ILEN)  instr;
    // From decode
    Bit#(5)     rs1_addr;
    Bit#(5)     rs2_addr;
    Bit#(XLEN)  rs1_data;
    Bit#(XLEN)  rs2_data;
    Bit#(XLEN)  pc_rdata;
    // TODO: Exceptions?
    Bit#(XLEN)  pc_wdata;
    // TODO: Needs 0'ing when unused?
    Bit#(MEMWIDTH)  mem_wdata;

    // From ALU:
    Bit#(5)     rd_addr;
    // Might be killed by memory OPs.
    Bool        rd_alu;
    Bit#(XLEN)  rd_wdata_alu;

    Bit#(XLEN)  mem_addr;

} Data_RVFI_Stage1 deriving (Bits, Eq);


`endif

instance FShow #(Data_Stage1_to_Stage2);
   function Fmt fshow (Data_Stage1_to_Stage2 x);
`ifdef ISA_CHERI
      let pc = getPC(x.pcc);
`else
      let pc = x.pc;
`endif
      Fmt fmt =   $format ("data_to_Stage 2 {pc:%h  instr:%h  priv:%0d\n", pc, x.instr, x.priv);
      fmt = fmt + $format ("            op_stage2:", fshow (x.op_stage2), "  rd:%0d\n", x.rd);
      fmt = fmt + $format ("            addr:%h  val1:%h  val2:%h",
			   x.addr, x.val1, x.val2);
`ifdef ISA_F
      fmt = fmt + $format ("\n");
      fmt = fmt + $format ("            fval1:%h  fval2:%h  fval3:%h",
			   x.fval1, x.fval2, x.fval3);
`endif
`ifdef ISA_CHERI
      if (x.check_enable) begin
          fmt = fmt + $format("\n            bounds_check: checking [0x%h - 0x%h) within 0x%h", x.check_address_low, x.check_address_high, x.check_authority_idx);
          fmt = fmt + $format("\n              0x%h = ", x.check_authority_idx, fshow(x.check_authority));
      end else begin
          fmt = fmt + $format("\n            no bounds_check");
      end
`endif
      fmt = fmt + $format ("}");
      return fmt;
   endfunction
endinstance

// ================================================================
// Output from Stage 2

typedef struct {
   Stage_OStatus          ostatus;
   Trap_Info_Pipe         trap_info;    // relevant if ostatus == OSTATUS_NONPIPE

`ifdef PERFORMANCE_MONITORING
   Output_Stage2_Perf     perf;
`endif

`ifdef ISA_CHERI
   // Whether a capability bounds check succeeded
   Bool                   check_success;
`endif

   // feedback
   Bypass                 bypass;
`ifdef ISA_F
   FBypass                fbypass;
`endif

   // feedforward data
   Data_Stage2_to_Stage3  data_to_stage3;
   } Output_Stage2
deriving (Bits);

`ifdef PERFORMANCE_MONITORING
typedef struct {
   Bool sc_success;
   Bool ld_cap;
   Bool ld_cap_tag_set;
   Bool ld_wait;
   Bool st_wait;
} Output_Stage2_Perf deriving (Bits);
`endif

instance FShow #(Output_Stage2);
   function Fmt fshow (Output_Stage2 x);
      Fmt fmt = $format ("Output_Stage2");
      if (x.ostatus == OSTATUS_EMPTY)
	 fmt = fmt + $format (" EMPTY");
      else if (x.ostatus == OSTATUS_BUSY)
	 fmt = fmt + $format (" BUSY: pc:%0h", getPC(x.data_to_stage3.pcc));
      else if (x.ostatus == OSTATUS_NONPIPE) begin
	 fmt = fmt + $format (" NONPIPE: ") + fshow (x.trap_info);
	 fmt = fmt + $format (" ") + fshow (x.trap_info);
      end
      else
	 fmt = fmt + $format (" PIPE: ") + fshow (x.data_to_stage3);
      return fmt;
   endfunction
endinstance

// ================================================================
// Data communicated from stage 2 to stage 3

typedef struct {
   PCC_T     pcc;            // For debugging only
   Instr     instr;         // For debugging only
`ifdef RVFI_DII
   Dii_Id instr_seq;
`endif
   Priv_Mode priv;

   Bool      rd_valid;
   RegName   rd;
   Pipeline_Val#(CapReg) rd_val;

`ifdef RVFI
   Data_RVFI_Stage2 info_RVFI_s2;
`endif

`ifdef ISA_F
   Bool      upd_flags;
   Bool      rd_in_fpr;
   Bit #(5)  fpr_flags;
   WordFL    frd_val;
`endif

`ifdef INCLUDE_TANDEM_VERIF
   Trace_Data             trace_data;
`endif
   } Data_Stage2_to_Stage3
deriving (Bits);

`ifdef RVFI

typedef struct {
    Data_RVFI_Stage1    stage1;
    // Hard to know what was written as SC pretends to write "0" on failure
    // instead of actual untouched value. So, indicate wmask = 0 perhaps?

    Bit#(TDiv#(MEMWIDTH,8))       mem_rmask;
    Bit#(TDiv#(MEMWIDTH,8))       mem_wmask;

}   Data_RVFI_Stage2 deriving (Bits);

`endif

instance FShow #(Data_Stage2_to_Stage3);
   function Fmt fshow (Data_Stage2_to_Stage3 x);
      Fmt fmt =   $format ("data_to_Stage3 {pc:%h  instr:%h  priv:%0d\n", getPC(x.pcc), x.instr, x.priv);
      fmt = fmt + $format ("        rd_valid:", fshow (x.rd_valid));

`ifdef ISA_F
      if (x.upd_flags)
         fmt = fmt + $format ("  fflags: %05b", fshow (x.fpr_flags));

      if (x.rd_in_fpr)
         fmt = fmt + $format ("  frd:%0d  rd_val:%h\n", x.rd, x.frd_val);
      else
`endif
         fmt = fmt + $format ("  grd:%0d  rd_val:\n", x.rd, fshow(x.rd_val));
      return fmt;
   endfunction
endinstance

// ================================================================
// Output from Stage 3

typedef struct {
   Stage_OStatus  ostatus;
   Bypass         bypass;
`ifdef ISA_F
   FBypass        fbypass;
`endif

`ifdef INCLUDE_TANDEM_VERIF
   Trace_Data     trace_data;
`endif
   } Output_Stage3
deriving (Bits);

instance FShow #(Output_Stage3);
   function Fmt fshow (Output_Stage3 x);
      Fmt fmt = $format ("Output_Stage3");
      if (x.ostatus == OSTATUS_EMPTY)
	 fmt = fmt + $format (" EMPTY");
      else if (x.ostatus == OSTATUS_BUSY)
	 fmt = fmt + $format (" BUSY");
      else if (x.ostatus == OSTATUS_PIPE)
	 fmt = fmt + $format (" PIPE");
      else if (x.ostatus == OSTATUS_NONPIPE)
	 fmt = fmt + $format (" NONPIPE");
      return fmt;
   endfunction
endinstance

// ================================================================

endpackage
