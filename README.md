# energy-ai-infra-lab

Energy-aware benchmarking of PyTorch training jobs across **bare metal,
Kubernetes and Slurm**, with Prometheus/Grafana monitoring and Kepler / RAPL /
NVML energy measurement.

> Portfolio project: the goal is to show hands-on AI/HPC infrastructure skills
> (container orchestration, batch scheduling, observability) combined with
> rigorous energy and performance measurement.

## What it does
- `bench/train_bench.py` — trains ResNet18 / MobileNetV2 on synthetic data for a
  fixed number of steps; records throughput, CPU energy (Intel RAPL, with counter
  wrap-around handling), GPU energy (NVML) and scheduler context (Slurm / Kubernetes)
  into one JSON per run.
- `k8s/` — kind cluster config, a parallel benchmark Job, Prometheus/Grafana and
  Kepler Helm values.
- `slurm/` — single job and job-array sweep scripts.
- `analysis/aggregate.py` — merges all runs into a CSV and plots energy vs throughput.
- CI (GitHub Actions) smoke-tests the benchmark and lints the manifests on every push.

## Architecture
```
            ┌──────────── same container / script ────────────┐
 bare metal │  python bench/train_bench.py  → results/*.json   │
 Kubernetes │  Job (kind, 2 workers) ── Prometheus ◄── Kepler  │
 Slurm      │  sbatch / job array      ── sacct ConsumedEnergy │
            └──────────────────────────────────────────────────┘
                              │
                     analysis/aggregate.py → summary.csv + plot
```

## Quick start (5 minutes, no cluster)
```bash
make venv && . .venv/bin/activate
make bench
make analyze
```

## Learning path
| Step | Guide | Skill shown |
|---|---|---|
| 1 | [Kubernetes](docs/01-kubernetes.md) | kind, Jobs, resources, Helm, Prometheus/Grafana, Kepler |
| 2 | [Slurm](docs/02-slurm.md) | sbatch, job arrays, accounting, RAPL energy plugin |
| 3 | [OpenStack (optional)](docs/03-openstack-optional.md) | IaaS basics |
| 4 | [Real hardware](docs/04-real-hardware.md) | Grid'5000 RAPL/NVML results |

## Results
_TODO: add a plot from real hardware (step 4) with hardware details and number of repetitions._

## Limitations
- Inside containers on VMs/macOS, RAPL is not readable; energy fields are `null`.
- Kepler in kind uses model-based estimates, not direct measurement.
- Synthetic data isolates compute; it does not measure data-loading I/O.

## License
MIT
