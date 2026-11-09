#!/bin/bash
#SBATCH --job-name=energy-bench
#SBATCH --output=logs/%x-%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:10:00
# Uncomment on a real cluster that has the RAPL energy plugin enabled:
# #SBATCH --acctg-freq=energy=5

set -euo pipefail
mkdir -p logs results

echo "job=$SLURM_JOB_ID node=$(hostname) cpus=$SLURM_CPUS_PER_TASK"
srun python bench/train_bench.py \
    --model resnet18 --steps 30 \
    --threads "$SLURM_CPUS_PER_TASK" \
    --tag slurm --output-dir results/slurm

# After the job ends, Slurm's own energy accounting (if configured):
#   sacct -j $SLURM_JOB_ID --format=JobID,Elapsed,ConsumedEnergy,AveCPUFreq
