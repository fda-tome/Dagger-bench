# Aurora Supercomputer Benchmark Configuration

## Aurora System Overview

**Aurora** at Argonne National Laboratory:
- **Architecture**: Intel Data Center GPU Max Series (Ponte Vecchio)
- **Nodes**: ~10,000+ compute nodes
- **CPUs per node**: 2x Intel Xeon CPU Max Series (Sapphire Rapids)
  - 52 cores per CPU → 104 cores per node
- **GPUs per node**: 6x Intel Data Center GPU Max 1550
- **Memory per node**: 512 GB DDR5 + 128 GB HBM per GPU
- **Interconnection**: HPE Slingshot-11 network

## 🔑 Key Insight: Dagger.jl Auto-Discovers Workers

**Unlike standard Julia Distributed**, Dagger.jl automatically:
1. Detects all available processors via `Dagger.compatible_processors()`
2. Schedules tasks across detected workers without manual assignment
3. Handles data movement and dependencies automatically
4. Works with Julia's threading (`-t`) and distributed (`-p`) backends

**You provide workers, Dagger distributes the work!**

## Recommended Benchmark Parameters

### For Distributed CPU-based Execution

#### **Barnes-Hut Benchmark**

**Single Node (104 cores):**
```bash
# Dagger uses Julia threading to discover CPU cores
export BARNES_N=50000
export BARNES_THETA=0.5
export BENCH_RUNS=10

# Launch with threading - Dagger auto-discovers all threads
julia --project=../../demos/advanced/barnes -t 104 barnes_benchmark.jl

# Dagger will report: 104 CPUProcessor instances detected
```

**Multi-Node Distributed (Example: 8 nodes = 832 cores via MPI):**
```bash
# Dagger works with MPI backend for distributed execution
export BARNES_N=2000000
export BARNES_THETA=0.5
export BENCH_RUNS=5
export JULIA_MPI_BINARY=system

# Launch via MPI - Dagger auto-discovers all MPI ranks
mpiexec -n 832 \
        -ppn 104 \
        --hostfile hostfile \
        julia --project=../../demos/advanced/barnes \
              -t 1 \
              barnes_benchmark_mpi.jl

# Dagger discovers 832 processors (1 per MPI rank)
# and automatically distributes Dagger.@spawn tasks across them
```

**Key points:**
- Single node: Use `-t 104` (threading), no MPI needed
- Multi-node: Use `mpiexec -n TOTAL_CORES -ppn 104` with `-t 1`
- Dagger automatically discovers and uses all provided processors
- No manual task assignment to specific workers required!

**Scaling Study (Multi-node):**
```bash
# Test scaling from 10K to 10M bodies
export RUN_SCALING=true
export BENCH_RUNS=3

# Suggested problem sizes for Aurora
N_VALUES="10000,50000,100000,500000,1000000,5000000,10000000"

julia --project=../../demos/advanced/barnes \
      --machine-file=hostfile \
      -p 832 \
      barnes_benchmark.jl
```

#### **Seam Carving Benchmark**

**Single Node:**
```bash
# Use high-resolution image
export SEAM_IMG="large_image_8k.jpg"  # 7680x4320 or larger
export SEAM_COUNT=100                  # Remove 100 seams
export BENCH_RUNS=10
julia --project=../../demos/real-world/seam -t 104 seam_benchmark.jl
```

**Multi-Node:**
```bash
# Very large image processing
export SEAM_IMG="ultra_hd_16k.jpg"    # 15360x8640
export SEAM_COUNT=500
export BENCH_RUNS=5

julia --project=../../demos/real-world/seam \
      --machine-file=hostfile \
      -p 416 \                          # 4 nodes × 104 cores
      seam_benchmark.jl
```

## PBS/Slurm Job Scripts

### PBS Script for Aurora

