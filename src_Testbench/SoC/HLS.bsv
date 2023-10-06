package HLS;

import BlueBasics  :: *;
import BlueAXI4    :: *;
import Vector      :: *;
import Connectable :: *;
`ifdef HLS_CAP_CHECKER
import AXI4_CapChecker :: *;
`else
// numeric type:
// number of bits required to hold the max number of bytes in a transfer
typedef TAdd #( // AXI4 len width + 1 because of representation is -1
                TAdd #(SizeOf #(AXI4_Len), 1)
                // (2^(AXI4 size width))-1 maximum shift amount
              , TSub #(TExp #(SizeOf #(AXI4_Size)), 1) ) MaxBytesSz;
`endif

// HLS types and interfaces
////////////////////////////////////////////////////////////////////////////////

interface HLS_Sig;
  interface AXI4_Master_Sig#(1, 64, 32, 0, 0, 0, 0, 0) m_axi_gmem;
  interface AXI4Lite_Slave_Sig#(64, 32, 0, 0, 0, 0, 0) s_axi_control;
  (* always_ready, always_enabled *) method Bool interrupt;
endinterface

interface HLS#(
  // main axi4 master port parameters
    numeric type m_id_, numeric type m_addr_, numeric type m_data_
  , numeric type m_awuser_, numeric type m_wuser_, numeric type m_buser_
  , numeric type m_aruser_, numeric type m_ruser_
  // management axi4 slave port parameters
  , numeric type s_id_, numeric type s_addr_, numeric type s_data_
  , numeric type s_awuser_, numeric type s_wuser_, numeric type s_buser_
  , numeric type s_aruser_, numeric type s_ruser_
  );
  interface AXI4_Master#( m_id_, m_addr_, m_data_
                        , m_awuser_, m_wuser_, m_buser_
                        , m_aruser_, m_ruser_ ) master;
  interface AXI4_Slave#( s_id_, s_addr_, s_data_
                       , s_awuser_, s_wuser_, s_buser_
                       , s_aruser_, s_ruser_ ) management;
  (* always_ready, always_enabled *) method Bool interrupt;
endinterface

interface HLSGroup#(
  // number of HLS
    numeric type n
  // main axi4 master port parameters
  , numeric type m_id_, numeric type m_addr_, numeric type m_data_
  , numeric type m_awuser_, numeric type m_wuser_, numeric type m_buser_
  , numeric type m_aruser_, numeric type m_ruser_
  // management axi4 slave port parameters
  , numeric type s_id_, numeric type s_addr_, numeric type s_data_
  , numeric type s_awuser_, numeric type s_wuser_, numeric type s_buser_
  , numeric type s_aruser_, numeric type s_ruser_
  );
  interface AXI4_Master#( m_id_, m_addr_, m_data_
                        , m_awuser_, m_wuser_, m_buser_
                        , m_aruser_, m_ruser_ ) master;
  interface AXI4_Slave#( s_id_, s_addr_, s_data_
                       , s_awuser_, s_wuser_, s_buser_
                       , s_aruser_, s_ruser_ ) management;
  (* always_ready, always_enabled *) method Vector#(n, Bool) interrupt;
endinterface

// HLS "sig" and "non-sig" bluespec wrappers
////////////////////////////////////////////////////////////////////////////////

(* synthesize *)
module mkHLS_Sig(HLS_Sig);
  interface m_axi_gmem = culDeSac;
  interface s_axi_control = culDeSac;
  method Bool interrupt;
    return False;
  endmethod
endmodule

typeclass MkHLS#(
  // main axi4 master port parameters
    numeric type m_id_, numeric type m_addr_, numeric type m_data_
  , numeric type m_awuser_, numeric type m_wuser_, numeric type m_buser_
  , numeric type m_aruser_, numeric type m_ruser_
  // management axi4 slave port parameters
  , numeric type s_id_, numeric type s_addr_, numeric type s_data_
  , numeric type s_awuser_, numeric type s_wuser_, numeric type s_buser_
  , numeric type s_aruser_, numeric type s_ruser_
  );
  module mkHLS(HLS#( m_id_, m_addr_, m_data_
                   , m_awuser_, m_wuser_, m_buser_
                   , m_aruser_, m_ruser_
                   , s_id_, s_addr_, s_data_
                   , s_awuser_, s_wuser_, s_buser_
                   , s_aruser_, s_ruser_
                   ));
endtypeclass

// when buses are of native data width, no width shimming
instance MkHLS#( m_id_, 64, 32
               , m_awuser_, m_wuser_, m_buser_
               , m_aruser_, m_ruser_
               , s_id_, 64, 32
               , s_awuser_, s_wuser_, s_buser_
               , s_aruser_, s_ruser_
               )
  provisos(Add#(a__, 1, m_id_));
  module mkHLS(HLS#( m_id_, 64, 32
                   , m_awuser_, m_wuser_, m_buser_
                   , m_aruser_, m_ruser_
                   , s_id_, 64, 32
                   , s_awuser_, s_wuser_, s_buser_
                   , s_aruser_, s_ruser_
                   ));
    // instantiate sig wrapper
    let ifc_Sig <- mkHLS_Sig;
    // prepare management port
    let ctrlLite <-fromAXI4Lite_Slave_Sig(ifc_Sig.s_axi_control);
    let mgnt <- mkAXI4LiteToAXI4_Slave(ctrlLite);
    mgnt = zero_AXI4_Slave_user(mgnt);
    // prepare main port
    let main <- fromAXI4_Master_Sig(ifc_Sig.m_axi_gmem);
    main = zero_AXI4_Master_user(main);
    main = prepend_AXI4_Master_id(0, main);
    // external interfaces
    interface master = main;
    interface management = mgnt;
    method interrupt = ifc_Sig.interrupt;
  endmodule
endinstance

// when buses are wider than the native width
instance MkHLS#( m_id_, 64, m_data_
               , m_awuser_, m_wuser_, m_buser_
               , m_aruser_, m_ruser_
               , s_id_, 64, s_data_
               , s_awuser_, s_wuser_, s_buser_
               , s_aruser_, s_ruser_
               )
  provisos(
    Add#(a__, 32, m_data_)
  , Add#(b__, 32, s_data_)
  , Add#(c__, 1, m_id_)
    // aliases
  , NumAlias#(addr_, 64)
  , NumAlias#(mgnt_in_bit_t, s_data_)
  , NumAlias#(mgnt_out_bit_t, 32)
  , NumAlias#(main_in_bit_t, 32)
  , NumAlias#(main_out_bit_t, m_data_)
    // inherited provisos from WideToNarrow (management interface)
  , NumAlias#(mgnt_out_byte_t, TDiv#(mgnt_out_bit_t, 8))
  , NumAlias#(mgnt_out_bit_idx_t, TLog#(mgnt_out_bit_t))
  , NumAlias#(mgnt_out_byte_idx_t, TLog#(mgnt_out_byte_t))
  , NumAlias#(mgnt_in_byte_t, TDiv#(mgnt_in_bit_t, 8))
  , NumAlias#(mgnt_in_bit_idx_t, TLog#(mgnt_in_bit_t))
  , NumAlias#(mgnt_in_byte_idx_t, TLog#(mgnt_in_byte_t))
  , Mul#(mgnt_in_byte_t, 8, mgnt_in_bit_t)
  , Add#(_mgnt_a, mgnt_out_bit_t, mgnt_in_bit_t)
  , Add#(_mgnt_b, mgnt_out_byte_t, mgnt_in_byte_t)
  , Add#(_mgnt_c, mgnt_out_byte_idx_t, mgnt_out_bit_idx_t)
  , Add#(_mgnt_d, mgnt_out_byte_idx_t, addr_)
  , Add#(_mgnt_e, mgnt_out_byte_idx_t, MaxBytesSz)
  , Add#(_mgnt_f, SizeOf#(AXI4_Len), TSub#(MaxBytesSz, mgnt_out_byte_idx_t))
  , Add#(_mgnt_g, mgnt_in_byte_idx_t, MaxBytesSz)
  , Add#(_mgnt_h, mgnt_out_byte_idx_t, mgnt_in_byte_idx_t)
  , Add#(_mgnt_i, mgnt_out_bit_idx_t, mgnt_in_bit_idx_t)
  , Add#(_mgnt_j, mgnt_in_byte_idx_t, mgnt_in_bit_idx_t)
  , Add#(_mgnt_k, mgnt_in_byte_idx_t, addr_)
    // inherited provisos from NarrowToWide (main interface)
  , NumAlias#(main_out_byte_t, TDiv#(main_out_bit_t, 8))
  , NumAlias#(main_out_bit_idx_t, TLog#(main_out_bit_t))
  , NumAlias#(main_out_byte_idx_t, TLog#(main_out_byte_t))
  , NumAlias#(main_in_byte_t, TDiv#(main_in_bit_t, 8))
  , NumAlias#(main_in_bit_idx_t, TLog#(main_in_bit_t))
  , NumAlias#(main_in_byte_idx_t, TLog#(main_in_byte_t))
  , Mul#(main_out_byte_t, 8, main_out_bit_t)
  , Add#(_main_a, main_in_bit_t, main_out_bit_t)
  , Add#(_main_b, main_in_byte_t, main_out_byte_t)
  , Add#(_main_c, main_in_byte_idx_t, main_out_byte_idx_t)
  , Add#(_main_d, main_in_byte_idx_t, main_in_bit_idx_t)
  , Add#(_main_e, main_out_byte_idx_t, main_out_bit_idx_t)
  , Add#(_main_f, main_out_byte_idx_t, addr_)
  , Add#(_main_g, main_in_bit_idx_t, main_out_bit_idx_t)
  , Add#(_main_h, main_out_byte_idx_t, MaxBytesSz)
  , Add#(_main_i, SizeOf#(AXI4_Len), TSub#(MaxBytesSz, main_out_byte_idx_t))
  );
  module mkHLS(HLS#( m_id_, 64, m_data_
                   , m_awuser_, m_wuser_, m_buser_
                   , m_aruser_, m_ruser_
                   , s_id_, 64, s_data_
                   , s_awuser_, s_wuser_, s_buser_
                   , s_aruser_, s_ruser_
                   ));
    // instantiate sig wrapper
    let ifc_Sig <- mkHLS_Sig;
    // prepare management port
    let ctrlLite <-fromAXI4Lite_Slave_Sig(ifc_Sig.s_axi_control);
    AXI4_Slave#(s_id_, 64, 32, 0, 0, 0, 0, 0)
      ctrl <- mkAXI4LiteToAXI4_Slave(ctrlLite);
    NumProxy#(1)  prxMgntIn = error("don't look inside a proxy");
    NumProxy#(1) prxMgntOut = error("don't look inside a proxy");
    Tuple2#( AXI4_Slave#(s_id_, 64, s_data_, 0, 0, 0, 0, 0)
           , AXI4_Master#(s_id_, 64, 32, 0, 0, 0, 0, 0) )
      mgntShim <- mkAXI4DataWidthShim_WideToNarrow(prxMgntIn, prxMgntOut);
    match {.mgntWidthS, .mgntWidthM} = mgntShim;
    mkConnection(mgntWidthM, ctrl);
    let mgnt = zero_AXI4_Slave_user(mgntWidthS);
    // prepare main port
    let gmem <- fromAXI4_Master_Sig(ifc_Sig.m_axi_gmem);
    NumProxy#(1)  prxMainIn = error("don't look inside a proxy");
    NumProxy#(1) prxMainOut = error("don't look inside a proxy");
    Tuple2#( AXI4_Slave#(1, 64, 32, 0, 0, 0, 0, 0)
           , AXI4_Master#(1, 64, m_data_, 0, 0, 0, 0, 0) )
      mainShim <- mkAXI4DataWidthShim_NarrowToWide(prxMainIn, prxMainOut);
    match {.mainWidthS, .mainWidthM} = mainShim;
    mkConnection(gmem, mainWidthS);
    let main = zero_AXI4_Master_user(mainWidthM);
    main = prepend_AXI4_Master_id(0, main);
    // external interfaces
    interface master = main;
    interface management = mgnt;
    method interrupt = ifc_Sig.interrupt;
  endmodule
endinstance

// helper functions
////////////////////////////////////////////////////////////////////////////////

typedef 8 CapIdxSz;

function Tuple2#(Bit#(CapIdxSz), Bit#(addrSz)) extractCapIdx(Bit#(addrSz) x)
  provisos (Add#(a__, CapIdxSz, addrSz));
  Bit#(CapIdxSz) idx = truncateLSB(x);
  Bit#(TSub#(addrSz, CapIdxSz)) addr = truncate(x);
  return tuple2(idx, zeroExtend(addr));
endfunction

function AXI4_Master#(a, b, c, CapIdxSz, e, f, CapIdxSz, h)
  mapAXI4_Master_extractCapIdx(AXI4_Master#(a, b, c, d, e, f, g, h)  m)
  provisos(Add#(a__, CapIdxSz, b));
  function AXI4_AWFlit#(a, b, CapIdxSz) fAW (AXI4_AWFlit#(a, b, d) x);
    match {.user, .addr} = extractCapIdx(x.awaddr);
    return AXI4_AWFlit { awid: x.awid
                       , awaddr: addr
                       , awlen: x.awlen
                       , awsize: x.awsize
                       , awburst: x.awburst
                       , awlock: x.awlock
                       , awcache: x.awcache
                       , awprot: x.awprot
                       , awqos: x.awqos
                       , awregion: x.awregion
                       , awuser: user };
  endfunction
  function AXI4_ARFlit#(a, b, CapIdxSz) fAR (AXI4_ARFlit#(a, b, g) x);
    match {.user, .addr} = extractCapIdx(x.araddr);
    return AXI4_ARFlit { arid: x.arid
                       , araddr: addr
                       , arlen: x.arlen
                       , arsize: x.arsize
                       , arburst: x.arburst
                       , arlock: x.arlock
                       , arcache: x.arcache
                       , arprot: x.arprot
                       , arqos: x.arqos
                       , arregion: x.arregion
                       , aruser: user };
  endfunction
  return mapAXI4_Master_AW(fAW, mapAXI4_Master_AR(fAR, m));
endfunction

// HLS group family of functions
////////////////////////////////////////////////////////////////////////////////

typeclass MkHLSGroup#(
    numeric type n
  // main axi4 master port parameters
  , numeric type m_id_, numeric type m_addr_, numeric type m_data_
  , numeric type m_awuser_, numeric type m_wuser_, numeric type m_buser_
  , numeric type m_aruser_, numeric type m_ruser_
  // management axi4 slave port parameters
  , numeric type s_id_, numeric type s_addr_, numeric type s_data_
  , numeric type s_awuser_, numeric type s_wuser_, numeric type s_buser_
  , numeric type s_aruser_, numeric type s_ruser_
  );
  module mkHLSGroup(HLSGroup#( n
                             , m_id_, m_addr_, m_data_
                             , m_awuser_, m_wuser_, m_buser_
                             , m_aruser_, m_ruser_
                             , s_id_, s_addr_, s_data_
                             , s_awuser_, s_wuser_, s_buser_
                             , s_aruser_, s_ruser_
                             ));
endtypeclass

instance MkHLSGroup#( 1
                    , m_id_, m_addr_, m_data_
                    , m_awuser_, m_wuser_, m_buser_
                    , m_aruser_, m_ruser_
                    , s_id_, s_addr_, s_data_
                    , s_awuser_, s_wuser_, s_buser_
                    , s_aruser_, s_ruser_ )
  provisos(MkHLS#( m_id_, m_addr_, m_data_
                 , m_awuser_, m_wuser_, m_buser_
                 , m_aruser_, m_ruser_
                 , s_id_, s_addr_, s_data_
                 , s_awuser_, s_wuser_, s_buser_
                 , s_aruser_, s_ruser_ ));
  module mkHLSGroup(HLSGroup#( 1
                             , m_id_, m_addr_, m_data_
                             , m_awuser_, m_wuser_, m_buser_
                             , m_aruser_, m_ruser_
                             , s_id_, s_addr_, s_data_
                             , s_awuser_, s_wuser_, s_buser_
                             , s_aruser_, s_ruser_
                             ));
    let ifc <- mkHLS;
    interface master = ifc.master;
    interface management = ifc.management;
    method interrupt = cons(ifc.interrupt, nil);
  endmodule
endinstance


instance MkHLSGroup#( n
                    , m_id_, m_addr_, m_data_
                    , m_awuser_, m_wuser_, m_buser_
                    , m_aruser_, m_ruser_
                    , s_id_, s_addr_, s_data_
                    , s_awuser_, s_wuser_, s_buser_
                    , s_aruser_, s_ruser_ )
  provisos( MkHLS#( m_id_, m_addr_, m_data_
                  , m_awuser_, m_wuser_, m_buser_
                  , m_aruser_, m_ruser_
                  , s_id_, s_addr_, s_data_
                  , s_awuser_, s_wuser_, s_buser_
                  , s_aruser_, s_ruser_ )
          , Add#(a__, 1, n)
          , Add#(b__, TLog#(n), m_id_)
          , Add#(c__, TLog#(n), s_addr_)
          );
  module mkHLSGroup(HLSGroup#( n
                             , m_id_, m_addr_, m_data_
                             , m_awuser_, m_wuser_, m_buser_
                             , m_aruser_, m_ruser_
                             , s_id_, s_addr_, s_data_
                             , s_awuser_, s_wuser_, s_buser_
                             , s_aruser_, s_ruser_
                             ))
    provisos( // aliases
              Alias#(hls_ifc, HLS#( m_id_, m_addr_, m_data_
                                  , m_awuser_, m_wuser_, m_buser_
                                  , m_aruser_, m_ruser_
                                  , s_id_, s_addr_, s_data_
                                  , s_awuser_, s_wuser_, s_buser_
                                  , s_aruser_, s_ruser_
                                  ))
            );

    let mgnt_shim <- mkAXI4Shim;

    NumProxy#(n) nbEntriesProxy =
      error("Don't look inside a proxy and give me type application");
    NumProxy#(1) depthProxy =
      error("Don't look inside a proxy and give me type application");
    match {.main_s, .main_m} <-
      mkAXI4IDNameSpaceCrossing(nbEntriesProxy, depthProxy);
    Vector#(n, hls_ifc) ifcs <- replicateM(mkHLS);
    function AXI4_Slave#( s_id_, s_addr_, s_data_
                        , s_awuser_, s_wuser_, s_buser_
                        , s_aruser_, s_ruser_ )
      get_mgnt (hls_ifc x) = x.management;
    function AXI4_Master#( m_id_, m_addr_, m_data_
                         , m_awuser_, m_wuser_, m_buser_
                         , m_aruser_, m_ruser_ )
      get_main (hls_ifc x) = x.master;
    function Bool get_irq (hls_ifc x) = x.interrupt;

    `define RANGE_SHIFT 12 // 4KiB of register space per hls
    function Vector#(m, Bool) route_mgnt (Bit#(s_addr_) addr) provisos (Add#(_a, TLog#(m), s_addr_));
      Vector#(m, Bool) where_to = replicate(False);
      Bit#(TLog#(m)) idx = truncate(addr>>`RANGE_SHIFT);
      where_to[idx] = True;
      return where_to;
    endfunction
    mkAXI4Bus(route_mgnt, cons(mgnt_shim.master, nil), map(get_mgnt, ifcs));
    mkAXI4Bus(constFn(cons(True, nil)), map(get_main, ifcs), cons(main_s, nil));
    interface master = main_m;
    interface management = mgnt_shim.slave;
    method interrupt = map(get_irq, ifcs);

  endmodule
