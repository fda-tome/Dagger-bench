using Distributed
using Dates
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

all_results = []

# ============================================================================
# CONFIGURATION
# ============================================================================
number_of_processes = [2, 4, 8, 16, 32, 64]  # Full scale run

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
# DISTRIBUTED BENCHMARK LOOP
# ============================================================================
ctx = Dagger.Sch.eager_context()
Dagger.addprocs!(ctx, [2])

println("\n" * "="^80)
println("CHOLESKY WEAK SCALING BENCHMARK (DISTRIBUTED)")
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
    # CHOLESKY BENCHMARK
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

println("\nEnd time: ", now())
