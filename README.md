# energy-ai-infra-lab

Energy-aware benchmarking of PyTorch training jobs on **bare metal, Slurm and
Kubernetes**, measured with RAPL, NVML and node power meters on real
[Grid'5000](https://www.grid5000.fr) nodes.

> Portfolio project: AI/HPC infrastructure skills (batch scheduling, container
> orchestration, observability) combined with careful energy and performance
> measurement.

**→ Results and lessons learned: [RESULTS.md](RESULTS.md)**

## Key findings (Xeon Gold 5220, ResNet18 on CPU)
- **1 → 4 threads: 4.3× throughput for 1.6× power**, so energy per sample drops 2.7×.
- **Node power meter vs RAPL:** the node's extra power under load (≈ 88 W) matches
  RAPL package power (84 W) within ~5 %; idle (~69 W) doubles the absolute node figure.
- **Identical nodes, same power, up to 21 % throughput difference** in one run,
  with an unstable ranking across runs: single short runs cannot compare nodes.
- Eight measurement pitfalls (ineffective frequency caps, unrecorded CPU state,
  Slurm task packing, …) were hit and are now prevented by the scripts.
  See [RESULTS.md § Lessons learned](RESULTS.md#lessons-learned).

## What is in the repo
| Path | Content |
|---|---|
| [`bench/train_bench.py`](bench/train_bench.py) | Benchmark: trains ResNet18 / MobileNetV2 on synthetic data; records throughput, RAPL CPU energy (with counter wrap-around), NVML GPU energy, scheduler context and CPU state into one JSON per run |
| [`slurm/`](slurm/) | Single job with an energy summary, thread-scaling job array, multi-node job |
| [`scripts/g5k/`](scripts/g5k/) | One script per step on Grid'5000: node setup, CPU state, frequency sweep, wattmeter cross-check, Slurm install and runs, k3s install, result collection |
| [`k8s/`](k8s/) | kind cluster config, benchmark Job, Prometheus/Grafana and Kepler Helm values |
| [`analysis/`](analysis/) | `aggregate.py` (merges `run_*.json` into a CSV and a plot) and its outputs |
| [`results/`](results/), [`logs/`](logs/) | Raw results and Slurm logs from Grid'5000 |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Smoke-tests the benchmark and lints the manifests on every push |

## Quick start (laptop, no cluster)
```bash
make venv && . .venv/bin/activate
make bench
make analyze
```

## Guides
| Where | Guide | Status |
|---|---|---|
| Grid'5000 | [Overview](docs/g5k/README.md) · [0. Setup](docs/g5k/00-setup.md) · [1. Bare metal](docs/g5k/01-bare-metal.md) · [2. Slurm](docs/g5k/02-slurm.md) · [3. Kubernetes](docs/g5k/03-kubernetes.md) · [4. Save](docs/g5k/04-save-and-release.md) | Slurm, RAPL and wattmeter tested; frequency sweep to rerun; k3s blocked |
| Laptop | [Kubernetes with kind](docs/01-kubernetes.md) | — |
| Laptop | [Slurm in Docker](docs/02-slurm.md) | — |
| Laptop | [OpenStack (optional)](docs/03-openstack-optional.md) | — |

## Limitations
- RAPL here measures the CPU package only (no DRAM domain); power meters see the whole node.
- Inside containers on VMs/macOS, RAPL is not readable and energy fields are `null`.
- Kepler in kind uses model-based estimates, not direct measurement.
- Synthetic data isolates compute; data-loading I/O is not measured.

## License
MIT — see [LICENSE](LICENSE).
