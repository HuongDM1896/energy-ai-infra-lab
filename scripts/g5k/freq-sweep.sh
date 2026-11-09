#!/bin/bash
# CPU frequency sweep on the current node, turbo disabled.
# The frequency list is built automatically: min -> base frequency, STEP_KHZ steps
# (intel_pstate exposes no scaling_available_frequencies file).
#
# Usage (from the repo root, venv activated):
#   bash scripts/g5k/freq-sweep.sh
#   REPS=5 STEPS=500 PASSIVE=1 bash scripts/g5k/freq-sweep.sh
#
#   REPS      repetitions per frequency (default 3); order is shuffled each repetition
#   STEPS     training steps per run (default 300, aim for runs of 30 s or more)
#   STEP_KHZ  frequency step in kHz (default 200000 = 200 MHz)
#   PASSIVE   1 = switch intel_pstate to passive mode first (use it if the
#             measured frequency does not follow the target)
#
# Writes results/g5k-freq/<timestamp>/run_*.json and freq_check.csv
# (target vs measured frequency under load). Restores the CPU settings on exit.
set -euo pipefail

REPS=${REPS:-3}
STEPS=${STEPS:-300}
STEP_KHZ=${STEP_KHZ:-200000}
PASSIVE=${PASSIVE:-0}
THREADS=${THREADS:-$(nproc --all)}
OUT=results/g5k-freq/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

CPU=/sys/devices/system/cpu
CPUFREQ=$CPU/cpu0/cpufreq
ORIG_MIN=$(cat $CPUFREQ/scaling_min_freq)
ORIG_MAX=$(cat $CPUFREQ/scaling_max_freq)
ORIG_TURBO_FILE=""
ORIG_TURBO=""
ORIG_STATUS=$(cat $CPU/intel_pstate/status 2>/dev/null || true)

restore() {
  echo "Restoring CPU settings..."
  if [ -n "$ORIG_STATUS" ] && [ "$PASSIVE" = "1" ]; then
    echo "$ORIG_STATUS" | sudo-g5k tee $CPU/intel_pstate/status >/dev/null || true
  fi
  sudo-g5k cpupower frequency-set -d "$ORIG_MIN" -u "$ORIG_MAX" >/dev/null || true
  if [ -n "$ORIG_TURBO_FILE" ]; then
    echo "$ORIG_TURBO" | sudo-g5k tee "$ORIG_TURBO_FILE" >/dev/null || true
  fi
}
trap restore EXIT

# 0) Optional: passive mode, so fixed frequencies are honored (no HWP)
if [ "$PASSIVE" = "1" ] && [ -f $CPU/intel_pstate/status ]; then
  echo passive | sudo-g5k tee $CPU/intel_pstate/status >/dev/null
fi
echo "driver=$(cat $CPUFREQ/scaling_driver)  governor=$(cat $CPUFREQ/scaling_governor)"

# 1) Disable turbo
if [ -f $CPU/intel_pstate/no_turbo ]; then
  ORIG_TURBO_FILE=$CPU/intel_pstate/no_turbo; ORIG_TURBO=$(cat $ORIG_TURBO_FILE)
  echo 1 | sudo-g5k tee $ORIG_TURBO_FILE >/dev/null
elif [ -f $CPU/cpufreq/boost ]; then
  ORIG_TURBO_FILE=$CPU/cpufreq/boost; ORIG_TURBO=$(cat $ORIG_TURBO_FILE)
  echo 0 | sudo-g5k tee $ORIG_TURBO_FILE >/dev/null
fi
echo "turbo disabled"

# 2) Frequency list (kHz)
MIN=$(cat $CPUFREQ/cpuinfo_min_freq)
if [ -f $CPUFREQ/scaling_available_frequencies ]; then
  FREQS=$(tr ' ' '\n' < $CPUFREQ/scaling_available_frequencies | grep . | sort -n | xargs)
else
  MAX=$(cat $CPUFREQ/base_frequency 2>/dev/null || cat $CPUFREQ/cpuinfo_max_freq)
  FREQS=$(seq "$MIN" "$STEP_KHZ" "$MAX" | xargs)
  [[ " $FREQS " == *" $MAX "* ]] || FREQS="$FREQS $MAX"
fi
echo "FREQS (kHz): $FREQS"
echo "rep,target_mhz,measured_mhz_under_load" > "$OUT/freq_check.csv"

avg_mhz() { awk '/MHz/{s+=$4;n++}END{printf "%.0f",s/n}' /proc/cpuinfo; }

# 3) Sweep: frequency order shuffled in each repetition to spread drift
for rep in $(seq 1 "$REPS"); do
  for F in $(echo $FREQS | tr ' ' '\n' | shuf); do
    sudo-g5k cpupower frequency-set -d "$F" -u "$F" >/dev/null
    sleep 2
    python bench/train_bench.py --model resnet18 --steps "$STEPS" --threads "$THREADS" \
      --tag "freq-$((F/1000))MHz" --output-dir "$OUT" >/dev/null &
    PID=$!
    sleep 8                                   # measure while the benchmark runs
    MEASURED=$(avg_mhz)
    wait "$PID"
    echo "rep=$rep target=$((F/1000)) MHz measured=${MEASURED} MHz"
    echo "$rep,$((F/1000)),$MEASURED" >> "$OUT/freq_check.csv"
  done
done

python analysis/aggregate.py "$OUT" --out "$OUT/analysis"
echo "Check $OUT/freq_check.csv: measured must follow target, otherwise rerun with PASSIVE=1."
