package HLS;

import BlueBasics :: *;
import BlueAXI4   :: *;
import Vector     :: *;

interface HLS_IFC_Sig;
  interface AXI4_Master_Sig#(6, 64, 32, 0, 0, 0, 0, 0) m_axi_gmem;
  interface AXI4Lite_Slave_Sig#(64, 32, 0, 0, 0, 0, 0) s_axi_control;
  (* always_ready, always_enabled *) method Bool interrupt;
endinterface

interface HLS_IFC;
  interface AXI4_Master#(6, 64, 32, 0, 0, 0, 0, 0) m_axi_gmem;
  interface AXI4Lite_Slave#(64, 32, 0, 0, 0, 0, 0) s_axi_control;
  (* always_ready, always_enabled *) method Bool interrupt;
endinterface

interface HLS_Group_IFC#(numeric type n);
  interface AXI4_Master#(6, 64, 32, 0, 0, 0, 0, 0) m_axi_gmem;
  interface AXI4Lite_Slave#(64, 32, 0, 0, 0, 0, 0) s_axi_control;
  (* always_ready, always_enabled *) method Vector#(n, Bool) interrupt;
endinterface

(* synthesize *)
module mkHLS_Sig(HLS_IFC_Sig);
  interface m_axi_gmem = culDeSac;
  interface s_axi_control = culDeSac;
  method Bool interrupt;
    return False;
  endmethod
endmodule

module mkHLS(HLS_IFC);
  let ifc_Sig <- mkHLS_Sig;
  let gmem <- fromAXI4_Master_Sig(ifc_Sig.m_axi_gmem);
  let control <-fromAXI4Lite_Slave_Sig(ifc_Sig.s_axi_control);
  interface m_axi_gmem = gmem;
  interface s_axi_control = control;
  method interrupt = ifc_Sig.interrupt;
endmodule

typeclass MkHLSGroup #(numeric type n);
  module mkHLSGroup(HLS_Group_IFC#(n));
endtypeclass

instance MkHLSGroup #(1);
  module mkHLSGroup(HLS_Group_IFC#(1));
    let ifc <- mkHLS;
    interface m_axi_gmem = ifc.m_axi_gmem;
    interface s_axi_control = ifc.s_axi_control;
    method interrupt = cons(ifc.interrupt, nil);
  endmodule
endinstance


instance MkHLSGroup #(n)
  provisos ( Add#(a__, TLog#(n), 64)
           , Add#(b__, 1, n)
           , Add#(c__, TLog #(n), 6)
           );
  module mkHLSGroup(HLS_Group_IFC#(n));

    let ctrl_shim <- mkAXI4LiteShimFF;

    NumProxy#(n) nbEntriesProxy =
      error("Don't look inside a proxy and give me type application");
    NumProxy#(1) depthProxy =
      error("Don't look inside a proxy and give me type application");
    match {.gmem_s, .gmem_m} <-
      mkAXI4IDNameSpaceCrossing(nbEntriesProxy, depthProxy);
    Vector#(n, HLS_IFC) ifcs <- replicateM(mkHLS);
    function AXI4Lite_Slave#(64, 32, 0, 0, 0, 0, 0) get_ctrl (HLS_IFC x) = x.s_axi_control;
    function AXI4_Master#(6, 64, 32, 0, 0, 0, 0, 0) get_gmem (HLS_IFC x) = x.m_axi_gmem;
    function Bool get_irq (HLS_IFC x) = x.interrupt;

    `define RANGE_SHIFT 12 // 4KiB of register space per hls
    function Vector#(m, Bool) route_ctrl (Bit#(64) addr) provisos (Add#(a__, TLog#(m), 64));
      Vector#(m, Bool) where_to = replicate(False);
      Bit#(TLog#(m)) idx = truncate(addr>>`RANGE_SHIFT);
      where_to[idx] = True;
      return where_to;
    endfunction
    mkAXI4LiteBus(route_ctrl, cons(ctrl_shim.master, nil), map(get_ctrl, ifcs));

    mkAXI4Bus( constFn(cons(True, nil))
             , map(get_gmem, ifcs)
             , cons(gmem_s, nil) );
    interface m_axi_gmem = gmem_m;
    interface s_axi_control = ctrl_shim.slave;
    method interrupt = map(get_irq, ifcs);

  endmodule
endinstance

endpackage
