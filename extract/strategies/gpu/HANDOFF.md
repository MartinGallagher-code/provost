# Handoff -- EnvoyExtract/strategies/gpu

## Status: Complete (3 strategies)

GPU and accelerator monitoring extraction strategies.

## Strategies

| File | Format | Description |
|------|--------|-------------|
| `nvidia-smi.sh` | nvidia-smi output | Table format and `-q` verbose format GPU status |
| `rocm-smi.sh` | AMD rocm-smi output | AMD GPU status and metrics |
| `cuda-devicequery.sh` | CUDA deviceQuery | GPU capability and hardware info |
