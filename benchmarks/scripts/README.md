# Scripts

Automation utilities, batch runners, and helper scripts for benchmarks.

All app benchmark entry points live at `benchmarks/scripts/<app>.jl` and expose `run_benchmark()`. Script runners should call that entry point rather than re-implementing logic.

These examples assume `apps/<app>/` exists and is a Julia project (i.e. has a `Project.toml`).

Example (repo root):

```bash
julia --project=apps/barnes-hut -e 'include("benchmarks/scripts/barnes-hut.jl"); run_benchmark()'
```

Run all app benchmarks:

```bash
julia run_benchmarks.jl
```
