# Grid'5000 — 1. Bare metal: RAPL, frequency sweep, wattmeter

Prerequisite: [0. Setup](00-setup.md) (venv activated, RAPL readable).

## Single run
```bash
python bench/train_bench.py --model resnet18 --steps 300 --threads 18 \
  --tag gros-bare --output-dir results/g5k
```
`cpu_energy_j` must be a number. `null` means RAPL is not readable: rerun
`onall 'sudo-g5k chmod a+r /sys/class/powercap/intel-rapl:*/energy_uj'`.

## CPU frequency sweep
```bash
bash scripts/g5k/freq-sweep.sh                    # 3 reps, 300 steps, 200 MHz steps
REPS=5 STEPS=500 bash scripts/g5k/freq-sweep.sh   # longer, more robust
```
What the script does:
1. disables turbo (on gros, 3.9 GHz is turbo; base is 2.2 GHz);
2. builds the frequency list automatically from min to base frequency
   (`intel_pstate` has no `scaling_available_frequencies` file);
3. shuffles the frequency order in every repetition;
4. measures the real frequency **while the benchmark runs** and writes
   `freq_check.csv` (target vs measured);
5. restores the original CPU settings when it exits, even after Ctrl-C.

**Check `freq_check.csv` first.** If the measured frequency does not follow
the target, the cap was ignored (HWP): rerun with `PASSIVE=1`, which switches
`intel_pstate` to passive mode (`intel_cpufreq` driver).

Sanity check on the results: ResNet18 on CPU is compute-bound, so throughput at
1 GHz should be clearly lower than at 2.2 GHz. A flat throughput curve means
the frequency was not applied (this happened in the first attempt, run with
turbo still on).

## Cross-check with the wattmeter (Kwollect)
```bash
bash scripts/g5k/wattmeter-check.sh
STEPS=2000 bash scripts/g5k/wattmeter-check.sh     # longer window, more samples
```
It takes a 30 s idle baseline, runs the benchmark, waits 90 s for Kwollect to
ingest the samples, then compares over the exact training window:

| line | meaning |
|---|---|
| node idle / load power | wattmeter, whole node |
| node dynamic power | load − idle |
| RAPL package power | in-process RAPL, CPU package only |

Expect node power > RAPL: the wattmeter also sees PSU losses, DRAM, fans and
NIC. Compare *node dynamic power* with *RAPL package power*.
The summary is saved as `wattmeter_summary.json` next to the raw Kwollect data.

If the query returns nothing, the script retries with ISO timestamps. To list
the metrics a node exposes:
`curl -s https://api.grid5000.fr/stable/sites/nancy/clusters/gros/nodes/$(hostname -s) | grep -i watt`

Next: [2. Slurm](02-slurm.md)
