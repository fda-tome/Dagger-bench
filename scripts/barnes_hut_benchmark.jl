# Use local Dagger.jl
import Pkg
Pkg.develop(path="/flare/dagger/paper/Dagger.jl")

using Dates, BenchmarkTools, Statistics
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

demo_results = []

# ============================================================================
# CONFIGURATION
# ============================================================================
SCRIPT_DIR = @__DIR__
DEMOS_DIR = joinpath(dirname(SCRIPT_DIR), "demos")

# Random seeds for multiple tree configurations (mitigates tree imbalance)
RANDOM_SEEDS = [1234, 5678, 9012, 3456, 7890]

# ============================================================================
# BARNES-HUT BENCHMARK (THREADS ONLY)
# ============================================================================
println("\n" * "="^80)
println("BARNES-HUT BENCHMARK (THREAD-BASED)")
println("="^80)
println("Start time: ", now())
println("Available threads: ", Threads.nthreads())

# Include Barnes-Hut demo on main process only (thread-based)
include(joinpath(DEMOS_DIR, "advanced", "barnes", "barnes-hut.jl"))

# Barnes-Hut uses Dagger's thread processors, not distributed workers
using Dagger, LinearAlgebra, Random, Test, Logging, Plots, DataFrames

function run_barnes_hut_benchmark(N::Int, theta::Float64, num_threads::Int; seeds=RANDOM_SEEDS)
    println("\n" * "="^60)
    println("BARNES-HUT N-BODY BENCHMARK (FORCE CALCULATION ONLY)")
    println("  N=$N particles, theta=$theta, threads=$num_threads")
    println("  Testing $(length(seeds)) different tree configurations")
    println("="^60)
    
    all_times = Float64[]
    
    for (i, seed) in enumerate(seeds)
        println("\n  --- Tree configuration $i (seed=$seed) ---")
        
        # Set seed for reproducible tree structure
        Random.seed!(seed)
        
        # Build tree with this seed (not timed)
        println("  Building tree...")
        result_tuple = bmark(N, theta)
        rootp = result_tuple[1]
        points = result_tuple[2]
        theta_val = result_tuple[3]
        println("  Tree built.")
        
        # Warmup run (compile) - only needed on first iteration
        if i == 1
            println("  Warmup run...")
            bmark_force_only(rootp, points, theta_val)
        end
        
        # Benchmark this tree configuration
        println("  Running benchmark...")
        bench_result = @benchmark bmark_force_only($rootp, $points, $theta_val) samples=5 evals=1
        
        # Collect median time for this configuration
        config_median = median(bench_result.times) / 1e9
        push!(all_times, config_median)
        println("  Config $i median: $(config_median) seconds")
    end
    
    # Aggregate statistics across all tree configurations
    overall_median = median(all_times)
    overall_mean = mean(all_times)
    overall_std = std(all_times)
    overall_min = minimum(all_times)
    overall_max = maximum(all_times)
    
    println("\n  " * "-"^50)
    println("  AGGREGATE RESULTS (across $(length(seeds)) tree configs):")
    println("  Median: $(overall_median) seconds")
    println("  Mean:   $(overall_mean) ± $(overall_std) seconds")
    println("  Min:    $(overall_min) seconds")
    println("  Max:    $(overall_max) seconds")
    println("  " * "-"^50)
    
    return (
        benchmark = "barnes_hut",
        N = N,
        theta = theta,
        par_time = overall_median,
        mean_time = overall_mean,
        std_time = overall_std,
        min_time = overall_min,
        max_time = overall_max,
        threads = num_threads,
        num_configs = length(seeds)
    )
end

# Run Barnes-Hut with current thread count
target_threads = Threads.nthreads()
barnes_N = 10000 * target_threads  # Weak scaling: more particles with more threads
barnes_theta = 0.05

println("\n" * "-"^80)
println("BARNES-HUT: $target_threads threads, N=$barnes_N")
println("-"^80)

barnes_result = run_barnes_hut_benchmark(barnes_N, barnes_theta, target_threads)
push!(demo_results, barnes_result)

# ============================================================================
# SUMMARY STATISTICS
# ============================================================================
println("\n" * "="^80)
println("SUMMARY - BARNES-HUT RESULTS")
println("="^80)
for result in demo_results
    println("BARNES_HUT, threads=$(result.threads), N=$(result.N), theta=$(result.theta)")
    println("  Median: $(result.par_time)s, Mean: $(result.mean_time)s ± $(result.std_time)s")
    println("  Min: $(result.min_time)s, Max: $(result.max_time)s")
    println("  Tree configs tested: $(result.num_configs)")
end

# Output CSV line for easy parsing by bash script (using median time)
println("\nCSV_OUTPUT:$(barnes_result.threads),$(barnes_result.N),$(barnes_result.theta),$(barnes_result.par_time)")

println("\nEnd time: ", now())
