# Data

Store input datasets and generated artifacts here **per app**.

- Put assets for app `<app>` under `benchmarks/data/<app>/` (where `<app>` matches the folder name under `apps/`).
- Document origin, licensing, and any preprocessing steps.
- Prefer linking to large/immutable datasets instead of committing them to git.

Note: current seam‑carving benchmarks use synthetic random images by default, so this folder is optional unless you customize the benchmark to read real images.
