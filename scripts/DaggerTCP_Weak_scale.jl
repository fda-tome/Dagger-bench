using Distributed
using Dates
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

all_results = []
demo_results = []

# ============================================================================
# CONFIGURATION
# ============================================================================
number_of_processes = [2, 4, 8, 16, 32, 64]  # Full scale run
SCRIPT_DIR = @__DIR__
DEMOS_DIR = joinpath(dirname(SCRIPT_DIR), "demos")
SEAM_DIR = joinpath(DEMOS_DIR, "real-world", "seam")

# ============================================================================
# BARNES-HUT BENCHMARK (THREADS ONLY - runs first before adding workers)
# ============================================================================
println("\n" * "="^80)
println("BARNES-HUT BENCHMARK (THREAD-BASED)")
println("="^80)
println("Available threads: ", Threads.nthreads())

# Include Barnes-Hut demo on main process only (thread-based)
include(joinpath(DEMOS_DIR, "advanced", "barnes", "barnes-hut.jl"))

# Barnes-Hut uses Dagger's thread processors, not distributed workers
using Dagger, LinearAlgebra, Random, Test, Logging, Plots, DataFrames

function run_barnes_hut_benchmark(N::Int, theta::Float64, num_threads::Int)
    println("\n" * "="^60)
    println("BARNES-HUT N-BODY BENCHMARK")
    println("  N=$N particles, theta=$theta, threads=$num_threads")
    println("="^60)
    
    # Sequential
    seq_result = @timed bmark_seq(N, theta)
    println("  Sequential: $(seq_result.time) seconds")
    
    # Parallel (thread-based via Dagger)
    par_result = @timed bmark(N, theta)
    println("  Parallel:   $(par_result.time) seconds")
    
    speedup = seq_result.time / par_result.time
    println("  Speedup:    $(speedup)x")
    
    return (
        benchmark = "barnes_hut",
        N = N,
        theta = theta,
        seq_time = seq_result.time,
        par_time = par_result.time,
        speedup = speedup,
        threads = num_threads
    )
end

# Run Barnes-Hut with thread scaling (weak scaling based on thread count)   
target_threads = Threads.nthreads() 
barnes_N = 100000  * target_threads # Weak scaling: more particles with more threads
barnes_theta = 0.01


println("\n" * "-"^80)
println("BARNES-HUT: $target_threads threads, N=$barnes_N")
println("-"^80)

Dagger.enable_logging!()
barnes_result = run_barnes_hut_benchmark(barnes_N, barnes_theta, target_threads)
logs = Dagger.fetch_logs!()
Dagger.disable_logging!()
push!(demo_results, barnes_result)

# ============================================================================
# INITIAL SETUP - First worker pool (for distributed benchmarks)
# ============================================================================
pool = addprocs(1, exeflags="--project=$(Base.current_project())")
@everywhere pool begin
    using Dagger, LinearAlgebra, Random, Test, Logging, Plots, DataFrames
    disable_logging(LogLevel(2999))
end

# ============================================================================
# INCLUDE DEMO CODE FOR DISTRIBUTED BENCHMARKS
# ============================================================================

# Include seam carving demos on main process only (uses Dagger distributed arrays)
include(joinpath(SEAM_DIR, "par_seam.jl"))
include(joinpath(SEAM_DIR, "seq_seam.jl"))

# ============================================================================
# DEMO RUNNER FUNCTIONS (for distributed benchmarks)
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
# DISTRIBUTED BENCHMARK LOOP (Seam Carving + Cholesky)
# ============================================================================
ctx = Dagger.Sch.eager_context()
Dagger.addprocs!(ctx, [2])

println("\n" * "="^80)
println("DAGGER TCP WEAK SCALING BENCHMARK (DISTRIBUTED)")
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
    seam_rows = 512 * floor(Int, sqrt(nworkers()))
    seam_cols = 512 * floor(Int, sqrt(nworkers()))
    seam_base = 200
    seam_assignment = :blockcol

    Dagger.enable_logging!()
    seam_result = run_seam_carving_benchmark(seam_rows, seam_cols, seam_base, seam_assignment)
    logs = Dagger.fetch_logs!()
    if !isnan(seam_result.par_time)  # Only save plot if parallel ran successfully
        #plot = Dagger.render_logs(logs, :plots_gantt)
        #savefig(plot, "/flare/dagger/paper/Dagger-bench/seam_carving_gantt_$(nworkers())workers.png")
    end
    Dagger.disable_logging!()
    push!(demo_results, seam_result)
    
    # ========================================================================
    # CHOLESKY BENCHMARK (original)
    # ========================================================================
    datatypes = [Float32, Float64]
    datasize = 8192 * floor(Int, sqrt(nworkers()))

    for T in datatypes
        A = rand(T, datasize, datasize)
        A = A * A'
        A[diagind(A)] .+= size(A, 1)
        DA = distribute(A, Blocks(8192, 8192))

        Dagger.enable_logging!()
        result = @timed begin
            chol_DA = LinearAlgebra._chol!(DA, UpperTriangular)
        end
        logs = Dagger.fetch_logs!()
        #plot = Dagger.render_logs(logs, :plots_gantt)
        #savefig(plot, "/flare/dagger/paper/Dagger-bench/cholesky_$(T)_gantt_$(nworkers())workers.png")
        Dagger.disable_logging!()

        if chol_DA[2] != 0
            throw(ErrorException("Cholesky factorization failed with info=$(chol_DA[2])"))
        end

        chol_result = (
            procs = Dagger.num_processors(),
            dtype = T,
            size = datasize,
            time = result.time,
            compile = result.compile_time,
            gctime = result.gctime,
            gflops = (datasize^3 / 3) / (result.time * 1e9)
        )
        push!(all_results, chol_result) 
        println("TCP,", chol_result.procs, ",", chol_result.dtype, ",", chol_result.size, ",", chol_result.time, ",", chol_result.compile, ",", chol_result.gctime, ",", chol_result.gflops)
    end
    
    sleep(1)
end

# ============================================================================
# SUMMARY STATISTICS
# ============================================================================
println("\n" * "="^80)
println("SUMMARY - CHOLESKY RESULTS")
println("="^80)
for result in all_results
    println("TCP,", result.procs, ",", result.dtype, ",", result.size, ",", result.time, ",", result.gflops)
end

println("\n" * "="^80)
println("SUMMARY - DEMO RESULTS")
println("="^80)
for result in demo_results
    if result.benchmark == "barnes_hut"
        println("BARNES_HUT, threads=$(result.threads), N=$(result.N), seq=$(result.seq_time)s, par=$(result.par_time)s, speedup=$(result.speedup)x")
    else
        println("SEAM_CARVING, workers=$(result.workers), size=$(result.rows)x$(result.cols), base=$(result.base), assignment=$(result.assignment), seq=$(result.seq_time)s, par=$(result.par_time)s, speedup=$(result.speedup)x")
    end
end

println("\nEnd time: ", now())
