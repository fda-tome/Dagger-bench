# Benchmarks

This directory groups standalone benchmark scripts by theme. Drop new benchmark experiments into the appropriate subfolder and document how to run them in a short README.

- `scalability/`: strong- and weak-scaling scenarios
- `throughput/`: steady-state and batch throughput tests
- `memory/`: memory pressure and footprint measurements
- `comparison/`: studies that compare Dagger.jl to alternative approaches

Each subfolder can contain its own `Project.toml` if dependencies deviate from the repository root environment.
