#!/bin/bash
#SBATCH --job-name=energy-bench
#SBATCH --output=logs/%x-%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=18
#SBATCH --exclusive
#SBATCH --time=00:15:00

# Measures the job's energy two ways, with no second terminal needed:
#   1) Slurm node counter (acct_gather_energy/rapl, ConsumedJoules)
#   2) in-process RAPL reading written by train_bench.py
# Submit from the repo root with the venv activated (sbatch exports the env):
#   source ~/venv-lab/bin/activate && mkdir -p logs
#   sbatch --wait slurm/bench.sbatch && tail -4 $(ls -t logs/energy-bench-*.out | head -1)
set -euo pipefail
mkdir -p results/slurm
NODE=$(hostname -s)
joules() { scontrol show node "$NODE" | grep -oP 'ConsumedJoules=\K[0-9]+'; }

E0=$(joules); T0=$(date +%s)
srun python bench/train_bench.py --model resnet18 --steps 500 \
    --threads "$SLURM_CPUS_PER_TASK" --tag slurm --output-dir results/slurm
sleep 6                      # let the counter catch up (AcctGatherNodeFreq=5)
E1=$(joules); T1=$(date +%s)

RAPL_J=$(python -c "import json,glob,os; f=max(glob.glob('results/slurm/run_*.json'),key=os.path.getmtime); print(round(json.load(open(f))['cpu_energy_j'] or 0))")
echo "===== energy summary (job $SLURM_JOB_ID on $NODE) ====="
echo "slurm node counter : $((E1 - E0)) J over $((T1 - T0)) s (includes startup + 6 s wait)"
echo "in-process RAPL    : ${RAPL_J} J (training loop only)"
