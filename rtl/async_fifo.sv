// Parameterised top-level asynchronous FIFO integrating dual-domain control,
// memory array, and multi-stage CDC synchronizers.


// async_fifo.sv Structural Netlist
//
//    ============================= WRITE DOMAIN ============================= | ============================== READ DOMAIN ==============================
//                                                                             |
//                    +---------------------------------------+                |                +---------------------------------------+
//    wclk ---------->|                                       |                |  rclk -------->|                                       |
//   wrst_n --------->|             u_wptr_full               |                | rrst_n ------->|             u_rptr_empty              |
//     winc --------->|                                       |                |   rinc ------->|                                       |
//                    |  wfull   waddr          wptr_gray     |                |                |  rempty   raddr          rptr_gray    |
//                    +----+-------+----------------+---------+                |                +----+--------+----------------+--------+
//                         |       |                |                          |                     |        |                |
//                         |       |                v                          |                     |        |                v
//                         |       |      +--------------------+               |                     |        |      +--------------------+
//                         |       |      |    u_sync_w2r      |               |                     |        |      |    u_sync_r2w      |
//                         |       |      |  (cdc_sync.sv)     |               |                     |        |      |  (cdc_sync.sv)     |
//                         |       |      |                    |               |                     |        |      |                    |
//                         |       |      | clk:    rclk       |               |                     |        |      | clk:    wclk       |
//                         |       |      | rst_n:  rrst_n     |               |                     |        |      | rst_n:  wrst_n     |
//                         |       |      | din:    wptr_gray  |               |                     |        |      | din:    rptr_gray  |
//                         |       |      | dout:wptr_gray_sync|---+           |                     |        |      | dout:rptr_gray_sync|---+
//                         |       |      +--------------------+   |           |                     |        |      +--------------------+   |
//                         |       |                               |           |                     |        |                               |
//                         |       |                               +----------------------------------------->|                               |
//                         |       |                                           |                     |        |                               |
//                         |       |   +-------------------------------------------------------------+        |                               |
//                         |       |   |                                       |                              |                               |
//                         |       |   |                                       |                              |                               |
//                         |       v   v                                       |                              v                               |
//                         |  +-----------------------------------------------------------------------------------+                           |
//    wdata --------------->  |                                    u_fifo_mem                                     |                           |
//                         |  |                                                                                   |------> rdata              |
//    wfull <--------------+  | Synchronous Write (wclk)                             Combinational Read (Async)   |                           |
//                            +-----------------------------------------------------------------------------------+                           |
//                                                                             |                                                              |
//                                                                             v                                                              v
//                                                                           rempty <---------------------------------------------------------+


`default_nettype none

module async_fifo #(
    parameter int unsigned DATA_WIDTH  = 32,
    parameter int unsigned ADDR_WIDTH  = 4,
    parameter int unsigned SYNC_STAGES = 2    // Number of synchronizer flip-flop stages
                                              // as mentioned in cdc_sync
) (
    // Write Domain Interface
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,

    // Read Domain Interface
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty
);

  // Pre-runtime checks
  initial begin
    if (DATA_WIDTH < 1)
      $fatal("[ASYNC_FIFO_ERR] DATA_WIDTH must be >= 1. Current: %0d", DATA_WIDTH);

    if (ADDR_WIDTH < 1)
      $fatal("[ASYNC_FIFO_ERR] ADDR_WIDTH must be >= 1. Current: %0d", ADDR_WIDTH);

    if (SYNC_STAGES < 2)
      $fatal("[ASYNC_FIFO_ERR] SYNC_STAGES must be >= 2. Current: %0d", SYNC_STAGES);
  end

  /// Interconnects

  // Memory addresses
  logic [ADDR_WIDTH-1:0] waddr;
  logic [ADDR_WIDTH-1:0] raddr;

  // Gray Pointers
  logic [  ADDR_WIDTH:0] wptr_gray;
  logic [  ADDR_WIDTH:0] wptr_gray_sync;
  logic [  ADDR_WIDTH:0] rptr_gray;
  logic [  ADDR_WIDTH:0] rptr_gray_sync;

  // Write-Domain Controller
  wptr_full #(
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_wptr_full (
      .wclk          (wclk),
      .wrst_n        (wrst_n),
      .winc          (winc),
      .wfull         (wfull),
      .waddr         (waddr),
      .wptr_gray     (wptr_gray),
      .rptr_gray_sync(rptr_gray_sync)
  );

  // Read-Domain Controller
  rptr_empty #(
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_rptr_empty (
      .rclk          (rclk),
      .rrst_n        (rrst_n),
      .rinc          (rinc),
      .rempty        (rempty),
      .raddr         (raddr),
      .rptr_gray     (rptr_gray),
      .wptr_gray_sync(wptr_gray_sync)
  );

  // wptr: wclk -> rclk
  cdc_sync #(
      .WIDTH (ADDR_WIDTH + 1),
      .STAGES(SYNC_STAGES)
  ) u_sync_w2r (
      .clk  (rclk),
      .rst_n(rrst_n),
      .din  (wptr_gray),
      .dout (wptr_gray_sync)
  );

  // rptr: rclk -> wclk
  cdc_sync #(
      .WIDTH (ADDR_WIDTH + 1),
      .STAGES(SYNC_STAGES)
  ) u_sync_r2w (
      .clk  (wclk),
      .rst_n(wrst_n),
      .din  (rptr_gray),
      .dout (rptr_gray_sync)
  );

  // Storage Array
  fifo_mem #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_fifo_mem (
      .wclk (wclk),
      .winc (winc),
      .wfull(wfull),
      .waddr(waddr),
      .wdata(wdata),
      .raddr(raddr),
      .rdata(rdata)
  );

endmodule

`default_nettype wire
