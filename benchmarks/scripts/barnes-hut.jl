using Distributed
using Dates
using Dagger
using Printf
using Statistics

const APP = "barnes-hut"
const APP_DIR = abspath(joinpath(@__DIR__, "..", "..", "apps", APP))
const APP_IMPL = joinpath(APP_DIR, "barnes-hut.jl")
const RESULTS_APP_DIR = abspath(joinpath(@__DIR__, "..", "results", APP))

@everywhere include($APP_IMPL)

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

function _write_runs_csv(path::AbstractString, scenario::AbstractString, procs::Int, N::Int, theta::Float64, times::Vector{Float64})
    open(path, "w") do io
        println(io, "scenario,dagger_processors,N,theta,run,time_sec")
        for (i, t) in enumerate(times)
            println(io, "$(scenario),$(procs),$(N),$(theta),$(i),$(@sprintf(\"%.9f\", t))")
        end
    end
end

"""
    run_benchmark(; runs=3, theta=0.5)

Runs both a strong-scaling and weak-scaling measurement for the current Dagger processor configuration.

Configuration (environment variables):
- `BENCH_RUNS` (default: 3)
- `BARNES_THETA` (default: 0.5)
- `BARNES_N_STRONG` (default: 10000)
- `BARNES_BODIES_PER_PROC` (default: 1000)
"""
function run_benchmark(;
    runs::Int=parse(Int, get(ENV, "BENCH_RUNS", "3")),
    theta::Float64=parse(Float64, get(ENV, "BARNES_THETA", "0.5")),
)
    procs = _dagger_processors()

    strong_N = parse(Int, get(ENV, "BARNES_N_STRONG", "10000"))
    weak_bodies_per_proc = parse(Int, get(ENV, "BARNES_BODIES_PER_PROC", "1000"))
    weak_N = max(1, weak_bodies_per_proc * max(1, procs))

    ts = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    out_dir = joinpath(RESULTS_APP_DIR, ts)
    mkpath(out_dir)

    println("="^70)
    println("BARNES-HUT BENCHMARK")
    println("="^70)
    println("Dagger processors: $procs")
    println("Runs: $runs")
    println("Theta: $theta")
    println()

    println(">>> Strong scaling (fixed N=$strong_N)")
    strong_times = _run_n(() -> bmark(strong_N, theta), runs)
    println(@sprintf "  mean=%.4fs  std=%.4fs", mean(strong_times), std(strong_times))

    println(">>> Weak scaling (N = bodies_per_proc * procs = $weak_bodies_per_proc * $procs = $weak_N)")
    weak_times = _run_n(() -> bmark(weak_N, theta), runs)
    println(@sprintf "  mean=%.4fs  std=%.4fs", mean(weak_times), std(weak_times))

    _write_runs_csv(joinpath(out_dir, "strong_scaling.csv"), "strong", procs, strong_N, theta, strong_times)
    _write_runs_csv(joinpath(out_dir, "weak_scaling.csv"), "weak", procs, weak_N, theta, weak_times)

    println()
    println("Results written to: $out_dir")
    return out_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_benchmark()
end
