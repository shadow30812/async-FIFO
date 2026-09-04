// Parameterised multi-stage FF synchronizer for CDC

`default_nettype none

module cdc_sync #(
    parameter int unsigned WIDTH  = 4,  // Width of each word
    parameter int unsigned STAGES = 2   // Number of stages (FFs)
) (
    // Control Signals
    input logic clk,
    input logic rst_n,

    // Data Signals
    input  logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);

  // Compile-time check for eliminating single-flop CDC
  initial begin
    if (STAGES < 2) begin
      $error("[CDC_SYNC_ERR] Synchronizer depth STAGES must be >= 2. Current: %0d", STAGES);
      $finish;
    end
  end

  (*ASYNC_REG = "TRUE" *)
  // For Vivado, disable timing checks
  (*dont_touch = "true" *)
  // Universal, stops optimizations
  logic [WIDTH-1:0] sync_pipeline[STAGES];

  always_ff @(posedge clk or negedge rst_n) begin
    // RESET to 0 (bit-independent)
    if (!rst_n) for (int unsigned i = 0; i < STAGES; i++) sync_pipeline[i] <= '0;
    else begin
      // Async input to stage 0; subsequent stages resolve metastability
      sync_pipeline[0] <= din;
      for (int unsigned i = 1; i < STAGES; i++) sync_pipeline[i] <= sync_pipeline[i-1];
    end
  end

  assign dout = sync_pipeline[STAGES-1];

endmodule

`default_nettype wire
