# Benchmarks

Optional benchmark suite for the apps in `apps/`.

## Entry points (per app)

For every app folder `apps/<app>/` (where `<app>` is the directory name, e.g. `barnes-hut`), there should be a matching benchmark script:

- `benchmarks/scripts/<app>.jl`

Each benchmark script defines a single entry point:

- `run_benchmark()`

Calling `run_benchmark()` runs:

- **Strong scaling**: fixed problem size (measure performance under the current Dagger processor configuration).
- **Weak scaling**: problem size proportional to the number of detected Dagger processors.

To generate an actual scaling curve, rerun the same benchmark under different resource allocations (threads/workers/MPI ranks), and aggregate the CSV outputs.

## Data and results (per app)

- `benchmarks/data/<app>/`: input datasets / test assets for an app’s benchmarks (same `<app>` name as under `apps/`)
- `benchmarks/results/<app>/`: outputs (CSVs, logs, plots), typically in timestamped subfolders (same `<app>` name as under `apps/`)

Keep large binaries out of git when possible.

## Running

These examples assume `apps/<app>/` exists and is a Julia project (i.e. has a `Project.toml`).

From repo root:

```bash
# Barnes–Hut
julia --project=apps/barnes-hut benchmarks/scripts/barnes-hut.jl

# Seam carving
julia --project=apps/seam-carving benchmarks/scripts/seam-carving.jl
```

Run all app benchmarks:

```bash
julia run_benchmarks.jl
```

Or from the REPL:

```julia
include("benchmarks/scripts/barnes-hut.jl")
run_benchmark()
```

## Folder layout

Benchmarks are organized under three folders:

- `benchmarks/data/`
- `benchmarks/results/`
- `benchmarks/scripts/`
