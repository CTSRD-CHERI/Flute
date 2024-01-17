// Ports:
// Name                         I/O  size props
// m_axi_gmem_awid                O     6 const
// m_axi_gmem_awaddr              O    64 const
// m_axi_gmem_awlen               O     8 const
// m_axi_gmem_awsize              O     3 const
// m_axi_gmem_awburst             O     2 const
// m_axi_gmem_awlock              O     1 const
// m_axi_gmem_awcache             O     4 const
// m_axi_gmem_awprot              O     3 const
// m_axi_gmem_awqos               O     4 const
// m_axi_gmem_awregion            O     4 const
// m_axi_gmem_awvalid             O     1 const
// m_axi_gmem_wdata               O    32 const
// m_axi_gmem_wstrb               O     4 const
// m_axi_gmem_wlast               O     1 const
// m_axi_gmem_wvalid              O     1 const
// m_axi_gmem_bready              O     1 const
// m_axi_gmem_arid                O     6 const
// m_axi_gmem_araddr              O    64 const
// m_axi_gmem_arlen               O     8 const
// m_axi_gmem_arsize              O     3 const
// m_axi_gmem_arburst             O     2 const
// m_axi_gmem_arlock              O     1 const
// m_axi_gmem_arcache             O     4 const
// m_axi_gmem_arprot              O     3 const
// m_axi_gmem_arqos               O     4 const
// m_axi_gmem_arregion            O     4 const
// m_axi_gmem_arvalid             O     1 const
// m_axi_gmem_rready              O     1 const
// s_axi_control_awready          O     1 const
// s_axi_control_wready           O     1 const
// s_axi_control_bresp            O     2 const
// s_axi_control_bvalid           O     1 const
// s_axi_control_arready          O     1 const
// s_axi_control_rdata            O    32 const
// s_axi_control_rresp            O     2 const
// s_axi_control_rvalid           O     1 const
// interrupt                      O     1 const
// CLK                            I     1 unused
// RST_N                          I     1 unused
// m_axi_gmem_awready             I     1 unused
// m_axi_gmem_wready              I     1 unused
// m_axi_gmem_bvalid              I     1 unused
// m_axi_gmem_bid                 I     6 unused
// m_axi_gmem_bresp               I     2 unused
// m_axi_gmem_arready             I     1 unused
// m_axi_gmem_rvalid              I     1 unused
// m_axi_gmem_rid                 I     6 unused
// m_axi_gmem_rdata               I    32 unused
// m_axi_gmem_rresp               I     2 unused
// m_axi_gmem_rlast               I     1 unused
// s_axi_control_awvalid          I     1 unused
// s_axi_control_awaddr           I    64 unused
// s_axi_control_awprot           I     3 unused
// s_axi_control_wvalid           I     1 unused
// s_axi_control_wdata            I    32 unused
// s_axi_control_wstrb            I     4 unused
// s_axi_control_bready           I     1 unused
// s_axi_control_arvalid          I     1 unused
// s_axi_control_araddr           I    64 unused
// s_axi_control_arprot           I     3 unused
// s_axi_control_rready           I     1 unused
//
// No combinational paths from inputs to outputs
//
//

`ifdef BSV_ASSIGNMENT_DELAY
`else
  `define BSV_ASSIGNMENT_DELAY
`endif

`ifdef BSV_POSITIVE_RESET
  `define BSV_RESET_VALUE 1'b1
  `define BSV_RESET_EDGE posedge
`else
  `define BSV_RESET_VALUE 1'b0
  `define BSV_RESET_EDGE negedge
