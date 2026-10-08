# Implementation Plan — Project 1: Parameterized Async FIFO with CDC Verification Harness

## 0. Context and rules

### 0.1 Task

Implement, verify, characterize and document a parameterized dual-clock asynchronous FIFO in SystemVerilog (Gray-coded pointers, multi-flop synchronizers) with a self-checking CDC verification harness, deliberate CDC fault injection, synthesis and timing results, and script-generated metrics. The project ends in a `v1.0` tag.

- **Repository:** `/mnt/Windows/Well/Projects/EE Core/async_fifo` (git). This plan supersedes `docs/SystemVerilog Asynchronous FIFO Architecture Plan.pdf`.
- **Current state:** §1. RTL exists and lints clean; everything else is an empty placeholder.
- **Start here:** step 1 of §11, then follow §11 in order.

### 0.2 Downstream use (do not break)

This is the first of three repositories. Project 2 (a single-clock streaming FFT with AXI4-Stream and AXI4-Lite) reuses `tb/sva/axis_protocol_sva.sv` unchanged. Project 3 (a two-clock RV32I CPU + FFT SoC) pulls this repository in unchanged as a git submodule at `v1.0` and uses:

- `axis_async_fifo` for the sample stream (clk\_cpu → clk\_dsp) and the result stream (clk\_dsp → clk\_cpu): 33 bits wide (32 data + TLAST); the result FIFO is 256 deep (must hold a whole FFT frame).
- Five `axis_async_fifo` instances, depth 2–4, as an AXI4-Lite clock-domain bridge (one per channel: AW, W, AR, B, R).
- `rst_sync`, one per clock domain.
- `wr_level` / `rd_level` for FIFO high-water-mark counters.
- `docs/cdc_checklist.md` and the `docs/cdc_analysis.md` format for the SoC-wide CDC sign-off.
- The `throughput_bench.py` depth-sizing rule, to size the SoC's TX FIFO.
- The clock-ratio matrix of §4 and the JSON regression-summary schema.

A bug found later by Project 3 is fixed here as a `v1.0.1` patch release with a regression test and a `docs/bug_postmortem.md` entry.

### 0.3 Conventions

Defined here and reused unchanged by Projects 2 and 3; write them into `docs/interface.md`:

