# Barnes-Hut N-Body Benchmark - Sequential vs Parallel Comparison
# Run with: julia --project=. barnes_benchmark.jl

include("benchmark_utils.jl")

# Add demo path to load path
push!(LOAD_PATH, joinpath(@__DIR__, "../../demos/advanced/barnes"))

using Dagger
using LinearAlgebra
using Statistics
using Printf
using Random

# Include Barnes-Hut implementation
include("../../demos/advanced/barnes/barnes-hut.jl")

"""
    generate_test_data(N::Int; seed::Int=42)

Generate reproducible test data for N-body simulation.
"""
function generate_test_data(N::Int; seed::Int=42)
    Random.seed!(seed)
    points = [rand(3) * 100 for _ in 1:N]
    masses = rand(N) * 10
    bounding_box = [[0.0, 0.0, 0.0], [100.0, 100.0, 100.0]]
    return points, masses, bounding_box
end

"""
    benchmark_barnes_sequential(N::Int, theta::Float64)

Benchmark sequential Barnes-Hut implementation.
"""
function benchmark_barnes_sequential(N::Int, theta::Float64; seed::Int=42)
    points, masses, bounding_box = generate_test_data(N; seed=seed)
    
    # Build tree
    root = buildTree(points, masses, bounding_box)
    
    # Calculate forces for all points
    forces = Vector{Vector{Float64}}(undef, N)
    for (i, point) in enumerate(points)
        forces[i] = calculateForce(root, point, theta)
    end
    
    return forces
end

"""
    benchmark_barnes_parallel(N::Int, theta::Float64)

Benchmark parallel Barnes-Hut implementation.
"""
function benchmark_barnes_parallel(N::Int, theta::Float64; seed::Int=42)
    points, masses, bounding_box = generate_test_data(N; seed=seed)
    
    # Build tree in parallel
    root = buildTreeP(points, masses, bounding_box)
    
    # Calculate forces for all points in parallel
    forces = Vector{Vector{Float64}}(undef, N)
    for (i, point) in enumerate(points)
        forces[i] = calculateForceP(root, point, theta)
    end
    
    return forces
end

"""
    verify_correctness(N::Int, theta::Float64)

Verify that parallel and sequential implementations produce similar results.
"""
function verify_correctness(N::Int, theta::Float64; tolerance::Float64=1e-6)
    println("\n>>> Verifying correctness...")
    
    points, masses, bounding_box = generate_test_data(N)
    
    # Sequential
    root_seq = buildTree(points, masses, bounding_box)
    force_seq = calculateForce(root_seq, points[1], theta)
    
    # Parallel
    root_par = buildTreeP(points, masses, bounding_box)
    force_par = calculateForceP(root_par, points[1], theta)
    
    # Compare
    diff = norm(force_seq - force_par)
    println("  Force difference (L2 norm): $diff")
    
    if diff < tolerance
        println("  ✓ Results match within tolerance")
        return true
    else
        println("  ✗ Results differ by more than tolerance ($tolerance)")
        return false
    end
end

"""
    run_barnes_benchmarks(;N=1000, theta=0.5, num_runs=5, verify=true)

Run comprehensive Barnes-Hut benchmarks.
"""
function run_barnes_benchmarks(;
    N::Int=1000,
    theta::Float64=0.5,
    num_runs::Int=5,
    verify::Bool=true
)
    println("\n" * "="^70)
    println("BARNES-HUT N-BODY BENCHMARK")
    println("="^70)
    println("Number of bodies: $N")
    println("Theta parameter: $theta")
    println("Number of runs: $num_runs")
    println("="^70)
    
    # Verify correctness first
    if verify
        is_correct = verify_correctness(N, theta)
        if !is_correct
            @warn "Correctness verification failed - results may differ"
        end
    end
    
    # Sequential benchmark
    println("\n>>> Running SEQUENTIAL benchmarks...")
    seq_results = run_multiple(
        () -> benchmark_barnes_sequential(N, theta),
        "Sequential Barnes-Hut",
        num_runs;
        num_processors=1,
        metadata=Dict("N" => N, "theta" => theta, "algorithm" => "Barnes-Hut")
    )
    seq_stats = compute_stats(seq_results)
    print_stats(seq_stats)
    
    # Parallel benchmark
    println("\n>>> Running PARALLEL benchmarks...")
    nprocs = length(Dagger.compatible_processors())
    println("Available processors: $nprocs")
    
    par_results = run_multiple(
        () -> benchmark_barnes_parallel(N, theta),
        "Parallel Barnes-Hut",
        num_runs;
        num_processors=nprocs,
        metadata=Dict("N" => N, "theta" => theta, "algorithm" => "Barnes-Hut")
    )
    par_stats = compute_stats(par_results)
    print_stats(par_stats)
    
    # Compare results
    speedup = compare_benchmarks(seq_stats, par_stats)
    
    # Compute efficiency
    efficiency = speedup / nprocs
    println("Parallel Efficiency: $(efficiency * 100)% (speedup / num_processors)")
    
    # Export results
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    export_to_csv("barnes_benchmark_detailed_$timestamp.csv", [seq_stats, par_stats])
    export_summary_to_csv("barnes_benchmark_summary_$timestamp.csv", [seq_stats, par_stats])
    
    return Dict(
        "sequential" => seq_stats,
        "parallel" => par_stats,
        "speedup" => speedup,
        "efficiency" => efficiency,
        "num_processors" => nprocs
    )
