## Simulation and Lint Makefile for Parameterized Async FIFO

# Directory Paths (relative to sim/)
RTL_DIR ?= ../rtl
TB_DIR  ?= ../tb

# Tool Binaries
VERILATOR ?= verilator
IVERILOG  ?= iverilog

# Parameters & Design Configuration
TOP_MODULE ?= async_fifo

# Synthesizable RTL Source Files
RTL_SRCS ?= \
	$(RTL_DIR)/gray_pkg.sv \
	$(RTL_DIR)/cdc_sync.sv \
	$(RTL_DIR)/fifo_mem.sv \
	$(RTL_DIR)/wptr_full.sv \
	$(RTL_DIR)/rptr_empty.sv \
	$(RTL_DIR)/async_fifo.sv

# Lint and Compilation Flags
VERILATOR_LINT_FLAGS ?= --lint-only -Wall -sv --top-module $(TOP_MODULE)
IVERILOG_LINT_FLAGS  ?= -g2012 -Wall -s $(TOP_MODULE)

# Default Target: Runs the blocking lint gate
.PHONY: all
all: lint

# Lint Targets
.PHONY: lint lint-verilator lint-iverilog
lint: lint-verilator lint-iverilog

lint-verilator:
	@echo "==> [Lint Gate] Running Verilator (--lint-only -Wall)..."
	$(VERILATOR) $(VERILATOR_LINT_FLAGS) $(RTL_SRCS)
	@echo "==> [Lint Gate] Verilator: PASSED (0 errors, 0 warnings)"

lint-iverilog:
	@echo "==> [Lint Gate] Running Icarus Verilog syntax check (-g2012 -Wall)..."
	$(IVERILOG) $(IVERILOG_LINT_FLAGS) $(RTL_SRCS) -o /dev/null
	@echo "==> [Lint Gate] Icarus Verilog: PASSED"

# Housekeeping
.PHONY: clean
clean:
	rm -rf obj_dir *.vcd *.vvp *.log