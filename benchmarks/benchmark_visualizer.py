#!/usr/bin/env python3
"""
BookMyShow Benchmark Visualizer & Latency Delta Reporter
Authors: Team T0132

Parses summary.csv across baseline, optimized, and large dataset benchmarks.
Renders side-by-side terminal comparison charts and Markdown summary tables.
"""

import os
import csv
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE_DIR = os.path.join(ROOT_DIR, 'benchmarks', 'results')

def load_summary(phase):
    path = os.path.join(BASE_DIR, phase, 'summary.csv')
    if not os.path.exists(path):
        return {}
    results = {}
    with open(path, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            results[row['query_id']] = {
                'type': row.get('type', 'READ'),
                'avg_ms': float(row['avg_ms']),
                'median_ms': float(row.get('median_ms', row['avg_ms'])),
                'scan_nodes': row.get('scan_nodes', '')
            }
    return results

def render_comparison():
    baseline = load_summary('baseline')
    optimized = load_summary('optimized')
    large = load_summary('large')

    if not baseline or not optimized:
        print("[!] Missing baseline or optimized summary.csv in benchmarks/results/")
        return

    print("=" * 88)
    print(f"{'Query':<6} | {'Type':<5} | {'Baseline (ms)':<14} | {'Optimized (ms)':<14} | {'Speedup':<10} | {'Large 20x (ms)':<14}")
    print("-" * 88)

    all_queries = sorted(list(set(list(baseline.keys()) + list(optimized.keys()))))
    total_base = 0.0
    total_opt = 0.0

    for q in all_queries:
        b_time = baseline.get(q, {}).get('avg_ms', 0.0)
        o_time = optimized.get(q, {}).get('avg_ms', 0.0)
        l_time = large.get(q, {}).get('avg_ms', 0.0)
        q_type = baseline.get(q, {}).get('type', 'READ')

        total_base += b_time
        total_opt += o_time

        if o_time > 0:
            speedup = f"{b_time / o_time:.1f}x" if b_time >= o_time else f"-{o_time / b_time:.1f}x"
        else:
            speedup = "N/A"

        print(f"{q:<6} | {q_type:<5} | {b_time:>14.3f} | {o_time:>14.3f} | {speedup:>10} | {l_time:>14.3f}")

    print("=" * 88)
    overall_gain = total_base / total_opt if total_opt > 0 else 1.0
    print(f"TOTAL RUNTIME: Baseline = {total_base:.3f} ms | Optimized = {total_opt:.3f} ms | Net Gain = {overall_gain:.2f}x")
    print("=" * 88)

if __name__ == '__main__':
    render_comparison()
