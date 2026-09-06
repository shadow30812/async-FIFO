// Parameterised dual-port memory array for async FIFO


// fifo_mem.sv Interface & Storage Structure
//
//                              wclk   winc   wfull
//                                |      |      |
//                                v      v      v
//                            +---------------------+
//     wdata [DATA_WIDTH-1:0] |                     |
//     ---------------------->|  Synchronous Write  |
//     waddr [ADDR_WIDTH-1:0] |  Port (mem[waddr])  |
//     ---------------------->|                     |
//                            +---------------------+
//                                       |
//                                       v
//                         +---------------------------+
//                         |   Dual-Port Memory Array  |
//                         |    DEPTH = 2^ADDR_WIDTH   |
//                         |   [DATA_WIDTH-1:0] mem[]  |
//                         +---------------------------+
//                                       |
//                                       v
//                            +--------------------+
//      raddr [ADDR_WIDTH-1:0]| Combinational Read |
//      --------------------->| Port (mem[raddr])  |---------------> rdata [DATA_WIDTH-1:0]
//                            +--------------------+

`default_nettype none

module fifo_mem #(
    parameter int unsigned DATA_WIDTH = 32,  // Width of each word
    parameter int unsigned ADDR_WIDTH = 4    // Width of FIFO memory addresses
) (
    // Write Interface (wclk domain)
    input logic wclk,
    input logic winc,  // Write increment/en-able
    input logic wfull,  // Full FIFO
    input logic [ADDR_WIDTH-1:0] waddr,
    input logic [DATA_WIDTH-1:0] wdata,

    // Read Interface (rclk domain)
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);

  localparam int unsigned DEPTH = 1 << ADDR_WIDTH;

  // Pre-runtime checks
  initial begin
    if (ADDR_WIDTH < 1) begin
      $fatal("[FIFO_MEM_ERR] ADDR-WIDTH must be >= 1. Current: %0d", ADDR_WIDTH);
    end

    if (DATA_WIDTH < 1) begin
      $fatal("[FIFO_MEM_ERR] DATA_WIDTH must be >= 1. Current: %0d", DATA_WIDTH);
    end
  end

  // Memory storage array w/o RESET to permit RAM primitive inference
  logic [DATA_WIDTH-1:0] mem[DEPTH];

  // Sync write port gated by wfull for overwrites
  always_ff @(posedge wclk) if (winc && !wfull) mem[waddr] <= wdata;

  // Async read port for 0-latency word access
  assign rdata = mem[raddr];

endmodule

`default_nettype wire
