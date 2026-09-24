module p4fab_reset_sync #(
  parameter int STAGES = 3
) (
  input  logic clk,
  input  logic async_aresetn,
  output logic sync_aresetn
);
  (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_ff;

  always_ff @(posedge clk or negedge async_aresetn) begin
    if (!async_aresetn)
      sync_ff <= '0;
    else
      sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
  end

  assign sync_aresetn = sync_ff[STAGES-1];
endmodule