- **Language:** synthesizable SystemVerilog-2017 subset with `` `default_nettype none ``. RV32I stays Verilog-2001, which SystemVerilog tools accept unchanged.
- **Naming:** AMBA-style port prefixes `s_axis_*`, `m_axis_*`, `s_axil_*`, `m_axil_*`; clocks `*_clk`; active-low resets `*_rst_n` (AMBA ARESETn convention).
- **Complex sample packing:** `{imag, real}` everywhere.
- **Lint gate:** `verilator --lint-only -Wall` clean, with any waivers listed in the README.
- **Regression output:** one JSON summary per run (seed, configuration, counts, PASS/FAIL) in the same schema across all three repositories. This project defines the schema and documents it in `docs/interface.md`.
- **Continuous integration:** a GitHub Actions workflow per repository running lint, a short smoke regression and Yosys synthesis on every push.
- **One FPGA part:** Kintex-7 xc7k325t for every Vivado result, so numbers line up with the existing RV32I results.
- **Integrity rule:** never fabricate or round up a number. Every reported number must trace to a script output in the repository.

### 0.4 Working rules

1. Proceed one file at a time; never generate a whole project in one pass. For each file, explain what is built, why, what to measure, and what evidence lands in the repository. The final code is rewritten by hand line by line, so every proposal must be justified and open to interrogation; sophisticated decisions are welcome when justified, and nothing is simplified just to make it easier.
2. Explain each major module before implementing it: purpose, interface, state, arithmetic and architectural role.
3. Keep synthesizable RTL separate from simulation-only code.
4. Test every layer independently before composing it.
5. Never invent performance, verification, synthesis or timing numbers.
6. Preserve reproducibility: record seeds, parameters, simulator versions, synthesis configurations and tool versions.
7. When a bug appears, diagnose before modifying, and document symptom, stimulus, expected result, actual result, waveform, root cause, correction and the regression test added.
8. Do not optimize before the baseline is correct; when alternatives exist, explain and quantify the trade-offs.
9. Never silently change interface semantics, reset behavior, numerical format, ordering, latency definitions or frame semantics.
10. Future work must never compromise completion of the core project.

## 1. Repository status

| Area | State |
| --- | --- |
| RTL | Written and committed: `async_fifo.sv` (top; `DATA_WIDTH`, `ADDR_WIDTH`, `SYNC_STAGES` ≥ 2; `$fatal` parameter checks; combinational read port), `cdc_sync.sv` (`ASYNC_REG` and `dont_touch` attributes), `fifo_mem.sv`, `wptr_full.sv` (separate full-compare branch for `ADDR_WIDTH = 1`), `rptr_empty.sv` |
| Testbench | `tb/pkg/fifo_types_pkg.sv` started (operation enum); every other file empty |
| Scripts, constraints, docs | Empty placeholders in the tree below |
| Compile and lint | Clean as of Oct 4, 2026: all five RTL files build under Icarus Verilog 13 (`-g2012 -Wall`) with no errors or warnings, and `verilator --lint-only -Wall` (5.030) reports zero warnings. No simulation, synthesis or timing run exists yet |

Layout follows `docs/directory_tree.md`: implementation is split into `fpga/vivado/`, `asic/yosys/` (Sky130) and `asic/opensta/`. Gray conversion is currently inline in the pointer modules; move `bin2gray`/`gray2bin` into `rtl/gray_pkg.sv` so the RTL and the exhaustive Gray tests (§4) share them.

Target tree (files on disk plus the ones this plan adds):

```text
async_fifo/
+-- rtl/
|   +-- async_fifo.sv           Parameterized top-level async FIFO
|   +-- fifo_mem.sv             Dual-port memory array
|   +-- wptr_full.sv            Write-domain control engine
|   +-- rptr_empty.sv           Read-domain control engine
|   +-- cdc_sync.sv             Generic multi-stage synchronizer
|   +-- gray_pkg.sv             bin2gray / gray2bin functions
|   +-- rst_sync.sv             Reset synchronizer (§8)
|   +-- axis_async_fifo.sv      AXI4-Stream wrapper (§8)
+-- fault_injection/
|   +-- broken_binary_cdc.sv    Fault #1: unsafe binary crossing
|   +-- broken_sync_cdc.sv      Fault #2: unsynchronized / 1-stage crossing
+-- tb/
|   +-- pkg/
|   |   +-- fifo_types_pkg.sv   Types, configuration structs, enums, logging macros
|   |   +-- fifo_agent_pkg.sv   Generator, driver, monitor, scoreboard classes
|   +-- sva/
|   |   +-- async_fifo_sva.sv   Concurrent assertions bound to the FIFO
|   |   +-- gray_chk_sva.sv     Gray continuity / Hamming-distance checks
|   |   +-- axis_protocol_sva.sv
|   +-- tb_async_fifo.sv        Golden testbench with dynamic clock generators
|   +-- tb_fault_injector.sv    Fault experiments, skew model, glitch capture
+-- formal/                     SymbiYosys scripts (§4)
+-- sim/
|   +-- Makefile                Icarus / Verilator targets (Questa / VCS optional)
|   +-- waves.gtkw              GTKWave layout for CDC debug
+-- fpga/vivado/
|   +-- run_vivado.tcl          Non-project out-of-context synthesis and P&R
|   +-- constraints.xdc         Asynchronous clocks and max-delay constraints
+-- asic/
|   +-- yosys/synth_sky130.tcl  Yosys to Sky130
|   +-- opensta/
|       +-- constraints.sdc
|       +-- run_sta.tcl
+-- scripts/                    run_regression, run_cdc_faults, run_parameter_sweep,
|                               parse_metrics, and the benchmarks in §9
+-- docs/
|   +-- cdc_analysis.md
|   +-- cdc_checklist.md
|   +-- bug_postmortem.md
|   +-- completed_work.md
|   +-- interface.md
|   +-- README.md                   Technical documentation and measured data
+-- .github/workflows/ci.yml
```

## 2. Goals

**Demonstrates:** SystemVerilog RTL design, CDC-safe architecture, metastability-aware reasoning, Gray-code pointer synchronization, dual-clock operation, self-checking verification, randomized stress testing, assertion-based verification, CDC fault injection, waveform-based debugging, parameterization, synthesis and resource analysis, timing analysis, quantitative verification metrics, reproducible regressions and engineering documentation.

**The finished repository answers:**

- How does the FIFO work, and why is it CDC-safe?
- Why are Gray-coded pointers needed, and why is a binary pointer unsafe to cross directly?
- How are metastability risks handled?
- How are full and empty detected?
- How was correctness verified, and how aggressively?
- What happens when the CDC architecture is intentionally broken?
- What bugs were found?
- What do synthesis and timing say, and how does the design scale with width and depth?
- What quantitative evidence supports each reported number?

## 3. Architecture

**Target.** A true asynchronous FIFO with independent write and read clocks; parameterized data and address width; depth = 2^ADDR\_WIDTH; independent pointer domains; binary plus Gray-coded pointers; synchronized Gray pointers crossing through multi-flop synchronizers; CDC-aware full and empty; parameterized storage; valid write/read handshaking; clear behavior at full and empty. Starting configuration `DATA_WIDTH = 32`, `ADDR_WIDTH = 4` (16 × 32 bits), but never specialized to it.

Before final implementation, write down: clock domains, write-side and read-side state, pointer representation, binary↔Gray conversion, pointer width, addressing, CDC crossings, synchronizer placement, full and empty detection, memory organization, reset behavior, assumptions about simultaneous reads and writes, throughput, latency and parameter scaling.

**Partitioning.** The Cummings dual-clock topology, split into five modules so clock domains stay isolated, synchronizers stay separate from control logic, and synthesis cannot optimize across the boundary:

| Module | Domain | Responsibility |
| --- | --- | --- |
| `async_fifo.sv` | both | Structural top; parameter propagation and interconnect |
| `fifo_mem.sv` | write wclk / read rclk | Simple dual-port storage, 2^ADDR\_WIDTH × DATA\_WIDTH; synchronous write gated by `winc && !wfull`; combinational read |
| `wptr_full.sv` | wclk | Binary and Gray write pointer, `waddr`, registered `wfull` from a look-ahead Gray compare |
| `rptr_empty.sv` | rclk | Binary and Gray read pointer, `raddr`, registered `rempty` from a look-ahead Gray compare |
| `cdc_sync.sv` | destination clock | Generic multi-bit `STAGES`-flop synchronizer with `ASYNC_REG`/`dont_touch` to block SRL inference and keep the flops placed together |

**Clock-domain crossings.** Two asynchronous domains, no assumed phase or frequency relationship. Only the two Gray pointers cross through synchronizers; data crosses through memory, qualified by those pointers.

| Signal | Source | Destination | Width | Synchronization | Rationale |
| --- | --- | --- | --- | --- | --- |
| `wptr_gray` | wclk | rclk | ADDR\_WIDTH+1 | `cdc_sync` | One bit flips per increment, so skew cannot create a false intermediate value |
| `rptr_gray` | rclk | wclk | ADDR\_WIDTH+1 | `cdc_sync` | Same |
| `wdata` / `waddr` via memory | wclk | rclk | DATA\_WIDTH / ADDR\_WIDTH | Pointer separation | A location is never written and read at once; full/empty guarantee margin |
| `wrst_n` | external | wclk | 1 | Async assert, sync deassert | Avoids reset-removal violations |
| `rrst_n` | external | rclk | 1 | Async assert, sync deassert | Avoids reset-removal violations |

**Why ADDR\_WIDTH + 1 pointer bits.** For depth D = 2^N the memory needs N address bits. With N-bit pointers, `wptr == rptr` is ambiguous: empty, or full after one wrap. An extra MSB records wrap parity; the low N bits address memory.

```latex
\text{occupancy} = (\mathit{wptr}_{bin} - \mathit{rptr}_{bin}) \bmod 2^{N+1}
```

Empty (binary): all N+1 bits equal. Full (binary): low N bits equal, MSBs differ.

**Why Gray code.** A binary increment can flip many bits (0111 → 1000 flips four). Wire skew lets the destination sample a transient such as 0000 or 1111 and raise a false flag. Gray code changes one bit per step, so a sample is either the old or the new value. In SystemVerilog: `gray = bin ^ (bin >> 1)`. With power-of-two depth the (N+1)-bit sequence also wraps with one bit change.

```latex
G[i] = B[i] \oplus B[i+1] \quad (0 \le i < N), \qquad G[N] = B[N]
```

**Empty.** The read domain is empty when the next read pointer reaches the synchronized write pointer. Binary-to-Gray is a bijection, so equality carries over bit for bit. Comparing the *next* pointer makes the registered flag correct on the same edge the pointer moves.

```latex
\mathit{rempty\_val} = (\mathit{rptr\_gray\_next} = \mathit{wptr\_gray\_sync})
```

**Full.** Full means the write pointer leads by exactly 2^N, and adding 2^N flips only the binary MSB. In Gray: the MSB inverts (G'\[N\] = ¬b\_N); bit N−1 inverts (b\_(N−1) ⊕ ¬b\_N = ¬G\[N−1\]); all lower bits are unchanged. So the synchronized read pointer is compared with its top two bits inverted, which is the Gray image of "read pointer plus one wrap". For N = 1 the pointer has only two bits and both invert, which is why the RTL has a separate branch.

```latex
\mathit{wfull\_val} = \big(\mathit{wptr\_gray\_next} = \{\lnot \mathit{rptr\_gray\_sync}[N{:}N{-}1],\ \mathit{rptr\_gray\_sync}[N{-}2{:}0]\}\big)
```

Both synchronized pointers are up to `SYNC_STAGES` destination edges stale. The FIFO may look empty or full longer than it really is. That is pessimistic and safe: it prevents underflow and overflow and only costs latency.

**SystemVerilog constructs.** Use the ones that materially improve the design and explain each: `logic`, `always_ff`, `always_comb`, `typedef enum`, packed and unpacked arrays, `parameter`/`localparam`, `generate`, functions, packages, interfaces/modports where appropriate, assertions and concurrent SVA, and compile-time checks. Keep everything synthesizable and ASIC-appropriate.

**Synchronizer.** `cdc_sync` has parameterizable width and depth, destination clock and reset, and a clean destination-domain output. Its documentation explains metastability and the first stage; what the second stage buys; why MTBF improves with resolution time; why simulation cannot reproduce analog metastability; why pointer encoding matters before synchronization; and what the `ASYNC_REG`/`dont_touch` attributes imply. Synthesize `SYNC_STAGES` = 2 and 3, report the flop and latency cost, and give the standard MTBF expression in `cdc_analysis.md`, using device constants only from a cited vendor source (or leaving them symbolic):

```latex
\mathrm{MTBF} = \frac{e^{t_r/\tau}}{T_0 \, f_{clk} \, f_{data}}
```

**Decisions to confirm.** (1) Look-ahead registered flags: computed from the next Gray pointer and registered, so they are glitch-free with zero output delay, at the cost of a comparator on the critical path. (2) Memory: a write-enable-gated dual-port array that infers FPGA RAM or maps to an ASIC register file, with no read-during-write conflict; the current combinational read maps to LUTRAM on Kintex-7 and gives first-word fall-through. (3) Reset: active-low asynchronous `wrst_n`/`rrst_n`, each through a local reset synchronizer (`rst_sync`, §8) for glitch-free assertion and synchronous removal.

## 4. Verification

**Gray code.** Verify binary→Gray and Gray→binary exhaustively for small widths: mathematical correctness, round-trip identity, and Hamming distance one on every sequential transition including wraparound. Record transitions tested, transitions expected to satisfy the one-bit property, transitions that do, and violations.

**Parameter configurations.** At minimum vary `DATA_WIDTH` and `ADDR_WIDTH` through both the test and synthesis flows:

| DATA\_WIDTH | ADDR\_WIDTH | Depth | Why |
| --- | --- | --- | --- |
| 8 | 2 | 4 | smallest practical |
| 16 | 3 | 8 | |
| 32 | 4 | 16 | baseline |
| 33 | 2 | 4 | Project 3 control-channel FIFOs (32 data + TLAST) |
| 64 | 5 | 32 | |
| 33 | 8 | 256 | Project 3 result FIFO |
| larger | | | if simulation and synthesis time allow |

Quantify configurations tested, smallest and largest width and depth, total combinations, passed and failed. Values come from experiments.

**Environment.** A class-based SystemVerilog harness ("UVM-lite") with no proprietary library, aimed at Icarus, Verilator or commercial simulators:

- `tb_async_fifo`: independent randomized wclk/rclk generators with skew and jitter injection.
- Write and read drivers: burst or random traffic.
- Write and read monitors feeding a self-checking scoreboard.
- Scoreboard: golden-queue reference model independent of the RTL; underflow/overflow checks; occupancy and latency counters.

Check the simulator first: class-based testbenches with randomization need Verilator 5.x (`--timing`); Icarus support for SV classes is limited. Compile a tiny class plus `$urandom`/`std::randomize` test before writing the harness.

**Scoreboard counters:** writes attempted, accepted, rejected because full; reads attempted, accepted, rejected because empty; data comparisons; mismatches; current reference occupancy; maximum and minimum observed occupancy. **It must detect:** data loss, duplication, corruption, ordering errors, illegal reads, illegal writes, pointer/flag inconsistencies.

**Functional coverage.** Count, per run, how often each interesting condition was hit: full asserted, empty asserted, write attempted while full, read attempted while empty, simultaneous write and read, pointer wraparound in each domain, occupancy at every level 0…depth, reset during traffic. Emit the counters in the JSON summary so coverage closure (bins hit / bins defined) becomes a reported number.

**Clock-domain stress.** Never assume related clocks. Cover write faster than read, read faster than write, balanced, awkward phase and non-trivial ratios:

| Write | Read | Exercises |
| --- | --- | --- |
| 5 ns | 11 ns | fast write, prime ratio |
| 7 ns | 11 ns | moderate, prime ratio |
| 7 ns | 13 ns | moderate, prime ratio |
| 10 ns | 20 ns | integer ratio |
| 11 ns | 7 ns | read faster |
| 13 ns | 7 ns | read faster |
| 20 ns | 10 ns | read faster, integer ratio |
| 100 MHz | 10 MHz | very fast write |
| 10 MHz | 100 MHz | very fast read |
| 100 MHz | 99.5 MHz | near-equal; maximizes edge-collision windows |
| 133 MHz | 37 MHz | high prime ratio |

Quantify clock configurations, passed, failed, cycles per configuration and total cycles.

**Randomized stress.** Randomize write and read enables, data, burst lengths, idle periods, clock ratios, traffic intensity, duration, and reset timing where the reset specification allows. Traffic profiles:

1. Burst write / burst read: fill to full, hold, drain to empty.
2. Alternating 1:1 push-pop (steady state).
3. Write-heavy / read-starved: sustained full backpressure and near-full operation.
4. Read-heavy / write-starved: sustained empty backpressure and near-empty operation.
5. Balanced continuous traffic.
6. Long idle periods.
7. Repeated fill/drain cycles.
8. Fully random delays, bursts and reset assertions.
9. Clock-domain sweeps across the matrix above.

Always record deterministic seeds; every regression must reproduce exactly.

**Scale targets.** At least 100,000 attempted and 50,000 accepted operations across several clock and parameter configurations; stretch to about 1,000,000+. Choose the final number from runtime and confidence and report it exactly. Collect total simulation cycles and time, attempted/accepted/rejected writes and reads, comparisons, mismatches, assertion failures, seeds, and testcases executed, passed and failed.

**Assertions.** Properties: no write accepted while full; no read accepted while empty; valid pointer-update conditions; Gray single-bit transitions; reset initialization; occupancy bounds; data ordering; full/empty relationships; synchronizer behavior; pointer stability where applicable. Proposed SVA:

- `assert_no_write_when_full`: `winc && wfull |-> ##0 !written`
- `assert_no_read_when_empty`: `rinc && rempty |-> ##0 !data_valid`
- `assert_gray_single_bit_flip`: on every increment, `$countones(ptr_gray ^ $past(ptr_gray)) == 1`
- `assert_reset_values`: pointers and flags reset to 0/1 within bounded cycles
- `assert_fifo_occupancy_bounds`: scoreboard checks 0 ≤ occupancy ≤ 2^N

