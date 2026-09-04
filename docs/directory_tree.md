```
async_fifo_core/
├── rtl/
│   ├── async_fifo.sv           # Parameterized Top-Level Async FIFO
│   ├── fifo_mem.sv             # Dual-Port Memory Array
│   ├── wptr_full.sv            # Write-Domain Control Engine
│   ├── rptr_empty.sv           # Read-Domain Control Engine
│   └── cdc_sync.sv             # Generic Multi-Stage Synchronizer
├── fault_injection/
│   ├── broken_binary_cdc.sv    # Fault #1: Unsafe Binary CDC Crossing
│   └── broken_sync_cdc.sv      # Fault #2: Un-synchronized / 1-Stage Crossing
├── tb/
│   ├── pkg/
│   │   ├── fifo_types_pkg.sv   # Type Definitions, Structs, Enums
│   │   └── fifo_agent_pkg.sv   # Generator, Driver, Monitor, Scoreboard Classes
│   ├── sva/
│   │   ├── async_fifo_sva.sv   # Concurrent SystemVerilog Assertions
│   │   └── gray_chk_sva.sv     # Gray Code Continuity & Hamming Verification
│   ├── tb_async_fifo.sv        # Golden Testbench Harness
│   └── tb_fault_injector.sv    # Fault Verification & Glitch Capture Harness
├── sim/
│   ├── Makefile                # Automated simulation build targets (Icarus / Verilator)
│   └── waves.gtkw              # Pre-configured GTKWave Signal Layout
├── fpga/
│   └── vivado/
│       ├── run_vivado.tcl      # Non-project mode OOC Synthesis & P&R Script
│       └── constraints.xdc     # Asynchronous Clock & Max Delay Constraints
├── asic/
│   ├── yosys/
│   │   └── synth_sky130.tcl    # Yosys Front-End Synthesis to Sky130 PDK
│   └── opensta/
│       ├── constraints.sdc     # ASIC SDC Timing Constraints
│       └── run_sta.tcl         # OpenSTA Static Timing Analysis & Report Script
├── scripts/
│   ├── run_regression.py       # Master regression runner (Seeds, Clock Matrix)
│   ├── run_cdc_faults.py       # Fault-injection test automation
│   ├── run_parameter_sweep.py  # FPGA & ASIC Multi-Parameter Sweep Engine
│   └── parse_metrics.py        # Log parser -> JSON & Markdown summary tables
├── docs/
│   ├── cdc_analysis.md         # In-depth CDC, Skew, and MTBF Whitepaper
│   ├── cdc_checklist.md        # Industrial RTL Sign-off Checklist
│   └── bug_postmortem.md       # Root-cause analysis of bugs found & injected
└── README.md                   # Technical Portfolio Documentation & Measured Data
```
