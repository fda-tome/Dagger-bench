# Comparison Benchmarks

This directory contains comprehensive benchmark scripts comparing sequential and parallel implementations of Dagger.jl demos, with detailed statistical analysis and performance metrics.

## 🚀 Quick Links

- **[Aurora Supercomputer Configuration](AURORA_CONFIG.md)** - Optimized parameters and PBS scripts for Aurora at ALCF
- **PBS Scripts**: `aurora_strong_scaling.pbs`, `aurora_weak_scaling.pbs`, `aurora_seam_benchmark.pbs`
- **Local Benchmarks**: See below for laptop/workstation runs

## Available Benchmarks

### 1. Seam Carving Benchmark (`seam_benchmark.jl`)

Compares sequential vs parallel image seam carving implementations.

**Quick Start:**
```bash
cd benchmarks/comparison
julia --project=../../demos/real-world/seam seam_benchmark.jl
```

**Configuration via environment variables:**
```bash
SEAM_IMG="path/to/image.jpg" SEAM_COUNT=20 BENCH_RUNS=5 julia --project=../../demos/real-world/seam seam_benchmark.jl
```

**Options:**
- `SEAM_IMG`: Path to input image (default: `../../demos/real-world/seam/mirage.jpg`)
- `SEAM_COUNT`: Number of seams to remove (default: 10)
- `BENCH_RUNS`: Number of benchmark runs for statistics (default: 3)

**Output:**
- Console: Detailed statistics including mean, median, std deviation, speedup
- CSV files: `seam_benchmark_detailed_*.csv` and `seam_benchmark_summary_*.csv`

### 2. Barnes-Hut N-Body Benchmark (`barnes_benchmark.jl`)

Compares sequential vs parallel Barnes-Hut tree-based force calculations.

**Quick Start:**
```bash
cd benchmarks/comparison
julia --project=../../demos/advanced/barnes barnes_benchmark.jl
```

**Configuration via environment variables:**
```bash
BARNES_N=2000 BARNES_THETA=0.5 BENCH_RUNS=5 julia --project=../../demos/advanced/barnes barnes_benchmark.jl
```

**Options:**
- `BARNES_N`: Number of bodies in simulation (default: 1000)
- `BARNES_THETA`: Barnes-Hut approximation threshold (default: 0.5)
- `BENCH_RUNS`: Number of benchmark runs (default: 5)
- `RUN_SCALING=true`: Run scaling study across multiple problem sizes

**Scaling Study:**
```bash
RUN_SCALING=true BENCH_RUNS=3 julia --project=../../demos/advanced/barnes barnes_benchmark.jl
```

**Output:**
- Console: Detailed statistics, speedup, and parallel efficiency
- CSV files: `barnes_benchmark_detailed_*.csv`, `barnes_benchmark_summary_*.csv`
- Scaling study: `barnes_scaling_*.csv` (when `RUN_SCALING=true`)

## Benchmark Utilities (`benchmark_utils.jl`)

Shared utilities for timing, memory profiling, and statistical analysis.

**Key Functions:**
- `time_benchmark(f, name)`: Run function and capture timing/memory stats
- `run_multiple(f, name, n)`: Run benchmark multiple times
- `compute_stats(results)`: Aggregate statistics from multiple runs
- `compare_benchmarks(baseline, comparison)`: Calculate speedup
- `export_to_csv(path, stats)`: Export detailed results
- `export_summary_to_csv(path, stats)`: Export summary statistics

## Understanding the Output

### Console Output

Each benchmark prints:
1. **Configuration**: Problem size, parameters, number of runs
2. **Per-benchmark statistics**:
   - Mean time ± standard deviation
   - Median, min, max times
   - Memory allocation statistics
   - GC time
3. **Comparison**:
   - Speedup (baseline time / comparison time)
   - Percentage improvement
   - Parallel efficiency (for parallel benchmarks)

### CSV Files

**Detailed CSV** (`*_detailed_*.csv`):
- One row per benchmark run
- Columns: benchmark name, run number, time, allocated memory, GC time

