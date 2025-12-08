# Barnes-Hut Benchmark with MPI/Dagger Distributed Execution
# Launched via: mpiexec -n NPROCS julia -t 1 barnes_benchmark_mpi.jl

include("benchmark_utils.jl")

using MPIClusterManagers
using Distributed
using Dagger
using LinearAlgebra
using Statistics
using Printf
using Random
using Dates

# Initialize MPI workers for Dagger
# MPIClusterManagers automatically handles worker setup
println("Initializing MPI workers for Dagger...")
manager = MPIManager(np=parse(Int, get(ENV, "OMPI_COMM_WORLD_SIZE", "1")))
addprocs(manager)

# Load required packages on all workers
@everywhere using Dagger
@everywhere using LinearAlgebra
@everywhere using Statistics
@everywhere using Random

# Load Barnes-Hut implementation on all workers
@everywhere include("../../demos/advanced/barnes/barnes-hut.jl")

# Show Dagger processor configuration
println("\nDagger Configuration:")
println("  Number of Julia workers: ", nworkers())
println("  Dagger processors detected: ", length(Dagger.compatible_processors()))
println()

# Include test data generation functions
@everywhere function generate_test_data(N::Int; seed::Int=42)
    Random.seed!(seed)
    points = [rand(3) * 100 for _ in 1:N]
    masses = rand(N) * 10
    bounding_box = [[0.0, 0.0, 0.0], [100.0, 100.0, 100.0]]
    return points, masses, bounding_box
end

# Benchmark functions (same as before, but now workers are MPI-based)
@everywhere function benchmark_barnes_sequential(N::Int, theta::Float64; seed::Int=42)
    points, masses, bounding_box = generate_test_data(N; seed=seed)
    root = buildTree(points, masses, bounding_box)
    forces = Vector{Vector{Float64}}(undef, N)
    for (i, point) in enumerate(points)
        forces[i] = calculateForce(root, point, theta)
    end
    return forces
end

@everywhere function benchmark_barnes_parallel(N::Int, theta::Float64; seed::Int=42)
    points, masses, bounding_box = generate_test_data(N; seed=seed)
    # Dagger auto-distributes work across MPI workers
    root = buildTreeP(points, masses, bounding_box)
    forces = Vector{Vector{Float64}}(undef, N)
    for (i, point) in enumerate(points)
        forces[i] = calculateForceP(root, point, theta)
    end
    return forces
end

"""
Run benchmarks with Dagger's MPI backend
"""
function run_barnes_benchmarks_mpi(;
    N::Int=1000,
    theta::Float64=0.5,
    num_runs::Int=5,
    verify::Bool=false  # Skip verification in MPI mode for simplicity
)
    println("\n" * "="^70)
    println("BARNES-HUT N-BODY BENCHMARK (Dagger MPI)")
    println("="^70)
    println("Number of bodies: $N")
    println("Theta parameter: $theta")
    println("Number of runs: $num_runs")
    println("MPI ranks: ", nworkers())
    println("Dagger processors: ", length(Dagger.compatible_processors()))
    println("="^70)
    
    # Sequential baseline (runs on master)
    println("\n>>> Running SEQUENTIAL baseline on master process...")
    seq_results = run_multiple(
        () -> benchmark_barnes_sequential(N, theta),
        "Sequential Barnes-Hut",
        num_runs;
        num_processors=1,
        metadata=Dict("N" => N, "theta" => theta, "backend" => "single-process")
    )
    seq_stats = compute_stats(seq_results)
    print_stats(seq_stats)
    
    # Parallel via Dagger (distributed across MPI workers)
    println("\n>>> Running PARALLEL via Dagger MPI...")
    nprocs = length(Dagger.compatible_processors())
    
    par_results = run_multiple(
        () -> benchmark_barnes_parallel(N, theta),
        "Parallel Barnes-Hut (Dagger MPI)",
        num_runs;
        num_processors=nprocs,
        metadata=Dict("N" => N, "theta" => theta, "backend" => "Dagger-MPI", "workers" => nworkers())
    )
    par_stats = compute_stats(par_results)
    print_stats(par_stats)
    
    # Compare
    speedup = compare_benchmarks(seq_stats, par_stats)
    efficiency = speedup / nprocs
    
    println("Parallel Efficiency: $(efficiency * 100)% (speedup / num_processors)")
    
    # Export results
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    export_to_csv("barnes_mpi_detailed_$timestamp.csv", [seq_stats, par_stats])
    export_summary_to_csv("barnes_mpi_summary_$timestamp.csv", [seq_stats, par_stats])
    
    return Dict(
        "sequential" => seq_stats,
        "parallel" => par_stats,
        "speedup" => speedup,
        "efficiency" => efficiency,
        "num_processors" => nprocs,
        "mpi_workers" => nworkers()
    )
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    # Parse from environment
    N = parse(Int, get(ENV, "BARNES_N", "1000"))
    theta = parse(Float64, get(ENV, "BARNES_THETA", "0.5"))
    num_runs = parse(Int, get(ENV, "BENCH_RUNS", "5"))
    
    results = run_barnes_benchmarks_mpi(
        N=N,
        theta=theta,
        num_runs=num_runs,
        verify=false
    )
    
    println("\n✓ MPI Benchmark complete!")
    println("\nQuick Summary:")
    println("  MPI workers:          ", results["mpi_workers"])
    println("  Dagger processors:    ", results["num_processors"])
    println("  Sequential mean time: ", mean(results["sequential"].times), " s")
    println("  Parallel mean time:   ", mean(results["parallel"].times), " s")
    println("  Speedup:              ", results["speedup"], "x")
    println("  Efficiency:           ", results["efficiency"] * 100, "%")
end
