module p4fab_frame_buffer_noready_8 #(
  parameter int MAX_FRAME_BYTES = 2048
) (
  input logic clk, input logic aresetn,
  input logic [7:0] s_data, input logic s_valid, input logic s_last, input logic s_error,
  output logic [7:0] m_data, output logic m_valid, input logic m_ready, output logic m_last,
  output logic [31:0] busy_drop_count,
  output logic [31:0] overflow_drop_count,
  output logic [31:0] bad_frame_drop_count
);
  localparam int PTR_W=$clog2(MAX_FRAME_BYTES);
  logic [7:0] mem[0:MAX_FRAME_BYTES-1]; logic [PTR_W-1:0] wr_ptr,rd_ptr; logic [PTR_W:0] frame_len;
  typedef enum logic [2:0] {IDLE,CAPTURE,CAPTURE_FULL,SENDING,DROP_BUSY,DROP_OVERFLOW} state_t; state_t state; logic drop_active;
  assign m_valid=(state==SENDING); assign m_data=mem[rd_ptr]; assign m_last=m_valid&&(rd_ptr==frame_len-1);
  always_ff @(posedge clk or negedge aresetn) begin
    if(!aresetn) begin state<=IDLE; wr_ptr<='0; rd_ptr<='0; frame_len<='0; busy_drop_count<='0; overflow_drop_count<='0; bad_frame_drop_count<='0; drop_active<=0; end
    else case(state)
      IDLE,CAPTURE: if(s_valid) begin mem[wr_ptr]<=s_data; if(s_last) begin frame_len<=wr_ptr+1'b1; rd_ptr<='0; wr_ptr<='0; if(s_error) begin bad_frame_drop_count<=bad_frame_drop_count+1'b1; state<=IDLE; end else state<=SENDING; end else if (wr_ptr == MAX_FRAME_BYTES-1) begin state<=CAPTURE_FULL; end else begin wr_ptr<=wr_ptr+1'b1; state<=CAPTURE; end end
      CAPTURE_FULL: if(s_valid) begin
        overflow_drop_count<=overflow_drop_count+1'b1;
        if(s_last) begin state<=IDLE; wr_ptr<='0; end else state<=DROP_OVERFLOW;
      end
      SENDING: begin
        if(!drop_active && s_valid) begin drop_active<=!s_last; busy_drop_count<=busy_drop_count+1'b1; end
        if(drop_active && s_valid && s_last) begin drop_active<=0; end
        if(m_valid&&m_ready) begin if(m_last) begin state <= ((drop_active || s_valid) && !(s_valid&&s_last)) ? DROP_BUSY : IDLE; rd_ptr<='0; end else rd_ptr<=rd_ptr+1'b1; end
      end
      DROP_BUSY: if(s_valid&&s_last) begin state<=IDLE; wr_ptr<='0; drop_active<=0; end
      DROP_OVERFLOW: if(s_valid&&s_last) begin state<=IDLE; wr_ptr<='0; end
    endcase
  end
endmodule
