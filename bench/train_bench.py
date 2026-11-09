#!/usr/bin/env python3
"""Energy-aware training benchmark.

Trains a small CNN (ResNet18 by default) on synthetic data for a fixed number
of steps and reports throughput, wall time and, when available, CPU package
energy from Intel RAPL (/sys/class/powercap) and GPU energy from NVML.

Results are written as one JSON file per run so they can be aggregated across
Kubernetes Jobs, Slurm array tasks or bare-metal runs.
"""
import argparse
import glob
import json
import os
import platform
import socket
import time
from datetime import datetime, timezone

import torch
import torch.nn as nn
import torchvision


# --------------------------------------------------------------------------
# Energy readers
# --------------------------------------------------------------------------
class RaplReader:
    """Reads cumulative energy (microjoules) from Intel RAPL package domains."""

    def __init__(self):
        self.domains = []
        for path in sorted(glob.glob("/sys/class/powercap/intel-rapl:*")):
            # Top-level package domains only (intel-rapl:0, intel-rapl:1, ...)
            if path.count(":") != 1:
                continue
            energy_file = os.path.join(path, "energy_uj")
            max_file = os.path.join(path, "max_energy_range_uj")
            try:
                with open(energy_file):
                    pass
                with open(max_file) as f:
                    max_range = int(f.read())
                self.domains.append((energy_file, max_range))
            except (OSError, ValueError):
                continue

    @property
    def available(self):
        return bool(self.domains)

    def read(self):
        values = []
        for energy_file, _ in self.domains:
            with open(energy_file) as f:
                values.append(int(f.read()))
        return values

    def delta_joules(self, start, end):
        total = 0
        for (s, e, (_, max_range)) in zip(start, end, self.domains):
            diff = e - s
            if diff < 0:  # counter wrapped around
                diff += max_range
            total += diff
        return total / 1e6


class NvmlReader:
    """Reads cumulative GPU energy (millijoules) via NVML, if present."""

    def __init__(self):
        self.handles = []
        try:
            import pynvml  # noqa: WPS433

            pynvml.nvmlInit()
            self._nvml = pynvml
            for i in range(pynvml.nvmlDeviceGetCount()):
                self.handles.append(pynvml.nvmlDeviceGetHandleByIndex(i))
        except Exception:  # pynvml missing or no NVIDIA driver
            self.handles = []

    @property
    def available(self):
        return bool(self.handles)

    def read(self):
        return [self._nvml.nvmlDeviceGetTotalEnergyConsumption(h) for h in self.handles]

    @staticmethod
    def delta_joules(start, end):
        return sum(e - s for s, e in zip(start, end)) / 1e3


# --------------------------------------------------------------------------
# Benchmark
# --------------------------------------------------------------------------
def build_model(name, num_classes):
    if name == "resnet18":
        return torchvision.models.resnet18(num_classes=num_classes)
    if name == "mobilenet_v2":
        return torchvision.models.mobilenet_v2(num_classes=num_classes)
    if name == "tiny":
        return nn.Sequential(
            nn.Conv2d(3, 16, 3, padding=1), nn.ReLU(), nn.AdaptiveAvgPool2d(1),
            nn.Flatten(), nn.Linear(16, num_classes),
        )
    raise ValueError(f"unknown model {name}")


def read_cpu_freq_khz():
    try:
        with open("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq") as f:
            return int(f.read())
    except OSError:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="resnet18", choices=["resnet18", "mobilenet_v2", "tiny"])
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--steps", type=int, default=50)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--image-size", type=int, default=32)
    parser.add_argument("--threads", type=int, default=0, help="torch CPU threads (0 = default)")
    parser.add_argument("--device", default="auto", choices=["auto", "cpu", "cuda"])
    parser.add_argument("--output-dir", default="results")
    parser.add_argument("--tag", default="", help="free-form label, e.g. k8s, slurm, freq-2.0GHz")
    args = parser.parse_args()

    if args.threads > 0:
        torch.set_num_threads(args.threads)
    if args.device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        device = args.device

    torch.manual_seed(0)
    model = build_model(args.model, num_classes=10).to(device)
    optimizer = torch.optim.SGD(model.parameters(), lr=0.01, momentum=0.9)
    loss_fn = nn.CrossEntropyLoss()
    x = torch.randn(args.batch_size, 3, args.image_size, args.image_size, device=device)
    y = torch.randint(0, 10, (args.batch_size,), device=device)

    def step():
        optimizer.zero_grad(set_to_none=True)
        loss = loss_fn(model(x), y)
        loss.backward()
        optimizer.step()
        return loss

    for _ in range(args.warmup):
        step()
    if device == "cuda":
        torch.cuda.synchronize()

    rapl, nvml = RaplReader(), NvmlReader()
    rapl_start = rapl.read() if rapl.available else None
    nvml_start = nvml.read() if nvml.available else None
    t0 = time.perf_counter()

    for _ in range(args.steps):
        loss = step()
    if device == "cuda":
        torch.cuda.synchronize()

    elapsed = time.perf_counter() - t0
    cpu_energy = rapl.delta_joules(rapl_start, rapl.read()) if rapl.available else None
    gpu_energy = nvml.delta_joules(nvml_start, nvml.read()) if nvml.available else None
    samples = args.steps * args.batch_size

    result = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "host": socket.gethostname(),
        "platform": platform.platform(),
        "tag": args.tag,
        "scheduler": "slurm" if "SLURM_JOB_ID" in os.environ
        else ("kubernetes" if "KUBERNETES_SERVICE_HOST" in os.environ else "bare"),
        "slurm_job_id": os.environ.get("SLURM_JOB_ID"),
        "slurm_array_task_id": os.environ.get("SLURM_ARRAY_TASK_ID"),
        "pod_name": os.environ.get("POD_NAME"),
        "model": args.model,
        "device": device,
        "threads": torch.get_num_threads(),
        "batch_size": args.batch_size,
        "steps": args.steps,
        "elapsed_s": elapsed,
        "throughput_samples_per_s": samples / elapsed,
        "cpu_freq_khz": read_cpu_freq_khz(),
        "cpu_energy_j": cpu_energy,
        "gpu_energy_j": gpu_energy,
        "energy_per_sample_j": ((cpu_energy or 0) + (gpu_energy or 0)) / samples
        if (cpu_energy is not None or gpu_energy is not None) else None,
        "final_loss": float(loss.item()),
    }

    os.makedirs(args.output_dir, exist_ok=True)
    name = f"run_{result['host']}_{int(time.time() * 1000)}.json"
    path = os.path.join(args.output_dir, name)
    with open(path, "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
    print(f"saved -> {path}")
    if not rapl.available:
        print("note: RAPL not readable here (container/VM or no permission); energy is null")


if __name__ == "__main__":
    main()
