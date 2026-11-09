#!/bin/bash
#SBATCH --job-name=energy-bench
#SBATCH --output=logs/%x-%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=18
#SBATCH --exclusive
#SBATCH --time=00:15:00

# Measures the job's energy two ways, with no second terminal needed:
#   1) Slurm's own view (acct_gather_energy/rapl):
#      - step energy from sstat (ConsumedEnergyRaw), polled while the step runs
#      - node power from scontrol (CurrentWatts), sampled every second and integrated
#   2) in-process RAPL reading written by train_bench.py (training loop only)
# Submit from the repo root with the venv activated (sbatch exports the env):
#   source ~/venv-lab/bin/activate && mkdir -p logs
#   sbatch --wait slurm/bench.sbatch; tail -8 $(ls -t logs/energy-bench-*.out | head -1)
set -uo pipefail
OUT=results/slurm
mkdir -p "$OUT"
NODE=$(hostname -s)
WATTS_LOG="$OUT/watts_${SLURM_JOB_ID}.txt"
STEP_LOG="$OUT/sstat_${SLURM_JOB_ID}.txt"

watts() { scontrol show node "$NODE" | grep -oP 'CurrentWatts=\K[0-9]+' || echo 0; }

# Background sampler: node power (W) every second + Slurm step energy (J)
(
  while true; do
    echo "$(date +%s.%N) $(watts)" >> "$WATTS_LOG"
    sstat -n -P -j "${SLURM_JOB_ID}.0" --format=ConsumedEnergyRaw 2>/dev/null | head -1 >> "$STEP_LOG"
    sleep 1
  done
) &
SAMPLER=$!

srun python bench/train_bench.py --model resnet18 --steps 500 \
    --threads "$SLURM_CPUS_PER_TASK" --tag slurm --output-dir "$OUT"
kill "$SAMPLER" 2>/dev/null

python - "$WATTS_LOG" "$STEP_LOG" "$OUT" "$SLURM_JOB_ID" "$NODE" <<'EOF'
import glob, json, os, sys
watts_log, step_log, out, job, node = sys.argv[1:]

pts = []
for line in open(watts_log):
    t, w = line.split()
    pts.append((float(t), float(w)))
node_j = sum((t2 - t1) * (w1 + w2) / 2 for (t1, w1), (t2, w2) in zip(pts, pts[1:]))
dur = pts[-1][0] - pts[0][0] if len(pts) > 1 else 0

step_vals = [int(l) for l in open(step_log).read().split() if l.strip().isdigit()]
step_j = step_vals[-1] if step_vals else None

run = json.load(open(max(glob.glob(f"{out}/run_*.json"), key=os.path.getmtime)))
rapl_j = run["cpu_energy_j"]

print(f"===== energy summary (job {job} on {node}) =====")
print(f"slurm step energy (sstat)      : {step_j if step_j is not None else 'n/a'} J  (whole srun step, incl. startup)")
print(f"slurm node power x time        : {node_j:.0f} J over {dur:.0f} s  (CurrentWatts, 5 s refresh)")
print(f"in-process RAPL                : {rapl_j:.0f} J over {run['elapsed_s']:.0f} s  (training loop only)" if rapl_j else "in-process RAPL                : n/a (RAPL not readable)")
print(f"throughput                     : {run['throughput_samples_per_s']:.0f} samples/s")
EOF