Keep immediate assertions, concurrent assertions and simulation checks separate. Track property count, evaluations where practical, failures, unexpected failures and passes where the simulator counts them. Target: zero unexpected failures on the correct design.

**Bounded formal proof.** Run SymbiYosys in multiclock mode at `ADDR_WIDTH` = 2 and 3 on four properties: no overflow, no underflow, Gray one-bit change, and ordering via a tracked-word check. Report "proved to depth K" exactly as the tool states. It complements simulation; it does not replace it.

**Metastability.** Never present RTL simulation as proof that metastability cannot occur. Keep four things separate: RTL correctness, CDC architectural correctness, metastability probability (MTBF), and analog behavior. The claim is that the design uses the established techniques that make asynchronous communication robust.

## 5. Deliberately broken designs and the bug log

**Broken design #1 — binary pointer crossing (`fault_injection/broken_binary_cdc.sv`).** Skip Gray coding: pass the registered binary counters straight through the synchronizers, keeping the design syntactically and structurally plausible. Under asynchronous ratios with phase drift, multi-bit transitions (0111 → 1000) are sampled with skew and the destination sees values such as 0000 or 1111. Expected symptoms: wrong full/empty, scoreboard corruption (stale reads, overwritten unread data) or deadlock. Lesson: Gray coding is mandatory for multi-bit counters crossing asynchronous boundaries.

