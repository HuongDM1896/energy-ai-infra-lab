#!/bin/bash
# Job array: one task per thread count -> energy/throughput scaling curve.
# Each task gets a whole node (--exclusive) and runs exactly one copy (--ntasks=1).
# Without --ntasks=1, --exclusive let srun start ~18 copies per node, which
# silently ruined the first sweep.
#SBATCH --job-name=thread-sweep
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --array=0-3
#SBATCH --cpus-per-task=4
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --time=00:15:00
# Submit from the repo root with the venv activated:
#   source ~/venv-lab/bin/activate && mkdir -p logs
#   sbatch --wait slurm/sweep-threads.sbatch
#   python analysis/aggregate.py results/slurm-sweep --out analysis/out-slurm-sweep

set -euo pipefail
mkdir -p logs results
THREADS=(1 2 3 4)
T=${THREADS[$SLURM_ARRAY_TASK_ID]}

srun -n 1 python bench/train_bench.py \
    --model resnet18 --steps 300 --threads "$T" \
    --tag "slurm-threads-$T" --output-dir "results/slurm-sweep/$SLURM_ARRAY_JOB_ID"
