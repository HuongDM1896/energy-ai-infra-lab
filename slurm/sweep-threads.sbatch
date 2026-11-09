#!/bin/bash
# Job array: one task per thread count -> energy/throughput scaling curve.
#SBATCH --job-name=thread-sweep
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --array=0-3
#SBATCH --cpus-per-task=4
#SBATCH --time=00:15:00

set -euo pipefail
mkdir -p logs results
THREADS=(1 2 3 4)
T=${THREADS[$SLURM_ARRAY_TASK_ID]}

srun python bench/train_bench.py \
    --model resnet18 --steps 30 --threads "$T" \
    --tag "slurm-threads-$T" --output-dir results/slurm-sweep
