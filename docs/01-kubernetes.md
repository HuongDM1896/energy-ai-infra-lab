# Step 1 — Kubernetes (about 1–2 weeks of evenings)

Goal: run the benchmark as a Kubernetes Job on a local multi-node cluster,
monitor it with Prometheus/Grafana, and get per-pod energy estimates from Kepler.

## 0. Install tools (Linux)
- Docker
- `kind` (Kubernetes in Docker): https://kind.sigs.k8s.io
- `kubectl`: https://kubernetes.io/docs/tasks/tools/
- `helm`: https://helm.sh/docs/intro/install/

Check: `docker ps`, `kind version`, `kubectl version --client`, `helm version`.

## 1. Create the cluster
```bash
make kind-up
kubectl get nodes -o wide        # 1 control-plane + 2 workers
kubectl get nodes --show-labels  # note lab/pool=bench
```
Concepts to understand here: node, control plane, kubelet, labels.

## 2. Build and load the image
```bash
make kind-load                   # docker build + load into kind (no registry needed)
```
Concepts: container image, why kind needs `kind load`, `imagePullPolicy`.

## 3. Run the benchmark Job
```bash
make k8s-run
kubectl get pods -l app=energy-bench -o wide   # which node ran each pod?
kubectl logs -l app=energy-bench --tail=20
make k8s-collect && make analyze
```
Concepts: Job vs Deployment, `completions`/`parallelism`, `nodeSelector`,
resource `requests`/`limits` (CPU pinning effect on throughput!), hostPath volumes.

**Exercise:** change `limits.cpu` to `"1"` and `--threads 1`, rerun, compare throughput.
This is exactly the kind of resource/performance trade-off question you get in interviews.

## 4. Monitoring: Prometheus + Grafana
```bash
make monitoring
kubectl -n monitoring get pods
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# open http://localhost:3000  (admin / lab-admin)
```
Look at the "Kubernetes / Compute Resources / Pod" dashboard while the Job runs.

## 5. Energy: Kepler
```bash
make kepler
kubectl -n kepler get pods
```
In Grafana → Explore, query:
```
sum by (pod_name) (rate(kepler_container_joules_total{container_namespace="default"}[1m]))
```
**Be honest in your README:** inside kind/VMs Kepler uses model-based estimates,
not real RAPL. Compare with the benchmark's own RAPL reading on bare metal (step 4 doc).
Metric names can change between Kepler versions — check `curl <kepler-pod>:9102/metrics`
if the query returns nothing.

## 6. Clean up
```bash
make kind-down
```

## What to write on your CV after this step
"Deployed a multi-node Kubernetes cluster (kind) with Prometheus/Grafana and Kepler
to benchmark PyTorch training jobs and compare per-pod energy estimates with RAPL measurements."
