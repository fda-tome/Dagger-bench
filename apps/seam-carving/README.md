# Seam Carving

This app provides the `DaggerSeamCarving` module (`src/DaggerSeamCarving.jl`) with CPU and GPU seam‑carving variants. Functions are not exported, so call them with the `DaggerSeamCarving.` prefix.

## Contents

- `src/DaggerSeamCarving.jl`: seam‑carving implementation (serial + Dagger variants)
- `Project.toml` / `Manifest.toml`: Julia environment for the app

## Quick usage

First time only:

```bash
julia --project=apps/seam-carving -e 'using Pkg; Pkg.instantiate()'
```

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

## Parallelism flavors

Seam carving has a mix of *algorithmic* dependencies (some steps must happen in order) and *implementation* choices about how to expose parallel work. All variants here are **single-node** (one Julia process); CPU parallelism comes from Julia threads (`-t` / `JULIA_NUM_THREADS`).

- **Pure serial baseline**: `seam_carve_cpu_serial` uses fully serial kernels (`energy_cpu_serial`, `cumulative_energy_cpu_serial`, `remove_seam_serial`). This is your reference for correctness and “no parallelism” overhead.
- **CPU loop threading**: most non-serial CPU helpers use `Threads.@threads` internally (e.g. `energy_cpu`, `cumulative_energy_cpu`, `remove_seam`). This is data-parallelism *within* each stage.
- **Dagger task graphs (CPU)**: the `seam_carve_cpu_dagger*` family uses Dagger tasks (`Dagger.@spawn`) to express higher-level parallel work and dependencies.
  - `seam_carve_cpu_dagger`: coarse pipeline over stages (energy → DP → backtrack → remove), where each stage can itself be threaded.
  - `seam_carve_cpu_dagger_tiled`: embarrassingly-parallel tiling for energy and seam-removal; DP/backtrack are still computed in a single step.
  - `seam_carve_cpu_dagger_wavefront`: a tiled DP with a *wavefront* dependency pattern (each DP tile depends on tiles “above” it).
  - `seam_carve_cpu_dagger_tileoverlap`: overlaps tiled energy with the DP wavefront to increase concurrency.
  - `seam_carve_cpu_dagger_triangles`: decomposes DP into alternating triangle-shaped regions to relax dependencies.
- **GPU kernel parallelism (KernelAbstractions)**: GPU variants use `@kernel` definitions for energy/DP/remove and rely on a loaded backend (CUDA/AMDGPU/oneAPI/Metal).
  - `seam_carve_gpu_dagger`: runs GPU kernels but backtracks the seam on the CPU (host/device copies).
  - `seam_carve_gpu_dagger_device`: keeps seam backtracking on-device (`find_seam_gpu_device`) to avoid host round-trips.

Note: some variants combine Dagger task parallelism *and* `Threads.@threads` inside tasks; when exploring CPU performance, be mindful of potential nested parallelism/oversubscription.

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
