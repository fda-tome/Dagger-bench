using CSV, DataFrames, Plots, Printf
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

# ============================================================================
# Barnes-Hut Weak Scaling Plot Generator
# Usage: julia --project=. scripts/plot_barnes_hut_scaling.jl <csv_file>
# ============================================================================

function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. scripts/plot_barnes_hut_scaling.jl <csv_file>")
        println("Example: julia --project=. scripts/plot_barnes_hut_scaling.jl results/barnes_hut_scaling_20251210.csv")
        exit(1)
    end

    csv_file = ARGS[1]
    
    if !isfile(csv_file)
        println("Error: File not found: $csv_file")
        exit(1)
    end

    # Determine output directory and timestamp from csv filename
    output_dir = dirname(csv_file)
    if output_dir == ""
        output_dir = "."
    end
    
    # Extract timestamp from filename if present
    basename_csv = basename(csv_file)
    timestamp = replace(basename_csv, r"barnes_hut_scaling_|\.csv" => "")
    if timestamp == basename_csv
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    end

    println("="^60)
    println("Barnes-Hut Weak Scaling Plot Generator")
    println("="^60)
    println("Input CSV: $csv_file")
    println("Output directory: $output_dir")
    println()

    # Read CSV data
    df = CSV.read(csv_file, DataFrame)
    println("Loaded $(nrow(df)) data points")
    println()

    # Calculate ideal weak scaling (constant time)
    ideal_time = df.par_time[1]  # Time with minimum threads as baseline

    # Create weak scaling plot
    p = plot(df.threads, df.par_time, 
        marker=:circle, 
        markersize=6,
        linewidth=2,
        label="Measured Time",
        xlabel="Number of Threads",
        ylabel="Time (seconds)",
        title="Barnes-Hut Weak Scaling\n(N = 150,000 × threads)",
        legend=:topright,
        xscale=:log2,
        xticks=(df.threads, string.(df.threads)),
        grid=true,
        size=(800, 600)
    )

    # Add ideal line (constant time for perfect weak scaling)
    hline!([ideal_time], linestyle=:dash, linewidth=2, label="Ideal (constant time)", color=:green)

    # Save plot
    scaling_plot_file = joinpath(output_dir, "barnes_hut_weak_scaling_$(timestamp).png")
    savefig(p, scaling_plot_file)
    println("Scaling plot saved to: $scaling_plot_file")

    # Calculate efficiency
    efficiency = ideal_time ./ df.par_time * 100

    # Create efficiency plot
    p2 = plot(df.threads, efficiency,
        marker=:square,
        markersize=6,
        linewidth=2,
        label="Efficiency",
        xlabel="Number of Threads",
        ylabel="Weak Scaling Efficiency (%)",
        title="Barnes-Hut Weak Scaling Efficiency",
        legend=:topright,
        xscale=:log2,
        xticks=(df.threads, string.(df.threads)),
        ylim=(0, max(120, maximum(efficiency) + 10)),
        grid=true,
        size=(800, 600),
        color=:orange
    )

    hline!([100], linestyle=:dash, linewidth=2, label="Ideal (100%)", color=:green)

    efficiency_plot_file = joinpath(output_dir, "barnes_hut_efficiency_$(timestamp).png")
    savefig(p2, efficiency_plot_file)
    println("Efficiency plot saved to: $efficiency_plot_file")

    # Print summary table
    println()
    println("Summary Table:")
    println("="^70)
    @printf("%-10s | %-12s | %-12s | %-15s\n", "Threads", "N", "Time (s)", "Efficiency (%)")
    println("-"^70)
    for i in 1:nrow(df)
        eff = ideal_time / df.par_time[i] * 100
        @printf("%-10d | %-12d | %-12.3f | %-15.1f\n", df.threads[i], df.N[i], df.par_time[i], eff)
    end
    println("="^70)

    # Save summary to text file
    summary_file = joinpath(output_dir, "barnes_hut_summary_$(timestamp).txt")
    open(summary_file, "w") do io
        println(io, "Barnes-Hut Weak Scaling Summary")
        println(io, "="^70)
        println(io, "Baseline (1 thread): $(ideal_time) seconds")
        println(io)
        @printf(io, "%-10s | %-12s | %-12s | %-15s\n", "Threads", "N", "Time (s)", "Efficiency (%)")
        println(io, "-"^70)
        for i in 1:nrow(df)
            eff = ideal_time / df.par_time[i] * 100
            @printf(io, "%-10d | %-12d | %-12.3f | %-15.1f\n", df.threads[i], df.N[i], df.par_time[i], eff)
        end
        println(io, "="^70)
    end
    println("\nSummary saved to: $summary_file")

    println("\nDone!")
end

main()
