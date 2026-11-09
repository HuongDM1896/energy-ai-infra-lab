#!/bin/bash
# Cross-check node-level power (Kwollect wattmeter) with RAPL package power over
# the exact training window, with a 30 s idle baseline. Run on any reserved node.
#
# Usage (from the repo root, venv activated):
#   bash scripts/g5k/wattmeter-check.sh
#   STEPS=2000 SITE=nancy METRIC=wattmetre_power_watt bash scripts/g5k/wattmeter-check.sh
set -euo pipefail

STEPS=${STEPS:-1000}
SITE=${SITE:-nancy}
METRIC=${METRIC:-wattmetre_power_watt}
WAIT=${WAIT:-90}           # Kwollect ingestion delay before querying
OUT=results/g5k-watt/$(date +%Y%m%d-%H%M%S)
N=$(hostname -s)
mkdir -p "$OUT"

echo "Idle baseline (30 s)..."
T0=$(date -u +%s); sleep 30; T1=$(date -u +%s)

python bench/train_bench.py --model resnet18 --steps "$STEPS" --threads "$(nproc --all)" \
  --tag gros-watt --output-dir "$OUT" >/dev/null
T2=$(date -u +%s)

echo "Waiting ${WAIT} s for Kwollect to ingest the data..."; sleep "$WAIT"
URL="https://api.grid5000.fr/stable/sites/${SITE}/metrics?nodes=${N}&metrics=${METRIC}"
if ! curl -sf "${URL}&start_time=${T0}&end_time=$((T2 + 5))" -o "$OUT/kwollect_${N}.json" \
   || [ "$(head -c 2 "$OUT/kwollect_${N}.json")" = "[]" ]; then
  echo "Epoch query failed or empty, retrying with ISO timestamps..."
  curl -sf "${URL}&start_time=$(date -u -d @$T0 +%FT%T)&end_time=$(date -u -d @$((T2 + 5)) +%FT%T)" \
    -o "$OUT/kwollect_${N}.json"
fi

python - "$T0" "$T1" "$N" "$OUT" <<'EOF'
import json, glob, sys
from datetime import datetime, timezone
t0, t1, node, out = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4]
run = json.load(open(sorted(glob.glob(f"{out}/run_*.json"))[-1]))
end = datetime.fromisoformat(run["timestamp"]).timestamp()
start = end - run["elapsed_s"]

pts = []
for x in json.load(open(f"{out}/kwollect_{node}.json")):
    ts = datetime.fromisoformat(x["timestamp"].replace("Z", "+00:00"))
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    pts.append((ts.timestamp(), x["value"]))
pts.sort()
if not pts:
    sys.exit("No wattmeter samples: check the metric name / time window / wait longer")
fmt = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%H:%M:%S")
print(f"wattmeter: {len(pts)} samples, {fmt(pts[0][0])} -> {fmt(pts[-1][0])} UTC")
print(f"RAPL window: {fmt(start)} -> {fmt(end)} UTC")

def mean(a, b):
    v = [p for t, p in pts if a <= t <= b]
    return (sum(v) / len(v), len(v)) if v else (float("nan"), 0)

idle, ni = mean(t0, t1)
load, nl = mean(start, end)
rapl_w = run["cpu_energy_j"] / run["elapsed_s"] if run["cpu_energy_j"] else float("nan")
summary = {
    "node": node, "idle_w": idle, "load_w": load, "dynamic_w": load - idle,
    "rapl_package_w": rapl_w, "elapsed_s": run["elapsed_s"],
    "node_energy_j": load * run["elapsed_s"], "rapl_energy_j": run["cpu_energy_j"],
}
json.dump(summary, open(f"{out}/wattmeter_summary.json", "w"), indent=2)
print(f"node idle power    : {idle:6.1f} W ({ni} samples)")
print(f"node load power    : {load:6.1f} W ({nl} samples)")
print(f"node dynamic power : {load - idle:6.1f} W")
print(f"RAPL package power : {rapl_w:6.1f} W")
print(f"node energy        : {summary['node_energy_j']:.0f} J  vs  RAPL {run['cpu_energy_j'] or float('nan'):.0f} J")
EOF
echo "If the sample window is shifted by exactly 1 h, timestamps are read as local time."
