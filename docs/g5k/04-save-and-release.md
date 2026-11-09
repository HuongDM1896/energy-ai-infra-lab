# Grid'5000 — 4. Save results and release the nodes

🖥️
```bash
cd ~/energy-ai-infra-lab
bash scripts/g5k/collect-results.sh
exit                       # leave the interactive job
```
🚪 make sure nothing is left running:
```bash
oarstat -u
oardel <JOBID>             # only if something is still listed
```
💻 copy the archive home:
```bash
scp nancy.g5k:results-*.tgz .
```

## Putting results in the repo
Raw `results/` is git-ignored (many small JSON files). Commit what a reader needs:
```bash
mkdir -p docs/results
cp analysis/out-slurm-sweep/summary.csv docs/results/slurm-thread-sweep.csv
cp analysis/out-slurm-sweep/energy_vs_throughput.png docs/results/slurm-thread-sweep.png
```
Then reference them from the top-level README, with the hardware, software
versions, CPU state and number of repetitions.
