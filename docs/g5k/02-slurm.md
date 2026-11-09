# Grid'5000 — 2. Slurm on the reserved nodes

Prerequisite: [0. Setup](00-setup.md). Works on gros; tested Nov 2026.

## Install and start
```bash
bash scripts/g5k/setup-slurm.sh
```
Installs `slurm-wlm` + `munge` on all nodes, shares one munge key, generates
`slurm.conf` with the RAPL energy plugin (`acct_gather_energy/rapl`) and starts
the daemons. `sinfo` at the end must show all nodes `idle`.

Fixes already built into the script:
- `slurmd -C` printed nothing on this Debian version, which left an empty
  `NodeName` line (`unrecognized key: State`). The script falls back to
  `nproc` / `free`.
- Node names in `slurm.conf` must be short (`gros-60`), not FQDNs.

## Run the experiments
With the venv activated (sbatch passes the environment to the jobs):
```bash
bash scripts/g5k/slurm-runs.sh                 # everything below
bash scripts/g5k/slurm-runs.sh single          # or one part at a time
REPS=5 bash scripts/g5k/slurm-runs.sh threads
```

| part | job file | what it shows |
|---|---|---|
| `single` | `slurm/bench.sbatch` | energy seen by Slurm vs in-process RAPL |
| `threads` | `slurm/sweep-threads.sbatch` | thread scaling 1–4, one node per task |
| `multinode` | `slurm/bench-multinode.sbatch` | same job on all nodes at once |
| `pernode` | `slurm/bench.sbatch -w <node>` | node-to-node variability, one at a time |

Each job can also be submitted by hand, e.g.
`sbatch --wait slurm/bench.sbatch; tail -6 $(ls -t logs/energy-bench-*.out | head -1)`.

## How to read the results

### `bench.sbatch` energy summary
```
slurm step energy (sstat)  : ... J  (whole srun step, incl. startup)
slurm node power x time    : ... J over ... s  (CurrentWatts, 5 s refresh)
in-process RAPL            : ... J over ... s  (training loop only)
```
The Slurm numbers include Python import, model build and warm-up; in-process
RAPL covers only the timed loop, so it is the smallest. Compare **power**
(energy / duration), not energy. `sstat` and RAPL use the same counters, so their
power should be close; `CurrentWatts` refreshes every 5 s and is the coarsest.
This Slurm version has no `ConsumedJoules` in `scontrol show node`, which is why
the script samples `CurrentWatts` and polls `sstat`.

### Thread sweep
```bash
python analysis/aggregate.py results/slurm-sweep --out analysis/out-slurm-sweep
```
One row per thread count. Throughput should rise and energy per sample fall
with more threads (static power spread over more work).

### Multi-node / per-node
Same model, same power, but throughput differs between nodes. Repeat before
drawing conclusions: on gros the node ranking changed between runs (see the
top-level README, "Results").

## Pitfalls met on the way (all fixed in the repo)
- `logs/` must exist before `sbatch` (Slurm opens the output file first).
- `--exclusive` without `--ntasks=1` made `srun` start ~18 copies per node.
- Results from different submissions piled up in one folder; the sweep now
  writes to `results/slurm-sweep/<job id>/`.
- `sacct` history needs `slurmdbd` + MariaDB, skipped in this minimal setup.

## Stop Slurm (before Kubernetes)
```bash
onall 'sudo-g5k systemctl stop slurmd slurmctld'
```

Next: [3. Kubernetes](03-kubernetes.md)
