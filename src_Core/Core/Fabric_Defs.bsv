// Copyright (c) 2018-2020 Bluespec, Inc. All Rights Reserved

//-
// AXI (user fields) + CHERI modifications:
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

package Fabric_Defs;

// ================================================================
// Defines key parameters of the AXI4/AXI4-Lite system interconnect
// fabric to which the core connects, such as address bus width, data
// bus width, etc.

// ***** WARNING! WARNING! WARNING! *****

// During system integration, these parameters should be checked to be
// identical to the system interconnect settings.  Strong
// type-checking (EXACT match on bus widths) will do this; but some
// languages/tools may silently ignore mismatched widths.

// ================================================================

import AXI4 :: *;
import ISA_Decls :: *;

// ================================================================
// Core local Fabric parameters

typedef 3  Num_Masters_3x4;
typedef 4  Num_Slaves_3x4;

typedef Bit#(TLog #(Num_Masters_3x4))  Master_Num_3x4;
typedef Bit#(TLog #(Num_Slaves_3x4))  Slave_Num_3x4;

// ----------------
// Width of fabric 'Id' buses
typedef 3 Wd_MId_3x4;
typedef TAdd#(Wd_MId_3x4, TLog#(Num_Masters_3x4)) Wd_SId_3x4;
typedef Wd_SId_3x4 Wd_MId;
`ifdef ISA_CHERI
`ifdef NO_TAG_CACHE
typedef Wd_MId Wd_MId_ext;
`else
typedef TAdd#(Wd_MId, 1) Wd_MId_ext;
`endif
`else
typedef Wd_MId Wd_MId_ext;
`endif

// ----------------
// Width of fabric 'addr' buses
`ifdef FABRIC64
typedef 64   Wd_Addr;
`endif

`ifdef FABRIC32
typedef 32   Wd_Addr;
`endif

typedef  Bit #(Wd_Addr)      Fabric_Addr;
typedef  TDiv #(Wd_Addr, 8)  Bytes_per_Fabric_Addr;

Integer  bytes_per_fabric_addr = valueOf (Bytes_per_Fabric_Addr);

// ----------------
// Widths of the main bus data are 128 bits. Peripherals each have a shim
// converting this down to 64 bits (and stripping tags).
// (caches <==> Bus <==> (tag controller) <==> main memory
//               |
//             Periph

typedef 64  Wd_Data;

// ----------------
// Width of fabric 'user' datapaths. Carry capability tags on data lines.
typedef 0 Wd_AW_User;
typedef Wd_AW_User Wd_AW_User_ext;
typedef 0 Wd_B_User;
typedef Wd_B_User Wd_B_User_ext;
typedef 0 Wd_AR_User;
typedef Wd_AR_User Wd_AR_User_ext;
`ifdef ISA_CHERI
typedef TMax#(TDiv#(Wd_Data, CLEN),1) Wd_W_User;
typedef TMax#(TDiv#(Wd_Data, CLEN),1) Wd_R_User;
`ifdef NO_TAG_CACHE
typedef Wd_W_User Wd_W_User_ext;
typedef Wd_R_User Wd_R_User_ext;
`else
typedef 0 Wd_W_User_ext;
typedef 0 Wd_R_User_ext;
`endif
`else
typedef 0 Wd_W_User;
typedef Wd_W_User Wd_W_User_ext;
typedef 0 Wd_R_User;
typedef Wd_R_User Wd_R_User_ext;
`endif

typedef  TDiv #(Wd_Data, 8)         Bytes_per_Fabric_Data;
Integer  bytes_per_fabric_data = valueOf (Bytes_per_Fabric_Data);

typedef  Bit #(Wd_Data)             Fabric_Data;
typedef  Bit #(TDiv #(Wd_Data, 8))  Fabric_Strb;

// ----------------
typedef 64   Wd_Data_Periph;

typedef 0    Wd_AW_User_Periph;
typedef 0    Wd_W_User_Periph;
typedef 0    Wd_B_User_Periph;
typedef 0    Wd_AR_User_Periph;
typedef 0    Wd_R_User_Periph;

typedef  Bit #(Wd_Data_Periph)             Fabric_Data_Periph;
typedef  Bit #(TDiv #(Wd_Data_Periph, 8))  Fabric_Strb_Periph;
typedef  TDiv #(Wd_Data_Periph, 8)         Bytes_per_Fabric_Data_Periph;

// ----------------
// Number of zero LSBs in a fabric address aligned to the fabric data width

typedef  TLog #(Bytes_per_Fabric_Data)  ZLSBs_Aligned_Fabric_Addr;
Integer  zlsbs_aligned_fabric_addr = valueOf (ZLSBs_Aligned_Fabric_Addr);

// ================================================================
// This part of the interface is lifted out to surrounding modules.

`ifdef MEM_512b

typedef Wd_MId_3x4 Wd_Id_Mem;
typedef 64  Wd_Addr_Mem;
typedef 512 Wd_Data_Mem;
typedef 0   Wd_AW_User_Mem;
`ifndef ISA_CHERI
typedef 0   Wd_W_User_Mem;
`else
typedef 4   Wd_W_User_Mem;
`endif
typedef 0   Wd_B_User_Mem;
typedef 0   Wd_AR_User_Mem;
`ifndef ISA_CHERI
typedef 0   Wd_R_User_Mem;
`else
typedef 4   Wd_R_User_Mem;
`endif

`else

typedef Wd_MId_3x4 Wd_Id_Mem;
typedef Wd_Addr    Wd_Addr_Mem;
typedef Wd_Data    Wd_Data_Mem;
typedef Wd_AW_User Wd_AW_User_Mem;
typedef Wd_W_User  Wd_W_User_Mem;
typedef Wd_B_User  Wd_B_User_Mem;
typedef Wd_AR_User Wd_AR_User_Mem;
typedef Wd_R_User  Wd_R_User_Mem;

`endif

typedef AXI4_Master #(Wd_Id_Mem,
			  Wd_Addr_Mem,
			  Wd_Data_Mem,
			  Wd_AW_User_Mem,
			  Wd_W_User_Mem,
			  Wd_B_User_Mem,
			  Wd_AR_User_Mem,
			  Wd_R_User_Mem)  Near_Mem_Fabric_IFC;

// ================================================================
// AXI4 defaults for this project
Bit#(Wd_MId_3x4) fabric_3x4_default_mid = 0;
Bit#(Wd_MId)     fabric_default_mid     = 0;
AXI4_Burst       fabric_default_burst   = INCR;
AXI4_Lock        fabric_default_lock    = NORMAL;
AXI4_Cache       fabric_default_arcache = arcache_dev_nonbuf;
AXI4_Cache       fabric_default_awcache = awcache_dev_nonbuf;
AXI4_Prot        fabric_default_prot    = axi4Prot(DATA, SECURE, UNPRIV);
AXI4_QoS         fabric_default_qos     = 0;
AXI4_Region      fabric_default_region  = 0;
Bit#(Wd_AW_User) fabric_default_awuser  = 0;
Bit#(Wd_W_User)  fabric_default_wuser   = 0;
Bit#(Wd_B_User)  fabric_default_buser   = 0;
Bit#(Wd_AR_User) fabric_default_aruser  = 0;
Bit#(Wd_R_User)  fabric_default_ruser   = 0;

// ================================================================

endpackage
