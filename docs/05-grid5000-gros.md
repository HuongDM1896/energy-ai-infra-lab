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

### CPU frequency sweep (turbo off, frequency list detected automatically)
`gros` is a Xeon Gold 5220: 2.2 GHz base, 3.9 GHz turbo. With the `intel_pstate`
driver there is no `scaling_available_frequencies` file, so the list is built
from min to base frequency in 200 MHz steps.
```bash
rm -rf results/g5k-freq   # do not mix with earlier runs
CPUFREQ=/sys/devices/system/cpu/cpu0/cpufreq
echo "driver=$(cat $CPUFREQ/scaling_driver)"
ORIG_MIN=$(cat $CPUFREQ/scaling_min_freq); ORIG_MAX=$(cat $CPUFREQ/scaling_max_freq)

# 1) Disable turbo (intel_pstate or acpi-cpufreq)
if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
  echo 1 | sudo-g5k tee /sys/devices/system/cpu/intel_pstate/no_turbo
elif [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
  echo 0 | sudo-g5k tee /sys/devices/system/cpu/cpufreq/boost
fi

# 2) Build the frequency list (kHz): min -> base, 200 MHz steps
MIN=$(cat $CPUFREQ/cpuinfo_min_freq)
if [ -f $CPUFREQ/scaling_available_frequencies ]; then
  FREQS=$(tr ' ' '\n' < $CPUFREQ/scaling_available_frequencies | grep . | sort -n | xargs)
else
  MAX=$(cat $CPUFREQ/base_frequency 2>/dev/null || cat $CPUFREQ/cpuinfo_max_freq)
  FREQS=$(seq $MIN 200000 $MAX | xargs)
  [[ " $FREQS " == *" $MAX "* ]] || FREQS="$FREQS $MAX"
fi
echo "FREQS (kHz): $FREQS"

# 3) Sweep: 3 repetitions, frequency order shuffled each time to avoid drift
for rep in 1 2 3; do
  for F in $(echo $FREQS | tr ' ' '\n' | shuf); do
    sudo-g5k cpupower frequency-set -d ${F} -u ${F} >/dev/null
    sleep 2
    echo "rep=$rep target=$((F/1000)) MHz actual=$(awk '/MHz/{s+=$4;n++}END{printf "%.0f",s/n}' /proc/cpuinfo) MHz"
    python bench/train_bench.py --model resnet18 --steps 50 --threads 18 \
      --tag freq-$((F/1000))MHz --output-dir results/g5k-freq
  done
done

# 4) Restore the original settings
sudo-g5k cpupower frequency-set -d $ORIG_MIN -u $ORIG_MAX >/dev/null
[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ] && echo 0 | sudo-g5k tee /sys/devices/system/cpu/intel_pstate/no_turbo
python analysis/aggregate.py results/g5k-freq --out analysis/out-freq
```
If `actual` drifts far from `target` (HWP), try passive mode:
`echo passive | sudo-g5k tee /sys/devices/system/cpu/intel_pstate/status` (untested on gros).
If `cpupower` is missing: `sudo-g5k apt-get install -y linux-cpupower`.

### Cross-check with the wattmeter (Kwollect)
Compares node-level power (wattmeter) with RAPL package power over the exact
training window, using a 30 s idle baseline.
```bash
mkdir -p results/g5k-watt
N=$(hostname -s)

# Idle baseline: 30 s
T0=$(date -u +%s); sleep 30; T1=$(date -u +%s)

# Run long enough (>30 s) to get many wattmeter samples
python bench/train_bench.py --model resnet18 --steps 1000 --threads 18 \
  --tag gros-watt --output-dir results/g5k-watt
T2=$(date -u +%s)

echo "Waiting for Kwollect to ingest the data..."; sleep 90
curl -sf "https://api.grid5000.fr/stable/sites/nancy/metrics?nodes=${N}&metrics=wattmetre_power_watt&start_time=${T0}&end_time=$((T2+5))" \
  -o results/g5k-watt/kwollect_${N}.json && echo "kwollect OK"

python - "$T0" "$T1" "$N" <<'EOF'
import json, glob, sys
from datetime import datetime, timezone
t0, t1, node = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
run = json.load(open(sorted(glob.glob("results/g5k-watt/run_*.json"))[-1]))
end = datetime.fromisoformat(run["timestamp"]).timestamp()
start = end - run["elapsed_s"]

pts = []
for x in json.load(open(f"results/g5k-watt/kwollect_{node}.json")):
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
print(f"node idle power    : {idle:6.1f} W ({ni} samples)")
print(f"node load power    : {load:6.1f} W ({nl} samples)")
print(f"node dynamic power : {load - idle:6.1f} W")
print(f"RAPL package power : {rapl_w:6.1f} W")
print(f"node energy        : {load * run['elapsed_s']:.0f} J  vs  RAPL {run['cpu_energy_j'] or float('nan'):.0f} J")
EOF
```
Expect node power > RAPL: the wattmeter sees PSU losses, DRAM, fans and NIC,
while RAPL here reads the package domain only. Compare *node dynamic power*
with *RAPL package power*.

If curl returns nothing, Kwollect may not accept epoch seconds: replace
`${T0}` with `$(date -u -d @$T0 +%FT%T)` (same for the end time). If the
sample window is shifted by exactly 1 h, timestamps are being read as local time.
To list the metrics `gros` exposes:
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
NODELINE=$(slurmd -C 2>/dev/null | grep -m1 '^NodeName=' | sed "s/NodeName=[^ ]*/NodeName=${SHORTNODES}/")
[ -z "$NODELINE" ] && NODELINE="NodeName=${SHORTNODES} CPUs=$(nproc --all) RealMemory=$(( $(free -m | awk '/Mem:/{print $2}') - 2048 ))"
echo "$NODELINE"
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
source ~/venv-lab/bin/activate     # sbatch passes this env to the job
mkdir -p logs                      # sbatch opens logs/ before the script runs
sbatch --wait slurm/bench.sbatch && tail -4 $(ls -t logs/energy-bench-*.out | head -1)
sbatch slurm/sweep-threads.sbatch
squeue
```
`bench.sbatch` prints an energy summary at the end: Slurm's node counter
(`ConsumedJoules`, includes startup) vs the in-process RAPL reading (training
loop only). Explaining that gap is the point of the exercise.
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
