# Verification

## Golden Model Flow

`models/gemm_golden.py` implements signed integer GEMM using the same
fixed-width two's-complement accumulator behavior as the RTL. `models/gen_tests.py`
uses it to emit:

- `a.mem`
- `b.mem`
- `c.mem`
- `meta.txt`
- `manifest.txt`

The SystemVerilog testbench reads the manifest, loads each vector set into the
A/B scratchpads, starts the accelerator, waits for `done`, and compares every
C element against the generated golden result.

## Test Cases

The generated suite includes:

- all zeros
- identity-like A matrix
- small hand-checkable matrices
- random positive values
- random signed values
- int8 min/max stress values
- edge tiles with dimensions not divisible by the tile size

`scripts/run_tests.py` runs the suite for both 2x2x2 and 4x4x4 tile
configurations by compiling the testbench with different tile parameters.

## Failure Behavior

On mismatch, the testbench prints:

- case name
- C row and column
- expected signed value
- observed signed value
- expected and observed hex values

The simulation then exits with `$fatal`.

## Commands

Default simulation:

```bash
./scripts/run_iverilog.sh
```

Full regression and report generation:

```bash
python3 scripts/run_tests.py
```
