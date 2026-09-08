// Parameterised write-domain controller with look-ahead full detection


// wptr_full.sv Control Microarchitecture
//
//                       +------------------+
//     winc ------------>| Increment Gating |<------------- wfull (Feedback)
//                       +--------+---------+
//                                |
//                                | (winc && !wfull)
//                                v
//                       +------------------+
//                       |   Binary Adder   |
//       wptr_bin ------>|       + 1        |-----> wptr_bin_next
//                       +--------+---------+             |
//                                |                       v
//                                |              +------------------+
//                                |              |  Binary-to-Gray  |
//                                |              |     ^ (>> 1)     |
//                                |              +--------+---------+
//                                |                       |
//                                |                       v
//                                |                wptr_gray_next
//                                v                       |
//                       +------------------+             v
//                       | Memory Address   |    +------------------+
//                       | wptr_bin[M-1:0]  |    | Look-ahead Gray  |<--- rptr_gray_sync
//                       +--------+---------+    | Full Comparator  |     (MSBs Inverted)
//                                |              +--------+---------+
//                                v                       |
//                              waddr                     v
//                                                    wfull_val
//                                                        |
//                                                        v
//                                               [DFF: resets to 0]
//                                                        |
//                                                        v
//                                                      wfull


`default_nettype none

module wptr_full #(
    parameter int unsigned ADDR_WIDTH = 4  // MSB for easy detection of full vs empty
) (
    // Write domain Clock & Reset
    input logic wclk,
    input logic wrst_n,

    // Write Interface
    input  logic                  winc,
    output logic                  wfull,
    output logic [ADDR_WIDTH-1:0] waddr,

    // Gray-coded pointers
    output logic [ADDR_WIDTH-1:0] wptr_gray,
    input  logic [ADDR_WIDTH-1:0] rptr_gray_sync
);
  // Pre-runtime
  initial
    if (ADDR_WIDTH < 1) $fatal("[WPTR_FULL_ERR] ADDR_WIDTH must be >= 1. Current: %0d", ADDR_WIDTH);

  // Local pointers for convenience
  logic [ADDR_WIDTH:0] wptr_bin;
  logic [ADDR_WIDTH:0] wptr_bin_next;
  logic [ADDR_WIDTH:0] wptr_gray_next;
  logic                wfull_val;

  // Next bit calculation
  assign wptr_bin_next = wptr_bin + (ADDR_WIDTH + 1)'(winc && !wfull);

  // Gray code calculation
  assign wptr_gray_next = wptr_bin_next ^ (wptr_bin_next >> 1);

  // MSB is only for full/empty detection
  assign waddr = wptr_bin[ADDR_WIDTH-1:0];

  // Look-ahead full evaluation with generate guard for boundary cases
  generate
    if (ADDR_WIDTH == 1) begin : gen_full_w1
      // For depth=2 (N=2), both bits are inverted; no lower bits exist
      assign wfull_val = (wptr_gray_next == ~rptr_gray_sync[1:0]);
    end else begin : gen_full_wn
      // Cummings full condition: invert two MSBs, match lower bits
      assign wfull_val = (wptr_gray_next == {~rptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1],
      rptr_gray_sync[ADDR_WIDTH-2:0]});
      // Gray code arithmetic ensures this difference in condition compared to standard binary full flag comparison
    end
  endgenerate

  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wptr_bin  <= '0;
      wptr_gray <= '0;
      wfull     <= 1'b0;  // Empty cannot be same as full heh

    end else begin
      // Write domain sequential state
      wptr_bin  <= wptr_bin_next;
      wptr_gray <= wptr_gray_next;
      wfull     <= wfull_val;
    end
  end

endmodule

`default_nettype wire