**Broken design #2 — synchronizer failure (`fault_injection/broken_sync_cdc.sv`).** Candidates: a missing stage, an improperly synchronized pointer, a wrong synchronizer connection, combinational logic in an unsafe place, or another more educational mistake. Proposed: an unregistered combinational signal entering the destination domain, or a single-flop synchronizer with simulated setup/hold jitter. Hazard glitches are sampled as valid transitions, producing multi-step pointer jumps that trip `gray_chk_sva`. It must teach something different from design #1.

**Making skew visible.** A zero-delay simulator samples a clean binary value, so design #1 can pass by luck. `tb_fault_injector.sv` gives each pointer bit its own small random delay before the synchronizer (a skew model), and the write-up says so plainly. This keeps architectural unsafety, simulator-visible consequences and physical silicon risk distinct.

Run the full regression on both. For each, capture configuration, seed, first failure, failing transaction, expected and actual values, raw and synchronized pointer values, waveform and root cause.

**Bug log (`docs/bug_postmortem.md`).** For every significant bug: symptom, exposing test, failing seed, waveform timestamp, relevant state, root cause, why it occurred, why the implementation allowed it, the fix, and the regression added. Candidate injected bugs: wrong full detection, wrong empty detection, wrong Gray conversion, wrong pointer width, bad synchronizer, binary pointer CDC, increment under the wrong condition, reset sequencing, address extraction, off-by-one occupancy. Keep real bugs clearly separate from injected validation defects, and never invent development bugs.

