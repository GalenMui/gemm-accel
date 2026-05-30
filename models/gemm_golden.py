#!/usr/bin/env python3
"""Golden-model helpers for signed integer GEMM test generation."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class GemmCase:
    name: str
    m: int
    n: int
    k: int
    a: list[list[int]]
    b: list[list[int]]


def signed_limits(width: int) -> tuple[int, int]:
    return -(1 << (width - 1)), (1 << (width - 1)) - 1


def wrap_signed(value: int, width: int) -> int:
    mask = (1 << width) - 1
    value &= mask
    sign_bit = 1 << (width - 1)
    return value - (1 << width) if value & sign_bit else value


def hex_word(value: int, width: int) -> str:
    digits = (width + 3) // 4
    return f"{value & ((1 << width) - 1):0{digits}x}"


def flatten_rows(matrix: Iterable[Iterable[int]]) -> list[int]:
    return [value for row in matrix for value in row]


def gemm(a: list[list[int]], b: list[list[int]], acc_width: int) -> list[list[int]]:
    if not a or not b:
        return []

    m = len(a)
    k = len(a[0])
    n = len(b[0])

    c: list[list[int]] = [[0 for _ in range(n)] for _ in range(m)]
    for row in range(m):
        for col in range(n):
            acc = 0
            for kk in range(k):
                acc = wrap_signed(acc + (a[row][kk] * b[kk][col]), acc_width)
            c[row][col] = acc
    return c


def write_hex_file(path: Path, values: Iterable[int], width: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(f"{hex_word(value, width)}\n" for value in values),
        encoding="utf-8",
    )


def write_case(out_dir: Path, case: GemmCase, data_width: int, acc_width: int) -> None:
    case_dir = out_dir / case.name
    expected = gemm(case.a, case.b, acc_width)

    write_hex_file(case_dir / "a.mem", flatten_rows(case.a), data_width)
    write_hex_file(case_dir / "b.mem", flatten_rows(case.b), data_width)
    write_hex_file(case_dir / "c.mem", flatten_rows(expected), acc_width)
    (case_dir / "meta.txt").write_text(
        "\n".join(
            [
                f"name={case.name}",
                f"m={case.m}",
                f"n={case.n}",
                f"k={case.k}",
                f"mac_ops={case.m * case.n * case.k}",
                "",
            ]
        ),
        encoding="utf-8",
    )
