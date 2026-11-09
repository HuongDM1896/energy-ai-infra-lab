#!/bin/bash
# All Slurm experiments from the guide in one go. Run on the head node, from the
# repo root, with the venv activated (sbatch passes the environment to the jobs).
#
#   bash scripts/g5k/slurm-runs.sh            # everything
#   bash scripts/g5k/slurm-runs.sh threads    # only the thread sweep
#   REPS=5 bash scripts/g5k/slurm-runs.sh multinode
#
# Parts:
#   single     one benchmark job + energy summary (Slurm vs in-process RAPL)
#   threads    thread-scaling job array (1-4 threads, one node per task), REPS times
#   multinode  benchmark on all nodes at once, REPS times
#   pernode    the single job pinned to each node in turn (node-to-node variability)
set -uo pipefail
source scripts/g5k/common.sh

REPS=${REPS:-3}
WHAT=${1:-all}
mkdir -p logs results

latest() { ls -t logs/"$1"-*.out 2>/dev/null | head -1; }

run_single() {
  echo "### single job"
  sbatch --wait slurm/bench.sbatch >/dev/null
  tail -6 "$(latest energy-bench)"
}

run_threads() {
  echo "### thread sweep x $REPS"
  for i in $(seq 1 "$REPS"); do
    sbatch --wait slurm/sweep-threads.sbatch >/dev/null
    echo "  repetition $i done"
  done
  python analysis/aggregate.py results/slurm-sweep --out analysis/out-slurm-sweep
}

run_multinode() {
  echo "### multi-node x $REPS"
  for i in $(seq 1 "$REPS"); do
    sbatch --wait slurm/bench-multinode.sbatch >/dev/null
    tail -"$(wc -l < "$NODES_FILE")" "$(latest multinode)"
  done
  python analysis/aggregate.py results/slurm-multinode --out analysis/out-slurm-multinode
}

run_pernode() {
  echo "### per-node (one node at a time)"
  for n in $(cat "$NODES_FILE"); do
    sbatch --wait -w "$(short "$n")" slurm/bench.sbatch >/dev/null
    echo "-- $(short "$n")"
    tail -2 "$(latest energy-bench)"
  done
}

case "$WHAT" in
  single) run_single ;;
  threads) run_threads ;;
  multinode) run_multinode ;;
  pernode) run_pernode ;;
  all) run_single; run_threads; run_multinode; run_pernode ;;
  *) echo "unknown part: $WHAT (single|threads|multinode|pernode|all)"; exit 1 ;;
esac
