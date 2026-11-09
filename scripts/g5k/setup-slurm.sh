#!/bin/bash
# Minimal Slurm cluster on the reserved nodes (head = controller + compute,
# workers = compute), with the RAPL energy plugin. No slurmdbd (no sacct history).
# Run on the head node, from the repo root:
#   bash scripts/g5k/setup-slurm.sh
set -euo pipefail
source scripts/g5k/common.sh

echo "== Installing slurm-wlm + munge on all nodes"
onall 'sudo-g5k apt-get update -qq && sudo-g5k env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq slurm-wlm munge >/dev/null'

echo "== Sharing one munge key (through the NFS home)"
sudo-g5k cp /etc/munge/munge.key ~/munge.key
sudo-g5k chmod 644 ~/munge.key
for n in $WORKERS; do
  $G5K_SSH "$n" 'sudo-g5k cp ~/munge.key /etc/munge/munge.key && sudo-g5k chown munge:munge /etc/munge/munge.key && sudo-g5k chmod 400 /etc/munge/munge.key'
done
rm -f ~/munge.key
onall 'sudo-g5k systemctl restart munge'
FIRST_WORKER=$(echo "$WORKERS" | cut -d' ' -f1)
if [ -n "$FIRST_WORKER" ]; then
  munge -n | $G5K_SSH "$FIRST_WORKER" unmunge | grep STATUS   # expect: Success
fi

echo "== Generating slurm.conf"
SHORTNODES=$(cut -d. -f1 "$NODES_FILE" | paste -sd,)
# slurmd -C can print nothing on recent Debian; fall back to nproc/free
NODELINE=$(slurmd -C 2>/dev/null | grep -m1 '^NodeName=' | sed "s/NodeName=[^ ]*/NodeName=${SHORTNODES}/" || true)
if [ -z "$NODELINE" ]; then
  NODELINE="NodeName=${SHORTNODES} CPUs=$(nproc --all) RealMemory=$(( $(free -m | awk '/Mem:/{print $2}') - 2048 ))"
fi
echo "$NODELINE"

cat > ~/slurm.conf <<EOF
ClusterName=g5klab
SlurmctldHost=$(short "$HEAD")
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

echo "== Installing the config and starting the daemons"
onall 'sudo-g5k mkdir -p /var/spool/slurmctld /var/spool/slurmd && sudo-g5k chown slurm:slurm /var/spool/slurmctld && sudo-g5k cp ~/slurm.conf /etc/slurm/slurm.conf'
onall 'sudo-g5k chmod a+r /sys/class/powercap/intel-rapl:*/energy_uj'
sudo-g5k systemctl restart slurmctld
onall 'sudo-g5k systemctl restart slurmd'
sleep 5
sinfo
scontrol show node "$(short "$HEAD")" | grep -iE "watts" || true
echo
echo "All nodes should be 'idle'. If 'down':  sudo-g5k scontrol update nodename=ALL state=resume"
echo "If anything failed:  sudo-g5k journalctl -u slurmctld -n 30 --no-pager"
