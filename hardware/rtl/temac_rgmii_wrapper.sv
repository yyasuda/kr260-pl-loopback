`timescale 1ps/1ps
module temac_rgmii_wrapper (
  input wire gtx_clk, refclk, glbl_rstn, rx_axi_rstn, tx_axi_rstn,
  output wire [7:0] rx_axis_mac_tdata,
  output wire rx_axis_mac_tvalid, rx_axis_mac_tlast, rx_axis_mac_tuser,
  output wire rx_mac_aclk, rx_reset,
  input wire [7:0] tx_axis_mac_tdata,
  input wire tx_axis_mac_tvalid, tx_axis_mac_tlast, tx_axis_mac_tuser,
  output wire tx_axis_mac_tready, tx_mac_aclk, tx_reset,
  output wire [31:0] tx_statistics_vector,
  output wire tx_statistics_valid,
  output wire [3:0] rgmii_txd, output wire rgmii_tx_ctl, rgmii_txc,
  input wire [3:0] rgmii_rxd, input wire rgmii_rx_ctl, rgmii_rxc
);
  wire [27:0] rx_statistics_vector; wire rx_statistics_valid;
  wire speedis100, speedis10100, inband_link_status, inband_duplex_status;
  wire [1:0] inband_clock_speed;
  temac_0 u_temac (
    .gtx_clk(gtx_clk), .refclk(refclk), .glbl_rstn(glbl_rstn),
    .rx_axi_rstn(rx_axi_rstn), .tx_axi_rstn(tx_axi_rstn),
    .rx_statistics_vector(rx_statistics_vector), .rx_statistics_valid(rx_statistics_valid),
    .rx_mac_aclk(rx_mac_aclk), .rx_reset(rx_reset),
    .rx_axis_mac_tdata(rx_axis_mac_tdata), .rx_axis_mac_tvalid(rx_axis_mac_tvalid),
    .rx_axis_mac_tlast(rx_axis_mac_tlast), .rx_axis_mac_tuser(rx_axis_mac_tuser),
    .tx_ifg_delay(8'h00), .tx_statistics_vector(tx_statistics_vector),
    .tx_statistics_valid(tx_statistics_valid), .tx_mac_aclk(tx_mac_aclk), .tx_reset(tx_reset),
    .tx_axis_mac_tdata(tx_axis_mac_tdata), .tx_axis_mac_tvalid(tx_axis_mac_tvalid),
    .tx_axis_mac_tlast(tx_axis_mac_tlast), .tx_axis_mac_tuser(tx_axis_mac_tuser),
    .tx_axis_mac_tready(tx_axis_mac_tready), .pause_req(1'b0), .pause_val(16'h0000),
    .speedis100(speedis100), .speedis10100(speedis10100),
    .rgmii_txd(rgmii_txd), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txc(rgmii_txc),
    .rgmii_rxd(rgmii_rxd), .rgmii_rx_ctl(rgmii_rx_ctl), .rgmii_rxc(rgmii_rxc),
    .inband_link_status(inband_link_status), .inband_clock_speed(inband_clock_speed),
    .inband_duplex_status(inband_duplex_status),
    .rx_configuration_vector(80'h2), .tx_configuration_vector(80'h2));
endmodule
