# Results — Grid'5000 `gros` (Nancy), 9 November 2026

All numbers are computed from the raw files in [`results/`](results/) and the
Slurm logs in [`logs/`](logs/). Aggregated tables and plots are in
[`analysis/`](analysis/).

## Setup

| | |
|---|---|
| Nodes | `gros` (Nancy): Intel Xeon Gold 5220, 18 cores / 36 threads, 2.2 GHz base, 3.9 GHz turbo, ~93 GB usable RAM |
| OS | Grid'5000 standard environment, Debian 13, Linux 6.12, Python 3.13, PyTorch (CPU) |
| Workload | ResNet18 training, synthetic 32×32 RGB images, batch size 32, SGD |
| Energy | Intel RAPL package domain, read in-process around the timed training loop; PDU outlet power from Kwollect; Slurm `acct_gather_energy/rapl` |
| Scheduler | 3-node Slurm cluster installed with [`scripts/g5k/setup-slurm.sh`](scripts/g5k/setup-slurm.sh) |

Throughput is in training samples per second. Energy per sample = RAPL package
energy / samples processed.

**CPU state.** Turbo was disabled on all nodes from about 15:31 UTC onwards
(sections 1 and 2, runs after that time). Earlier runs were made with the
benchmark version that did not yet record the CPU state, so their turbo setting
is not documented. The current benchmark stores driver, governor, frequency
limits and turbo in every result file.

---

## 1. Thread scaling under Slurm

Slurm job array, one task per thread count, a whole node per task
(`--exclusive --ntasks=1`), 300 training steps, 3 repetitions, turbo off.
(One extra 30-step repetition in `results/slurm-sweep/` is excluded here.)

| Threads | Throughput (samples/s) | Std | RAPL power (W) | Energy per sample (J) | Node |
|---:|---:|---:|---:|---:|---|
| 1 | 163 | 2.1 | 41.1 | 0.253 | gros-60 |
| 2 | 406 | 6.3 | 54.7 | 0.135 | gros-64 |
| 3 | 572 | 13.4 | 61.4 | 0.107 | gros-65 |
| 4 | 699 | 16.6 | 66.4 | 0.095 | gros-65 |

- From 1 to 4 threads, throughput grows **4.3×** while package power grows only
  **1.6×** (41 → 66 W), so energy per sample drops **2.7×**. A large part of the
  package power is fixed, and using more cores spreads it over more work.
- **Open question:** 1 → 2 threads gives **2.5×** the throughput, more than
  linear, with low variance across repetitions. Not explained yet. Candidates:
  a less efficient single-thread code path in PyTorch, or the 1-thread case
  losing the most from turbo being off.
- **Caveat:** Slurm placed each thread count on the same node in every
  repetition (1 thread always on gros-60, 2 on gros-64, 3–4 on gros-65), so the
  thread effect is confounded with the node. Node-to-node differences are much
  smaller than the effects above (section 2), but a cleaner design would rotate
  nodes or pin all thread counts to one node with `sbatch -w`.

Reproduce: `REPS=3 bash scripts/g5k/slurm-runs.sh threads`

---

## 2. Node-to-node variability

ResNet18, 18 threads, 500 training steps (16–19 s per run).

| Node | Multi-node job 7 | Multi-node job 33 | Alone (jobs 34–36) |
|---|---:|---:|---:|
| gros-60 (Slurm head) | 881 | 824 | 913 |
| gros-64 | 940 | 925 | **997** |
| gros-65 | **943** | **998** | 884 |

RAPL package power stayed within **80–84 W** on every node and every run.

- With the same power, throughput differs by up to **21 %** within one run
  (824 vs 998, job 33).
- The ranking is **not stable**: gros-65 was the fastest in job 33 and the
  slowest when run alone.
- gros-60, which also hosts the Slurm controller, was the slowest in both
  multi-node runs but not when run alone. With two runs, a head-node effect on
  simultaneous runs can be neither confirmed nor ruled out.
- Consequence: report medians over several repetitions of runs ≥ 30 s; a single
  run of ~17 s cannot separate nodes.

Reproduce: `REPS=5 bash scripts/g5k/slurm-runs.sh multinode` and
`bash scripts/g5k/slurm-runs.sh pernode`

---

## 3. Wattmeter vs RAPL

gros-120, 18 threads, 1000 steps (34 s), PDU outlet power from Kwollect
(`pdu_outlet_power_watt`, 1 sample/s).

| | Power |
|---|---:|
| Node, before the run (idle + Python start-up) | 69.4 W (28 samples) |
| Node, during training (steady part) | 157.3 W (31 samples) |
| **Node dynamic power** (load − idle) | **≈ 88 W** |
| **RAPL package power** (in-process) | **84.3 W** |

