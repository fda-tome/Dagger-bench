# Use local Dagger.jl
import Pkg
Pkg.develop(path="/flare/dagger/paper/Dagger.jl")

using Distributed
using Dates
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

demo_results = []

# ============================================================================
# CONFIGURATION
# ============================================================================
SCRIPT_DIR = @__DIR__
DEMOS_DIR = joinpath(dirname(SCRIPT_DIR), "demos")
SEAM_DIR = joinpath(DEMOS_DIR, "real-world", "seam")

# Strong scaling: Fixed image size, varying workers
SEAM_ROWS = parse(Int, get(ENV, "SEAM_ROWS", "4096"))
SEAM_COLS = parse(Int, get(ENV, "SEAM_COLS", "4096"))

# Block size for distribution (larger = fewer tasks, less overhead)
SEAM_BASE = parse(Int, get(ENV, "SEAM_BLOCK_BASE", "512"))

# Assignment strategy for distributed arrays
SEAM_ASSIGNMENT = Symbol(get(ENV, "SEAM_ASSIGNMENT", "blockcol"))

# Number of samples for benchmarking
NUM_SAMPLES = parse(Int, get(ENV, "NUM_SAMPLES", "3"))

# ============================================================================
# SEAM CARVING STRONG SCALING BENCHMARK (DISTRIBUTED)
# ============================================================================
println("\n" * "="^80)
println("SEAM CARVING STRONG SCALING BENCHMARK (DISTRIBUTED)")
println("="^80)
println("Start time: ", now())
println("Configuration:")
println("  Fixed image size: $(SEAM_ROWS) x $(SEAM_COLS)")
println("  Total pixels: $(SEAM_ROWS * SEAM_COLS)")
println("  Block base: $(SEAM_BASE)")
println("  Assignment: $(SEAM_ASSIGNMENT)")
println("  Samples: $(NUM_SAMPLES)")

# Get target workers from environment (set by bash script)
target_workers = parse(Int, get(ENV, "TARGET_WORKERS", "1"))
println("  Target workers: $(target_workers)")

# ============================================================================
# SETUP WORKERS
# ============================================================================
println("\nSetting up $(target_workers) workers...")

# Add workers
if target_workers > 1
    pool = addprocs(target_workers, exeflags="--project=$(Base.current_project())")
    
    @everywhere pool begin
        using Dagger, LinearAlgebra, Random, Logging, DataFrames
        disable_logging(LogLevel(2999))
    end
else
    pool = Int[]
end

using Dagger, LinearAlgebra, Random, Logging, DataFrames

# ============================================================================
# INCLUDE DEMO CODE (after workers are set up)
# ============================================================================
include(joinpath(SEAM_DIR, "par_seam.jl"))
include(joinpath(SEAM_DIR, "seq_seam.jl"))

# Register workers with Dagger
ctx = Dagger.Sch.eager_context()
if !isempty(pool)
    Dagger.addprocs!(ctx, pool)
end

println("Workers active: ", nworkers())
println("Dagger processors: ", Dagger.num_processors())

# ============================================================================
# BENCHMARK FUNCTION
# ============================================================================
function run_seam_carving_benchmark(rows::Int, cols::Int, base::Int, assignment::Symbol; num_samples::Int=3)
    println("\n" * "="^60)
    println("SEAM CARVING BENCHMARK")
    println("  Image size: $(rows)x$(cols)")
    println("  Block base: $(base), sheight: $(Int(base/2 + 1))")
    println("  Assignment: $(assignment)")
    println("  Workers: $(nworkers())")
    println("="^60)
    
    # Generate synthetic energy map
    energy = rand(Float64, rows, cols)
    
    # Sequential reference (only run once - it's deterministic)
    println("  Running sequential version...")
    seq_result = @timed find_vertical_seam(energy)
    seq_time = seq_result.time
    println("  Sequential: $(seq_time) seconds")
    
    # Parallel version - multiple samples
    println("  Running parallel version ($(num_samples) samples)...")
    par_times = Float64[]
    
    for sample in 1:num_samples
        # Fresh distribution for each sample
        sheight = Int(base / 2 + 1)
        cost = distribute(energy, Blocks(sheight, base), assignment)
        backtrack = zeros(Blocks(sheight, base), Int, rows, cols; assignment)
        
        par_result = @timed par_find_vseam(base, cost, backtrack)
        push!(par_times, par_result.time)
        println("    Sample $sample: $(par_result.time) seconds")
    end
    
    # Statistics
    par_median = length(par_times) > 0 ? median(par_times) : NaN
    par_mean = length(par_times) > 0 ? mean(par_times) : NaN
    par_std = length(par_times) > 1 ? std(par_times) : 0.0
    par_min = length(par_times) > 0 ? minimum(par_times) : NaN
    par_max = length(par_times) > 0 ? maximum(par_times) : NaN
    
    speedup = seq_time / par_median
    
    println("\n  Results:")
    println("    Sequential: $(seq_time) seconds")
    println("    Parallel median: $(par_median) seconds")
    println("    Parallel mean: $(par_mean) ± $(par_std) seconds")
    println("    Speedup: $(speedup)x")

    return (
        benchmark = "seam_carving_strong",
        rows = rows,
        cols = cols,
        pixels = rows * cols,
        base = base,
        assignment = assignment,
        seq_time = seq_time,
        par_time = par_median,
        par_mean = par_mean,
        par_std = par_std,
        par_min = par_min,
        par_max = par_max,
        speedup = speedup,
        workers = nworkers(),
        num_samples = num_samples
    )
end

# ============================================================================
# RUN BENCHMARK
# ============================================================================
println("\n" * "-"^80)
println("STRONG SCALING: $(target_workers) workers, fixed image $(SEAM_ROWS)x$(SEAM_COLS)")
println("  Total pixels: $(SEAM_ROWS * SEAM_COLS)")
println("  Pixels per worker: $(SEAM_ROWS * SEAM_COLS / max(1, target_workers))")
println("-"^80)

result = run_seam_carving_benchmark(SEAM_ROWS, SEAM_COLS, SEAM_BASE, SEAM_ASSIGNMENT; num_samples=NUM_SAMPLES)
push!(demo_results, result)

# ============================================================================
# SUMMARY STATISTICS
# ============================================================================
println("\n" * "="^80)
println("SUMMARY - SEAM CARVING STRONG SCALING RESULTS")
println("="^80)
for r in demo_results
    println("SEAM_CARVING_STRONG, workers=$(r.workers), size=$(r.rows)x$(r.cols), pixels=$(r.pixels), base=$(r.base), seq=$(r.seq_time)s, par=$(r.par_time)s, speedup=$(r.speedup)x")
end

# Output CSV line for easy parsing by bash script
r = result
println("\nCSV_OUTPUT:$(r.workers),$(r.rows),$(r.cols),$(r.pixels),$(r.base),$(r.seq_time),$(r.par_time),$(r.par_mean),$(r.par_std),$(r.speedup)")

println("\nEnd time: ", now())
