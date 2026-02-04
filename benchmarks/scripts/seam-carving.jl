using Distributed
using Dates
using Dagger
using Printf
using Random
using Statistics

const APP = "seam-carving"
const RESULTS_APP_DIR = abspath(joinpath(@__DIR__, "..", "results", APP))

@everywhere begin
    using Random

    function find_vertical_seam(energy::AbstractMatrix{<:Real})
        rows, cols = size(energy)
        cost = copy(energy)
        backtrack = zeros(Int, rows, cols)

        for i in 2:rows
            for j in 1:cols
                left = j > 1 ? cost[i - 1, j - 1] : Inf
                up = cost[i - 1, j]
                right = j < cols ? cost[i - 1, j + 1] : Inf
                min_val, idx = findmin((left, up, right))
                cost[i, j] += min_val
                backtrack[i, j] = j + (idx - 2)
            end
        end

        seam = zeros(Int, rows)
        seam[rows] = argmin(@view cost[rows, :])
        for i in (rows - 1):-1:1
            seam[i] = backtrack[i + 1, seam[i + 1]]
        end
        return seam
    end

    function seam_job(rows::Int, cols::Int, seed::Int)
        Random.seed!(seed)
        energy = rand(Float32, rows, cols)
        return find_vertical_seam(energy)
    end
end

function _dagger_processors()::Int
    return length(Dagger.compatible_processors())
end

function _time_sec(f)::Float64
    GC.gc()
    t0 = time_ns()
    f()
    return (time_ns() - t0) / 1e9
end

function _run_n(f, n::Int)::Vector{Float64}
    times = Vector{Float64}(undef, n)
    for i in 1:n
        times[i] = _time_sec(f)
    end
    return times
end

function _write_runs_csv(path::AbstractString, scenario::AbstractString, procs::Int, rows::Int, cols::Int, jobs::Int, times::Vector{Float64})
    open(path, "w") do io
        println(io, "scenario,dagger_processors,rows,cols,jobs,run,time_sec")
        for (i, t) in enumerate(times)
            println(io, "$(scenario),$(procs),$(rows),$(cols),$(jobs),$(i),$(@sprintf(\"%.9f\", t))")
        end
    end
end

function _run_jobs(rows::Int, cols::Int, jobs::Int)
    tasks = Vector{Any}(undef, jobs)
    for i in 1:jobs
        tasks[i] = Dagger.@spawn seam_job(rows, cols, i)
    end
    fetch.(tasks)
    return nothing
end

"""
    run_benchmark(; runs=3, rows=512, cols=512, strong_jobs=32, jobs_per_proc=2)

Runs both a strong-scaling and weak-scaling measurement for the current Dagger processor configuration.

Configuration (environment variables):
- `BENCH_RUNS` (default: 3)
- `SEAM_ROWS` (default: 512)
- `SEAM_COLS` (default: 512)
- `SEAM_JOBS_STRONG` (default: 32)
- `SEAM_JOBS_PER_PROC` (default: 2)
"""
function run_benchmark(;
    runs::Int=parse(Int, get(ENV, "BENCH_RUNS", "3")),
    rows::Int=parse(Int, get(ENV, "SEAM_ROWS", "512")),
    cols::Int=parse(Int, get(ENV, "SEAM_COLS", "512")),
    strong_jobs::Int=parse(Int, get(ENV, "SEAM_JOBS_STRONG", "32")),
    jobs_per_proc::Int=parse(Int, get(ENV, "SEAM_JOBS_PER_PROC", "2")),
)
    procs = _dagger_processors()

    weak_jobs = max(1, jobs_per_proc * max(1, procs))

    ts = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    out_dir = joinpath(RESULTS_APP_DIR, ts)
    mkpath(out_dir)

    println("="^70)
    println("SEAM-CARVING BENCHMARK (synthetic seam-finding workload)")
    println("="^70)
    println("Dagger processors: $procs")
    println("Runs: $runs")
    println("Matrix size: $(rows)x$(cols)")
    println()

    println(">>> Strong scaling (fixed jobs=$strong_jobs)")
    strong_times = _run_n(() -> _run_jobs(rows, cols, strong_jobs), runs)
    println(@sprintf "  mean=%.4fs  std=%.4fs", mean(strong_times), std(strong_times))

    println(">>> Weak scaling (jobs = jobs_per_proc * procs = $jobs_per_proc * $procs = $weak_jobs)")
    weak_times = _run_n(() -> _run_jobs(rows, cols, weak_jobs), runs)
    println(@sprintf "  mean=%.4fs  std=%.4fs", mean(weak_times), std(weak_times))

    _write_runs_csv(joinpath(out_dir, "strong_scaling.csv"), "strong", procs, rows, cols, strong_jobs, strong_times)
    _write_runs_csv(joinpath(out_dir, "weak_scaling.csv"), "weak", procs, rows, cols, weak_jobs, weak_times)

    println()
    println("Results written to: $out_dir")
    return out_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_benchmark()
end
