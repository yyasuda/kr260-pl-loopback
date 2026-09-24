module p4fab_pack_8to32 (
  input  logic       clk,
  input  logic       aresetn,
  input  logic [7:0] s_data,
  input  logic       s_valid,
  output logic       s_ready,
  input  logic       s_last,
  output logic [31:0] m_tdata,
  output logic [3:0]  m_tkeep,
  output logic        m_tvalid,
  input  logic        m_tready,
  output logic        m_tlast
);
  logic [7:0] b0, b1, b2;
  logic [1:0] count;
  assign s_ready = ~m_tvalid;
  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      b0 <= 0; b1 <= 0; b2 <= 0; count <= 0;
      m_tdata <= 0; m_tkeep <= 0; m_tvalid <= 0; m_tlast <= 0;
    end else begin
      if (m_tvalid && m_tready) begin
        m_tvalid <= 1'b0;
        m_tlast <= 1'b0;
        m_tkeep <= 4'b0;
        m_tdata <= 32'b0;
      end
      if (s_valid && s_ready) begin
        if (count == 2'd0) begin b0 <= s_data; end
        else if (count == 2'd1) begin b1 <= s_data; end
        else if (count == 2'd2) begin b2 <= s_data; end
        if ((count == 2'd3) || s_last) begin
          case (count)
            2'd0: begin m_tdata <= {24'b0,s_data}; m_tkeep <= 4'b0001; end
            2'd1: begin m_tdata <= {16'b0,s_data,b0}; m_tkeep <= 4'b0011; end
            2'd2: begin m_tdata <= {8'b0,s_data,b1,b0};  m_tkeep <= 4'b0111; end
            default: begin m_tdata <= {s_data,b2,b1,b0}; m_tkeep <= 4'b1111; end
          endcase
          m_tlast <= s_last;
          m_tvalid <= 1'b1;
          count <= 2'd0;
        end else begin
          count <= count + 1'b1;
        end
      end
    end
  end
endmodule
