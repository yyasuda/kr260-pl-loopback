`timescale 1ps/1ps
module stage1g4_hw_top (
  input wire som240_1_connector_hpa_clk0p_clk,
  output wire [3:0] rgmii_txd, output wire rgmii_tx_ctl, output wire rgmii_txc,
  input wire [3:0] rgmii_rxd, input wire rgmii_rx_ctl, input wire rgmii_rxc,
  output wire phy_reset_n,
  output wire phy_mdc,
  inout wire phy_mdio
);
  wire gtx_clk, refclk, clocks_locked;
  reg [7:0] reset_count = 0;
  reg resetn = 0;

  stage1g4_clk_wiz u_clk_wiz (
    .clk_in1(som240_1_connector_hpa_clk0p_clk), .clk_out1(gtx_clk),
    .clk_out2(refclk), .locked(clocks_locked));
  always @(posedge gtx_clk or negedge clocks_locked) begin
    if (!clocks_locked) begin reset_count <= 0; resetn <= 0; end
    else if (!resetn) begin reset_count <= reset_count + 1'b1; if (&reset_count) resetn <= 1; end
  end
  assign phy_reset_n = resetn;

  stage1g4_ps_usb_gem2_mdio_wrapper u_ps_mdio (
    .MDIO_PHY_mdc(phy_mdc),
    .MDIO_PHY_mdio_io(phy_mdio));

  wire [7:0] rx_axis_mac_tdata;
  wire rx_axis_mac_tvalid, rx_axis_mac_tlast, rx_axis_mac_tuser;
  wire rx_mac_aclk, rx_reset, tx_axis_mac_tready, tx_mac_aclk, tx_reset;
  wire [7:0] tx_axis_mac_tdata;
  wire tx_axis_mac_tvalid, tx_axis_mac_tlast, tx_axis_mac_tuser;
  wire [31:0] tx_statistics_vector;
  wire tx_statistics_valid;

  // The P4Fab v1 boundary remains explicit.  This checkpoint connects it as
  // the minimum 32-bit AXI4-Stream loopback used by the later hardware test.
  (* keep = "true" *) wire [31:0] p4fab_loop_tdata;
  (* keep = "true" *) wire [3:0] p4fab_loop_tkeep;
  (* keep = "true" *) wire p4fab_loop_tvalid;
  (* keep = "true" *) wire p4fab_loop_tready;
  (* keep = "true" *) wire p4fab_loop_tlast;
  wire p4fab_aresetn, rx_path_aresetn, tx_path_aresetn;
  wire [31:0] rx_busy_drop_count, rx_overflow_drop_count, rx_bad_frame_drop_count;

  // Debug-only vectors for the 03m-5 P4Fab/TX observer.  They do not
  // participate in the functional datapath.
  wire [2:0] ila_p4fab_control;
  wire [5:0] ila_tx_reset_control;
  assign ila_p4fab_control = {p4fab_loop_tlast, p4fab_loop_tready,
                              p4fab_loop_tvalid};
  assign ila_tx_reset_control = {tx_reset, tx_path_aresetn, p4fab_aresetn,
                                 tx_axis_mac_tlast, tx_axis_mac_tready,
                                 tx_axis_mac_tvalid};

  temac_rgmii_wrapper u_temac_wrapper (
    .gtx_clk(gtx_clk), .refclk(refclk), .glbl_rstn(resetn),
    .rx_axi_rstn(resetn), .tx_axi_rstn(resetn),
    .rx_axis_mac_tdata(rx_axis_mac_tdata), .rx_axis_mac_tvalid(rx_axis_mac_tvalid),
    .rx_axis_mac_tlast(rx_axis_mac_tlast), .rx_axis_mac_tuser(rx_axis_mac_tuser),
    .rx_mac_aclk(rx_mac_aclk), .rx_reset(rx_reset),
    .tx_axis_mac_tdata(tx_axis_mac_tdata), .tx_axis_mac_tvalid(tx_axis_mac_tvalid),
    .tx_axis_mac_tlast(tx_axis_mac_tlast), .tx_axis_mac_tuser(tx_axis_mac_tuser),
    .tx_axis_mac_tready(tx_axis_mac_tready), .tx_mac_aclk(tx_mac_aclk), .tx_reset(tx_reset),
    .tx_statistics_vector(tx_statistics_vector), .tx_statistics_valid(tx_statistics_valid),
    .rgmii_txd(rgmii_txd), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txc(rgmii_txc),
    .rgmii_rxd(rgmii_rxd), .rgmii_rx_ctl(rgmii_rx_ctl), .rgmii_rxc(rgmii_rxc));

  // p4fab_clk is deliberately the existing gtx_clk.  TEMAC's generated
  // tx_mac_aclk is checked post-synthesis to be the same clock net/domain.
  (* keep_hierarchy = "yes", dont_touch = "yes" *)
  p4fab_temac_endpoint u_p4fab_endpoint (
    .global_aresetn(resetn), .p4fab_clk(gtx_clk),
    .rx_mac_aclk(rx_mac_aclk), .rx_reset(rx_reset), .tx_reset(tx_reset),
    .rx_axis_mac_tdata(rx_axis_mac_tdata),
    .rx_axis_mac_tvalid(rx_axis_mac_tvalid),
    .rx_axis_mac_tlast(rx_axis_mac_tlast),
    .rx_axis_mac_tuser(rx_axis_mac_tuser),
    .p4fab_rx_tdata(p4fab_loop_tdata),
    .p4fab_rx_tkeep(p4fab_loop_tkeep),
    .p4fab_rx_tvalid(p4fab_loop_tvalid),
    .p4fab_rx_tready(p4fab_loop_tready),
    .p4fab_rx_tlast(p4fab_loop_tlast),
    .p4fab_tx_tdata(p4fab_loop_tdata),
    .p4fab_tx_tkeep(p4fab_loop_tkeep),
    .p4fab_tx_tvalid(p4fab_loop_tvalid),
    .p4fab_tx_tready(p4fab_loop_tready),
    .p4fab_tx_tlast(p4fab_loop_tlast),
    .tx_axis_mac_tdata(tx_axis_mac_tdata),
    .tx_axis_mac_tvalid(tx_axis_mac_tvalid),
    .tx_axis_mac_tready(tx_axis_mac_tready),
    .tx_axis_mac_tlast(tx_axis_mac_tlast),
    .tx_axis_mac_tuser(tx_axis_mac_tuser),
    .p4fab_aresetn(p4fab_aresetn),
    .rx_path_aresetn(rx_path_aresetn),
    .tx_path_aresetn(tx_path_aresetn),
    .rx_busy_drop_count(rx_busy_drop_count),
    .rx_overflow_drop_count(rx_overflow_drop_count),
    .rx_bad_frame_drop_count(rx_bad_frame_drop_count));

  ila_03m5_p4fab_tx u_ila_03m5_p4fab_tx (
    .clk(gtx_clk),
    .probe0(p4fab_loop_tdata),
    .probe1(p4fab_loop_tkeep),
    .probe2(ila_p4fab_control),
    .probe3(tx_axis_mac_tdata),
    .probe4(ila_tx_reset_control));
endmodule
