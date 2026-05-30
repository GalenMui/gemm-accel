#!/usr/bin/env python3
"""Generate deterministic signed-GEMM vectors for the RTL testbench."""

from __future__ import annotations

import argparse
import random
import shutil
from pathlib import Path

from gemm_golden import GemmCase, signed_limits, write_case


def matrix(rows: int, cols: int, fn) -> list[list[int]]:
    return [[fn(row, col) for col in range(cols)] for row in range(rows)]


def random_matrix(
    rng: random.Random,
    rows: int,
    cols: int,
    lo: int,
    hi: int,
) -> list[list[int]]:
    return [[rng.randint(lo, hi) for _ in range(cols)] for _ in range(rows)]


def identity_like(size: int) -> list[list[int]]:
    return [[1 if row == col else 0 for col in range(size)] for row in range(size)]


def make_cases(tile_m: int, tile_n: int, tile_k: int, data_width: int) -> list[GemmCase]:
    lo, hi = signed_limits(data_width)
    rng = random.Random(0xC0DEC0DE + tile_m * 101 + tile_n * 17 + tile_k)

    base_m = max(4, tile_m * 2)
    base_n = max(4, tile_n * 2)
    base_k = max(4, tile_k * 2)
    edge_m = tile_m * 2 + 1
    edge_n = tile_n * 2 + 1
    edge_k = tile_k * 2 + 1

    cases = [
        GemmCase(
            name="zeros_4x4x4",
            m=4,
            n=4,
            k=4,
            a=matrix(4, 4, lambda _r, _c: 0),
            b=matrix(4, 4, lambda _r, _c: 0),
        ),
        GemmCase(
            name="identity_4x4x4",
            m=4,
            n=4,
            k=4,
            a=identity_like(4),
            b=matrix(4, 4, lambda r, c: ((r + 1) * (c + 2)) - 5),
        ),
        GemmCase(
            name="hand_small_4x4x4",
            m=4,
            n=4,
            k=4,
            a=matrix(4, 4, lambda r, c: (r * 3) - c + 1),
            b=matrix(4, 4, lambda r, c: (r - (c * 2)) + 2),
        ),
        GemmCase(
            name=f"random_positive_{base_m}x{base_n}x{base_k}",
            m=base_m,
            n=base_n,
            k=base_k,
            a=random_matrix(rng, base_m, base_k, 0, min(hi, 7)),
            b=random_matrix(rng, base_k, base_n, 0, min(hi, 7)),
        ),
        GemmCase(
            name=f"random_signed_{base_m}x{base_n}x{base_k}",
            m=base_m,
            n=base_n,
            k=base_k,
            a=random_matrix(rng, base_m, base_k, max(lo, -8), min(hi, 7)),
            b=random_matrix(rng, base_k, base_n, max(lo, -8), min(hi, 7)),
        ),
        GemmCase(
            name="int8_extremes_4x4x4",
            m=4,
            n=4,
            k=4,
            a=matrix(4, 4, lambda r, c: [lo, -1, 0, hi][(r + c) % 4]),
            b=matrix(4, 4, lambda r, c: [hi, 1, -1, lo][((r * 2) + c) % 4]),
        ),
        GemmCase(
            name=f"edge_tiles_{edge_m}x{edge_n}x{edge_k}",
            m=edge_m,
            n=edge_n,
            k=edge_k,
            a=random_matrix(rng, edge_m, edge_k, max(lo, -5), min(hi, 5)),
            b=random_matrix(rng, edge_k, edge_n, max(lo, -5), min(hi, 5)),
        ),
    ]

    return cases


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=Path("tb/test_vectors/default"))
    parser.add_argument("--data-width", type=int, default=8)
    parser.add_argument("--acc-width", type=int, default=32)
    parser.add_argument("--tile-m", type=int, default=2)
    parser.add_argument("--tile-n", type=int, default=2)
    parser.add_argument("--tile-k", type=int, default=2)
    parser.add_argument("--clean", action="store_true", help="Remove the output directory first")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.clean and args.out_dir.exists():
        shutil.rmtree(args.out_dir)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    cases = make_cases(args.tile_m, args.tile_n, args.tile_k, args.data_width)

    manifest_lines = []
    for case in cases:
        write_case(args.out_dir, case, args.data_width, args.acc_width)
        manifest_lines.append(f"{case.name} {case.m} {case.n} {case.k}\n")

    (args.out_dir / "manifest.txt").write_text("".join(manifest_lines), encoding="utf-8")
    print(f"Generated {len(cases)} GEMM test cases in {args.out_dir}")


if __name__ == "__main__":
    main()
