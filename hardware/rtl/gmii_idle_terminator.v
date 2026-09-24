module gmii_idle_terminator (
    output wire       gmii_rx_clk,
    output wire       gmii_tx_clk,
    output wire [7:0] gmii_rxd,
    output wire       gmii_rx_dv,
    output wire       gmii_rx_er,
    output wire       gmii_crs,
    output wire       gmii_col,
    input  wire [7:0] gmii_txd,
    input  wire       gmii_tx_en,
    input  wire       gmii_tx_er
);
    assign gmii_rx_clk = 1'b0;
    assign gmii_tx_clk = 1'b0;
    assign gmii_rxd   = 8'h00;
    assign gmii_rx_dv = 1'b0;
    assign gmii_rx_er = 1'b0;
    assign gmii_crs   = 1'b0;
    assign gmii_col   = 1'b0;

    wire unused_tx = ^{gmii_txd, gmii_tx_en, gmii_tx_er};
endmodule
