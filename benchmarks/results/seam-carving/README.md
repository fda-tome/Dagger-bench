# Seam‑carving benchmark results

Benchmark outputs for seam‑carving are written under this folder, typically in timestamped subfolders like:

```
benchmarks/results/seam-carving/<timestamp>/
```

Each run writes:

- `strong_scaling.csv`
- `weak_scaling.csv`

Columns:

```
scenario,variant,threads,rows,cols,k,tile_h,tile_w,run,time_sec
```

Notes:

- The seam‑carving benchmark is single‑node (no `Distributed` workers).
- Control parallelism via `-t` / `JULIA_NUM_THREADS`.