## 6. CDC documents

**`docs/cdc_analysis.md`:** clock-domain inventory; every crossing with source, destination, width, method and rationale (the table in §3); metastability; Gray-code rationale; full/empty rationale; multi-bit CDC; reconvergence; reset domains; potential violations; why the architecture is structurally sound; skew, MTBF and synchronizer-depth analysis.

**`docs/cdc_checklist.md`**, a concise sign-off list that Project 3 reuses for the whole SoC:

- [ ] All asynchronous control signals synchronized?
- [ ] Multi-bit CDC signals handled correctly?
- [ ] Gray-coded counters used where appropriate?
- [ ] Synchronizer stages placed in the destination domain?
- [ ] Synchronizer outputs used rather than asynchronous inputs?
- [ ] Reconvergence hazards considered?
- [ ] Resets handled consistently?
- [ ] Full/empty generated entirely within their owning domains?
- [ ] Any combinational paths crossing domains?
- [ ] Any unguaranteed assumptions about clock frequency or phase?
- [ ] Parameter changes still CDC-safe?

## 7. Synthesis, timing and CDC sign-off

After simulation is stable, synthesize and record measured values only. Never present FPGA LUT/FF counts as ASIC area.

| Flow | Files | Metrics |
| --- | --- | --- |
| FPGA (Vivado, out-of-context, Kintex-7) | `fpga/vivado/run_vivado.tcl`, `constraints.xdc` | LUTs, FFs, LUTRAM/BRAM, DSP, utilization, Fmax, slack, power |
| ASIC synthesis (Yosys → Sky130) | `asic/yosys/synth_sky130.tcl` | total cells, flip-flops, combinational cells, area, memory implementation (flop array vs latch/macro), inferred latches and memories, warnings |
| ASIC timing (OpenSTA) | `asic/opensta/constraints.sdc`, `run_sta.tcl` | critical path, slack, logic depth, Fmax per domain |