end

"""
    run_scaling_study(;N_values=[100, 500, 1000, 2000, 5000], theta=0.5, num_runs=3)

Study how performance scales with problem size.
"""
function run_scaling_study(;
    N_values::Vector{Int}=[100, 500, 1000, 2000, 5000],
    theta::Float64=0.5,
    num_runs::Int=3
)
    println("\n" * "="^70)
    println("BARNES-HUT SCALING STUDY")
    println("="^70)
    println("Problem sizes: $N_values")
    println("Runs per size: $num_runs")
    println("="^70)
    
    results = []
    
    for N in N_values
        println("\n\n>>> Testing N=$N...")
        
        # Sequential
        seq_results = run_multiple(
            () -> benchmark_barnes_sequential(N, theta),
            "Sequential N=$N",
            num_runs;
            metadata=Dict("N" => N, "theta" => theta)
        )
        seq_stats = compute_stats(seq_results)
        
        # Parallel
        par_results = run_multiple(
            () -> benchmark_barnes_parallel(N, theta),
            "Parallel N=$N",
            num_runs;
            metadata=Dict("N" => N, "theta" => theta)
        )
        par_stats = compute_stats(par_results)
        
        speedup = mean(seq_stats.times) / mean(par_stats.times)
        
        push!(results, Dict(
            "N" => N,
            "seq_time" => mean(seq_stats.times),
            "par_time" => mean(par_stats.times),
            "speedup" => speedup
        ))
        
        println(@sprintf "  N=%5d: Seq=%.4fs, Par=%.4fs, Speedup=%.2fx", 
                N, mean(seq_stats.times), mean(par_stats.times), speedup)
    end
    
    # Export scaling results
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    open("barnes_scaling_$timestamp.csv", "w") do io
        println(io, "N,seq_time_sec,par_time_sec,speedup")
        for r in results
            println(io, "$(r["N"]),$(r["seq_time"]),$(r["par_time"]),$(r["speedup"])")
        end
    end
    println("\nScaling results exported to: barnes_scaling_$timestamp.csv")
    
    return results
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    using Dates
    
    # Parse command line arguments or use defaults
    N = parse(Int, get(ENV, "BARNES_N", "1000"))
    theta = parse(Float64, get(ENV, "BARNES_THETA", "0.5"))
    num_runs = parse(Int, get(ENV, "BENCH_RUNS", "5"))
    run_scaling = get(ENV, "RUN_SCALING", "false") == "true"
    
    if run_scaling
        println("\n🚀 Running scaling study...")
        scaling_results = run_scaling_study(num_runs=num_runs)
        
        println("\n\nScaling Summary:")
        println("="^70)
        for r in scaling_results
            println(@sprintf "N=%5d: %.2fx speedup", r["N"], r["speedup"])
        end
    else
        results = run_barnes_benchmarks(
            N=N,
            theta=theta,
            num_runs=num_runs,
            verify=true
        )
        
        println("\n✓ Benchmark complete!")
        println("\nQuick Summary:")
        println("  Sequential mean time: $(mean(results["sequential"].times)) s")
        println("  Parallel mean time:   $(mean(results["parallel"].times)) s")
        println("  Speedup:              $(results["speedup"])x")
        println("  Efficiency:           $(results["efficiency"] * 100)%")
    end
end