`endif

module mkHLS_Sig(CLK,
                 RST_N,

                 m_axi_gmem_awid,

                 m_axi_gmem_awaddr,

                 m_axi_gmem_awlen,

                 m_axi_gmem_awsize,

                 m_axi_gmem_awburst,

                 m_axi_gmem_awlock,

                 m_axi_gmem_awcache,

                 m_axi_gmem_awprot,

                 m_axi_gmem_awqos,

                 m_axi_gmem_awregion,

                 m_axi_gmem_awvalid,

                 m_axi_gmem_awready,

                 m_axi_gmem_wdata,

                 m_axi_gmem_wstrb,

                 m_axi_gmem_wlast,

                 m_axi_gmem_wvalid,

                 m_axi_gmem_wready,

                 m_axi_gmem_bvalid,
                 m_axi_gmem_bid,
                 m_axi_gmem_bresp,

                 m_axi_gmem_bready,

                 m_axi_gmem_arid,

                 m_axi_gmem_araddr,

                 m_axi_gmem_arlen,

                 m_axi_gmem_arsize,

                 m_axi_gmem_arburst,

                 m_axi_gmem_arlock,

                 m_axi_gmem_arcache,

                 m_axi_gmem_arprot,

                 m_axi_gmem_arqos,

                 m_axi_gmem_arregion,

                 m_axi_gmem_arvalid,

                 m_axi_gmem_arready,

                 m_axi_gmem_rvalid,
                 m_axi_gmem_rid,
                 m_axi_gmem_rdata,
                 m_axi_gmem_rresp,
                 m_axi_gmem_rlast,

                 m_axi_gmem_rready,

                 s_axi_control_awvalid,
                 s_axi_control_awaddr,
                 s_axi_control_awprot,

                 s_axi_control_awready,

                 s_axi_control_wvalid,
                 s_axi_control_wdata,
                 s_axi_control_wstrb,

                 s_axi_control_wready,

                 s_axi_control_bresp,

                 s_axi_control_bvalid,

                 s_axi_control_bready,

                 s_axi_control_arvalid,
                 s_axi_control_araddr,
                 s_axi_control_arprot,

                 s_axi_control_arready,

                 s_axi_control_rdata,

                 s_axi_control_rresp,

                 s_axi_control_rvalid,

                 s_axi_control_rready,

                 interrupt);
  input  CLK;
  input  RST_N;

  // value method m_axi_gmem_aw_awid
  output [5 : 0] m_axi_gmem_awid;

  // value method m_axi_gmem_aw_awaddr
  output [63 : 0] m_axi_gmem_awaddr;

  // value method m_axi_gmem_aw_awlen
  output [7 : 0] m_axi_gmem_awlen;

  // value method m_axi_gmem_aw_awsize
  output [2 : 0] m_axi_gmem_awsize;

  // value method m_axi_gmem_aw_awburst
  output [1 : 0] m_axi_gmem_awburst;

  // value method m_axi_gmem_aw_awlock
  output m_axi_gmem_awlock;

  // value method m_axi_gmem_aw_awcache
  output [3 : 0] m_axi_gmem_awcache;

  // value method m_axi_gmem_aw_awprot
  output [2 : 0] m_axi_gmem_awprot;

  // value method m_axi_gmem_aw_awqos
  output [3 : 0] m_axi_gmem_awqos;

  // value method m_axi_gmem_aw_awregion
  output [3 : 0] m_axi_gmem_awregion;

  // value method m_axi_gmem_aw_awuser

  // value method m_axi_gmem_aw_awvalid
  output m_axi_gmem_awvalid;

  // action method m_axi_gmem_aw_awready
  input  m_axi_gmem_awready;

  // value method m_axi_gmem_w_wdata
  output [31 : 0] m_axi_gmem_wdata;

  // value method m_axi_gmem_w_wstrb
  output [3 : 0] m_axi_gmem_wstrb;

  // value method m_axi_gmem_w_wlast
  output m_axi_gmem_wlast;

  // value method m_axi_gmem_w_wuser

  // value method m_axi_gmem_w_wvalid
  output m_axi_gmem_wvalid;

  // action method m_axi_gmem_w_wready
  input  m_axi_gmem_wready;

  // action method m_axi_gmem_b_bflit
  input  m_axi_gmem_bvalid;
  input  [5 : 0] m_axi_gmem_bid;
  input  [1 : 0] m_axi_gmem_bresp;

  // value method m_axi_gmem_b_bready
  output m_axi_gmem_bready;

  // value method m_axi_gmem_ar_arid
  output [5 : 0] m_axi_gmem_arid;

  // value method m_axi_gmem_ar_araddr
  output [63 : 0] m_axi_gmem_araddr;

  // value method m_axi_gmem_ar_arlen
  output [7 : 0] m_axi_gmem_arlen;

  // value method m_axi_gmem_ar_arsize
  output [2 : 0] m_axi_gmem_arsize;

  // value method m_axi_gmem_ar_arburst
  output [1 : 0] m_axi_gmem_arburst;

  // value method m_axi_gmem_ar_arlock
  output m_axi_gmem_arlock;

  // value method m_axi_gmem_ar_arcache
  output [3 : 0] m_axi_gmem_arcache;

  // value method m_axi_gmem_ar_arprot
  output [2 : 0] m_axi_gmem_arprot;

  // value method m_axi_gmem_ar_arqos
  output [3 : 0] m_axi_gmem_arqos;

  // value method m_axi_gmem_ar_arregion
  output [3 : 0] m_axi_gmem_arregion;

  // value method m_axi_gmem_ar_aruser

  // value method m_axi_gmem_ar_arvalid
  output m_axi_gmem_arvalid;

  // action method m_axi_gmem_ar_arready
  input  m_axi_gmem_arready;

  // action method m_axi_gmem_r_rflit
  input  m_axi_gmem_rvalid;
  input  [5 : 0] m_axi_gmem_rid;
  input  [31 : 0] m_axi_gmem_rdata;
  input  [1 : 0] m_axi_gmem_rresp;
  input  m_axi_gmem_rlast;

  // value method m_axi_gmem_r_rready
  output m_axi_gmem_rready;

  // action method s_axi_control_aw_awflit
  input  s_axi_control_awvalid;
  input  [63 : 0] s_axi_control_awaddr;
  input  [2 : 0] s_axi_control_awprot;

  // value method s_axi_control_aw_awready
  output s_axi_control_awready;

  // action method s_axi_control_w_wflit
  input  s_axi_control_wvalid;
  input  [31 : 0] s_axi_control_wdata;
  input  [3 : 0] s_axi_control_wstrb;

  // value method s_axi_control_w_wready
  output s_axi_control_wready;

  // value method s_axi_control_b_bresp
  output [1 : 0] s_axi_control_bresp;

  // value method s_axi_control_b_buser

  // value method s_axi_control_b_bvalid
  output s_axi_control_bvalid;

  // action method s_axi_control_b_bready
  input  s_axi_control_bready;

  // action method s_axi_control_ar_arflit
  input  s_axi_control_arvalid;
  input  [63 : 0] s_axi_control_araddr;
  input  [2 : 0] s_axi_control_arprot;

  // value method s_axi_control_ar_arready
  output s_axi_control_arready;

  // value method s_axi_control_r_rdata
  output [31 : 0] s_axi_control_rdata;

  // value method s_axi_control_r_rresp
  output [1 : 0] s_axi_control_rresp;

  // value method s_axi_control_r_ruser

  // value method s_axi_control_r_rvalid
  output s_axi_control_rvalid;

  // action method s_axi_control_r_rready
  input  s_axi_control_rready;

  // value method interrupt
  output interrupt;

  hls_top # (
      .C_M_AXI_GMEM_ID_WIDTH(6),
      ) hls (
      .ap_clk(CLK),
      .ap_rst_n(RST_N),
      .m_axi_gmem_AWID(m_axi_gmem_awid),
      .m_axi_gmem_AWADDR(m_axi_gmem_awaddr),
      .m_axi_gmem_AWLEN(m_axi_gmem_awlen),
      .m_axi_gmem_AWSIZE(m_axi_gmem_awsize),
      .m_axi_gmem_AWBURST(m_axi_gmem_awburst),
      .m_axi_gmem_AWLOCK(m_axi_gmem_awlock),
      .m_axi_gmem_AWCACHE(m_axi_gmem_awcache),
      .m_axi_gmem_AWPROT(m_axi_gmem_awprot),
      .m_axi_gmem_AWQOS(m_axi_gmem_awqos),
      .m_axi_gmem_AWREGION(m_axi_gmem_awregion),
      .m_axi_gmem_AWVALID(m_axi_gmem_awvalid),
      .m_axi_gmem_AWREADY(m_axi_gmem_awready),
      .m_axi_gmem_AWUSER(/* NC */),
      .m_axi_gmem_WVALID(m_axi_gmem_wvalid),
      .m_axi_gmem_WREADY(m_axi_gmem_wready),
      .m_axi_gmem_WDATA(m_axi_gmem_wdata),
      .m_axi_gmem_WSTRB(m_axi_gmem_wstrb),
      .m_axi_gmem_WLAST(m_axi_gmem_wlast),
      .m_axi_gmem_WID(/* NC */),
      .m_axi_gmem_WUSER(/* NC */),
      .m_axi_gmem_ARVALID(m_axi_gmem_arvalid),
      .m_axi_gmem_ARREADY(m_axi_gmem_arready),
      .m_axi_gmem_ARADDR(m_axi_gmem_araddr),
      .m_axi_gmem_ARID(m_axi_gmem_arid),
      .m_axi_gmem_ARLEN(m_axi_gmem_arlen),
      .m_axi_gmem_ARSIZE(m_axi_gmem_arsize),
      .m_axi_gmem_ARBURST(m_axi_gmem_arburst),
      .m_axi_gmem_ARLOCK(m_axi_gmem_arlock),
      .m_axi_gmem_ARCACHE(m_axi_gmem_arcache),
      .m_axi_gmem_ARPROT(m_axi_gmem_arprot),
      .m_axi_gmem_ARQOS(m_axi_gmem_arqos),
      .m_axi_gmem_ARREGION(m_axi_gmem_arregion),
      .m_axi_gmem_ARUSER(/* NC */),
      .m_axi_gmem_RVALID(m_axi_gmem_rvalid),
      .m_axi_gmem_RREADY(m_axi_gmem_rready),
      .m_axi_gmem_RDATA(m_axi_gmem_rdata),
      .m_axi_gmem_RLAST(m_axi_gmem_rlast),
      .m_axi_gmem_RID(m_axi_gmem_rid),
      .m_axi_gmem_RUSER(/* NC */),
      .m_axi_gmem_RRESP(m_axi_gmem_rresp),
      .m_axi_gmem_BVALID(m_axi_gmem_bvalid),
      .m_axi_gmem_BREADY(m_axi_gmem_bready),
      .m_axi_gmem_BRESP(m_axi_gmem_bresp),
      .m_axi_gmem_BID(m_axi_gmem_bid),
      .m_axi_gmem_BUSER(/* NC */),
      .s_axi_control_AWVALID(s_axi_control_awvalid),
      .s_axi_control_AWREADY(s_axi_control_awready),
      .s_axi_control_AWADDR(s_axi_control_awaddr),
      .s_axi_control_WVALID(s_axi_control_wvalid),
      .s_axi_control_WREADY(s_axi_control_wready),
      .s_axi_control_WDATA(s_axi_control_wdata),
      .s_axi_control_WSTRB(s_axi_control_wstrb),
      .s_axi_control_ARVALID(s_axi_control_arvalid),
      .s_axi_control_ARREADY(s_axi_control_arready),
      .s_axi_control_ARADDR(s_axi_control_araddr),
      .s_axi_control_RVALID(s_axi_control_rvalid),
      .s_axi_control_RREADY(s_axi_control_rready),
      .s_axi_control_RDATA(s_axi_control_rdata),
      .s_axi_control_RRESP(s_axi_control_rresp),
      .s_axi_control_BVALID(s_axi_control_bvalid),
      .s_axi_control_BREADY(s_axi_control_bready),
      .s_axi_control_BRESP(s_axi_control_bresp),
      .interrupt(interrupt)
  );

endmodule
