#!/bin/bash
# Package results, logs and analysis outputs before the reservation ends.
# Run on the head node, from the repo root:
#   bash scripts/g5k/collect-results.sh
# Then on your laptop:
#   scp nancy.g5k:results-*.tgz .
set -euo pipefail
NAME=~/results-$(date +%F-%H%M).tgz
tar czf "$NAME" results logs analysis/out* 2>/dev/null || tar czf "$NAME" results
echo "Saved $NAME"
echo "On your laptop:  scp nancy.g5k:$(basename "$NAME") ."
