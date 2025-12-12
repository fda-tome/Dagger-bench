# Use local Dagger.jl
import Pkg
Pkg.develop(path="/flare/dagger/paper/Dagger.jl")

using Dates
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

# ============================================================================
# GPU CHOLESKY BENCHMARK (AMD GPUs via AMDGPU/ROCm)
# ============================================================================
println("\n" * "="^80)
println("CHOLESKY GPU BENCHMARK (AMD ROCm)")
println("="^80)
println("Start time: ", now())

# Load AMDGPU for AMD GPUs
using AMDGPU
using Dagger
using LinearAlgebra
using Random
using Statistics

# Check GPU availability
println("\nGPU Information:")
println("  AMDGPU functional: ", AMDGPU.functional())
if AMDGPU.functional()
    println("  ROCm version: ", AMDGPU.runtime_version())
    agents = AMDGPU.agents()
    gpu_agents = filter(a -> AMDGPU.device_type(a) == :gpu, agents)
    println("  Number of GPU agents: ", length(gpu_agents))
    for (i, agent) in enumerate(gpu_agents)
        println("    Device $i: ", AMDGPU.get_name(agent))
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
    A = AMDGPU.rand(T, n, n)
    A = A * A'
    # Add to diagonal to ensure positive definiteness
    A[diagind(A)] .+= n
    AMDGPU.synchronize()
    return A
end

function benchmark_cpu_cholesky(A::Matrix{T}) where T
    A_copy = copy(A)
    result = @timed cholesky!(A_copy)
    return result.time
end

function benchmark_gpu_cholesky_direct(A_cpu::Matrix{T}) where T
    # Direct GPU Cholesky using AMDGPU's built-in implementation
    A_gpu = ROCArray(A_cpu)
    AMDGPU.synchronize()
    
    result = @timed begin
        cholesky!(A_gpu)
        AMDGPU.synchronize()
    end
    
    return result.time
end

function benchmark_gpu_cholesky_dagger(A_gpu::ROCArray{T}, block_size::Int) where T
    n = size(A_gpu, 1)
    
    # Use Dagger with GPU scope - this is the KEY for GPU execution
    Dagger.with_options(scope=Dagger.scope(rocm_gpus=:)) do
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
        
        # Direct GPU Cholesky (ROCm native)
        println("    Direct GPU Cholesky (ROCm native)...")
        direct_times = Float64[]
        for i in 1:(NUM_WARMUP + NUM_RUNS)
            t = benchmark_gpu_cholesky_direct(A_cpu)
            if i > NUM_WARMUP
                push!(direct_times, t)
            end
        end
        direct_median = length(direct_times) > 0 ? median(direct_times) : NaN
        println("      Time: $(direct_median) s")
        
        # GPU Dagger Cholesky - create GPU array and use GPU scope
        println("    Dagger GPU Cholesky (block_size=$BLOCK_SIZE)...")
        dagger_times = Float64[]
        for i in 1:(NUM_WARMUP + NUM_RUNS)
            # Create fresh GPU array for each run (Cholesky modifies in-place)
            A_gpu = ROCArray(A_cpu)
            AMDGPU.synchronize()
            
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
        direct_gflops = flops / (direct_median * 1e9)
        dagger_gflops = flops / (dagger_median * 1e9)
        speedup_direct = cpu_median / direct_median
        speedup_dagger = cpu_median / dagger_median
        
        result = (
            dtype = T,
            size = n,
            block_size = BLOCK_SIZE,
            cpu_time = cpu_median,
            direct_gpu_time = direct_median,
            dagger_gpu_time = dagger_median,
            cpu_gflops = cpu_gflops,
            direct_gflops = direct_gflops,
            dagger_gflops = dagger_gflops,
            speedup_direct = speedup_direct,
            speedup_dagger = speedup_dagger
        )
        push!(all_results, result)
        
        println("      CPU GFLOPS: $(cpu_gflops)")
        println("      Direct GPU GFLOPS: $(direct_gflops)")
        println("      Dagger GPU GFLOPS: $(dagger_gflops)")
        println("      Speedup (Direct): $(speedup_direct)x")
        println("      Speedup (Dagger): $(speedup_dagger)x")
    end
end

# ============================================================================
# SUMMARY
# ============================================================================
println("\n" * "="^80)
println("SUMMARY - AMD GPU CHOLESKY RESULTS")
println("="^80)
println("dtype,size,block_size,cpu_time,direct_gpu_time,dagger_gpu_time,cpu_gflops,direct_gflops,dagger_gflops,speedup_direct,speedup_dagger")
for r in all_results
    println("$(r.dtype),$(r.size),$(r.block_size),$(r.cpu_time),$(r.direct_gpu_time),$(r.dagger_gpu_time),$(r.cpu_gflops),$(r.direct_gflops),$(r.dagger_gflops),$(r.speedup_direct),$(r.speedup_dagger)")
end

println("\nEnd time: ", now())
