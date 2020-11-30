package ISA_Decls_CSR;
// TODO make this `included rather than imported?

typedef enum {
   // machine mode
   SCR_MTDC,
   SCR_MTCC,
   SCR_MEPCC,
   SCR_MSCRATCHC,
   CSR_MSCRATCH,

   // supervisor mode
   SCR_STDC,
   SCR_STCC,
   SCR_SEPCC,
   SCR_SSCRATCHC,
   CSR_SSCRATCH,

   // debug
   CSR_TSELECT,
   CSR_TDATA1,
   CSR_TDATA2,
   CSR_TDATA3,
   CSR_DSCRATCH0,
   CSR_DSCRATCH1
} CSR_SCR_RegName deriving (Eq, Bits, FShow, Bounded);


endpackage
