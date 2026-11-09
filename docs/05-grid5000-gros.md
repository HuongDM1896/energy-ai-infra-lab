# Grid'5000 `gros` (Nancy) — copy-paste guide

Everything below runs in the **standard environment** (no kadeploy).
`sudo-g5k` gives you root on the nodes for the duration of the job; nodes are
reinstalled after the job, so nothing you break survives.

Layout used here: **3 nodes** — node 1 = head (Slurm controller / k3s server),
nodes 2–3 = workers. Commands are grouped by *where* to run them:

- 💻 your laptop
- 🚪 Nancy frontend (`fnancy`)
- 🖥️ head node (the node `oarsub -I` drops you on)

> Not tested end-to-end by the author of this file. If a step fails, keep the
> error output — most fixes are one line.

---

## Part 0 — Get the repo onto Nancy (once)

💻
```bash
scp energy-ai-infra-lab.zip nancy.g5k:
ssh nancy.g5k
```
🚪
```bash
unzip -o energy-ai-infra-lab.zip
cd ~/energy-ai-infra-lab
```
Your home directory is NFS-shared with every Nancy node, so the repo is
visible everywhere.

---

## Part 1 — Reserve nodes

🚪 Interactive, 3 `gros` nodes, 2 hours:
```bash
oarsub -I -p gros -l host=3,walltime=2:00
```
Respect the usage policy: keep walltime short on weekdays 09:00–19:00, and
use nights/weekends for long sweeps. If `gros` is busy, check
https://intranet.grid5000.fr/oar/Nancy/drawgantt-svg/

🖥️ Save the node list (reused by every later step):
```bash
uniq $OAR_NODEFILE > ~/lab-nodes.txt
export HEAD=$(head -1 ~/lab-nodes.txt)
export WORKERS=$(tail -n +2 ~/lab-nodes.txt | tr '\n' ' ')
echo "HEAD=$HEAD  WORKERS=$WORKERS"
```
Helper to run a command on all nodes (used a lot below):
```bash
onall() { for n in $(cat ~/lab-nodes.txt); do echo "== $n"; ssh -o StrictHostKeyChecking=no $n "$@"; done; }
onall hostname
```
If `ssh` between nodes is refused, replace `ssh` with `oarsh` in `onall`.

---

## Part 2 — Bare-metal benchmark with real RAPL

🖥️ Python environment (in home, so all nodes share it):
```bash
cd ~/energy-ai-infra-lab
python3 -m venv ~/venv-lab
source ~/venv-lab/bin/activate
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu \
  || pip install torch torchvision
pip install pandas matplotlib
```
Allow reading RAPL counters on all nodes:
```bash
onall 'sudo-g5k chmod a+r /sys/class/powercap/intel-rapl:*/energy_uj'
```
Single run:
```bash
python bench/train_bench.py --model resnet18 --steps 50 --threads 18 \
  --tag gros-bare --output-dir results/g5k
```
`cpu_energy_j` should now be a number, not `null`.

### CPU frequency sweep (your thesis skill, shown in a portfolio)
```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null \
  || cpupower frequency-info | grep -i "hardware limits"
```
```bash
for F in 1000000 1400000 1800000 2200000; do
  sudo-g5k cpupower frequency-set -d ${F} -u ${F} >/dev/null
  for rep in 1 2 3; do
    python bench/train_bench.py --model resnet18 --steps 50 --threads 18 \
      --tag freq-$((F/1000))MHz --output-dir results/g5k-freq
  done
done
sudo-g5k cpupower frequency-set -d 1000000 -u 3900000 >/dev/null   # reset
python analysis/aggregate.py results/g5k-freq --out analysis/out-freq
```
Frequency values are in kHz; adjust them to what the first command prints.
If `cpupower` is missing: `sudo-g5k apt-get install -y linux-cpupower`.

### Cross-check with the wattmeter (Kwollect)
```bash
START=$(date -u +%Y-%m-%dT%H:%M:%S)
python bench/train_bench.py --model resnet18 --steps 200 --threads 18 --tag gros-watt --output-dir results/g5k-watt
END=$(date -u +%Y-%m-%dT%H:%M:%S)
N=$(hostname -s)
curl -s "https://api.grid5000.fr/stable/sites/nancy/metrics?nodes=${N}&metrics=wattmetre_power_watt&start_time=${START}&end_time=${END}" \
  -o results/g5k-watt/kwollect_${N}.json
python - <<'EOF'
import json, glob
d = json.load(open(glob.glob("results/g5k-watt/kwollect_*.json")[0]))
vals = [x["value"] for x in d]
print(f"{len(vals)} samples, mean {sum(vals)/max(len(vals),1):.1f} W")
EOF
```
If the metric list is empty, check which metrics `gros` exposes:
`curl -s https://api.grid5000.fr/stable/sites/nancy/clusters/gros/nodes/${N} | grep -i watt`

---

## Part 3 — Slurm on the 3 nodes

