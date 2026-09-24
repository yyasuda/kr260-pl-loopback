module p4fab_unpack_32to8 (
  input  logic        clk,
  input  logic        aresetn,
  input  logic [31:0] s_tdata,
  input  logic [3:0]  s_tkeep,
  input  logic        s_tvalid,
  output logic        s_tready,
  input  logic        s_tlast,
  output logic [7:0]  m_data,
  output logic        m_valid,
  input  logic        m_ready,
  output logic        m_last
);
  logic [31:0] beat_data;
  logic        beat_last;
  logic [1:0]  lane;
  logic [1:0]  last_lane;
  logic        beat_valid;

  assign s_tready = !beat_valid;
  assign m_valid  = beat_valid;
  assign m_data   = beat_data[8*lane +: 8];
  assign m_last   = beat_valid && beat_last && (lane == last_lane);

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      beat_data  <= 32'b0;
      beat_last  <= 1'b0;
      lane       <= 2'b0;
      last_lane  <= 2'b0;
      beat_valid <= 1'b0;
    end else begin
      if (beat_valid && m_ready) begin
        if (lane == last_lane) begin
          beat_valid <= 1'b0;
          lane <= 2'b0;
        end else begin
          lane <= lane + 1'b1;
        end
      end
      if (s_tvalid && s_tready) begin
        beat_data <= s_tdata;
        beat_last <= s_tlast;
        case (s_tkeep)
          4'b0001: last_lane <= 2'd0;
          4'b0011: last_lane <= 2'd1;
          4'b0111: last_lane <= 2'd2;
          default: last_lane <= 2'd3;
        endcase
        lane <= 2'b0;
        beat_valid <= 1'b1;
      end
    end
  end
endmodule
