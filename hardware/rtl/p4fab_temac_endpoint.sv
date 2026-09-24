module p4fab_temac_endpoint (
  input  logic        global_aresetn,
  input  logic        p4fab_clk,
  input  logic        rx_mac_aclk,
  input  logic        rx_reset,
  input  logic        tx_reset,

  input  logic [7:0]  rx_axis_mac_tdata,
  input  logic        rx_axis_mac_tvalid,
  input  logic        rx_axis_mac_tlast,
  input  logic        rx_axis_mac_tuser,

  output logic [31:0] p4fab_rx_tdata,
  output logic [3:0]  p4fab_rx_tkeep,
  output logic        p4fab_rx_tvalid,
  input  logic        p4fab_rx_tready,
  output logic        p4fab_rx_tlast,

  input  logic [31:0] p4fab_tx_tdata,
  input  logic [3:0]  p4fab_tx_tkeep,
  input  logic        p4fab_tx_tvalid,
  output logic        p4fab_tx_tready,
  input  logic        p4fab_tx_tlast,

  output logic [7:0]  tx_axis_mac_tdata,
  output logic        tx_axis_mac_tvalid,
  input  logic        tx_axis_mac_tready,
  output logic        tx_axis_mac_tlast,
  output logic        tx_axis_mac_tuser,

  output logic        p4fab_aresetn,
  output logic        rx_path_aresetn,
  output logic        tx_path_aresetn,
  output logic [31:0] rx_busy_drop_count,
  output logic [31:0] rx_overflow_drop_count,
  output logic [31:0] rx_bad_frame_drop_count
);
  logic rx_async_aresetn, tx_async_aresetn;
  logic [7:0] rx_fb_data;
  logic rx_fb_valid, rx_fb_ready, rx_fb_last;
  logic [31:0] rx_pack_tdata;
  logic [3:0] rx_pack_tkeep;
  logic rx_pack_tvalid, rx_pack_tready, rx_pack_tlast;
  logic [31:0] rx_cdc_tdata;
  logic [3:0] rx_cdc_tkeep;
  logic rx_cdc_tvalid, rx_cdc_tready, rx_cdc_tlast;
  logic [7:0] tx_unpack_data;
  logic tx_unpack_valid, tx_unpack_ready, tx_unpack_last;
  logic tx_unpack_s_ready;
  logic [7:0] tx_fb_data;
  logic tx_fb_valid, tx_fb_ready, tx_fb_last;
  logic [31:0] tx_busy_drop_count;
  logic [31:0] tx_overflow_drop_count;
  logic [31:0] tx_bad_frame_drop_count;

  assign rx_async_aresetn = global_aresetn && !rx_reset;
  assign tx_async_aresetn = global_aresetn && !tx_reset;

  p4fab_reset_sync u_p4fab_reset_sync (
    .clk(p4fab_clk), .async_aresetn(global_aresetn),
    .sync_aresetn(p4fab_aresetn));
  p4fab_reset_sync u_rx_reset_sync (
    .clk(rx_mac_aclk), .async_aresetn(rx_async_aresetn),
    .sync_aresetn(rx_path_aresetn));
  p4fab_reset_sync u_tx_reset_sync (
    .clk(p4fab_clk), .async_aresetn(tx_async_aresetn && p4fab_aresetn),
    .sync_aresetn(tx_path_aresetn));

  p4fab_frame_buffer_noready_8 u_rx_frame_buffer (
    .clk(rx_mac_aclk), .aresetn(rx_path_aresetn),
    .s_data(rx_axis_mac_tdata), .s_valid(rx_axis_mac_tvalid),
    .s_last(rx_axis_mac_tlast), .s_error(rx_axis_mac_tuser),
    .m_data(rx_fb_data), .m_valid(rx_fb_valid),
    .m_ready(rx_fb_ready), .m_last(rx_fb_last),
    .busy_drop_count(rx_busy_drop_count),
    .overflow_drop_count(rx_overflow_drop_count),
    .bad_frame_drop_count(rx_bad_frame_drop_count));

  p4fab_pack_8to32 u_rx_packer (
    .clk(rx_mac_aclk), .aresetn(rx_path_aresetn),
    .s_data(rx_fb_data), .s_valid(rx_fb_valid),
    .s_ready(rx_fb_ready), .s_last(rx_fb_last),
    .m_tdata(rx_pack_tdata), .m_tkeep(rx_pack_tkeep),
    .m_tvalid(rx_pack_tvalid), .m_tready(rx_pack_tready),
    .m_tlast(rx_pack_tlast));

  axis_clock_converter_03m_rx u_rx_clock_converter (
    .s_axis_aresetn(rx_path_aresetn),
    .s_axis_aclk(rx_mac_aclk),
    .s_axis_tvalid(rx_pack_tvalid),
    .s_axis_tready(rx_pack_tready),
    .s_axis_tdata(rx_pack_tdata),
    .s_axis_tkeep(rx_pack_tkeep),
    .s_axis_tlast(rx_pack_tlast),
    .m_axis_aresetn(p4fab_aresetn),
    .m_axis_aclk(p4fab_clk),
    .m_axis_tvalid(rx_cdc_tvalid),
    .m_axis_tready(rx_cdc_tready),
    .m_axis_tdata(rx_cdc_tdata),
    .m_axis_tkeep(rx_cdc_tkeep),
    .m_axis_tlast(rx_cdc_tlast));

  assign p4fab_rx_tdata  = rx_cdc_tdata;
  assign p4fab_rx_tkeep  = rx_cdc_tkeep;
  assign p4fab_rx_tlast  = rx_cdc_tlast;
  assign p4fab_rx_tvalid = p4fab_aresetn && rx_cdc_tvalid;
  assign rx_cdc_tready   = p4fab_aresetn && p4fab_rx_tready;

  p4fab_unpack_32to8 u_tx_unpacker (
    .clk(p4fab_clk), .aresetn(tx_path_aresetn),
    .s_tdata(p4fab_tx_tdata), .s_tkeep(p4fab_tx_tkeep),
    .s_tvalid(p4fab_tx_tvalid && tx_path_aresetn),
    .s_tready(tx_unpack_s_ready), .s_tlast(p4fab_tx_tlast),
    .m_data(tx_unpack_data), .m_valid(tx_unpack_valid),
    .m_ready(tx_unpack_ready), .m_last(tx_unpack_last));

  assign p4fab_tx_tready    = tx_path_aresetn && tx_unpack_s_ready;
  // Keep the existing unpacker bubble and absorb it with a complete-frame
  // store-and-forward buffer before the TEMAC TX client interface.
  assign tx_unpack_ready = tx_path_aresetn;

  p4fab_frame_buffer_noready_8 u_tx_frame_buffer (
    .clk(p4fab_clk), .aresetn(tx_path_aresetn),
    .s_data(tx_unpack_data), .s_valid(tx_unpack_valid),
    .s_last(tx_unpack_last), .s_error(1'b0),
    .m_data(tx_fb_data), .m_valid(tx_fb_valid),
    .m_ready(tx_fb_ready), .m_last(tx_fb_last),
    .busy_drop_count(tx_busy_drop_count),
    .overflow_drop_count(tx_overflow_drop_count),
    .bad_frame_drop_count(tx_bad_frame_drop_count));

  assign tx_fb_ready          = tx_path_aresetn && tx_axis_mac_tready;
  assign tx_axis_mac_tdata    = tx_fb_data;
  assign tx_axis_mac_tvalid   = tx_path_aresetn && tx_fb_valid;
  assign tx_axis_mac_tlast    = tx_path_aresetn && tx_fb_last;
  assign tx_axis_mac_tuser  = 1'b0;
endmodule