**Timing.** Identify startpoint, endpoint, path delay, combinational depth, limiting logic, slack and Fmax. The expected limiting path is `wptr_bin → adder → bin2gray → look-ahead comparator → wfull`. Discuss how the architecture shapes timing and explain trade-offs rather than optimizing blindly.

**CDC constraints.** Declare the clocks asynchronous (`set_clock_groups -asynchronous`) and bound each Gray-pointer path with `set_max_delay -datapath_only` of about one destination period, so skew between pointer bits stays below one cycle; a blanket false path does not bound it. Then run `report_cdc` and `report_clock_interaction` and commit the reports. Explain the timing assumptions in `cdc_analysis.md`.

**Scaling.** Sweep `DATA_WIDTH` over \[8, 16, 32, 64, 128\] and `ADDR_WIDTH` over \[2, 3, 4, 5, 6, 7\] (depth 4–128) with `run_parameter_sweep.py`. Plot only what is meaningful: resources vs width, resources vs depth, memory bits vs depth, Fmax vs width, Fmax vs depth, flip-flops vs combinational cells.

## 8. SoC-facing deliverables

These make Project 1 the CDC library of Project 3. Each is small and tested inside Project 1.

| Deliverable | Specification | Test |
| --- | --- | --- |
| `rtl/rst_sync.sv` | Asynchronous assert, `SYNC_STAGES`-deep synchronous deassert, one per domain | Reset asserted and released at random phases; assertion that deassert aligns to the destination clock |
| `rtl/axis_async_fifo.sv` | AXI4-Stream ports around `async_fifo`. Write: `s_axis_tready = !wfull`, `winc = s_axis_tvalid && s_axis_tready`. Read: `m_axis_tvalid = !rempty`, `m_axis_tdata = rdata`, `rinc = m_axis_tvalid && m_axis_tready`. TLAST rides as an extra data bit. | Existing scoreboard plus random `tvalid`/`tready` gaps; AXIS checker on both sides |
| Occupancy outputs `wr_level`, `rd_level` (parameter `EN_LEVEL`) | Each computed in its own domain from the local binary pointer and the synchronized remote pointer converted back to binary; conservative by up to the synchronizer latency | Scoreboard checks the read side never overstates data and the write side never overstates space |
| `tb/sva/axis_protocol_sva.sv` | Payload stable while `tvalid && !tready`; `tvalid` not withdrawn before handshake; no X on valid after reset; TLAST only with valid | Bound to `axis_async_fifo`; reused unchanged in Projects 2 and 3 |
| `docs/interface.md` | Ports, parameters, legal ranges, reset requirements, latency in destination cycles, XDC snippet to copy | Frozen at `v1.0` |

