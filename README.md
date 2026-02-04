# DaggerApps

A collection of [Dagger.jl](https://github.com/JuliaParallel/Dagger.jl) application folders (apps), plus optional benchmark scaffolding.

The primary goal of this repo is **apps**. Benchmarking scripts exist as an **optional add-on**, not the main focus.

Current status: the repo is being reorganized; app folders currently contain **docs-only placeholders** (README files) and will be populated with runnable Julia projects.

## Repo Layout

```
DaggerApps/
├── apps/                      # Dagger applications (one folder per app)
│   ├── barnes-hut/            # Barnes–Hut N-body simulation
│   └── seam-carving/          # Content-aware image resizing (seam carving)
└── benchmarks/                # Optional benchmark suite for the apps
```

## Apps

Apps live under `apps/<name>/`. Each app folder is expected to contain:

- `README.md`
- a Julia project (`Project.toml`, optionally `Manifest.toml`)
- one or more runnable entrypoints

## Benchmarks (optional)

Benchmarks live under `benchmarks/` and are intended to be run against the apps (once an app folder contains a Julia project).

Example:

```bash
julia --project=apps/barnes-hut benchmarks/scripts/barnes-hut.jl
```

Run all app benchmarks:

```bash
julia run_benchmarks.jl
```

## Contributing

- Add new apps under `apps/<name>/` and include a short `README.md` plus a Julia project (`Project.toml`).
- Keep apps runnable by default; document any cluster/GPU/MPI requirements.

## Related Resources

- [Dagger.jl Documentation](https://juliaparallel.org/Dagger.jl/stable/)
- [Julia Parallel Computing](https://docs.julialang.org/en/v1/manual/parallel-computing/)
- [JuliaParallel Organization](https://github.com/JuliaParallel)

---

**Note**: This repository is actively maintained; apps and benchmarks may evolve over time. For reproducible runs, rely on each app’s `Manifest.toml` (when present).
