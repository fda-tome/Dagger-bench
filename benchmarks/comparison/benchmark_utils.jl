# Benchmark utilities for statistical analysis
# Provides timing, memory, and statistical aggregation functions

using Statistics
using Printf

"""
    BenchmarkResult

Stores timing and memory statistics for a single benchmark run.
"""
mutable struct BenchmarkResult
    name::String
    elapsed_time::Float64  # seconds
    allocated_bytes::Int64
    gc_time::Float64       # seconds
    num_processors::Int
    metadata::Dict{String, Any}
end

function BenchmarkResult(name::String; metadata::Dict{String, Any}=Dict{String, Any}())
    BenchmarkResult(name, 0.0, 0, 0.0, 0, metadata)
end

"""
    BenchmarkStats

Aggregates statistics from multiple runs.
"""
struct BenchmarkStats
    name::String
    times::Vector{Float64}         # seconds
    allocations::Vector{Int64}     # bytes
    gc_times::Vector{Float64}      # seconds
    num_runs::Int
    metadata::Dict{String, Any}
end

function BenchmarkStats(name::String, results::Vector{BenchmarkResult})
    times = [r.elapsed_time for r in results]
    allocs = [r.allocated_bytes for r in results]
    gc_times = [r.gc_time for r in results]
    metadata = isempty(results) ? Dict{String, Any}() : results[1].metadata
    BenchmarkStats(name, times, allocs, gc_times, length(results), metadata)
end

"""
    time_benchmark(f::Function, name::String; num_processors::Int=0, metadata::Dict=Dict())

Run function `f` and capture timing and memory statistics.
Returns a BenchmarkResult.
"""
function time_benchmark(f::Function, name::String; num_processors::Int=0, metadata::Dict{String, Any}=Dict{String, Any}())
    # Force garbage collection before benchmark
    GC.gc()
    
    # Capture statistics
    stats = @timed f()
    
    result = BenchmarkResult(name; metadata=metadata)
    result.elapsed_time = stats.time
    result.allocated_bytes = stats.bytes
    result.gc_time = stats.gctime
    result.num_processors = num_processors
    
    return result
end

"""
    run_multiple(f::Function, name::String, n::Int; kwargs...)

Run benchmark `f` multiple times and return vector of results.
"""
function run_multiple(f::Function, name::String, n::Int; kwargs...)
    results = BenchmarkResult[]
    for i in 1:n
        println("  Run $i/$n...")
        push!(results, time_benchmark(f, name; kwargs...))
    end
    return results
end

"""
    compute_stats(results::Vector{BenchmarkResult}) -> BenchmarkStats

Compute aggregate statistics from multiple benchmark runs.
"""
function compute_stats(results::Vector{BenchmarkResult})
    @assert !isempty(results) "Cannot compute stats from empty results"
    name = results[1].name
    return BenchmarkStats(name, results)
end

"""
    print_stats(stats::BenchmarkStats)

Print formatted statistics summary.
"""
function print_stats(stats::BenchmarkStats)
    println("\n" * "="^70)
    println("Benchmark: $(stats.name)")
    println("="^70)
    println("Number of runs: $(stats.num_runs)")
    
    if !isempty(stats.metadata)
        println("\nMetadata:")
        for (k, v) in stats.metadata
            println("  $k: $v")
        end
    end
    
    println("\nTiming Statistics (seconds):")
    println(@sprintf "  Mean:   %.6f ± %.6f", mean(stats.times), std(stats.times))
    println(@sprintf "  Median: %.6f", median(stats.times))
    println(@sprintf "  Min:    %.6f", minimum(stats.times))
    println(@sprintf "  Max:    %.6f", maximum(stats.times))
    
    println("\nMemory Statistics:")
    mean_mb = mean(stats.allocations) / 1024^2
    std_mb = std(stats.allocations) / 1024^2
    println(@sprintf "  Mean allocated: %.2f ± %.2f MB", mean_mb, std_mb)
    println(@sprintf "  Total GC time:  %.6f s", sum(stats.gc_times))
    
    println("="^70 * "\n")
end

"""
    compare_benchmarks(baseline::BenchmarkStats, comparison::BenchmarkStats)

Compare two benchmark results and compute speedup.
"""
function compare_benchmarks(baseline::BenchmarkStats, comparison::BenchmarkStats)
    baseline_mean = mean(baseline.times)
    comparison_mean = mean(comparison.times)
    speedup = baseline_mean / comparison_mean
    
    println("\n" * "="^70)
    println("Performance Comparison")
    println("="^70)
    println("Baseline:   $(baseline.name)")
    println(@sprintf "  Mean time: %.6f s", baseline_mean)
    println("\nComparison: $(comparison.name)")
    println(@sprintf "  Mean time: %.6f s", comparison_mean)
    println("\nSpeedup: $(speedup)x")
    
    if speedup > 1.0
        pct_faster = (speedup - 1.0) * 100
        println(@sprintf "Comparison is %.1f%% faster than baseline", pct_faster)
    else
        pct_slower = (1.0 - speedup) * 100
        println(@sprintf "Comparison is %.1f%% slower than baseline", pct_slower)
    end
    println("="^70 * "\n")
    
    return speedup
end

"""
    export_to_csv(filepath::String, stats_list::Vector{BenchmarkStats})

Export benchmark statistics to CSV file.
"""
function export_to_csv(filepath::String, stats_list::Vector{BenchmarkStats})
    open(filepath, "w") do io
        # Header
        println(io, "benchmark,run,time_sec,allocated_mb,gc_time_sec")
        
        # Data rows
        for stats in stats_list
            for (i, (t, a, g)) in enumerate(zip(stats.times, stats.allocations, stats.gc_times))
                alloc_mb = a / 1024^2
                println(io, "$(stats.name),$i,$t,$alloc_mb,$g")
            end
        end
    end
    println("Results exported to: $filepath")
end

"""
    export_summary_to_csv(filepath::String, stats_list::Vector{BenchmarkStats})

Export summary statistics to CSV file.
"""
function export_summary_to_csv(filepath::String, stats_list::Vector{BenchmarkStats})
    open(filepath, "w") do io
        # Header
        println(io, "benchmark,num_runs,mean_time_sec,std_time_sec,median_time_sec,min_time_sec,max_time_sec,mean_alloc_mb")
        
        # Data rows
        for stats in stats_list
            mean_t = mean(stats.times)
            std_t = std(stats.times)
            median_t = median(stats.times)
            min_t = minimum(stats.times)
            max_t = maximum(stats.times)
            mean_a = mean(stats.allocations) / 1024^2
            
            println(io, "$(stats.name),$(stats.num_runs),$mean_t,$std_t,$median_t,$min_t,$max_t,$mean_a")
        end
    end
    println("Summary exported to: $filepath")
end