**Summary CSV** (`*_summary_*.csv`):
- One row per benchmark
- Columns: benchmark name, num runs, mean/std/median/min/max times, mean allocation

**Scaling CSV** (`barnes_scaling_*.csv`):
- One row per problem size
- Columns: N, sequential time, parallel time, speedup

## Interpreting Results

### Speedup
- **Speedup > 1.0**: Parallel version is faster
- **Speedup < 1.0**: Sequential version is faster (overhead dominated)
- **Speedup ≈ num_processors**: Linear scaling (ideal)

### Parallel Efficiency
```
Efficiency = Speedup / Number of Processors
```
- **100%**: Perfect scaling
- **50-80%**: Good scaling
- **< 50%**: Poor scaling, overhead significant

### Statistical Significance
- Multiple runs provide mean ± standard deviation
- Low standard deviation (< 5% of mean) indicates stable performance
- High standard deviation may indicate system noise or warmup effects

## Hardware Considerations

Benchmark results depend on:
- **CPU**: Number of cores/threads available
- **Memory**: RAM size and bandwidth
- **Cache**: L1/L2/L3 cache sizes
- **System load**: Other processes running

For reproducible results:
1. Close unnecessary applications
2. Run multiple iterations (3-5 minimum)
3. Use consistent problem sizes
4. Document hardware specifications

## Tips for Best Results

1. **Warmup**: First run may be slower due to JIT compilation
2. **Problem size**: Use large enough problems to overcome parallel overhead
3. **Multiple runs**: Run 5+ times for robust statistics
4. **System isolation**: Minimize background processes
5. **Consistent parameters**: Use same configuration for comparisons

## Extending Benchmarks

To add a new benchmark:

1. Create `mybenchmark.jl` in this directory
2. Include `benchmark_utils.jl`
3. Define sequential and parallel versions of your algorithm
4. Use `run_multiple()` and `compute_stats()` for measurements
5. Export results with `export_to_csv()`
6. Document in this README

Example structure:
```julia
include("benchmark_utils.jl")

function my_sequential_impl(args...)
    # Your code here
end

function my_parallel_impl(args...)
    # Your Dagger.jl code here
end

function run_my_benchmarks(; num_runs=3)
    seq_results = run_multiple(() -> my_sequential_impl(...), "Sequential", num_runs)
    par_results = run_multiple(() -> my_parallel_impl(...), "Parallel", num_runs)
    
    seq_stats = compute_stats(seq_results)
    par_stats = compute_stats(par_results)
    
    print_stats(seq_stats)
    print_stats(par_stats)
    compare_benchmarks(seq_stats, par_stats)
end
```

## Common Issues

**"Image file not found"** (seam benchmark):
- Ensure you're in the correct directory
- Check that demo images exist in `demos/real-world/seam/`
- Use absolute path or correct relative path

**Low/negative speedup**:
- Problem size may be too small
- Parallel overhead dominates for small inputs
- Try larger problem sizes

**High variance in results**:
- System may be under load
- Increase number of runs
- Close background applications

## Running on Aurora Supercomputer

For distributed execution on the Aurora supercomputer at Argonne National Laboratory:

### Quick Start

```bash
# Submit strong scaling study (8 nodes)
qsub aurora_strong_scaling.pbs

# Submit weak scaling study (16 nodes)
qsub aurora_weak_scaling.pbs

# Submit seam carving benchmark (4 nodes)
qsub aurora_seam_benchmark.pbs
```

### Recommended Parameters

**Barnes-Hut:**
- Single node: `N=50,000`, `BENCH_RUNS=10`
- 8 nodes (832 cores): `N=2,000,000`, `BENCH_RUNS=5`
- 16 nodes (1,664 cores): `N=5,000,000+`, `BENCH_RUNS=3`

**Seam Carving:**
- 1 node: 4K image, 50-100 seams
- 2 nodes: 8K image, 100-200 seams
- 4 nodes: 16K+ image, 200-500 seams

**See [AURORA_CONFIG.md](AURORA_CONFIG.md) for detailed configuration, PBS scripts, and performance tuning.**

## Citation

If you use these benchmarks in research, please cite our paper and reference the Dagger.jl repository.