The stream wrapper is this simple because the read port is combinational: `rdata` shows the head entry whenever `rempty` is low (first-word fall-through). A registered (BRAM) read would need a one-entry output register, which is a parameter option, not a redesign. No pulse or handshake synchronizer is needed: in the SoC every status bit crosses through the AXI4-Lite CDC bridge built from this FIFO, so the SoC uses one crossing mechanism plus reset synchronizers.

## 9. Quantified metrics and benchmark scripts

Every number below is produced by a script and lands in one JSON file per run; `parse_metrics.py` merges them into the README tables and plots.

| Category | Metric | How it is measured |
| --- | --- | --- |
| Verification scale | attempted / accepted operations, data comparisons, mismatches, simulated cycles, seeds | Scoreboard counters via `run_regression.py` |
| Coverage | functional-coverage bins hit / defined (§4) | Coverage counters in the JSON summary |
| Robustness | clock configurations and parameter configurations passed / run | Regression matrix |
| Gray property | transitions checked, violations | `gray_chk_sva` counters plus exhaustive test |
| Assertions and formal | properties, evaluations, failures; properties proved and bounded depth | Simulator log; SymbiYosys log |
| Fault detection | broken designs detected / built; detection rate versus injected skew; cycles to first failure | `run_cdc_faults.py` |
| Latency | write-to-visible latency in read-clock cycles (min / mean / max) per clock ratio; flag release latency | `latency_profile.py` |
| Throughput efficiency | sustained accepted words/s ÷ min(f\_wr, f\_rd); minimum depth that sustains full rate per ratio | `throughput_bench.py` |
| Resources | LUT, FF, LUTRAM, cells, Sky130 area, per configuration | `run_parameter_sweep.py` |
| Resource model | closed-form register count (pointers, flags, 2 × SYNC\_STAGES × (ADDR\_WIDTH + 1) synchronizer flops) versus synthesized count; CDC overhead as a share of all flops | `resource_model.py` |
| Timing | Fmax and WNS per domain, critical path, logic depth (Vivado and OpenSTA) | Report parsers |
| CDC sign-off | `report_cdc` crossings by category, unsafe count | Report parser |
| Reliability | MTBF for `SYNC_STAGES` = 2 and 3 at the target clocks, with cited device constants | `mtbf_calc.py` |
| Benchmark against vendor IP | LUT, FF, memory, Fmax and latency against Xilinx `xpm_fifo_async` at the same width, depth and part | `compare_xpm.py` |
| Reproducibility | same seed → identical transaction-log hash on rerun | `repro_check.py` in CI |

**Scripts (behavior, not code):**

- `run_regression.py` — runs the seed × clock-ratio × parameter matrix, in parallel, and writes one JSON summary per run plus a roll-up.
- `run_cdc_faults.py` — runs the same matrix on each broken design; sweeps the skew model's maximum delay from zero up to one destination period and records, per skew, the fraction of seeds that fail and the cycles to first failure. Produces the "detection rate vs skew" plot.
- `latency_profile.py` — timestamps each word at write and at first visibility on the read side and histograms the latency in read-clock cycles per ratio; compares the measured range with the predicted bound from `SYNC_STAGES`.
- `throughput_bench.py` — drives continuous traffic, measures sustained words per second against the ideal min(f\_wr, f\_rd), and finds the smallest depth that reaches full rate for each ratio. Project 3 uses this sizing rule.
- `run_parameter_sweep.py` — synthesizes the width × depth grid in Vivado and Yosys/Sky130 and collects resources and timing.
- `resource_model.py` — predicts flip-flop counts from the architecture and reports predicted versus measured, plus the share of flops spent on synchronization.
- `mtbf_calc.py` — evaluates the MTBF expression for 2 and 3 stages at the chosen clock and data rates, with the constants' source cited in the output.
- `compare_xpm.py` — generates a Vivado run of `xpm_fifo_async` at matching parameters and tabulates it next to this design, explaining any gap.
- `repro_check.py` — reruns a fixed seed and checks the transaction-log hash matches.
- `parse_metrics.py` — merges everything into `results.json`, the README tables and the plots in `docs/img/`.

## 10. Results, reporting and documentation

