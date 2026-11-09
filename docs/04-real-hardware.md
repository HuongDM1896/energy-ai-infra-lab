# Step 4 — Real hardware results (your differentiator)

Laptop clusters prove you know the tools. Real-node results prove you can measure.

On Grid'5000 (or any bare-metal Linux box with RAPL readable):
```bash
sudo chmod a+r /sys/class/powercap/intel-rapl:*/energy_uj   # if permitted
python bench/train_bench.py --model resnet18 --steps 50 --tag bare-g5k --output-dir results/g5k
```
On a GPU node (NVML energy is recorded automatically if `pynvml` is installed):
```bash
python bench/train_bench.py --device cuda --model resnet18 --batch-size 128 --tag gpu --output-dir results/g5k-gpu
```
Ideas for a results section in the README (pick one, keep it small):
- CPU frequency sweep (you already know cpufreq): energy per sample vs frequency
- GPU power cap sweep with `nvidia-smi -pl`: throughput vs energy
- Same job on bare metal vs Kubernetes vs Slurm: scheduling overhead

Put the final plot in `docs/img/` and embed it in the top-level README.
Report the hardware, software versions, and number of repetitions — reproducibility
is exactly what you know how to do.