🖥️ Install on all nodes:
```bash
onall 'sudo-g5k apt-get update -qq && sudo-g5k DEBIAN_FRONTEND=noninteractive apt-get install -y -qq slurm-wlm munge'
```
Share one munge key (via your NFS home):
```bash
sudo-g5k cp /etc/munge/munge.key ~/munge.key && sudo-g5k chmod 644 ~/munge.key
for n in $WORKERS; do
  ssh $n 'sudo-g5k cp ~/munge.key /etc/munge/munge.key && sudo-g5k chown munge:munge /etc/munge/munge.key && sudo-g5k chmod 400 /etc/munge/munge.key'
done
onall 'sudo-g5k systemctl restart munge'
rm ~/munge.key
munge -n | ssh $(echo $WORKERS | cut -d" " -f1) unmunge | grep STATUS   # expect: Success
```
Generate `slurm.conf` (CPU/memory line comes from `slurmd -C` on this node):
```bash
SHORTNODES=$(cut -d. -f1 ~/lab-nodes.txt | paste -sd,)
NODELINE=$(slurmd -C | head -1 | sed "s/NodeName=[^ ]*/NodeName=${SHORTNODES}/")
cat > ~/slurm.conf <<EOF
ClusterName=g5klab
SlurmctldHost=$(echo $HEAD | cut -d. -f1)
AuthType=auth/munge
ProctrackType=proctrack/linuxproc
TaskPlugin=task/none
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core
SlurmUser=slurm
StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
ReturnToService=2
JobAcctGatherType=jobacct_gather/linux
AcctGatherEnergyType=acct_gather_energy/rapl
AcctGatherNodeFreq=5
JobAcctGatherFrequency=energy=5
${NODELINE} State=UNKNOWN
PartitionName=main Nodes=ALL Default=YES MaxTime=INFINITE State=UP
EOF
cat ~/slurm.conf | tail -3
```
Install the config and start the daemons:
```bash
onall 'sudo-g5k mkdir -p /var/spool/slurmctld /var/spool/slurmd && sudo-g5k chown slurm:slurm /var/spool/slurmctld && sudo-g5k cp ~/slurm.conf /etc/slurm/slurm.conf'
sudo-g5k systemctl restart slurmctld
onall 'sudo-g5k systemctl restart slurmd'
sleep 5; sinfo
```
All 3 nodes should show `idle`. If they show `down`: `sudo-g5k scontrol update nodename=ALL state=resume`.

Run the repo's jobs:
```bash
cd ~/energy-ai-infra-lab
sed -i 's|^srun python|srun ~/venv-lab/bin/python|' slurm/bench.sbatch slurm/sweep-threads.sbatch
sbatch slurm/bench.sbatch
sbatch slurm/sweep-threads.sbatch
squeue
```
Energy as seen by Slurm (no database needed for these two):
```bash
scontrol show node $(echo $HEAD | cut -d. -f1) | grep -iE "watts|joules"
# while a job is running:
sstat -j <JOBID>.0 --format=JobID,AveCPUFreq,ConsumedEnergy
```
Note: `sacct` history needs `slurmdbd` + MariaDB, which this minimal setup
skips. `sstat` and `scontrol` are enough for the RAPL-vs-Slurm comparison exercise.

---

## Part 4 — Kubernetes (k3s) on the same 3 nodes

Start from a fresh reservation (Part 1) or stop Slurm first:
`onall 'sudo-g5k systemctl stop slurmd slurmctld'`.

🖥️ Server on the head node:
```bash
curl -sfL https://get.k3s.io | sudo-g5k sh -s - --write-kubeconfig-mode 644
sudo-g5k cat /var/lib/rancher/k3s/server/node-token > ~/k3s-token
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```
Join the workers:
```bash
for n in $WORKERS; do
  ssh $n "curl -sfL https://get.k3s.io | sudo-g5k env K3S_URL=https://${HEAD}:6443 K3S_TOKEN=$(cat ~/k3s-token) sh -"
done
sleep 20; kubectl get nodes -o wide
rm ~/k3s-token
```
Label the workers for the benchmark Job:
```bash
for n in $WORKERS; do kubectl label node $(echo $n | cut -d. -f1) lab/pool=bench --overwrite; done
```
Build the image with Docker and import it into k3s on every node:
```bash
g5k-setup-docker -t
cd ~/energy-ai-infra-lab
docker build -t energy-bench:0.1 bench/
docker save energy-bench:0.1 -o ~/energy-bench.tar
onall 'sudo-g5k k3s ctr images import ~/energy-bench.tar'
```
Run the Job — pods read **real RAPL** here, unlike on kind:
```bash
kubectl apply -f k8s/bench-job.yaml
kubectl get pods -l app=energy-bench -o wide -w     # Ctrl-C when all Completed
kubectl logs -l app=energy-bench --tail=5 | grep -E "cpu_energy|saved"
```
Collect results from the workers:
```bash
mkdir -p results/k8s
for n in $WORKERS; do scp -q $n:/tmp/energy-bench-results/*.json results/k8s/ ; done
python analysis/aggregate.py results --out analysis/out
```
Monitoring + Kepler (Helm):
```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -- --no-sudo 2>/dev/null \
  || (curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o ~/get_helm.sh && HELM_INSTALL_DIR=~/bin USE_SUDO=false bash ~/get_helm.sh)
export PATH=~/bin:$PATH
make monitoring
make kepler
kubectl -n monitoring get pods; kubectl -n kepler get pods
```
Open Grafana from your laptop through an SSH tunnel:

🖥️
```bash
kubectl -n monitoring port-forward --address 0.0.0.0 svc/monitoring-grafana 3000:80
```
💻 (new terminal; replace `gros-XX` with your `$HEAD`)
```bash
ssh -L 3000:gros-XX.nancy.grid5000.fr:3000 nancy.g5k
# then open http://localhost:3000  — user admin / password lab-admin
```

---

## Part 5 — Save and release

🖥️
```bash
cd ~/energy-ai-infra-lab
tar czf ~/results-$(date +%F).tgz results analysis/out*
exit            # leaves the interactive job
```
🚪 Make sure nothing is left running:
```bash
oarstat -u
oardel <JOBID>  # only if something is still listed
```
💻 Copy results home:
```bash
scp nancy.g5k:results-*.tgz .
```
