#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/sim/out"

mkdir -p "${OUT_DIR}"

iverilog -g2012 -Wall \
  -o "${OUT_DIR}/gemm_top_tb.vvp" \
  -c "${ROOT_DIR}/sim/filelist.f"

vvp "${OUT_DIR}/gemm_top_tb.vvp"
