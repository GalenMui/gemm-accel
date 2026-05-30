#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/sim/out"

mkdir -p "${OUT_DIR}"

python3 "${ROOT_DIR}/models/gen_tests.py" \
  --clean \
  --out-dir "${ROOT_DIR}/tb/test_vectors/default" \
  --tile-m 2 \
  --tile-n 2 \
  --tile-k 2

iverilog -g2012 -Wall \
  -o "${OUT_DIR}/gemm_accel_tb.vvp" \
  -c "${ROOT_DIR}/sim/filelist.f"

vvp "${OUT_DIR}/gemm_accel_tb.vvp" "+VECTOR_ROOT=${ROOT_DIR}/tb/test_vectors/default"
