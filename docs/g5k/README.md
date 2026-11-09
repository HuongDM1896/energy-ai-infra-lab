# Running on Grid'5000

Copy-paste guides for the `gros` cluster (Nancy). Each step has its own page and
script; run them in order, all from the repo root on the head node.

| Step | Guide | Script(s) | Status |
|---|---|---|---|
| 0 | [Reserve and set up](00-setup.md) | `common.sh`, `setup-node.sh`, `set-cpu-state.sh` | works |
| 1 | [Bare metal: RAPL, frequency sweep, wattmeter](01-bare-metal.md) | `freq-sweep.sh`, `wattmeter-check.sh` | works; freq sweep to rerun with turbo off |
| 2 | [Slurm](02-slurm.md) | `setup-slurm.sh`, `slurm-runs.sh` | works |
| 3 | [Kubernetes (k3s)](03-kubernetes.md) | `setup-k3s.sh` | blocked: k3s stuck in `activating` |
| 4 | [Save and release](04-save-and-release.md) | `collect-results.sh` | works |

All scripts live in `scripts/g5k/`.
