IMAGE := energy-bench:0.1
CLUSTER := energy-lab

.PHONY: venv bench analyze image kind-up kind-load k8s-run k8s-collect monitoring kepler kind-down

venv:
	python3 -m venv .venv && . .venv/bin/activate && pip install -r bench/requirements.txt pandas matplotlib

bench:            ## run once on this machine
	python bench/train_bench.py --model resnet18 --steps 30 --tag bare --output-dir results/bare

analyze:
	python analysis/aggregate.py results --out analysis/out

image:
	docker build -t $(IMAGE) bench/

kind-up:
	kind create cluster --config k8s/kind-config.yaml

kind-load: image
	kind load docker-image $(IMAGE) --name $(CLUSTER)

k8s-run:
	kubectl apply -f k8s/bench-job.yaml
	kubectl wait --for=condition=complete job/energy-bench --timeout=15m

k8s-collect:      ## copy results from each worker node container
	mkdir -p results/k8s
	for n in $$(kind get nodes --name $(CLUSTER) | grep worker); do \
	  docker cp $$n:/tmp/energy-bench-results/. results/k8s/ ; done

monitoring:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
	  -n monitoring --create-namespace -f k8s/monitoring/kube-prometheus-values.yaml

kepler:
	helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
	helm repo update
	helm upgrade --install kepler kepler/kepler -n kepler --create-namespace \
	  -f k8s/monitoring/kepler-values.yaml

kind-down:
	kind delete cluster --name $(CLUSTER)
