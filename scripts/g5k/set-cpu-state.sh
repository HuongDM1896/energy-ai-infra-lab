#!/bin/bash
# Put every reserved node in the same, known CPU state before an experiment,
# then print it so it can be checked (and pasted into the results notes).
#
#   bash scripts/g5k/set-cpu-state.sh            # turbo off, full range up to base freq
#   TURBO=on bash scripts/g5k/set-cpu-state.sh   # turbo on, full hardware range
#
# Lesson from the first runs: a frequency sweep with turbo left on, and a node
# left pinned at 1 GHz after a quick test, both silently corrupted results.
set -euo pipefail
source scripts/g5k/common.sh

TURBO=${TURBO:-off}
if [ "$TURBO" = "off" ]; then
  onall 'C=/sys/devices/system/cpu; F=$C/cpu0/cpufreq;
    [ -f $C/intel_pstate/no_turbo ] && echo 1 | sudo-g5k tee $C/intel_pstate/no_turbo >/dev/null;
    [ -f $C/cpufreq/boost ] && echo 0 | sudo-g5k tee $C/cpufreq/boost >/dev/null;
    MAX=$(cat $F/base_frequency 2>/dev/null || cat $F/cpuinfo_max_freq);
    sudo-g5k cpupower frequency-set -d $(cat $F/cpuinfo_min_freq) -u $MAX >/dev/null'
else
  onall 'C=/sys/devices/system/cpu; F=$C/cpu0/cpufreq;
    [ -f $C/intel_pstate/no_turbo ] && echo 0 | sudo-g5k tee $C/intel_pstate/no_turbo >/dev/null;
    [ -f $C/cpufreq/boost ] && echo 1 | sudo-g5k tee $C/cpufreq/boost >/dev/null;
    sudo-g5k cpupower frequency-set -d $(cat $F/cpuinfo_min_freq) -u $(cat $F/cpuinfo_max_freq) >/dev/null'
fi

echo
echo "node | driver | governor | min-max kHz | no_turbo"
onall 'F=/sys/devices/system/cpu/cpu0/cpufreq;
  echo "$(hostname -s) | $(cat $F/scaling_driver) | $(cat $F/scaling_governor) | $(cat $F/scaling_min_freq)-$(cat $F/scaling_max_freq) | $(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo n/a)"' \
  | grep -v '^=='
