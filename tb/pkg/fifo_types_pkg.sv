// Package containing verification transaction definitions, operational enums,
// and metric tracking data structures for the asynchronous FIFO

`default_nettype none

package fifo_types_pkg;

  // Operational transaction type
  typedef enum logic [1:0] {
    OP_IDLE  = 2'b00,
    OP_WRITE = 2'b01,
    OP_READ  = 2'b10
  } fifo_op_e;

endpackage : fifo_types_pkg

`default_nettype wire
