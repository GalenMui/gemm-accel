# Tiled INT8 GEMM Accelerator

This repository implements a small but realistic SystemVerilog GEMM accelerator
for signed integer matrix multiplication:

```text
C = A x B
```

The default working target is signed INT8 input data with signed INT32
accumulation. The primary top level is `rtl/gemm_accel.sv`, which exposes a
simple host scratchpad interface plus `start`, `busy`, and `done` control.

## Current Architecture

- `TILE_M x TILE_N` output-stationary systolic array
- `TILE_K` reduction blocking
- local A tile buffer, B tile buffer, and C output tile buffer
- BRAM-style A, B, and C scratchpads
- controller FSM with `CLEAR`, `LOAD`, `COMPUTE`, `DRAIN`, `CAPTURE`, `STORE`
- signed MAC datapath with optional zero gating
- edge-tile support by zero-padding inactive tile lanes

The first target configuration is:

```text
DATA_WIDTH = 8
ACC_WIDTH  = 32
M,N,K      = runtime configured
TILE_M     = 2
TILE_N     = 2
TILE_K     = 2
```

The regression also compiles and runs a `4x4x4` tile configuration.

## Repository Layout

```text
rtl/
  gemm_accel.sv       top-level accelerator wrapper
  gemm_top.sv         tiled core integration
  controller.sv       tile-loop FSM
  tile_buffer.sv      reusable local tile buffer
  scratchpad.sv       true dual-port local memory
  systolic_array.sv   output-stationary PE mesh
  pe.sv               processing element
  mac_unit.sv         signed integer MAC helper
tb/
  gemm_accel_tb.sv    generated-vector SystemVerilog testbench
  test_vectors/       generated input and expected-output vectors
models/
  gemm_golden.py      Python signed GEMM golden model
  gen_tests.py        deterministic randomized vector generator
scripts/
  run_iverilog.sh     default single-config simulation
  run_tests.py        vector generation, tile sweep, report collection
  vivado_synth.tcl    optional non-project Vivado synthesis flow
docs/
  architecture.md
  verification.md
  performance.md
reports/
  simulation_results/
  performance_results/
```

## Run Simulation

Default 2x2x2 tile simulation:

```bash
./scripts/run_iverilog.sh
```

Full regression with generated vectors, 2x2x2 and 4x4x4 tile builds, logs, and
performance summaries:

```bash
python3 scripts/run_tests.py
```

The full run writes:

- `reports/simulation_results/*.txt`
- `reports/performance_results/performance_summary.csv`
- `reports/performance_results/performance_summary.md`

## Example Results

Measured with `python3 scripts/run_tests.py`:

| Case | Shape | Tile | Cycles | MAC Ops | MACs/Cycle | Peak | Utilization |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| random_signed_4x4x4 | 4x4x4 | 2x2x2 | 109 | 64 | 0.587 | 4 | 14.68% |
| edge_tiles_5x5x5 | 5x5x5 | 2x2x2 | 325 | 125 | 0.385 | 4 | 9.62% |
| random_signed_8x8x8 | 8x8x8 | 4x4x4 | 349 | 512 | 1.467 | 16 | 9.17% |
| edge_tiles_9x9x9 | 9x9x9 | 4x4x4 | 1027 | 729 | 0.710 | 16 | 4.44% |

Utilization is low for these small matrices because the current design uses a
simple one-element-per-cycle scratchpad load path and explicit capture/store
phases. That is intentional for a clean first RTL target.

## Vivado Synthesis

The repo includes a simple non-project synthesis script:

```bash
vivado -mode batch -source scripts/vivado_synth.tcl -tclargs xc7a200tfbg484-1 gemm_accel 5.0
```

This flow is provided as collateral, not as a claimed FPGA result. Resource,
timing, and power numbers should only be reported after running Vivado locally.

## Current Limitations

- no AXI, DMA, or cache-coherent host interface yet
- no floating point
- no double-buffering or load/compute overlap
- no synthesis/resource claims checked into the repo
- accumulator overflow follows fixed-width two's-complement RTL behavior

Good next extensions would be double-buffered tile loads, richer counters,
AXI-Lite control, AXI-Stream or DMA data movement, and synthesis-driven area
and timing exploration.
