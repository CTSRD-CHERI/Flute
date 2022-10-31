// Copyright (c) 2018-2020 Bluespec, Inc. All Rights Reserved

package TLB;

// ================================================================
// This package implements a TLB (Translation Lookaside Buffer)
// for use by RISC-V system MMUs
// for VM schemes Sv32 (for RV32) and Sv39 (for RV64)

// ================================================================
// Bluespec libraries

import RegFile :: *;
import Vector  :: *;
import FIFOF   :: *;
import Map     :: *;

// ----------------
// BSV additional libs

import Cur_Cycle  :: *;

// ================================================================
// Project imports

import ISA_Decls        :: *;
import MMU_Cache_Common :: *;

// ================================================================

export  TLB_IFC (..), mkTLB;
export  VM_Xlate_Outcome (..);

// ================================================================
// Abbreviations (from ISA spec)
//    ASID:   Address space identifier
//    VPN:    Virtual Page Number
//    PPN:    Physical Page Number
//    VA:     Virtual Address
//    PA:     Physical Address    (= { PPN, 12'b_Offset }
//    PTE:    Page Table Entry

// Abbreviations (other)
//    TLB:    Translation Lookaside Buffer (a cache mapping {ASID,VPN}->PPN)

// ================================================================
// TLB interface

interface TLB_IFC;
   // Put the virtual address that mv_vm_get_xlate will see at least the cycle before.
   method Action mv_vm_put_va (WordXL full_va);
   // Translate a VA to a PA (or exception)
   // plus additional info for PTE writeback (if A,D bits modified)
   method VM_Xlate_Result  mv_vm_get_xlate (
					WordXL             satp,
					Bool               read_not_write,
                    Bool               cap,
					Priv_Mode          priv,
					Bit #(1)           sstatus_SUM,
					Bit #(1)           mstatus_MXR);

   // ----------------
   // Insert a PTE into the TLB
   method Action ma_insert (ASID asid, VPN vpn, PTE pte, Bit #(2) level, PA pte_pa);

    // Invalidate all entries, in 1 cycle
   method Action ma_flush;
endinterface

// ================================================================
// Types and help-functions

// ----------------
// This is the intermediate result from a TLB probe.

typedef struct {
   Bool      hit;
   PTE       pte;            // The leaf PTE for this translation (contains PPN)

   // Information needed to write back updated PTE (A,D bits) to TLB and mem
   Bit #(2)  pte_level;      // Level of leaf PTE for this translation
   PA        pte_pa;         // PA from which PTE was loaded, for writeback if A,D bits are updated
   } TLB_Lookup_Result
deriving (Bits, FShow);

// ================================================================
// This function does all the translation work, based on result of TLB probe

function VM_Xlate_Result  fv_vm_xlate (WordXL             addr,
				       WordXL             satp,
				       Bool               dmem_not_imem,
				       Bool               read_not_write,
					   Bool               capability,
				       Priv_Mode          priv,
				       Bit #(1)           sstatus_SUM,
				       Bit #(1)           mstatus_MXR,
				       TLB_Lookup_Result  tlb_result);
      // Translate if in VM mode (sv32, sv39), and priv <= s_Priv_Mode
      // Default PA (no translation) = addr

`ifdef RV32
      Bool xlate = ((priv <= s_Priv_Mode) && (fn_satp_to_VM_Mode (satp) == satp_mode_RV32_sv32));
      PA   pa    = zeroExtend (addr);
`elsif SV39
      Bool xlate = ((priv <= s_Priv_Mode) && (fn_satp_to_VM_Mode (satp) == satp_mode_RV64_sv39));
      PA   pa    = truncate (addr);
`endif

      VM_Xlate_Outcome   outcome      = VM_XLATE_OK;
      Bool               allow_cap    = True;
      Bool               pte_modified = False;
      PTE                pte          = tlb_result.pte;

      match { .pte_fault, .exc_code } = is_pte_fault (dmem_not_imem, read_not_write, capability, priv, sstatus_SUM, mstatus_MXR, pte);

      if (xlate) begin
	 if (tlb_result.pte_level == 0)
	    pa = zeroExtend ({fn_PTE_to_PPN (pte),
			      fn_Addr_to_Offset (addr) });

	 else if (tlb_result.pte_level == 1)
	    pa = zeroExtend ({fn_PTE_to_PPN_mega (pte),
			      fn_Addr_to_VPN_0 (addr),
			      fn_Addr_to_Offset (addr) });
`ifdef SV39
	 else if (tlb_result.pte_level == 2)
	    pa = zeroExtend ({fn_PTE_to_PPN_giga (pte),
			      fn_Addr_to_VPN_1 (addr),
			      fn_Addr_to_VPN_0 (addr),
			      fn_Addr_to_Offset (addr) });
`endif

	 // $display ("    fav_vm_xlate: PTE.A = %0d", fn_PTE_to_A (pte));
	 if (fn_PTE_to_A (pte) == 1'b0) begin
	    pte_modified = True;
	    pte[pte_A_offset] = 1'b1;
	 end

	 // $display ("    fav_vm_xlate: PTE.D = %0d  read = %0d", fn_PTE_to_D (pte), pack (read_not_write));
	 if ((fn_PTE_to_D (pte) == 1'b0) && (! read_not_write)) begin
	    pte_modified = True;
	    pte[pte_D_offset] = 1'b1;
	 end

	 if (fn_PTE_to_LoadCap (pte) == 1'b0)
	    allow_cap = False;

	 if (tlb_result.hit) begin
	    if (pte_fault) begin
	       outcome = VM_XLATE_EXCEPTION;
	       // $display ("fav_vm_xlate: page fault due to pte_denial");
	    end
	 end
	 else
	    outcome = VM_XLATE_TLB_MISS;
      end
      return VM_Xlate_Result {outcome:      outcome,
			      allow_cap:    allow_cap,
			      pa:           pa,
			      exc_code:     exc_code,
			      pte_modified: pte_modified,
               pte_level:    tlb_result.pte_level,
               pte_pa:       tlb_result.pte_pa,
			      pte:          pte};
endfunction: fv_vm_xlate

// ================================================================
// TLB implementation notes:

// RV32.sv32 page tables are 2-level trees (levels are called 1,0).
// A leaf can occur at any level ('megapages', 'pages').

// RV64.sv39 page tables are 3-level trees (levels are called 2,1,0).
// A leaf can occur at any level ('gigapages', 'megapages', 'pages').

// For maximum hashing (least collisions), the TLB cache index should
// be taken from the least-significant bits of the VPN.
// The remaining VPN bits form the cache tag.
//                   Tag bits            Index bits
// For gigapages:    in VPN [2]          in VPN [2]
// For megapages:    in VPN [2,1]        in VPN [1]
// For pages:        in VPN [2,1,0]      in VPN [0]

// When we do a TLB lookup for a VA, we don't know whether it'll be in
// a page, megapage or gigapage, or is unmapped.

// Thus our "TLB" is actually multiple sub-TLBs, one each for ordinary,
// mega and giga pages.

// These are probed concurrently (at most one should HIT).
// Note: we can choose different params for each sub-TLB
//    (size, associativity)

// ================================================================
// TLB parameters and help-functions
// These TLBs are direct-mapped caches.
// The index is a few bits from VPN [level]
// The tag is (asid, remaining bits from VPN)

typedef Bit#(TSub #(TMul #(TSub#(VPN_max_levels,lvl), VPN_J_sz), idx_sz))
   TLB_Tag#(numeric type lvl, numeric type idx_sz);

// ----------------
// Level 2 tags and indexes (for RV64 only)
`ifdef RV64
typedef  4                           TLB2_Size;  // # of entries in TLB2
typedef  TLog #(TLB2_Size)           TLB2_Index_sz;
typedef  Bit #(TLB2_Index_sz)        TLB2_Index;
typedef  TLB_Tag#(2, TLB2_Index_sz)  TLB2_Tag;
`endif
// ----------------
// Level 1 tags and indexes

typedef  4                           TLB1_Size;    // # of entries in TLB1
typedef  TLog #(TLB1_Size)           TLB1_Index_sz;
typedef  Bit #(TLB1_Index_sz)        TLB1_Index;
typedef  TLB_Tag#(1, TLB1_Index_sz)  TLB1_Tag;
// ----------------
// Level 0 tags and indexes

typedef  16                                     TLB0_Size;    // # of entries in TLB0
typedef   1                                     TLB0_Assos;
typedef  TLog #(TDiv#(TLB0_Size,TLB0_Assos))    TLB0_Index_sz;
typedef  Bit #(TLB0_Index_sz)                   TLB0_Index;
typedef  TLB_Tag#(0, TLB0_Index_sz)             TLB0_Tag;

// ----------------
// Each of the 3 sub-TLBs contains TLBEs (TLB Entries)
// Each TLBE is a PTE + additional info (tag, pte_pa)
// We keep the whole PTE even though PTEs have 'reserved' fields
// which we don't use, to avoid disturbing those fields on
// PTE write-back, both because software may use those fields
// and to preserve tandem-verification.

typedef struct {
   ASID           asid_tag;   // Address-space tag
   //Bit #(tag_sz)  vpn_tag;    // VPN tag (Tag_sz MSBs of VPN)
   PTE            pte;        // Contains PPN + control bits
   PA             pte_pa;     // For future writes-back of this PTE
   } TLBE // #(numeric type tag_sz)
deriving (Bits, FShow);

// ================================================================
// TLB module

(* synthesize *)
module mkTLB #(parameter Bool      dmem_not_imem,
	       parameter Bit #(3)  verbosity)
             (TLB_IFC);

   // The TLBs below use Vector-of-Reg for 'valids', allowing 1-cycle flushing
   // They use RegFiles for 'entries', which should map to LUTRAMs.
   // (Should we change them to BRAMs?  Would take a 1-cycle hit)

   // ----------------
   // Level 2 TLB (for gigapages)
`ifdef RV64
   Map#(TLB2_Tag, TLB2_Index, TLBE, 1) tlb2_entries <- mkMapLossy(?);
`endif

   // ----------------
   // Level 1 TLB (for megapages)
   Map#(TLB1_Tag, TLB1_Index, TLBE, 1) tlb1_entries <- mkMapLossy(?);

   // ----------------
   // Level 0 TLB (for pages)
   MapSplit#(TLB0_Tag, TLB0_Index, TLBE, TLB0_Assos) tlb0_entries <- mkMapLossyBRAM;

   Reg#(WordXL) rg_va <- mkRegU;
   // ----------------------------------------------------------------
   // Lookup functions for each sub-page
   // In each case 2-tuple results is (HIT/MISS, index into TLB array)

   // Note: these are not straightforward to combine into a single
   // polymorphic function because of the different types for tags,
   // indexes and tlb_entries.

   function Maybe#(TLBE) fn_lookup (ASID asid, Maybe#(TLBE) mtlbe);
      let ret = mtlbe;
      if (mtlbe matches tagged Valid .tlbe) begin
         Bool global_mapping = (tlbe.pte [pte_G_offset] == 1'b1);
         if ((tlbe.asid_tag != asid) && !global_mapping) ret = Invalid;
      end
      return ret;
   endfunction

   // ================================================================
   // Flush
   // The actions in this rule are technically in the ma_flush method
   // but are decoupled via pw_flushing to relax scheduling constraints.

   PulseWire pw_flushing <- mkPulseWireOR;

   rule rl_flush (pw_flushing);
      // Invalidate all tlb entries
`ifdef RV64
      tlb2_entries.clear;
`endif
      tlb1_entries.clear;
      tlb0_entries.clear;
      if (verbosity > 1)
	 $display ("%0d: %m.rl_flush", cur_cycle);
   endrule

   // ================================================================
   // INTERFACE
   // Put the virtual address that mv_vm_xlate will see at least the cycle before.
   method Action mv_vm_put_va (WordXL full_va);
      Bit#(VA_sz) va = truncate(full_va);
      tlb0_entries.lookupStart(unpack(truncateLSB(va)));
      //tlb1_entries.lookupStart(unpack(truncateLSB(va)));
      //tlb2_entries.lookupStart(unpack(truncateLSB(va)));
      rg_va <= full_va;
   endmethod
   // Translate a VA to a PA (or exception)
   // plus additional info for PTE writeback (if A,D bits modified)
   method VM_Xlate_Result  mv_vm_get_xlate (
					WordXL             satp,
					Bool               read_not_write,
                    Bool               cap,
					Priv_Mode          priv,
					Bit #(1)           sstatus_SUM,
					Bit #(1)           mstatus_MXR);

      ASID asid = fn_satp_to_ASID (satp);
      // ----------------
      // Look for a matching entry for a given va in the three TLBs
      let tlbe0 = fn_lookup (asid, tlb0_entries.lookupRead);
      Bit#(VA_sz) va = truncate(rg_va);
      let tlbe1 = fn_lookup (asid, tlb1_entries.lookup(unpack(truncateLSB(va))));
`ifdef RV64
      let tlbe2 = fn_lookup (asid, tlb2_entries.lookup(unpack(truncateLSB(va))));
`endif

      TLB_Lookup_Result  result0 = unpack (0);
      TLB_Lookup_Result  result1 = unpack (0);
      TLB_Lookup_Result  result2 = unpack (0);

      if (tlbe0 matches tagged Valid .e)
         result0 = TLB_Lookup_Result {hit: True, pte: e.pte, pte_level: 0, pte_pa: e.pte_pa};
      if (tlbe1 matches tagged Valid .e)
         result1 = TLB_Lookup_Result {hit: True, pte: e.pte, pte_level: 1, pte_pa: e.pte_pa};
`ifdef RV64
      if (tlbe2 matches tagged Valid .e)
         result2 = TLB_Lookup_Result {hit: True, pte: e.pte, pte_level: 2, pte_pa: e.pte_pa};
`endif
      TLB_Lookup_Result tlb_result = unpack ((pack (result0) | pack (result1) | pack (result2)));

      // Translate, based on TLB probe
      VM_Xlate_Result   result = fv_vm_xlate (rg_va, satp, dmem_not_imem, read_not_write,
					      cap, priv, sstatus_SUM, mstatus_MXR, tlb_result);
      return result;
   endmethod

   // ----------------
   // Insert a PTE into the TLB

   method Action ma_insert (ASID asid, VPN vpn, PTE pte, Bit #(2) level, PA pte_pa);
      if (verbosity > 1)
	 $display ("%0d: %m.ma_insert: asid 0x%0h  vpn 0x%0h  pte 0x%0h  level %0d  pa 0x%0h",
		   cur_cycle, asid, vpn, pte, level, pte_pa);

      TLBE tlbe = TLBE {asid_tag: asid, pte: pte, pte_pa: pte_pa};
      case (level)
         0: tlb0_entries.update(unpack(pack(vpn)), tlbe);
         1: tlb1_entries.update(unpack(truncateLSB(vpn)), tlbe);
`ifdef RV64
         2: tlb2_entries.update(unpack(truncateLSB(vpn)), tlbe);
`endif
      endcase
   endmethod

   // Invalidate all entries, in 1 cycle
   method Action ma_flush;
      pw_flushing.send;
   endmethod

endmodule: mkTLB

// ================================================================

endpackage
