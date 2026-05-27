# INT8 GEMM Accelerator on FPGA

This project implements a synthesizable SystemVerilog INT8 GEMM accelerator
organized like a small FPGA RTL repository. The default configuration is an
8x8 output-stationary systolic array that performs `INT8 x INT8 -> INT32`
matrix multiplication with tiled execution, BRAM-backed scratchpads, and a
simple sparsity-aware MAC gating scheme.

## Project goal

The design is meant to look like a realistic FPGA hardware project rather than
a toy matrix-multiply example. The emphasis is on:

- parameterized RTL that scales beyond the default 8x8 array
- Vivado-friendly coding style for DSP and BRAM inference
- explicit controller-driven `load / compute / store` execution
- readable verification and synthesis collateral

## Repository structure

```text
rtl/
  pe.sv
  systolic_array.sv
  scratchpad.sv
  controller.sv
  gemm_top.sv
tb/
  gemm_top_tb.sv
sim/
  filelist.f
scripts/
  run_iverilog.sh
  vivado_synth.tcl
docs/
  architecture.md
README.md
```

## Architecture overview

### Processing array

- `pe.sv` implements one output-stationary processing element.
- Each PE receives one activation and one weight, forwards them to its
  neighbors, and accumulates the product into a local INT32 register.
- The multiply-accumulate expression is written in a DSP-friendly style for
  Xilinx synthesis.

### Systolic dataflow

- `systolic_array.sv` instantiates a parameterized `ARRAY_M x ARRAY_N` grid.
- Input skewing is handled inside the array. Row `i` activations are delayed by
  `i` cycles and column `j` weights are delayed by `j` cycles before entering
  the mesh.
- This keeps the top-level streaming interface simple: one `k` slice of `A`
  rows and `B` columns is presented per cycle, while the array itself aligns
  the wavefront.

### Scratchpads

- `scratchpad.sv` is a generic true dual-port RAM.
- `gemm_top.sv` instantiates separate A, B, and C scratchpads.
- One port is host-facing for preloading matrices and reading back results.
- The second port is accelerator-facing so the controller can read A/B tiles
  and store C results without sharing the host port.
- The memory declaration uses `(* ram_style = "block" *)` so Vivado is more
  likely to infer BRAM instead of distributing large memories into registers.

### Tile buffers

- The controller does not try to read many values per cycle directly from BRAM.
- Instead, it stages one tile of A and one tile of B into small local buffers
  inside `gemm_top.sv`.
- This is a practical FPGA tradeoff: BRAM provides capacity, while the tile
  buffers provide the per-cycle bandwidth needed to feed the systolic array.

### Tiling strategy

- The output tile size is `ARRAY_M x ARRAY_N`.
- The inner reduction dimension is processed in chunks of `TILE_K`.
- For each output tile `(m_tile, n_tile)`, the controller loops over all
  `k_tile` chunks, accumulating partial sums in the PE array.
- After the final `k_tile`, the completed output tile is written to the C
  scratchpad.
- Partial edge tiles are handled by zero-padding inactive rows, columns, or
  `k` lanes in the local tile buffers.

### Control flow

`controller.sv` sequences:

1. `CLEAR`: reset the PE accumulators for a new output tile
2. `LOAD`: fetch the next A/B tile chunk from scratchpads
3. `COMPUTE`: stream one `k` slice per cycle into the array
4. `DRAIN`: allow the systolic wavefront to finish propagating
5. `STORE`: write the completed output tile to the output scratchpad

This produces a realistic accelerator control path for repeated tile
processing across larger matrices.

### Sparsity-aware gating

- Each PE checks whether the incoming activation or weight is zero.
- If either operand is zero, the accumulator update is skipped for that cycle.
- The zero values still propagate through the array, so the dataflow timing
  remains systolic and synthesizable.

This is intentionally simple, but it is a believable first-step sparsity
optimization for an FPGA accelerator.

## Module summary

- `rtl/pe.sv`: INT8 MAC PE with operand forwarding and zero gating
- `rtl/systolic_array.sv`: parameterized systolic mesh with input skew logic
- `rtl/scratchpad.sv`: BRAM-friendly true dual-port local memory
- `rtl/controller.sv`: tile-loop FSM for load/compute/drain/store sequencing
- `rtl/gemm_top.sv`: top-level integration of scratchpads, tile buffers,
  controller, and compute array
- `tb/gemm_top_tb.sv`: deterministic top-level verification

## Simulation

The supplied testbench runs:

- a small 4x4x4 case with embedded zeros to exercise sparse gating
- a larger 10x9x12 case that crosses tile boundaries in `M`, `N`, and `K`

Run the simulation with:

```bash
./scripts/run_iverilog.sh
```

The script compiles the RTL and testbench with `iverilog -g2012` and executes
the simulation with `vvp`.

## Vivado synthesis

The repository includes a simple non-project synthesis TCL flow:

```bash
vivado -mode batch -source scripts/vivado_synth.tcl -tclargs xc7a200tfbg484-1 gemm_top 5.0
```

Arguments:

- FPGA part: defaults to `xc7a200tfbg484-1`
- top module: defaults to `gemm_top`
- clock period in ns: defaults to `5.0`

The script emits:

- `vivado_out/post_synth_utilization.rpt`
- `vivado_out/post_synth_utilization_hier.rpt`
- `vivado_out/post_synth_timing.rpt`
- `vivado_out/post_synth_power.rpt`
- `vivado_out/post_synth.dcp`

## What to inspect in Vivado

When reviewing synthesis results, pay attention to:

- DSP utilization: confirm multiplies are mapping into DSP resources rather
  than LUT-heavy soft multipliers
- BRAM utilization: confirm the scratchpads infer block RAMs
- hierarchical utilization: check where BRAM and DSP resources land
- inferred memory style: verify the scratchpad arrays are not implemented as
  distributed registers
- timing summary and slack: especially on the PE MAC path, controller address
  generation, and the array interconnect

## FPGA-oriented design decisions

- Output-stationary accumulation keeps partial sums local inside PEs, which is
  a natural fit for systolic GEMM hardware.
- Dual-port scratchpads separate host access from accelerator access.
- Small tile buffers avoid unrealistic multi-port BRAM assumptions.
- Zero gating is implemented in the PE datapath, not as a fragile external
  shortcut that would break the systolic schedule.

## Future extensions

- scale the array beyond 8x8 and tune `TILE_K` independently
- add double-buffered tile buffers to overlap load and compute
- wrap the scratchpads and control plane in AXI-Lite / AXI-Stream interfaces
- add quantization, dequantization, or bias support around GEMM
- improve sparsity handling with compressed metadata or row/column skipping
- add performance counters for tile latency, utilization, and zero-skip events
