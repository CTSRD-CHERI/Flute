package HLS;

import BlueAXI4 :: *;

interface HLS_IFC;
interface AXI4_Master_Sig#(6, 64, 64, 0, 0, 0, 0, 0) m_axi_gmem;
interface AXI4Lite_Slave_Sig#(64, 64, 0, 0, 0, 0, 0) s_axi_control;
(* always_ready, always_enabled *) method Bool interrupt;
endinterface

(* synthesize *)
module mkHLS(HLS_IFC);
interface m_axi_gmem = culDeSac;
interface s_axi_control = culDeSac;
method Bool interrupt;
    return False;
endmethod
endmodule

endpackage
