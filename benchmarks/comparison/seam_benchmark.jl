# Seam Carving Benchmark - Sequential vs Parallel Comparison
# Run with: julia --project=. seam_benchmark.jl

include("benchmark_utils.jl")

# Add demo paths to load path
push!(LOAD_PATH, joinpath(@__DIR__, "../../demos/real-world/seam"))

using Dagger
using Images
using FileIO
using ImageFiltering
using Statistics
using Printf

# Load seam carving functions
include("../../demos/real-world/seam/seq_seam.jl")
# Note: par_seam.jl defines its own main(), so we'll include functions selectively

# Inline key parallel functions from par_seam.jl
function load_color_image(path)
    img = load(path)
    return RGB.(img)
end

function energy_map(img)
    rgb = RGB.(img)
    rows, cols = size(rgb)
    chs = channelview(rgb)
    kx = [-1 0 1; -2 0 2; -1 0 1] ./ 8
    ky = [-1 -2 -1; 0 0 0; 1 2 1] ./ 8
    energy = zeros(Float32, rows, cols)
    @inbounds for c in 1:size(chs, 1)
        chan = Float32.(view(chs, c, :, :))
        gx = imfilter(chan, kx)
        gy = imfilter(chan, ky)
        energy .+= abs.(gx) .+ abs.(gy)
    end
    return energy
end

function find_vertical_seam(energy)
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

function remove_vertical_seam(img, seam)
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

"""
    benchmark_sequential_seam(img_path::String, num_seams::Int)

Benchmark the sequential seam carving implementation.
"""
function benchmark_sequential_seam(img_path::String, num_seams::Int)
    img = load_color_image(img_path)
    carved = transpose(img)
    
    # Clamp to available columns
    num_seams = min(num_seams, size(carved, 2) - 1)
    
    for i in 1:num_seams
        e = energy_map(carved)
        seam = find_vertical_seam(e)
        carved = remove_vertical_seam(carved, seam)
    end
    
    return carved
end

"""
    benchmark_parallel_seam(img_path::String, num_seams::Int, base::Int, assignment::Symbol)

Benchmark parallel seam carving with specified parameters.
Note: This is a simplified version - full parallel implementation requires more complex setup.
"""
function benchmark_parallel_seam_simple(img_path::String, num_seams::Int)
    # For now, just benchmark the sequential version with Dagger overhead
    # A full parallel benchmark would require the complete par_seam.jl implementation
    img = load_color_image(img_path)
    carved = transpose(img)
    num_seams = min(num_seams, size(carved, 2) - 1)
    
    # Using simple Dagger task spawning
    for i in 1:num_seams
        e = energy_map(carved)
        # Spawn seam finding as a task
        seam_task = Dagger.@spawn find_vertical_seam(e)
        seam = fetch(seam_task)
        carved = remove_vertical_seam(carved, seam)
    end
    
    return carved
end

"""
    run_seam_benchmarks(;img_path="mirage.jpg", num_seams=10, num_runs=3)

Run comprehensive seam carving benchmarks comparing sequential and parallel.
"""
function run_seam_benchmarks(;
    img_path::String="../../demos/real-world/seam/mirage.jpg",
    num_seams::Int=10,
    num_runs::Int=3
)
    println("\n" * "="^70)
    println("SEAM CARVING BENCHMARK")
    println("="^70)
    println("Image: $img_path")
    println("Seams to remove: $num_seams")
    println("Number of runs: $num_runs")
    println("="^70)
    
    # Check if image exists
    if !isfile(img_path)
        error("Image file not found: $img_path")
    end
    
    # Get image dimensions
    img = load_color_image(img_path)
    rows, cols = size(img)
    println("\nImage dimensions: $(rows)x$(cols)")
    
    # Sequential benchmark
    println("\n>>> Running SEQUENTIAL benchmarks...")
    seq_results = run_multiple(
        () -> benchmark_sequential_seam(img_path, num_seams),
        "Sequential Seam Carving",
        num_runs;
        num_processors=1,
        metadata=Dict("num_seams" => num_seams, "image_size" => "$(rows)x$(cols)")
    )
    seq_stats = compute_stats(seq_results)
    print_stats(seq_stats)
    
    # Parallel benchmark (simplified)
    println("\n>>> Running PARALLEL benchmarks...")
    nprocs = length(Dagger.compatible_processors())
    println("Available processors: $nprocs")
    
    par_results = run_multiple(
        () -> benchmark_parallel_seam_simple(img_path, num_seams),
        "Parallel Seam Carving (Simple)",
        num_runs;
        num_processors=nprocs,
        metadata=Dict("num_seams" => num_seams, "image_size" => "$(rows)x$(cols)")
    )
    par_stats = compute_stats(par_results)
    print_stats(par_stats)
    
    # Compare results
    speedup = compare_benchmarks(seq_stats, par_stats)
    
    # Export results
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    export_to_csv("seam_benchmark_detailed_$timestamp.csv", [seq_stats, par_stats])
    export_summary_to_csv("seam_benchmark_summary_$timestamp.csv", [seq_stats, par_stats])
    
    return Dict(
        "sequential" => seq_stats,
        "parallel" => par_stats,
        "speedup" => speedup
    )
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    using Dates
    
    # Parse command line arguments or use defaults
    img_path = get(ENV, "SEAM_IMG", "../../demos/real-world/seam/mirage.jpg")
    num_seams = parse(Int, get(ENV, "SEAM_COUNT", "10"))
    num_runs = parse(Int, get(ENV, "BENCH_RUNS", "3"))
    
    results = run_seam_benchmarks(
        img_path=img_path,
        num_seams=num_seams,
        num_runs=num_runs
    )
    
    println("\n✓ Benchmark complete!")
    println("\nQuick Summary:")
    println("  Sequential mean time: $(mean(results["sequential"].times)) s")
    println("  Parallel mean time:   $(mean(results["parallel"].times)) s")
    println("  Speedup:              $(results["speedup"])x")
end
