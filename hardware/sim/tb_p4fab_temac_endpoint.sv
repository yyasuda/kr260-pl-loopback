`timescale 1ns/1ps
module tb_p4fab_temac_endpoint;
  logic p4fab_clk = 0, rx_mac_aclk = 0;
  logic global_aresetn = 0, rx_reset = 0, tx_reset = 0;
  always #4.0 p4fab_clk = ~p4fab_clk;
  always #4.1 rx_mac_aclk = ~rx_mac_aclk;

  logic [7:0] rx_axis_mac_tdata = 0;
  logic rx_axis_mac_tvalid = 0, rx_axis_mac_tlast = 0, rx_axis_mac_tuser = 0;
  logic [31:0] p4fab_rx_tdata;
  logic [3:0] p4fab_rx_tkeep;
  logic p4fab_rx_tvalid, p4fab_rx_tready = 1, p4fab_rx_tlast;
  logic [31:0] p4fab_tx_tdata = 0;
  logic [3:0] p4fab_tx_tkeep = 0;
  logic p4fab_tx_tvalid = 0, p4fab_tx_tready, p4fab_tx_tlast = 0;
  logic [7:0] tx_axis_mac_tdata;
  logic tx_axis_mac_tvalid, tx_axis_mac_tready = 1;
  logic tx_axis_mac_tlast, tx_axis_mac_tuser;
  logic p4fab_aresetn, rx_path_aresetn, tx_path_aresetn;
  logic [31:0] rx_busy_drop_count, rx_overflow_drop_count, rx_bad_frame_drop_count;

  p4fab_temac_endpoint dut (.*);

  byte expected[0:139];
  int frame_len[0:1];
  int out_pos = 0, out_frame = 0;
  int errors = 0, source_starvation = 0, output_stalls = 0;
  int unpacker_gap_cycles = 0, completed_frames = 0, started_frames = 0;
  int ready_tick = 0;
  bit stall_enable = 0, output_frame_open = 0, unpack_capture_open = 0;
  logic hold_valid = 0, hold_ready = 1, hold_last = 0;
  logic [7:0] hold_data = 0;

  initial begin
    #2000000;
    $fatal(1, "TIMEOUT out_frame=%0d out_pos=%0d errors=%0d", out_frame, out_pos, errors);
  end

  // Case B/C deliberately applies TEMAC backpressure.  It never changes the
  // source; the frame buffer must keep TVALID/data/TLAST stable while stalled.
  always @(negedge p4fab_clk) begin
    ready_tick++;
    if (stall_enable)
      tx_axis_mac_tready <= ((ready_tick % 7) != 2) && ((ready_tick % 11) != 5);
    else
      tx_axis_mac_tready <= 1'b1;
  end

  always @(posedge p4fab_clk) begin
    if (tx_axis_mac_tuser !== 1'b0) begin
      $display("ERROR TX TUSER not zero"); errors++;
    end

    // Prove the unchanged unpacker still creates bubbles at buffer input.
    if (dut.tx_unpack_valid && dut.tx_unpack_ready) begin
      if (!unpack_capture_open) unpack_capture_open = 1;
      if (dut.tx_unpack_last) begin
        unpack_capture_open = 0;
        completed_frames++;
      end
    end else if (unpack_capture_open && !dut.tx_unpack_valid) begin
      unpacker_gap_cycles++;
    end

    // No TEMAC-side TVALID may appear before input TLAST was stored.
    if (tx_axis_mac_tvalid && !output_frame_open && completed_frames <= started_frames) begin
      $display("ERROR output started before complete frame was stored"); errors++;
    end

    // Once the first byte handshakes, ready-high/valid-low is starvation.
    if (output_frame_open && tx_axis_mac_tready && !tx_axis_mac_tvalid) begin
      $display("ERROR source starvation at output byte %0d", out_pos);
      source_starvation++; errors++;
    end

    if (hold_valid && !hold_ready &&
        (!tx_axis_mac_tvalid || tx_axis_mac_tdata !== hold_data ||
         tx_axis_mac_tlast !== hold_last)) begin
      $display("ERROR output changed during TREADY stall"); errors++;
    end
    hold_valid <= tx_axis_mac_tvalid;
    hold_ready <= tx_axis_mac_tready;
    hold_data <= tx_axis_mac_tdata;
    hold_last <= tx_axis_mac_tlast;

    if (tx_axis_mac_tvalid && !tx_axis_mac_tready) output_stalls++;
    if (tx_axis_mac_tvalid && tx_axis_mac_tready) begin
      int frame_end;
      if (!output_frame_open) begin
        output_frame_open = 1;
        started_frames++;
      end
      if (tx_axis_mac_tdata !== expected[out_pos]) begin
        $display("ERROR data pos=%0d exp=%02x got=%02x",
          out_pos, expected[out_pos], tx_axis_mac_tdata); errors++;
      end
      out_pos++;
      frame_end = 0;
      for (int f=0; f<=out_frame; f++) frame_end += frame_len[f];
      if (tx_axis_mac_tlast !== (out_pos == frame_end)) begin
        $display("ERROR TLAST pos=%0d expected_end=%0d", out_pos, frame_end); errors++;
      end
      if (tx_axis_mac_tlast) begin
        output_frame_open = 0;
        out_frame++;
      end
    end
  end

  task automatic send_p4fab_frame(input int len, input int base);
    int pos, n;
    logic [31:0] data;
    logic [3:0] keep;
    pos = 0;
    while (pos < len) begin
      n = ((len-pos) >= 4) ? 4 : (len-pos);
      data = '0;
      for (int i=0; i<n; i++) data[i*8 +: 8] = base+pos+i;
      keep = (1 << n)-1;
      @(negedge p4fab_clk);
      p4fab_tx_tdata <= data;
      p4fab_tx_tkeep <= keep;
      p4fab_tx_tlast <= (pos+n == len);
      p4fab_tx_tvalid <= 1;
      do @(posedge p4fab_clk); while (!p4fab_tx_tready);
      @(negedge p4fab_clk);
      p4fab_tx_tvalid <= 0;
      p4fab_tx_tlast <= 0;
      p4fab_tx_tkeep <= 0;
      pos += n;
    end
  endtask

  task automatic wait_paths_ready;
    wait (p4fab_aresetn && rx_path_aresetn && tx_path_aresetn);
    repeat (8) @(posedge p4fab_clk);
  endtask

  initial begin
    frame_len[0] = 60;
    frame_len[1] = 80;
    for (int i=0; i<60; i++) expected[i] = byte'(8'h10+i);
    for (int i=0; i<80; i++) expected[60+i] = byte'(8'h80+i);

    repeat (8) @(posedge p4fab_clk);
    global_aresetn <= 1;
    wait_paths_ready();

    // Case A/D: 60 bytes, old unpacker gaps present, TEMAC always ready.
    send_p4fab_frame(60, 8'h10);
    wait (out_frame == 1);
    repeat (6) @(posedge p4fab_clk);

    // Case B/C/D: 80 bytes with repeatable mid-frame TEMAC stalls.
    stall_enable = 1;
    ready_tick = 0;
    send_p4fab_frame(80, 8'h80);
    wait (out_frame == 2);
    stall_enable = 0;
    repeat (10) @(posedge p4fab_clk);

    if (out_pos != 140 || completed_frames != 2 || started_frames != 2 ||
        unpacker_gap_cycles == 0 || output_stalls == 0 ||
        source_starvation != 0 || output_frame_open ||
        dut.tx_busy_drop_count != 0 || dut.tx_overflow_drop_count != 0 ||
        dut.tx_bad_frame_drop_count != 0 || errors != 0)
      $fatal(1, "03M6_TX_FRAME_BUFFER_FAIL errors=%0d bytes=%0d frames=%0d completed=%0d unpack_gaps=%0d output_stalls=%0d starvation=%0d drops=%0d/%0d/%0d",
        errors, out_pos, out_frame, completed_frames, unpacker_gap_cycles,
        output_stalls, source_starvation, dut.tx_busy_drop_count,
        dut.tx_overflow_drop_count, dut.tx_bad_frame_drop_count);

    $display("03M6_TX_FRAME_BUFFER_PASS frames=2 bytes=140 case60=PASS case80=PASS unpacker_gap_cycles=%0d temac_output_stalls=%0d temac_source_starvation=%0d tlast_final_only=PASS store_forward=PASS",
      unpacker_gap_cycles, output_stalls, source_starvation);
    $finish;
  end
endmodule
