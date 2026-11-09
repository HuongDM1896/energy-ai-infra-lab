# CPU image for the benchmark. Small enough to load into a kind cluster.
# For GPU nodes, swap the base for an official CUDA-enabled PyTorch image.
FROM python:3.11-slim

WORKDIR /app
RUN pip install --no-cache-dir \
        torch torchvision --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir pynvml

COPY train_bench.py /app/train_bench.py

ENTRYPOINT ["python", "/app/train_bench.py"]
CMD ["--model", "resnet18", "--steps", "30", "--output-dir", "/results"]
