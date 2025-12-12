#!/usr/bin/env julia
# Plot Seam Carving Strong Scaling Results

ENV["GKSwstype"] = "100"  # Headless GR backend

using CSV
using DataFrames
using Plots
using Statistics

# Find the most recent results file
function find_latest_results(results_dir::String, pattern::String)
    files = filter(f -> occursin(pattern, f) && endswith(f, ".csv"), readdir(results_dir))
    if isempty(files)
        error("No results files found matching pattern: $pattern")
    end
    return joinpath(results_dir, sort(files)[end])
end

# Main plotting function
function plot_strong_scaling(csv_file::String, output_dir::String)
    println("Reading results from: $csv_file")
    df = CSV.read(csv_file, DataFrame)
    
    println("\nData summary:")
    println(df)
    
    # Sort by workers
    sort!(df, :workers)
    
    # Create output directory
    mkpath(output_dir)
    
    # Get baseline (1 worker) time for speedup calculation
    baseline_time = df[df.workers .== minimum(df.workers), :par_time][1]
    actual_speedup = baseline_time ./ df.par_time
    
    # Plot 1: Execution Time vs Workers
    p1 = plot(df.workers, df.par_time,
        xlabel="Workers",
        ylabel="Time (seconds)",
        title="Seam Carving Strong Scaling - Execution Time",
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Actual",
        legend=:topright,
        xscale=:log2,
        yscale=:log10,
        xticks=(df.workers, string.(df.workers))
    )
    
    # Ideal scaling line (time = baseline / workers)
    ideal_time = baseline_time ./ df.workers
    plot!(p1, df.workers, ideal_time,
        linestyle=:dash,
        linewidth=2,
        color=:gray,
        label="Ideal"
    )
    
    savefig(p1, joinpath(output_dir, "seam_carving_strong_time.png"))
    println("Saved: seam_carving_strong_time.png")
    
    # Plot 2: Speedup vs Workers
    p2 = plot(df.workers, actual_speedup,
        xlabel="Workers",
        ylabel="Speedup",
        title="Seam Carving Strong Scaling - Speedup",
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Actual speedup",
        legend=:topleft,
        xscale=:log2,
        xticks=(df.workers, string.(df.workers))
    )
    
    # Ideal speedup line
    plot!(p2, df.workers, df.workers,
        linestyle=:dash,
        linewidth=2,
        color=:gray,
        label="Ideal (linear)"
    )
    
    savefig(p2, joinpath(output_dir, "seam_carving_strong_speedup.png"))
    println("Saved: seam_carving_strong_speedup.png")
    
    # Plot 3: Parallel Efficiency
    efficiency = actual_speedup ./ df.workers .* 100
    
    p3 = plot(df.workers, efficiency,
        xlabel="Workers",
        ylabel="Efficiency (%)",
        title="Seam Carving Strong Scaling - Parallel Efficiency",
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Efficiency",
        legend=:topright,
        xscale=:log2,
        xticks=(df.workers, string.(df.workers)),
        ylims=(0, 120)
    )
    
    # Ideal efficiency line
    hline!(p3, [100], linestyle=:dash, color=:gray, label="Ideal (100%)")
    
    savefig(p3, joinpath(output_dir, "seam_carving_strong_efficiency.png"))
    println("Saved: seam_carving_strong_efficiency.png")
    
    # Plot 4: Speedup vs Sequential (from benchmark)
    p4 = plot(df.workers, df.speedup,
        xlabel="Workers",
        ylabel="Speedup vs Sequential",
        title="Seam Carving - Speedup vs Sequential Reference",
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Speedup",
        legend=:topleft,
        xscale=:log2,
        xticks=(df.workers, string.(df.workers))
    )
    
    savefig(p4, joinpath(output_dir, "seam_carving_strong_speedup_vs_seq.png"))
    println("Saved: seam_carving_strong_speedup_vs_seq.png")
    
    # Combined plot
    p_combined = plot(p1, p2, p3, p4, layout=(2,2), size=(1200, 900))
    savefig(p_combined, joinpath(output_dir, "seam_carving_strong_scaling_combined.png"))
    println("Saved: seam_carving_strong_scaling_combined.png")
    
    # Print summary table
    println("\n" * "="^80)
    println("STRONG SCALING SUMMARY")
    println("="^80)
    println("Workers | Image Size   | Seq Time | Par Time | Speedup(1w) | Speedup(seq) | Efficiency")
    println("-"^80)
    for (i, row) in enumerate(eachrow(df))
        @printf("%7d | %4dx%-4d    | %7.3fs | %7.3fs | %10.2fx | %11.2fx | %6.2f%%\n",
            row.workers, row.rows, row.cols,
            row.seq_time, row.par_time,
            actual_speedup[i], row.speedup,
            efficiency[i])
    end
    println("="^80)
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    using Printf
    
    script_dir = @__DIR__
    bench_dir = dirname(script_dir)
    results_dir = joinpath(bench_dir, "results")
    output_dir = joinpath(results_dir, "plots")
    
    # Use command line argument or find latest
    csv_file = if length(ARGS) >= 1
        ARGS[1]
    else
        find_latest_results(results_dir, "seam_carving_strong_scaling")
    end
    
    plot_strong_scaling(csv_file, output_dir)
end
