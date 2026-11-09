#!/bin/bash
# Python venv (shared through the NFS home) + RAPL read access on all nodes.
# Run on the head node, from the repo root:
#   bash scripts/g5k/setup-node.sh
set -euo pipefail
source scripts/g5k/common.sh

VENV=${VENV:-$HOME/venv-lab}
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet torch torchvision --index-url https://download.pytorch.org/whl/cpu \
  || "$VENV/bin/pip" install --quiet torch torchvision
"$VENV/bin/pip" install --quiet pandas matplotlib pynvml

# RAPL counters are root-only by default
onall 'sudo-g5k chmod a+r /sys/class/powercap/intel-rapl:*/energy_uj'
# cpupower is needed for the frequency sweep
onall 'command -v cpupower >/dev/null || sudo-g5k apt-get install -y -qq linux-cpupower >/dev/null'

echo
echo "Done. Activate with:  source $VENV/bin/activate"
