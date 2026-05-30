#!/usr/bin/env python3
"""Generate vectors, run RTL simulations, and collect GEMM performance data."""

from __future__ import annotations

import csv
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIM_OUT = ROOT / "sim" / "out"
SIM_REPORTS = ROOT / "reports" / "simulation_results"
PERF_REPORTS = ROOT / "reports" / "performance_results"


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.returncode != 0:
        if proc.stderr:
            print(proc.stderr, end="")
        raise SystemExit(proc.returncode)
    return proc


def parse_perf(stdout: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line in stdout.splitlines():
        if not line.startswith("PERF "):
            continue
        row: dict[str, str] = {}
        for token in line.split()[1:]:
            if "=" in token:
                key, value = token.split("=", 1)
                row[key] = value
        rows.append(row)
    return rows


def write_perf_reports(rows: list[dict[str, str]]) -> None:
    PERF_REPORTS.mkdir(parents=True, exist_ok=True)
    csv_path = PERF_REPORTS / "performance_summary.csv"
    md_path = PERF_REPORTS / "performance_summary.md"

    fields = [
        "case",
        "M",
        "N",
        "K",
        "TILE_M",
        "TILE_N",
        "TILE_K",
        "cycles",
        "mac_ops",
        "macs_per_cycle",
        "peak_macs_per_cycle",
        "utilization_pct",
    ]

    with csv_path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    lines = [
        "# Performance Summary",
        "",
        "| Case | Shape | Tile | Cycles | MAC Ops | MACs/Cycle | Peak | Utilization |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {case} | {M}x{N}x{K} | {TILE_M}x{TILE_N}x{TILE_K} | {cycles} | "
            "{mac_ops} | {macs_per_cycle} | {peak_macs_per_cycle} | {utilization_pct}% |".format(
                **row
            )
        )
    lines.append("")
    md_path.write_text("\n".join(lines), encoding="utf-8")


def run_config(tile_m: int, tile_n: int, tile_k: int) -> list[dict[str, str]]:
    cfg_name = f"tm{tile_m}_tn{tile_n}_tk{tile_k}"
    vector_dir = ROOT / "tb" / "test_vectors" / cfg_name
    sim_bin = SIM_OUT / f"gemm_accel_tb_{cfg_name}.vvp"
    sim_log = SIM_REPORTS / f"{cfg_name}.txt"

    run(
        [
            "python3",
            str(ROOT / "models" / "gen_tests.py"),
            "--clean",
            "--out-dir",
            str(vector_dir),
            "--tile-m",
            str(tile_m),
            "--tile-n",
            str(tile_n),
            "--tile-k",
            str(tile_k),
        ]
    )

    SIM_OUT.mkdir(parents=True, exist_ok=True)
    run(
        [
            "iverilog",
            "-g2012",
            "-Wall",
            f"-DTILE_M={tile_m}",
            f"-DTILE_N={tile_n}",
            f"-DTILE_K={tile_k}",
            "-o",
            str(sim_bin),
            "-c",
            str(ROOT / "sim" / "filelist.f"),
        ]
    )

    proc = run(["vvp", str(sim_bin), f"+VECTOR_ROOT={vector_dir}"])
    SIM_REPORTS.mkdir(parents=True, exist_ok=True)
    sim_log.write_text(proc.stdout, encoding="utf-8")
    return parse_perf(proc.stdout)


def main() -> None:
    all_rows: list[dict[str, str]] = []
    for tile_m, tile_n, tile_k in [(2, 2, 2), (4, 4, 4)]:
        all_rows.extend(run_config(tile_m, tile_n, tile_k))
    write_perf_reports(all_rows)
    print(f"Wrote performance reports to {PERF_REPORTS}")


if __name__ == "__main__":
    main()