```bash
#!/bin/bash
#PBS -l select=8:system=aurora
#PBS -l place=scatter
#PBS -l walltime=02:00:00
#PBS -q prod
#PBS -A YourProjectID
#PBS -N dagger_barnes_benchmark

# Load modules
module use /soft/modulefiles
module load frameworks/2024.1  # Julia + MPI
module load julia

cd $PBS_O_WORKDIR/benchmarks/comparison

# Generate machine file
cat $PBS_NODEFILE > hostfile

# Set number of workers (8 nodes × 104 cores = 832)
export NPROCS=832

# Barnes-Hut parameters for distributed run
export BARNES_N=5000000
export BARNES_THETA=0.5
export BENCH_RUNS=5

# Run benchmark
julia --project=../../demos/advanced/barnes \
      --machine-file=hostfile \
      -p $NPROCS \
      barnes_benchmark.jl \
      2>&1 | tee barnes_aurora_${PBS_JOBID}.log

# Scaling study
export RUN_SCALING=true
export BENCH_RUNS=3
julia --project=../../demos/advanced/barnes \
      --machine-file=hostfile \
      -p $NPROCS \
      barnes_benchmark.jl \
      2>&1 | tee barnes_scaling_aurora_${PBS_JOBID}.log
```

### Seam Carving PBS Script

```bash
#!/bin/bash
#PBS -l select=4:system=aurora
#PBS -l place=scatter
#PBS -l walltime=01:00:00
#PBS -q debug
#PBS -A YourProjectID
#PBS -N dagger_seam_benchmark

module use /soft/modulefiles
module load frameworks/2024.1
module load julia

cd $PBS_O_WORKDIR/benchmarks/comparison

cat $PBS_NODEFILE > hostfile

export NPROCS=416  # 4 nodes × 104 cores

# Prepare large test image (if not already available)
# convert input.jpg -resize 15360x8640 ultra_hd_16k.jpg

export SEAM_IMG="../../demos/real-world/seam/large_test_image.jpg"
export SEAM_COUNT=200
export BENCH_RUNS=5

julia --project=../../demos/real-world/seam \
      --machine-file=hostfile \
      -p $NPROCS \
      seam_benchmark.jl \
      2>&1 | tee seam_aurora_${PBS_JOBID}.log
```

## Optimal Problem Sizes for Aurora

### Barnes-Hut N-Body

| Configuration | Bodies (N) | Theta | Expected Runtime | Notes |
|--------------|-----------|-------|------------------|-------|
| 1 node (104 cores) | 50,000 | 0.5 | ~10s | Baseline single-node |
| 4 nodes (416 cores) | 500,000 | 0.5 | ~30s | Medium distributed |
| 8 nodes (832 cores) | 1,000,000 | 0.5 | ~45s | Large distributed |
| 16 nodes (1,664 cores) | 5,000,000 | 0.5 | ~2-3min | Strong scaling study |
| 32 nodes (3,328 cores) | 10,000,000 | 0.5 | ~5min | Weak scaling study |

**Theta recommendations:**
- `0.3`: High accuracy, slower (scientific simulation)
- `0.5`: Balanced (default, recommended for benchmarks)
- `0.8`: Lower accuracy, faster (stress testing)

### Seam Carving

| Configuration | Image Size | Seams | Expected Runtime | Notes |
|--------------|-----------|-------|------------------|-------|
| 1 node | 4K (3840×2160) | 100 | ~20s | Single node baseline |
| 2 nodes | 8K (7680×4320) | 200 | ~1min | Medium image |
| 4 nodes | 16K (15360×8640) | 500 | ~3-5min | Large image processing |
| 8 nodes | Custom very large | 1000 | ~10min | Stress test |

## Dagger.jl Distributed Computing Setup

**Key Difference**: Dagger.jl auto-detects processors and manages workers internally. You don't use `addprocs` explicitly - instead, configure Julia's threading and let Dagger discover resources.

### Multi-Node Setup for Dagger

Dagger works with Julia's built-in distributed computing but manages scheduling automatically:

```julia
using Distributed

# Add workers across nodes (Dagger will auto-discover these)
machines = readlines("hostfile")
addprocs(machines; exeflags="--project=. -t auto")

# Load Dagger on all workers
@everywhere using Dagger

# Dagger auto-discovers all available processors
@show Dagger.compatible_processors()
# Output: 832-element Vector showing all CPUProcessor instances

# Dagger tasks automatically distribute across these processors
# No manual work distribution needed!
```

### Alternative: MPI Backend for Dagger

For better Aurora performance, use Dagger's MPI backend:

