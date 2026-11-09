#!/bin/bash
# k3s (lightweight Kubernetes) on the reserved nodes: head = server, workers = agents.
# Run on the head node, from the repo root. Stop Slurm first if it is running:
#   onall 'sudo-g5k systemctl stop slurmd slurmctld'
#   bash scripts/g5k/setup-k3s.sh
#
# STATUS: on gros (standard environment, Nov 2026) the k3s server stayed in
# "activating" for more than 10 minutes and never registered the node. Not solved
# yet; the script waits, then prints the relevant journal lines for debugging.
set -uo pipefail
source scripts/g5k/common.sh
TIMEOUT=${TIMEOUT:-300}

echo "== Installing the k3s server on $HEAD"
curl -sfL https://get.k3s.io | sudo-g5k sh -s - --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "== Waiting up to ${TIMEOUT}s for the server node to be Ready"
READY=0
for _ in $(seq 1 $((TIMEOUT / 10))); do
  STATE=$(sudo-g5k systemctl is-active k3s || true)
  NODES=$(kubectl get nodes --no-headers 2>/dev/null | tr '\n' ' ')
  echo "  k3s=$STATE  nodes: ${NODES:-none}"
  if echo "$NODES" | grep -q " Ready"; then READY=1; break; fi
  sleep 10
done

if [ "$READY" != "1" ]; then
  echo
  echo "k3s server is not Ready. Relevant journal lines:"
  sudo-g5k journalctl -u k3s -n 200 --no-pager | grep -iE "error|fail|cgroup|fatal" | tail -20
  echo
  echo "Ideas to try: check cgroup v2 support (stat -fc %T /sys/fs/cgroup),"
  echo "free disk space in /var (df -h /var), and whether port 6443 is reachable."
  exit 1
fi

echo "== Joining the workers"
TOKEN=$(sudo-g5k cat /var/lib/rancher/k3s/server/node-token)
for n in $WORKERS; do
  $G5K_SSH "$n" "curl -sfL https://get.k3s.io | sudo-g5k env K3S_URL=https://${HEAD}:6443 K3S_TOKEN=${TOKEN} sh -"
done
sleep 20

echo "== Labelling the workers for the benchmark Job"
for n in $WORKERS; do
  kubectl label node "$(short "$n")" lab/pool=bench --overwrite
done
kubectl get nodes -o wide
echo
echo "Next: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml, then follow docs/g5k/03-kubernetes.md"
