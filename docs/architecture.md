# Architecture Notes

## Datapath style

The design uses an output-stationary systolic array. Each PE owns one INT32
accumulator and forwards INT8 activations to the right and INT8 weights
downward every cycle.

## Why this is FPGA-friendly

- The PE MAC is written as a signed multiply followed by an INT32 accumulate,
  which is a natural fit for Xilinx DSP inference.
- Larger matrix storage lives in dedicated scratchpad memories coded as
  true dual-port RAMs with `ram_style="block"` to encourage BRAM inference.
- Only the active tile is staged into small local tile buffers, which keeps the
  high-bandwidth working set close to the array without requiring many-port
  BRAM structures.

## Tile flow

For each output tile:

1. `CLEAR`
   Reset PE accumulators before a new `C` tile starts.
2. `LOAD`
   Read one `A` element and one `B` element per cycle from BRAM-backed
   scratchpads into local tile buffers.
3. `COMPUTE`
   Stream one `k` slice per cycle into the systolic array.
4. `DRAIN`
   Wait for the systolic wavefront to reach the bottom-right PE.
5. `STORE`
   Write the completed `C` tile back into the output scratchpad.

If the full GEMM has more than one `K` tile, the controller repeats
`LOAD -> COMPUTE -> DRAIN` while preserving the PE accumulators, then stores
the output tile after the final `K` tile completes.

## Sparse gating

Each PE checks for `act_in == 0` or `wgt_in == 0`. When either operand is zero,
the multiply-accumulate update is skipped for that cycle. The operand stream
still propagates through the array, so the systolic schedule remains intact.
