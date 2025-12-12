#!/usr/bin/env julia
# Plot Seam Carving Weak Scaling Results

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
function plot_weak_scaling(csv_file::String, output_dir::String)
    println("Reading results from: $csv_file")
    df = CSV.read(csv_file, DataFrame)
    
    println("\nData summary:")
    println(df)
    
    # Sort by workers
    sort!(df, :workers)
    
    # Create output directory
    mkpath(output_dir)
    
    # Plot 1: Execution Time vs Workers
    p1 = plot(df.workers, df.par_time,
        xlabel="Workers",
        ylabel="Time (seconds)",
        title="Seam Carving Weak Scaling - Execution Time",
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Parallel time",
        legend=:topleft,
        xscale=:log2,
        xticks=(df.workers, string.(df.workers))
    )
    
    # Add sequential time for reference
    plot!(p1, df.workers, df.seq_time,
        marker=:square,
        markersize=5,
        linewidth=2,
        linestyle=:dash,
        label="Sequential time"
    )
    
    savefig(p1, joinpath(output_dir, "seam_carving_weak_time.png"))
    println("Saved: seam_carving_weak_time.png")
    
    # Plot 2: Speedup vs Workers
    p2 = plot(df.workers, df.speedup,
        xlabel="Workers",
        ylabel="Speedup",
        title="Seam Carving Weak Scaling - Speedup",
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Actual speedup",
        legend=:topleft,
        xscale=:log2,
        xticks=(df.workers, string.(df.workers))
    )
    
    # Ideal speedup line (for weak scaling, ideal is constant speedup = workers)
    # Actually for weak scaling, ideal is that time stays constant (speedup = workers/1 * 1 = workers)
    # But typically we compare to sequential on same size, so speedup should grow
    
    savefig(p2, joinpath(output_dir, "seam_carving_weak_speedup.png"))
    println("Saved: seam_carving_weak_speedup.png")
    
    # Plot 3: Parallel Efficiency (speedup / workers)
    efficiency = df.speedup ./ df.workers
    
    p3 = plot(df.workers, efficiency .* 100,
        xlabel="Workers",
        ylabel="Efficiency (%)",
        title="Seam Carving Weak Scaling - Parallel Efficiency",
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
    
    savefig(p3, joinpath(output_dir, "seam_carving_weak_efficiency.png"))
    println("Saved: seam_carving_weak_efficiency.png")
    
    # Plot 4: Time per pixel (should be constant for perfect weak scaling)
    time_per_pixel = df.par_time ./ df.pixels .* 1e6  # microseconds per pixel
    
    p4 = plot(df.workers, time_per_pixel,
        xlabel="Workers",
        ylabel="Time per pixel (μs)",
        title="Seam Carving Weak Scaling - Time per Pixel",
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Parallel",
        legend=:topright,
        xscale=:log2,
        xticks=(df.workers, string.(df.workers))
    )
    
    savefig(p4, joinpath(output_dir, "seam_carving_weak_time_per_pixel.png"))
    println("Saved: seam_carving_weak_time_per_pixel.png")
    
    # Combined plot
    p_combined = plot(p1, p2, p3, p4, layout=(2,2), size=(1200, 900))
    savefig(p_combined, joinpath(output_dir, "seam_carving_weak_scaling_combined.png"))
    println("Saved: seam_carving_weak_scaling_combined.png")
    
    # Print summary table
    println("\n" * "="^80)
    println("WEAK SCALING SUMMARY")
    println("="^80)
    println("Workers | Image Size   | Pixels      | Seq Time | Par Time | Speedup | Efficiency")
    println("-"^80)
    for row in eachrow(df)
        @printf("%7d | %4dx%-4d    | %10d  | %7.3fs | %7.3fs | %6.2fx | %6.2f%%\n",
            row.workers, row.rows, row.cols, row.pixels,
            row.seq_time, row.par_time, row.speedup,
            row.speedup / row.workers * 100)
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
        find_latest_results(results_dir, "seam_carving_weak_scaling")
    end
    
    plot_weak_scaling(csv_file, output_dir)
end