```julia
using MPIClusterManagers
using Distributed

# Launch workers via MPI
manager = MPIManager(np=832)  # 8 nodes × 104 cores
addprocs(manager)

@everywhere using Dagger

# Dagger will use MPI for inter-node communication
println("Dagger processors: ", length(Dagger.compatible_processors()))
```

## Performance Tuning for Aurora

### 1. Thread Configuration
```bash
# Use all physical cores per node
export JULIA_NUM_THREADS=104

# For NUMA-aware execution
export JULIA_EXCLUSIVE=1
```

### 2. Memory Settings
```bash
# Increase heap size for large problems
export JULIA_HEAP_SIZE_HINT=400G  # For 512GB node

# Garbage collection tuning
export JULIA_GC_ALLOC_POOL=10000000
export JULIA_GC_ALLOC_OTHER=5000000
```

### 3. Network Optimization
```bash
# For MPI-based distributed computing
export UCX_TLS=rc,ud,sm,self
export UCX_NET_DEVICES=mlx5_0:1

# Increase message buffer sizes
export JULIA_MPI_BINARY=system
export JULIA_MPI_PATH=/path/to/aurora/mpi
```

### 4. Dagger-Specific Configuration

```julia
# In your benchmark script
using Dagger

# Configure Dagger for Aurora
Dagger.with_options(
    threads=104,           # Threads per worker
    procs=:auto,          # Auto-detect workers
    single=false          # Disable single-threaded mode
) do
    # Run your benchmark here
end
```

## Recommended Benchmark Suite for Aurora

### Complete Test Plan

1. **Single Node Baseline** (1 node, 104 cores)
   - Barnes-Hut: N=50,000, runs=10
   - Seam: 4K image, 100 seams, runs=10
   - Purpose: Establish baseline performance

2. **Strong Scaling** (Fixed problem size, increase nodes)
   - Nodes: 1, 2, 4, 8, 16
   - Barnes-Hut: N=1,000,000 (constant)
   - Measure: Speedup vs ideal linear scaling

3. **Weak Scaling** (Increase problem size with nodes)
   - Nodes: 1, 2, 4, 8, 16
   - Barnes-Hut: N=100K per node (100K, 200K, 400K, 800K, 1.6M)
   - Measure: Constant time as nodes increase

4. **Production Scale** (Large problems)
   - 32+ nodes
   - Barnes-Hut: N=10,000,000+
   - Seam: Ultra-HD images
   - Measure: Absolute performance, efficiency

## Expected Results

### Performance Targets

**Barnes-Hut on 8 nodes (832 cores):**
- Sequential baseline (1 core): ~500s for N=1M
- Parallel (832 cores): ~5-10s for N=1M
- Expected speedup: 50-100x (accounting for communication overhead)
- Parallel efficiency: 60-80%

**Seam Carving on 4 nodes (416 cores):**
- Sequential baseline (1 core): ~60s for 8K image, 100 seams
- Parallel (416 cores): ~2-5s
- Expected speedup: 12-30x
- Parallel efficiency: 40-60% (more communication intensive)

## Troubleshooting

### Common Issues on Aurora

1. **"Cannot connect to workers"**
   - Check machine file format
   - Verify SSH keys are set up
   - Use `--machine-file=hostfile` correctly

2. **Low speedup**
   - Problem size too small (increase N or image size)
   - Network bottleneck (check UCX settings)
   - Load imbalance (try different Dagger scheduling)

3. **Out of memory**
   - Reduce problem size per node
   - Increase heap size hint
   - Use more nodes to distribute memory

4. **Slow compilation**
   - Precompile packages: `julia --project -e 'using Pkg; Pkg.precompile()'`
   - Use system image for faster startup

## Data Collection Checklist

For publishable results, collect:
- [ ] Hardware configuration (nodes, cores, memory)
- [ ] Julia version and Dagger.jl version
- [ ] Problem parameters (N, image size, etc.)
- [ ] Number of benchmark runs
- [ ] Mean, median, std deviation of timing
- [ ] Speedup and efficiency calculations
- [ ] Memory usage per node
- [ ] Network/communication overhead
- [ ] Load balancing statistics

## Contact

For Aurora-specific support:
- ALCF Support: support@alcf.anl.gov
- Julia HPC Slack: #hpc channel
- Dagger.jl Issues: https://github.com/JuliaParallel/Dagger.jl/issues
