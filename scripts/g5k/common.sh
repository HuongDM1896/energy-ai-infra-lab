# Shared helpers for the Grid'5000 scripts. Source it, do not execute it:
#   source scripts/g5k/common.sh
#
# Defines: NODES_FILE, HEAD, WORKERS, onall, short

NODES_FILE=~/lab-nodes.txt
if [ -n "${OAR_NODEFILE:-}" ]; then
  uniq "$OAR_NODEFILE" > "$NODES_FILE"
fi
if [ ! -s "$NODES_FILE" ]; then
  echo "No node list: run this inside an oarsub job (OAR_NODEFILE is not set)." >&2
  return 1 2>/dev/null || exit 1
fi

HEAD=$(head -1 "$NODES_FILE")
WORKERS=$(tail -n +2 "$NODES_FILE" | tr '\n' ' ')
export NODES_FILE HEAD WORKERS

# Run a command on every reserved node. If ssh between nodes is refused, set
# G5K_SSH=oarsh before sourcing this file.
G5K_SSH=${G5K_SSH:-ssh}
onall() {
  for n in $(cat "$NODES_FILE"); do
    echo "== $n"
    $G5K_SSH -o StrictHostKeyChecking=no "$n" "$@"
  done
}

# gros-60.nancy.grid5000.fr -> gros-60
short() { echo "$1" | cut -d. -f1; }

echo "HEAD=$HEAD  WORKERS=$WORKERS"
