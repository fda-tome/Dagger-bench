# Seam Carving Benchmark with MPI/Dagger Distributed Execution
# Launched via: mpiexec -n NPROCS julia -t 1 seam_benchmark_mpi.jl

include("benchmark_utils.jl")

using MPIClusterManagers
using Distributed
using Dagger
using Images
using FileIO
using ImageFiltering
using Statistics
using Printf
using Dates

# Initialize MPI workers for Dagger
println("Initializing MPI workers for Dagger...")
manager = MPIManager(np=parse(Int, get(ENV, "OMPI_COMM_WORLD_SIZE", "1")))
addprocs(manager)

# Load packages on all workers
@everywhere using Dagger
@everywhere using Images
@everywhere using FileIO
@everywhere using ImageFiltering

println("\nDagger Configuration:")
println("  Julia workers: ", nworkers())
println("  Dagger processors: ", length(Dagger.compatible_processors()))
println()

# Load functions on all workers
@everywhere function load_color_image(path)
    img = load(path)
    return RGB.(img)
end

@everywhere function energy_map(img)
    rgb = RGB.(img)
    rows, cols = size(rgb)
    chs = channelview(rgb)
    kx = [-1 0 1; -2 0 2; -1 0 1] ./ 8
    ky = [-1 -2 -1; 0 0 0; 1 2 1] ./ 8
    energy = zeros(Float32, rows, cols)
    @inbounds for c in 1:size(chs, 1)
        chan = Float32.(view(chs, c, :, :))
        gx = imfilter(chan, kx)
        gy = imfilter(chan, gy)
        energy .+= abs.(gx) .+ abs.(gy)
    end
    return energy
end

@everywhere function find_vertical_seam(energy)
    rows, cols = size(energy)
    cost = copy(energy)
    backtrack = zeros(Int, size(energy))
    for i in 2:rows
        for j in 1:cols
            left = j > 1 ? cost[i-1, j-1] : Inf
            up = cost[i-1, j]
            right = j < cols ? cost[i-1, j+1] : Inf
            min_val, idx = findmin([left, up, right])
            cost[i, j] += min_val
            backtrack[i, j] = j + (idx - 2)
        end
    end
    seam = zeros(Int, rows)
    seam[rows] = argmin(vec(@view cost[rows, :]))
    for i in rows-1:-1:1
        seam[i] = backtrack[i+1, seam[i+1]]
    end
    return seam
end

@everywhere function remove_vertical_seam(img, seam)
    rows, cols = size(img)
    out = similar(img, rows, cols - 1)
    for i in 1:rows
        j = seam[i]
        if j > 1
            @inbounds out[i, 1:j-1] = img[i, 1:j-1]
        end
        if j <= cols - 1
            @inbounds out[i, j:cols-1] = img[i, j+1:cols]
        end
    end
    return out
end

# Sequential version
function benchmark_sequential_seam(img_path::String, num_seams::Int)
    img = load_color_image(img_path)
    carved = transpose(img)
    num_seams = min(num_seams, size(carved, 2) - 1)
    
    for i in 1:num_seams
        e = energy_map(carved)
        seam = find_vertical_seam(e)
        carved = remove_vertical_seam(carved, seam)
    end
    
    return carved
end

# Parallel version using Dagger tasks
# Note: Real parallel seam requires the full par_seam.jl implementation
# This is a simplified version showing Dagger task usage
function benchmark_parallel_seam_dagger(img_path::String, num_seams::Int)
    img = load_color_image(img_path)
    carved = transpose(img)
    num_seams = min(num_seams, size(carved, 2) - 1)
    
    # Use Dagger tasks for parallel execution
    for i in 1:num_seams
        e = energy_map(carved)
        # Spawn seam finding as Dagger task (distributed automatically)
        seam_task = Dagger.@spawn find_vertical_seam(e)
        seam = fetch(seam_task)
        carved = remove_vertical_seam(carved, seam)
    end
    
    return carved
end

function run_seam_benchmarks_mpi(;
    img_path::String="../../demos/real-world/seam/mirage.jpg",
    num_seams::Int=10,
    num_runs::Int=3
)
    println("\n" * "="^70)
    println("SEAM CARVING BENCHMARK (Dagger MPI)")
    println("="^70)
    println("Image: $img_path")
    println("Seams to remove: $num_seams")
    println("Number of runs: $num_runs")
    println("MPI workers: ", nworkers())
    println("Dagger processors: ", length(Dagger.compatible_processors()))
    println("="^70)
    
    if !isfile(img_path)
        error("Image file not found: $img_path")
    end
    
    img = load_color_image(img_path)
    rows, cols = size(img)
    println("\nImage dimensions: $(rows)x$(cols)")
    
    # Sequential
    println("\n>>> Running SEQUENTIAL benchmarks...")
    seq_results = run_multiple(
        () -> benchmark_sequential_seam(img_path, num_seams),
        "Sequential Seam Carving",
        num_runs;
        num_processors=1,
        metadata=Dict("num_seams" => num_seams, "image_size" => "$(rows)x$(cols)", "backend" => "single-process")
    )
    seq_stats = compute_stats(seq_results)
    print_stats(seq_stats)
    
    # Parallel via Dagger MPI
    println("\n>>> Running PARALLEL benchmarks via Dagger MPI...")
    nprocs = length(Dagger.compatible_processors())
    
    par_results = run_multiple(
        () -> benchmark_parallel_seam_dagger(img_path, num_seams),
        "Parallel Seam Carving (Dagger MPI)",
        num_runs;
        num_processors=nprocs,
        metadata=Dict("num_seams" => num_seams, "image_size" => "$(rows)x$(cols)", "backend" => "Dagger-MPI")
    )
    par_stats = compute_stats(par_results)
    print_stats(par_stats)
    
    # Compare
    speedup = compare_benchmarks(seq_stats, par_stats)
    
    # Export
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    export_to_csv("seam_mpi_detailed_$timestamp.csv", [seq_stats, par_stats])
    export_summary_to_csv("seam_mpi_summary_$timestamp.csv", [seq_stats, par_stats])
    
    return Dict(
        "sequential" => seq_stats,
        "parallel" => par_stats,
        "speedup" => speedup,
        "mpi_workers" => nworkers()
    )
end

# Main
if abspath(PROGRAM_FILE) == @__FILE__
    img_path = get(ENV, "SEAM_IMG", "../../demos/real-world/seam/mirage.jpg")
    num_seams = parse(Int, get(ENV, "SEAM_COUNT", "10"))
    num_runs = parse(Int, get(ENV, "BENCH_RUNS", "3"))
    
    results = run_seam_benchmarks_mpi(
        img_path=img_path,
        num_seams=num_seams,
        num_runs=num_runs
    )
    
    println("\n✓ MPI Benchmark complete!")
    println("\nQuick Summary:")
    println("  MPI workers:        ", results["mpi_workers"])
    println("  Sequential time:    ", mean(results["sequential"].times), " s")
    println("  Parallel time:      ", mean(results["parallel"].times), " s")
    println("  Speedup:            ", results["speedup"], "x")
end
