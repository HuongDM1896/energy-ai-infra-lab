#!/bin/bash
# Runs the benchmark simultaneously on every node (one task per node).
# Each task writes its own run_<host>_*.json, so per-node results can be compared.
#SBATCH --job-name=multinode
#SBATCH --output=logs/%x-%j.out
#SBATCH --nodes=3
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=18
#SBATCH --exclusive
#SBATCH --time=00:15:00
# Submit from the repo root with the venv activated:
#   source ~/venv-lab/bin/activate && mkdir -p logs
#   sbatch --wait slurm/bench-multinode.sbatch; cat $(ls -t logs/multinode-*.out | head -1)

set -uo pipefail
OUT=results/slurm-multinode
mkdir -p "$OUT"
echo "job=$SLURM_JOB_ID nodes=$SLURM_JOB_NODELIST"

# --label prefixes every output line with the task id (0, 1, 2)
srun --label bash -c '
  echo "running on $(hostname -s)"
  python bench/train_bench.py --model resnet18 --steps 500 \
      --threads "$SLURM_CPUS_PER_TASK" --tag multinode --output-dir '"$OUT"' \
    | grep -E "\"host\"|throughput_samples|cpu_energy_j|elapsed_s"
'

echo "===== per-node summary ====="
python - "$OUT" "$SLURM_JOB_ID" <<'EOF'
import glob, json, os, sys
out, job = sys.argv[1:]
files = sorted(glob.glob(f"{out}/run_*.json"), key=os.path.getmtime)[-int(os.environ["SLURM_NNODES"]):]
for f in files:
    r = json.load(open(f))
    p = r["cpu_energy_j"] / r["elapsed_s"] if r["cpu_energy_j"] else float("nan")
    print(f"{r['host']:<30} {r['throughput_samples_per_s']:8.0f} samples/s   RAPL {p:6.1f} W")
EOF
