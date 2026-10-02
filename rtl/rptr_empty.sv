// Parameterised read-domain controller with look-ahead empty detection


// rptr_empty.sv Control Microarchitecture
//
//                       +------------------+
//     rinc ------------>| Increment Gating |<------------- rempty (Feedback)
//                       +--------+---------+
//                                |
//                                | (rinc && !rempty)
//                                v
//                       +------------------+
//                       |    Binary Adder  |
//       rptr_bin ------>|       + 1        |-----> rptr_bin_next
//                       +--------+---------+             |
//                                |                       v
//                                |              +------------------+
//                                |              |  Binary-to-Gray  |
//                                |              |     ^ (>> 1)     |
//                                |              +--------+---------+
//                                |                       |
//                                |                       v
//                                |                rptr_gray_next
//                                v                       |
//                       +------------------+             v
//                       | Memory Address   |    +------------------+
//                       | rptr_bin[M-1:0]  |    | Look-ahead Gray  |<--- wptr_gray_sync
//                       +--------+---------+    | Comparator (==)  |
//                                |              +--------+---------+
//                                v                       |
//                              raddr                     v
//                                                    rempty_val
//                                                        |
//                                                        v
//                                               [DFF: resets to 1]
//                                                        |
//                                                        v
//                                                      rempty


`default_nettype none

module rptr_empty #(
    parameter int unsigned ADDR_WIDTH = 4  // MSB for easy detection of empty vs full
) (
    // Read domain Clock & Reset
    input logic rclk,
    input logic rrst_n,

    // Read Interface
    input  logic                  rinc,
    output logic                  rempty,
    output logic [ADDR_WIDTH-1:0] raddr,

    // Gray-coded pointers
    output logic [ADDR_WIDTH:0] rptr_gray,
    input  logic [ADDR_WIDTH:0] wptr_gray_sync
);

  // Pre-runtime check
  initial
    if (ADDR_WIDTH < 1) $fatal("[RPTR_EMPTY_ERR] ADDR_WIDTH must be >=1. Current:%0d", ADDR_WIDTH);

  // Local pointers for convenience
  logic [ADDR_WIDTH:0] rptr_bin;
  logic [ADDR_WIDTH:0] rptr_bin_next;
  logic [ADDR_WIDTH:0] rptr_gray_next;
  logic                rempty_val;

  // Next bit calculation
  assign rptr_bin_next = rptr_bin + (ADDR_WIDTH + 1)'(rinc && !rempty);

  // Gray code calculation
  assign rptr_gray_next = rptr_bin_next ^ (rptr_bin_next >> 1);

  // MSB is only for empty/full detection
  assign raddr = rptr_bin[ADDR_WIDTH-1:0];

  // Why do you need a comment everywhere?
  assign rempty_val = (rptr_gray_next == wptr_gray_sync);

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      rptr_bin  <= '0;
      rptr_gray <= '0;
      rempty    <= 1'b1;  // Start at empty obv

    end else begin
      // Regular sequential updates
      rptr_bin <= rptr_bin_next;
      rptr_gray <= rptr_gray_next;
      rempty <= rempty_val;
    end
  end

endmodule

`default_nettype wire
