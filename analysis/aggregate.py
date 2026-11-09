#!/usr/bin/env python3
"""Aggregate benchmark JSON files into a CSV and plot energy vs throughput.

Usage:
    python analysis/aggregate.py results/ --out analysis/out
"""
import argparse
import glob
import json
import os

import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def load(results_dir):
    rows = []
    for path in sorted(glob.glob(os.path.join(results_dir, "**", "*.json"), recursive=True)):
        with open(path) as f:
            rows.append(json.load(f))
    if not rows:
        raise SystemExit(f"no JSON results found under {results_dir}")
    return pd.DataFrame(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results_dir")
    parser.add_argument("--out", default="analysis/out")
    args = parser.parse_args()

    df = load(args.results_dir)
    os.makedirs(args.out, exist_ok=True)
    csv_path = os.path.join(args.out, "summary.csv")
    df.to_csv(csv_path, index=False)

    group_cols = ["scheduler", "tag", "model", "threads"]
    summary = (
        df.groupby(group_cols, dropna=False)
        .agg(runs=("elapsed_s", "size"),
             throughput_mean=("throughput_samples_per_s", "mean"),
             throughput_std=("throughput_samples_per_s", "std"),
             energy_per_sample_mean=("energy_per_sample_j", "mean"))
        .reset_index()
    )
    print(summary.to_string(index=False))

    fig, ax = plt.subplots(figsize=(6, 4))
    has_energy = df["energy_per_sample_j"].notna()
    if has_energy.any():
        for label, part in df[has_energy].groupby("tag", dropna=False):
            ax.scatter(part["throughput_samples_per_s"], part["energy_per_sample_j"],
                       label=label or "untagged")
        ax.set_ylabel("Energy per sample (J)")
        ax.set_title("Energy vs throughput")
    else:
        for label, part in df.groupby("tag", dropna=False):
            ax.bar(str(label or "untagged"), part["throughput_samples_per_s"].mean())
        ax.set_ylabel("Throughput (samples/s)")
        ax.set_title("Throughput (no energy data on this host)")
    ax.set_xlabel("Throughput (samples/s)" if has_energy.any() else "Run tag")
    if has_energy.any():
        ax.legend()
    fig.tight_layout()
    png_path = os.path.join(args.out, "energy_vs_throughput.png")
    fig.savefig(png_path, dpi=150)
    print(f"wrote {csv_path} and {png_path}")


if __name__ == "__main__":
    main()