**Results table** (measured values only; never rounded up):

| Group | Fields |
| --- | --- |
| Design | data width, depth, pointer width, clock domains, CDC crossings, synchronizer stages |
| Verification | attempted operations, accepted writes and reads, blocked writes and reads, comparisons, mismatches, coverage, assertion properties, assertion failures, clock configurations, parameter configurations, simulated cycles, regression runtime, seeds |
| CDC | Gray transitions checked, violations, broken designs, failures detected, detection rate vs skew, `report_cdc` unsafe crossings |
| Performance | latency range per ratio, throughput efficiency, minimum full-rate depth |
| Hardware | registers, logic/cells, memory bits, area/resources, critical path, Fmax, slack, comparison with `xpm_fifo_async` |

**Throughput claims.** Never a generic "FIFO throughput": it depends on both clocks, interface assumptions, traffic, occupancy and backpressure. Report it only with a precise definition, such as accepted writes per second under a stated clock configuration.

**Waveforms** (few, annotated): reset → empty; normal write/read; filling; reaching full; draining; pointer wraparound; Gray transition; correct synchronization; broken binary-pointer failure; second broken-CDC failure.

**README:** overview; motivation; architecture; CDC architecture; Gray code; full/empty detection; SystemVerilog design; verification architecture; randomized testing; assertions; broken CDC versions; waveform evidence; verification results; synthesis; timing; scaling; benchmarks; bug postmortem; lessons learned; limitations; future work. Include an architecture diagram, a clock-domain diagram and a compact results table near the top.

**Tools:** SystemVerilog, Icarus Verilog, Verilator, GTKWave, Yosys, OpenSTA, SymbiYosys, Python, Bash, Make, Vivado. Where useful, map each open tool to its commercial counterpart.

## 11. Execution order and definition of done

**Order** (one file at a time):

1. Make the existing clean `verilator --lint-only -Wall` result the lint gate in `sim/Makefile`, so it stays clean after every RTL change.
2. Review `cdc_sync`, Gray conversion, the pointer engines, memory and top against §3.
3. Assertions: `tb/sva/async_fifo_sva.sv`, `gray_chk_sva.sv`.
4. Harness: `tb/pkg/*.sv`, `tb_async_fifo.sv`, coverage counters.
5. Fault injection: `fault_injection/*.sv`, `tb_fault_injector.sv`.
6. Scripts and implementation: `sim/Makefile`, Vivado/Yosys/OpenSTA scripts, `scripts/*.py`.
7. SoC-facing deliverables (§8), formal proof, benchmarks (§9), CI.
8. Documents: `cdc_analysis.md`, `cdc_checklist.md`, `bug_postmortem.md`, `interface.md`, `README.md`; tag `v1.0`.

**Done when:**

- [ ] The implementation is SystemVerilog, genuinely parameterized, with an appropriate async FIFO architecture.
- [ ] Binary and Gray pointers and CDC synchronization are correct; full/empty logic is verified.
- [ ] The testbench is self-checking; randomized regressions reproduce from seeds.
- [ ] Multiple clock relationships and parameter configurations pass.
- [ ] Assertions are present and passing; Gray behavior is explicitly verified.
- [ ] At least two broken CDC architectures exist, produce diagnostic evidence, and at least one failure is shown in a waveform.
- [ ] Real development bugs are documented.
- [ ] Regression statistics, synthesis, timing (where practical), scaling and benchmarks are collected by scripts.
- [ ] CDC crossings are documented; the README has quantitative results reproducible from scripts.
- [ ] The SoC-facing deliverables pass their own tests and `docs/interface.md` is frozen.
- [ ] Every reported number traces to a script output in the repository.

## 12. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Simulator cannot run the class-based SV harness | Prove a tiny class + randomize test on Verilator 5 first (§4) |
| Broken binary-pointer FIFO passes in zero-delay simulation | Per-bit skew model, stated openly; detection-rate-versus-skew sweep (§5, §9) |

## 13. Progress Tracking and Maintenance Protocol

After every major change (such as adding or modifying an RTL module, implementing an assertion suite or testbench component, executing a regression or synthesis run, or creating documentation):
1. **Read the Implementation Plan:** Review `docs/Async FIFO Implementation Plan.md` thoroughly to ensure full alignment with architectural specifications, verification requirements, lint rules, downstream constraints, and the execution sequence.
2. **Update the Completed Work File:** Immediately record and update progress in `docs/completed_work.md`, detailing:
   - Specific files created, modified, or verified.
   - Architectural and implementation details completed.
   - Verification status, test logs, and lint results (`verilator --lint-only -Wall`).
   - The immediate next task according to §11 of this plan.

