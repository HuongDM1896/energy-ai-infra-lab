# Step 2 — Slurm (about 1 week)

Goal: run the same benchmark under Slurm, use job arrays for a parameter sweep,
and read Slurm's energy accounting.

## Option A — local Slurm cluster in Docker (recommended to start)
Use the well-known community project `giovtorres/slurm-docker-cluster`
(check its README for the current instructions — they change):
```bash
git clone https://github.com/giovtorres/slurm-docker-cluster.git
cd slurm-docker-cluster
docker compose up -d            # slurmctld, slurmdbd, mysql, 2 compute nodes
docker exec -it slurmctld bash
sinfo                           # see partitions and nodes
```
Copy this repo into the shared `/data` volume, install Python + PyTorch (CPU)
inside the containers, then:
```bash
cd /data/energy-ai-infra-lab
sbatch slurm/bench.sbatch
squeue
sacct --format=JobID,JobName,State,Elapsed,AllocCPUS
sbatch slurm/sweep-threads.sbatch   # job array: 1,2,3,4 threads
```

## Option B — a real cluster you already have: Grid'5000
Grid'5000 uses OAR, not Slurm, but you can deploy Slurm yourself on reserved
nodes (or use any university cluster that runs Slurm). On a real node you get
**real RAPL** and can enable Slurm's energy plugin:
```
# slurm.conf
AcctGatherEnergyType=acct_gather_energy/rapl
JobAcctGatherFrequency=energy=5
```
Then `sacct -j <id> --format=JobID,Elapsed,ConsumedEnergy,AveCPUFreq`.

**Exercise:** compare `ConsumedEnergy` from Slurm with `cpu_energy_j`
from the benchmark JSON for the same job. Explain the gap (node-level vs
package-level, sampling interval). This is your thesis skill, shown in an industry tool.

## Concepts to be able to explain in an interview
- slurmctld / slurmd / slurmdbd roles
- partition, QoS, fairshare (basics)
- `sbatch` vs `srun` vs `salloc`
- job arrays, `--cpus-per-task`, `--gres=gpu:1`
- how Slurm vs Kubernetes differ (batch HPC vs long-running services; gang scheduling)

## CV line after this step
"Ran PyTorch training benchmarks under Slurm (job arrays, accounting) and validated
Slurm RAPL energy accounting against in-process measurements."
