# Seam Carving

This app provides the `DaggerSeamCarving` module (`src/DaggerSeamCarving.jl`) with CPU and GPU seam‑carving variants. Functions are not exported, so call them with the `DaggerSeamCarving.` prefix.

## Contents

- `src/DaggerSeamCarving.jl`: seam‑carving implementation (serial + Dagger variants)
- `Project.toml` / `Manifest.toml`: Julia environment for the app

## Quick usage

```bash
julia --project=apps/seam-carving -e 'using DaggerSeamCarving; img=rand(Float32, 512, 512); DaggerSeamCarving.seam_carve_cpu_serial(img; k=1)'
```

Available variants (all require an `AbstractMatrix` / `AbstractArray`):

- CPU: `seam_carve_cpu_serial`, `seam_carve_cpu_dagger`, `seam_carve_cpu_dagger_tiled`, `seam_carve_cpu_dagger_wavefront`, `seam_carve_cpu_dagger_tileoverlap`, `seam_carve_cpu_dagger_triangles`
- GPU: `seam_carve_gpu_dagger`, `seam_carve_gpu_dagger_device` (expects GPU arrays)

GPU example:

```bash
julia --project=apps/seam-carving -e 'using CUDA, DaggerSeamCarving; img=CUDA.CuArray(rand(Float32, 512, 512)); DaggerSeamCarving.seam_carve_gpu_dagger(img; k=1)'
```

## Benchmarks (single‑node)

The seam‑carving benchmark runs on a single Julia process (no `Distributed` workers). Use threads via `-t` or `JULIA_NUM_THREADS`.

From the repo root:

```bash
julia --project=apps/seam-carving -t16 -e 'include("benchmarks/scripts/seam-carving.jl"); run_benchmark()'
```

Results are written under `benchmarks/results/seam-carving/<timestamp>/`.

### Configuration

Benchmarks are driven by environment variables (timed with BenchmarkTools after a warmup run):

- `BENCH_RUNS` (default: 3)
- `SEAM_ROWS` / `SEAM_COLS` (default: 512x512)
- `SEAM_K` (default: 1)
- `SEAM_TILE_H` / `SEAM_TILE_W` (default: 150x150)
- `SEAM_VARIANTS` (default: all; comma/space‑separated)
- `SEAM_GPU` (default: 1; set to 0 to skip GPU variants)
- `SEAM_DEVICE` (default: auto; cpu|cuda|amdgpu|oneapi|metal)
- `SEAM_WEAK_SCALE` (default: sqrt; options: sqrt|linear|<float>)
- `SEAM_WEAK_ROWS` / `SEAM_WEAK_COLS` (override weak dimensions)
