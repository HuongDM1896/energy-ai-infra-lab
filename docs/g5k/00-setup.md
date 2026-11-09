# Grid'5000 — 0. Reserve nodes and set up

Tested on `gros` (Nancy, Xeon Gold 5220: 18 cores / 36 threads, 2.2 GHz base,
3.9 GHz turbo, ~93 GB usable RAM), standard environment, no kadeploy.
`sudo-g5k` gives root for the duration of the job; nodes are reinstalled afterwards.

Symbols: 💻 your laptop · 🚪 Nancy frontend · 🖥️ head node (where `oarsub -I` drops you).

## Get the repo onto Nancy
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
Your home is NFS-shared with every Nancy node, so the repo, the venv and the
results are visible on all nodes (and survive the reservation).

## Reserve
🚪 3 nodes, 2 hours, interactive:
```bash
oarsub -I -p gros -l host=3,walltime=2:00
```
Keep walltime short on weekdays 09:00–19:00; run long sweeps at night or on
weekends. Availability: https://intranet.grid5000.fr/oar/Nancy/drawgantt-svg/

## Set up (once per reservation)
🖥️
```bash
cd ~/energy-ai-infra-lab
source scripts/g5k/common.sh          # node list, $HEAD, $WORKERS, onall
bash scripts/g5k/setup-node.sh        # venv in ~/venv-lab, RAPL access, cpupower
source ~/venv-lab/bin/activate
bash scripts/g5k/set-cpu-state.sh     # same known CPU state on all nodes (turbo off)
```
`setup-node.sh` reuses the venv if it already exists, so later reservations are fast.
If `ssh` between nodes is refused: `G5K_SSH=oarsh source scripts/g5k/common.sh`.

## Before every experiment
Run `bash scripts/g5k/set-cpu-state.sh` and check the table it prints.
Every result JSON also records `turbo_enabled`, `cpu_driver`,
`cpu_min_khz`/`cpu_max_khz`, so a wrong state can be spotted afterwards.

Next: [1. Bare metal](01-bare-metal.md)
