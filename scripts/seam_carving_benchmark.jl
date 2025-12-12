using Distributed
using Dates
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

demo_results = []

# ============================================================================
# CONFIGURATION
# ============================================================================
number_of_processes = [2, 4, 8, 16, 32, 64]  # Full scale run
SCRIPT_DIR = @__DIR__
DEMOS_DIR = joinpath(dirname(SCRIPT_DIR), "demos")
SEAM_DIR = joinpath(DEMOS_DIR, "real-world", "seam")

# ============================================================================
# INITIAL SETUP - First worker pool
# ============================================================================
pool = addprocs(1, exeflags="--project=$(Base.current_project())")
@everywhere pool begin
    using Dagger, LinearAlgebra, Random, Test, Logging, Plots, DataFrames
    disable_logging(LogLevel(2999))
end

using Dagger, LinearAlgebra, Random, Test, Logging, Plots, DataFrames

# ============================================================================
# INCLUDE DEMO CODE
# ============================================================================
include(joinpath(SEAM_DIR, "par_seam.jl"))
include(joinpath(SEAM_DIR, "seq_seam.jl"))

# ============================================================================
# BENCHMARK FUNCTION
# ============================================================================
function run_seam_carving_benchmark(rows::Int, cols::Int, base::Int, assignment::Symbol)
    println("\n" * "="^60)
    println("SEAM CARVING BENCHMARK")
    println("  Image size: $(rows)x$(cols), base=$base, assignment=$assignment")
    println("="^60)
    
    # Generate synthetic energy map (simulates energy_map output without needing an image)
    energy = rand(Float64, rows, cols)
    
    # Sequential version - use find_vertical_seam from seq_seam.jl
    seq_result = @timed find_vertical_seam(energy)
    println("  Sequential: $(seq_result.time) seconds")
    
    # Parallel version - use par_find_vseam from par_seam.jl
    par_time = NaN
    speedup = NaN
    sheight = Int(base / 2 + 1)
    cost = distribute(energy, Blocks(sheight, base), assignment)
    backtrack = zeros(Blocks(sheight, base), Int, rows, cols; assignment)
    par_result = @timed parallel_find_vertical_seam(base, cost, backtrack)
    par_time = par_result.time
    println("  Parallel:   $(par_time) seconds")
    speedup = seq_result.time / par_time
    println("  Speedup:    $(speedup)x")

    return (
        benchmark = "seam_carving",
        rows = rows,
        cols = cols,
        base = base,
        assignment = assignment,
        seq_time = seq_result.time,
        par_time = par_time,
        speedup = speedup,
        workers = nworkers()
    )
end

# ============================================================================
# DISTRIBUTED BENCHMARK LOOP
# ============================================================================
ctx = Dagger.Sch.eager_context()
Dagger.addprocs!(ctx, [2])

println("\n" * "="^80)
println("SEAM CARVING WEAK SCALING BENCHMARK (DISTRIBUTED)")
println("="^80)
println("Start time: ", now())

for target_workers in number_of_processes
    pool = addprocs(target_workers-nworkers(), exeflags="--project=$(Base.current_project())")
    
    @everywhere pool begin
        using Dagger, LinearAlgebra, Random, Test, Logging, Plots, DataFrames
        disable_logging(LogLevel(2999))
    end
    
    ctx = Dagger.Sch.eager_context()
    Dagger.addprocs!(ctx, pool)
    
    println("\n" * "-"^80)
    println("SCALING LEVEL: $target_workers workers")
    println("-"^80)
    println("Processors: ", Dagger.num_processors())
    println("Workers: ", nworkers())
    
    # ========================================================================
    # SEAM CARVING BENCHMARK  
    # ========================================================================
    # Increase image size for more work per task
    seam_rows = 1024 * floor(Int, sqrt(nworkers()))
    seam_cols = 1024 * floor(Int, sqrt(nworkers()))
    # Increase base for coarser blocks (fewer tasks, more work per task)
    # This reduces task creation overhead significantly
    seam_base = 512
    seam_assignment = :blockcol

    Dagger.enable_logging!()
    seam_result = run_seam_carving_benchmark(seam_rows, seam_cols, seam_base, seam_assignment)
    logs = Dagger.fetch_logs!()
    if !isnan(seam_result.par_time)
        #plot = Dagger.render_logs(logs, :plots_gantt)
        #savefig(plot, "/flare/dagger/paper/Dagger-bench/seam_carving_gantt_$(nworkers())workers.png")
    end
    Dagger.disable_logging!()
    push!(demo_results, seam_result)
    
    sleep(1)
end

# ============================================================================
# SUMMARY STATISTICS
# ============================================================================
println("\n" * "="^80)
println("SUMMARY - SEAM CARVING RESULTS")
println("="^80)
for result in demo_results
    println("SEAM_CARVING, workers=$(result.workers), size=$(result.rows)x$(result.cols), base=$(result.base), assignment=$(result.assignment), seq=$(result.seq_time)s, par=$(result.par_time)s, speedup=$(result.speedup)x")
end

println("\nEnd time: ", now())
