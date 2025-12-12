# Use local Dagger.jl
import Pkg
Pkg.develop(path="/flare/dagger/paper/Dagger.jl")

using Dates
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

# ============================================================================
# GPU CHOLESKY BENCHMARK (Intel GPUs via oneAPI)
# ============================================================================
println("\n" * "="^80)
println("CHOLESKY GPU BENCHMARK (Intel oneAPI)")
println("="^80)
println("Start time: ", now())

# Load oneAPI for Intel GPUs
using oneAPI
using Dagger
using LinearAlgebra
using Random
using Statistics

# Check GPU availability
println("\nGPU Information:")
println("  oneAPI functional: ", oneAPI.functional())
if oneAPI.functional()
    devices = oneAPI.devices()
    println("  Number of devices: ", length(devices))
    for (i, dev) in enumerate(devices)
        println("    Device $i: ", dev)
    end
end

# ============================================================================
# CONFIGURATION
# ============================================================================
# Matrix sizes to benchmark
MATRIX_SIZES = parse.(Int, split(get(ENV, "MATRIX_SIZES", "1024,2048,4096,8192"), ","))

# Block size for tiled Cholesky
BLOCK_SIZE = parse(Int, get(ENV, "BLOCK_SIZE", "1024"))

# Data types
DTYPES = [Float32, Float64]

# Number of warmup and benchmark runs
NUM_WARMUP = parse(Int, get(ENV, "NUM_WARMUP", "1"))
NUM_RUNS = parse(Int, get(ENV, "NUM_RUNS", "3"))

println("\nConfiguration:")
println("  Matrix sizes: $MATRIX_SIZES")
println("  Block size: $BLOCK_SIZE")
println("  Data types: $DTYPES")
println("  Warmup runs: $NUM_WARMUP")
println("  Benchmark runs: $NUM_RUNS")

all_results = []

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function generate_spd_matrix_cpu(T, n)
    # Generate symmetric positive definite matrix on CPU
    A = rand(T, n, n)
    A = A * A'
    A[diagind(A)] .+= n  # Ensure positive definiteness
    return A
end

function generate_spd_matrix_gpu(T, n)
    # Generate symmetric positive definite matrix directly on GPU
    A = oneAPI.rand(T, n, n)
    A = A * A'
    # Add to diagonal to ensure positive definiteness
    for i in 1:n
        A[i, i] += n
    end
    oneAPI.synchronize()
    return A
end

function benchmark_cpu_cholesky(A::Matrix{T}) where T
    A_copy = copy(A)
    result = @timed cholesky!(A_copy)
    return result.time
end

function benchmark_gpu_cholesky_dagger(A_gpu::oneArray{T}, block_size::Int) where T
    n = size(A_gpu, 1)
    
    # Use Dagger with GPU scope - this is the KEY for GPU execution
    Dagger.with_options(scope=Dagger.scope(intel_gpus=:)) do
        # Distribute the GPU array using Dagger
        DA = Dagger.distribute(A_gpu, Blocks(block_size, block_size))
        
        # Run Cholesky via Dagger on GPUs
        result = @timed begin
            chol_result = LinearAlgebra._chol!(DA, UpperTriangular)
        end
        
        return result.time, DA
    end
end

# ============================================================================
# RUN BENCHMARKS
# ============================================================================
println("\n" * "="^80)
println("RUNNING BENCHMARKS")
println("="^80)

for T in DTYPES
    println("\n" * "-"^60)
    println("Data type: $T")
    println("-"^60)
    
    for n in MATRIX_SIZES
        println("\n  Matrix size: $n x $n")
        
        # Generate SPD matrix on CPU for baseline
        A_cpu = generate_spd_matrix_cpu(T, n)
        
        # CPU baseline
        println("    CPU Cholesky...")
        cpu_times = Float64[]
        for i in 1:(NUM_WARMUP + NUM_RUNS)
            t = benchmark_cpu_cholesky(A_cpu)
            if i > NUM_WARMUP
                push!(cpu_times, t)
            end
        end
        cpu_median = length(cpu_times) > 0 ? median(cpu_times) : NaN
        println("      Time: $(cpu_median) s")
        
        # GPU Dagger Cholesky - create GPU array and use GPU scope
        println("    Dagger GPU Cholesky (block_size=$BLOCK_SIZE)...")
        dagger_times = Float64[]
        for i in 1:(NUM_WARMUP + NUM_RUNS)
            # Create fresh GPU array for each run (Cholesky modifies in-place)
            A_gpu = oneArray(A_cpu)
            oneAPI.synchronize()
            
            t, _ = benchmark_gpu_cholesky_dagger(A_gpu, BLOCK_SIZE)
            if i > NUM_WARMUP
                push!(dagger_times, t)
            end
        end
        dagger_median = length(dagger_times) > 0 ? median(dagger_times) : NaN
        println("      Time: $(dagger_median) s")
        
        # Calculate GFLOPS (Cholesky is ~n³/3 FLOPs)
        flops = n^3 / 3
        cpu_gflops = flops / (cpu_median * 1e9)
        dagger_gflops = flops / (dagger_median * 1e9)
        speedup = cpu_median / dagger_median
        
        result = (
            dtype = T,
            size = n,
            block_size = BLOCK_SIZE,
            cpu_time = cpu_median,
            gpu_time = dagger_median,
            cpu_gflops = cpu_gflops,
            gpu_gflops = dagger_gflops,
            speedup = speedup
        )
        push!(all_results, result)
        
        println("      CPU GFLOPS: $(cpu_gflops)")
        println("      GPU GFLOPS: $(dagger_gflops)")
        println("      Speedup: $(speedup)x")
    end
end

# ============================================================================
# SUMMARY
# ============================================================================
println("\n" * "="^80)
println("SUMMARY - GPU CHOLESKY RESULTS")
println("="^80)
println("dtype,size,block_size,cpu_time,gpu_time,cpu_gflops,gpu_gflops,speedup")
for r in all_results
    println("$(r.dtype),$(r.size),$(r.block_size),$(r.cpu_time),$(r.gpu_time),$(r.cpu_gflops),$(r.gpu_gflops),$(r.speedup)")
end

println("\nEnd time: ", now())