endinstance

`ifdef HLS_CAP_CHECKER
// HLS group with cap checker
////////////////////////////////////////////////////////////////////////////////

module mkHLSGroupWithCapChecker#( Range#(s_addr_) hls_mgnt_range
                                , Range#(s_addr_) cap_checker_mgnt_range )
                                (HLSGroup#( n
                                          , m_id_, 64, m_data_
                                          , m_awuser_, m_wuser_, m_buser_
                                          , m_aruser_, m_ruser_
                                          , s_id_, s_addr_, 128
                                          , s_awuser_, s_wuser_, s_buser_
                                          , s_aruser_, s_ruser_
                                          ))
  provisos( MkHLSGroup#( n
                       , m_id_, 64, m_data_
                       , m_awuser_, m_wuser_, m_buser_
                       , m_aruser_, m_ruser_
                       , s_id_, s_addr_, 128
                       , s_awuser_, s_wuser_, s_buser_
                       , s_aruser_, s_ruser_
                       )
          , Add#(a__, 1, s_wuser_)
          , Add#(b__, 1, s_ruser_)
          , Add#(c__, 8, s_addr_)
          , Add#(d__, 8, 64)
          );
  // HLS group
  ////////////
  HLSGroup#( n
           , m_id_, 64, m_data_
           , m_awuser_, m_wuser_, m_buser_
           , m_aruser_, m_ruser_
           , s_id_, s_addr_, 128
           , s_awuser_, s_wuser_, s_buser_
           , s_aruser_, s_ruser_
           ) group <- mkHLSGroup;
  let groupS = debugAXI4_Slave( group.management
                              , $format("hls management axi4 slave") );
  groupS = zero_AXI4_Slave_user(groupS);
  let groupM = debugAXI4_Master( group.master
                               , $format ("hls main axi4 master") );
  // HLS cap checker
  //////////////////
  NumProxy#(256) nCapPrxy = error("don't look inside a proxy");
  AXI4_CapChecker#( // main interfaces with both values for AW/AR
                    m_id_, 64, m_data_
                  , CapIdxSz, m_awuser_, m_wuser_, m_buser_
                  , CapIdxSz, m_aruser_, m_ruser_
                    // management slave
                  , s_id_, s_addr_, 128, s_awuser_, 1, s_buser_, s_aruser_, 1 )
    cap_checker <- mkAXI4_CapChecker(nCapPrxy);
  let capCheckS = debugAXI4_Slave( cap_checker.slave
                                 , $format("cap checker main axi4 slave") );
  let capCheckM = debugAXI4_Master( cap_checker.master
                                  , $format("cap checker main axi4 master") );
  let capCheckSMgnt = mapAXI4_Slave_user( id, truncate, id, id, zeroExtend
                                        , cap_checker.management );
  capCheckSMgnt =
    debugAXI4_Slave( capCheckSMgnt
                   , $format("cap checker management axi4 slave") );
  // internal connections
  ///////////////////////
  // from HLS to cap checker
  mkConnection(mapAXI4_Master_extractCapIdx(groupM), capCheckS);
  // demux management traffic
  let mgntShim <- mkAXI4Shim;
  let mappingTable = cons(hls_mgnt_range, cons(cap_checker_mgnt_range, nil));
  mkAXI4Bus ( routeFromMappingTable(mappingTable)
            , cons(mgntShim.master, nil)
            , cons(groupS, cons(capCheckSMgnt, nil))
            );
  // external interfaces
  //////////////////////
  interface master = capCheckM;
  interface management = mgntShim.slave;
  method interrupt = group.interrupt;

endmodule
`endif

endpackage