The extra node power under load matches RAPL package power within about **4 W
(~5 %)**. The remainder fits what RAPL package does not see (DRAM, fans, PSU
losses). Absolute node power is almost twice the RAPL value, because of the
~69 W the node draws at idle.

Single run only; the script now records a clean 30 s idle baseline
([`scripts/g5k/wattmeter-check.sh`](scripts/g5k/wattmeter-check.sh)).

---

## 4. Energy as seen by Slurm vs in-process RAPL

Same 18-thread, 500-step job ([`slurm/bench.sbatch`](slurm/bench.sbatch)),
energy summaries from `logs/energy-bench-*.out`.

| Job | Node | Slurm step energy (`sstat`) | Node power × time (`CurrentWatts`) | In-process RAPL (training loop) |
|---|---|---:|---:|---:|
| 6 | gros-60 | 2270 J | 1780 J / 20 s (89 W) | 1324 J / 16 s (83 W) |
| 8 | gros-60 | 2634 J | 2103 J / 23 s (91 W) | 1488 J / 18 s (80 W) |
| 34 | gros-60 | 2461 J | 1835 J / 22 s (83 W) | 1407 J / 18 s (80 W) |
| 35 | gros-64 | 2280 J | 1700 J / 20 s (85 W) | 1300 J / 16 s (81 W) |
| 36 | gros-65 | 2709 J | 2155 J / 23 s (94 W) | 1506 J / 18 s (83 W) |

- In-process RAPL is the smallest: it covers only the timed loop, while Slurm
  also counts Python import, model build and warm-up.
- `CurrentWatts` power (83–94 W) is close to in-process RAPL power (80–83 W).
- `sstat` step energy is **~30 % higher** than `CurrentWatts` × time over a
  similar duration. One likely reason is that Slurm's RAPL plugin also adds the
  DRAM domain, which the benchmark does not read. Not verified yet: comparing
  with `/sys/class/powercap/intel-rapl:0:0` (DRAM) would settle it.

---

## 5. CPU frequency sweep — first attempt discarded

The first sweep (1.0 → 2.2 GHz in 200 MHz steps, 3 runs each, 50 steps,
gros-120) gave flat throughput, 899–942 samples/s at every frequency. That is not
plausible for a compute-bound workload, so the frequency caps were evidently not
applied. Turbo was still on during that sweep; whether `intel_pstate` (HWP) also
ignored the caps is not known.

[`scripts/g5k/freq-sweep.sh`](scripts/g5k/freq-sweep.sh) now disables turbo,
records the measured frequency under load in `freq_check.csv` (target vs real),
offers `PASSIVE=1` to bypass HWP, and restores the settings on exit.
**Status: to be rerun.** Raw files of the discarded sweep were not kept; only
[`analysis/out-freq/`](analysis/out-freq/) remains, for the record.

---

## Lessons learned

Each pitfall below produced wrong or unusable numbers at least once while
building this lab. Each is now prevented by the code.

| Pitfall | Effect | Fix |
|---|---|---|
| Frequency caps not effective (turbo on, possibly HWP) | flat, meaningless frequency sweep | `freq-sweep.sh` disables turbo, checks real frequency under load, optional passive mode |
| CPU state not recorded | turbo setting of early runs unknown | CPU state saved in every result JSON; `set-cpu-state.sh` before experiments |
| `--exclusive` without `--ntasks=1` in a job array | ~18 concurrent copies per node, throughput roughly halved | `--ntasks=1` + `srun -n 1` |
| Results of several submissions in one folder | inflated run counts, averages over different conditions | one output folder per job ID |
| Runs of a few seconds (first bare-metal run: 1.6 s) | numbers dominated by noise | 300–1000 steps (≥ 15 s), repetitions |
| Aggregating every `*.json` | crash on wattmeter dumps | only `run_*.json` are read |
| Slurm version without `ConsumedJoules` | job-energy script failed | sample `CurrentWatts` + poll `sstat` |
| Wattmeter metric name differs per cluster | empty Kwollect query | gros exposes `pdu_outlet_power_watt`; metric is a script parameter |

The common thread: **record the full experimental state with every
measurement** (CPU settings, node, job ID), keep runs long enough, and repeat
before interpreting a difference.

## Next steps
- Rerun the frequency sweep with turbo off and check `freq_check.csv`.
- Thread sweep with all thread counts on the same node (removes the confound).
- More repetitions for node-to-node variability; test the head-node effect.
- Check whether Slurm's RAPL energy includes DRAM.
- Kubernetes on Grid'5000: k3s stayed in `activating` on gros
  ([docs/g5k/03-kubernetes.md](docs/g5k/03-kubernetes.md)).
- GPU nodes (NVML energy is already recorded by the benchmark when available).
