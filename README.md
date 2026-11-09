# energy-ai-infra-lab

Energy-aware benchmarking of PyTorch training jobs across **bare metal,
Slurm and Kubernetes**, with RAPL / NVML / wattmeter energy measurement,
run on real Grid'5000 nodes.

> Portfolio project: hands-on AI/HPC infrastructure skills (batch scheduling,
> container orchestration, observability) combined with careful energy and
> performance measurement.

## What it does
- `bench/train_bench.py` — trains ResNet18 / MobileNetV2 on synthetic data for a
  fixed number of steps; records throughput, CPU energy (Intel RAPL, with counter
  wrap-around handling), GPU energy (NVML), the scheduler context (Slurm /
  Kubernetes) **and the CPU state** (driver, governor, frequency limits, turbo)
  into one JSON per run.
- `slurm/` — single job with an energy summary, thread-scaling job array,
  multi-node job.
- `scripts/g5k/` — one script per step on Grid'5000: node setup, CPU state,
  frequency sweep, wattmeter cross-check, Slurm install and runs, k3s install,
  result collection.
- `k8s/` — kind cluster config, a parallel benchmark Job, Prometheus/Grafana and
  Kepler Helm values.
- `analysis/aggregate.py` — merges all `run_*.json` into a CSV and plots energy
  vs throughput.
- CI (GitHub Actions) smoke-tests the benchmark and lints the manifests on every push.

## Quick start (laptop, no cluster)
```bash
make venv && . .venv/bin/activate
make bench
make analyze
```

## Guides
| Where | Guide | Skill shown |
|---|---|---|
| Laptop | [Kubernetes with kind](docs/01-kubernetes.md) | kind, Jobs, resources, Helm, Prometheus/Grafana, Kepler |
| Laptop | [Slurm in Docker](docs/02-slurm.md) | sbatch, job arrays, accounting |
| Laptop | [OpenStack (optional)](docs/03-openstack-optional.md) | IaaS basics |
| Grid'5000 | [Overview](docs/g5k/README.md) | — |
| Grid'5000 | [0. Reserve and set up](docs/g5k/00-setup.md) | OAR, reproducible node state |
| Grid'5000 | [1. Bare metal](docs/g5k/01-bare-metal.md) | RAPL, DVFS sweep, wattmeter cross-check |
| Grid'5000 | [2. Slurm](docs/g5k/02-slurm.md) | Slurm install, RAPL energy plugin, job arrays, multi-node |
| Grid'5000 | [3. Kubernetes (k3s)](docs/g5k/03-kubernetes.md) | k3s on bare metal (blocked, see status) |
| Grid'5000 | [4. Save and release](docs/g5k/04-save-and-release.md) | — |

## Results (Grid'5000 `gros`, Nancy, Nov 2026)
Hardware: Xeon Gold 5220 (18 cores / 36 threads, 2.2 GHz base), ResNet18,
synthetic 32×32 images, batch 32. Energy = in-process RAPL, CPU package only.

### Thread scaling under Slurm (turbo off, 4 repetitions, 300 steps)
| threads | throughput (samples/s) | std | energy per sample (J) |
|---|---|---|---|
| 1 | 162 | 2.0 | 0.254 |
| 2 | 408 | 5.9 | 0.134 |
| 3 | 580 | 18.7 | 0.106 |
| 4 | 708 | 22.4 | 0.094 |

Energy per sample drops by 2.7× from 1 to 4 threads: the package's static
power is spread over more work. Open question: going from 1 to 2 threads gives
2.5× the throughput (more than linear), consistently across repetitions; the
cause is not identified yet (a less efficient single-thread code path in
PyTorch is one hypothesis).

### Node-to-node variability (18 threads, 500 steps)
| node | 3 nodes at once (job 33) | one node at a time |
|---|---|---|
| gros-60 | 824 | 913 |
| gros-64 | 925 | **997** |
| gros-65 | **998** | 884 |

RAPL package power was ~81 W on all three. Single-run throughput varied by up
to ~12–20% across identical nodes, and the node ranking was **not stable**
between runs, so the spread is run-to-run noise rather than a property of one
node (or of the Slurm head node). Results should be reported as the median of
several repetitions with runs of 30 s or more.

### CPU frequency sweep — to be rerun
The first sweep showed flat throughput from 1.0 to 2.2 GHz, which is not
plausible for a compute-bound workload: turbo had been left on, so the
frequency caps were not effective. `scripts/g5k/freq-sweep.sh` now disables
turbo, measures the real frequency under load (`freq_check.csv`) and restores
the settings afterwards.

## Lessons learned
Measurement pitfalls met while building this lab, each now prevented by the code:

| Pitfall | Effect | Fix in the repo |
|---|---|---|
| Turbo left on during a frequency sweep | flat, meaningless curve | `freq-sweep.sh` disables turbo and checks the measured frequency |
| One node left pinned at 1 GHz after a quick test | mixed conditions within one sweep | `set-cpu-state.sh` before every experiment; CPU state saved in every JSON |
| `--exclusive` without `--ntasks=1` in a job array | ~18 concurrent copies per node, throughput halved | `--ntasks=1` + `srun -n 1` |
| Results from several submissions in one folder | wrong run counts and averages | per-job output folders |
| Aggregating every `*.json` | crash on wattmeter dumps | only `run_*.json` are read |
| Slurm version without `ConsumedJoules` | job-energy script failed | sample `CurrentWatts` + poll `sstat` |

## Limitations
- RAPL measures the CPU package only (no DRAM domain here); the wattmeter sees
  the whole node.
- Inside containers on VMs/macOS, RAPL is not readable; energy fields are `null`.
- Kepler in kind uses model-based estimates, not direct measurement.
- Synthetic data isolates compute; it does not measure data-loading I/O.
- Kubernetes on Grid'5000 (k3s) is not working yet; see its guide.

## License
MIT
