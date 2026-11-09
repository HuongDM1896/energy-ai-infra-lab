# Grid'5000 — 3. Kubernetes (k3s) on the reserved nodes

> **Status: blocked.** On gros (standard environment, Nov 2026) the k3s server
> stayed in `activating` for more than 10 minutes and never registered the node.
> The API answered (`No resources found`) but the node never became `Ready`.
> Root cause not found yet. Until it is, use the local kind cluster
> ([../01-kubernetes.md](../01-kubernetes.md)) for the Kubernetes part.

## Install (server + workers)
Stop Slurm first if it ran in the same reservation:
```bash
onall 'sudo-g5k systemctl stop slurmd slurmctld'
bash scripts/g5k/setup-k3s.sh
```
The script waits up to 5 minutes (`TIMEOUT=600 bash ...` for longer). If the
node is not `Ready`, it prints the relevant `journalctl` lines and stops.

### Debugging the "activating" state (next session)
```bash
sudo-g5k journalctl -u k3s -n 200 --no-pager | grep -iE "error|fail|cgroup|fatal" | tail -20
stat -fc %T /sys/fs/cgroup        # cgroup2fs expected
df -h /var /tmp                   # k3s needs a few GB
sudo-g5k ss -ltnp | grep 6443
```
Things worth trying, one at a time:
- a fresh reservation (Slurm installed earlier on the same nodes may interfere);
- `kadeploy` a minimal Debian image instead of the standard environment
  (`oarsub -t deploy ...`), which gives a clean, fully owned OS;
- an older k3s release: `curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=v1.33 sudo-g5k sh -s - --write-kubeconfig-mode 644`.

## Once the nodes are Ready
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes -o wide
```
Build the image and load it into k3s on every node:
```bash
g5k-setup-docker -t
docker build -t energy-bench:0.1 bench/
docker save energy-bench:0.1 -o ~/energy-bench.tar
onall 'sudo-g5k k3s ctr images import ~/energy-bench.tar'
```
Run the benchmark Job (pods read real RAPL here, unlike kind):
```bash
kubectl apply -f k8s/bench-job.yaml
kubectl get pods -l app=energy-bench -o wide -w      # Ctrl-C when all Completed
mkdir -p results/k8s
for n in $WORKERS; do scp -q $n:/tmp/energy-bench-results/*.json results/k8s/; done
python analysis/aggregate.py results/k8s --out analysis/out-k8s
```
Monitoring + Kepler:
```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o ~/get_helm.sh
HELM_INSTALL_DIR=~/bin USE_SUDO=false bash ~/get_helm.sh && export PATH=~/bin:$PATH
make monitoring
make kepler
kubectl -n monitoring port-forward --address 0.0.0.0 svc/monitoring-grafana 3000:80
```
💻 then `ssh -L 3000:<head>.nancy.grid5000.fr:3000 nancy.g5k` and open
http://localhost:3000 (admin / lab-admin).

Next: [4. Save and release](04-save-and-release.md)
