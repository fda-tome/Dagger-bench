using CSV, DataFrames, Plots, Printf
ENV["GKSwstype"] = "100"  # Use null/headless GR backend for supercomputer

# ============================================================================
# Barnes-Hut Strong Scaling Plot Generator
# Usage: julia --project=. scripts/plot_barnes_hut_strong_scaling.jl <csv_file>
# ============================================================================

function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. scripts/plot_barnes_hut_strong_scaling.jl <csv_file>")
        println("Example: julia --project=. scripts/plot_barnes_hut_strong_scaling.jl results/barnes_hut_strong_scaling_20251210.csv")
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
    timestamp = replace(basename_csv, r"barnes_hut_strong_scaling_|\.csv" => "")
    if timestamp == basename_csv
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    end

    println("="^60)
    println("Barnes-Hut Strong Scaling Plot Generator")
    println("="^60)
    println("Input CSV: $csv_file")
    println("Output directory: $output_dir")
    println()

    # Read CSV data
    df = CSV.read(csv_file, DataFrame)
    println("Loaded $(nrow(df)) data points")
    println("Fixed problem size: N = $(df.N[1])")
    
    # Check if we have statistics columns
    has_stats = hasproperty(df, :std_time)
    if has_stats
        println("Statistics from multiple tree configurations available")
    end
    println()

    # Baseline time (1 thread)
    baseline_time = df.par_time[1]
    
    # Calculate speedup
    speedup = baseline_time ./ df.par_time
    
    # Calculate ideal speedup (linear)
    ideal_speedup = df.threads ./ df.threads[1]

    # Create speedup plot with error bars if statistics available
    p = plot(df.threads, speedup, 
        marker=:circle, 
        markersize=6,
        linewidth=2,
        label="Measured Speedup (median)",
        xlabel="Number of Threads",
        ylabel="Speedup (T₁/Tₚ)",
        title="Barnes-Hut Strong Scaling\n(N = $(df.N[1]) particles, 5 tree configs)",
        legend=:topleft,
        xscale=:log2,
        yscale=:log2,
        xticks=(df.threads, string.(df.threads)),
        yticks=(df.threads, string.(df.threads)),
        grid=true,
        size=(800, 600)
    )
    
    # Add error ribbon if statistics available
    if has_stats
        speedup_min = baseline_time ./ df.max_time
        speedup_max = baseline_time ./ df.min_time
        plot!(p, df.threads, speedup, ribbon=(speedup .- speedup_min, speedup_max .- speedup), 
              fillalpha=0.2, label="")
    end

    # Add ideal linear speedup line
    plot!(df.threads, ideal_speedup, linestyle=:dash, linewidth=2, label="Ideal (linear)", color=:green)

    # Save plot
    speedup_plot_file = joinpath(output_dir, "barnes_hut_strong_speedup_$(timestamp).png")
    savefig(p, speedup_plot_file)
    println("Speedup plot saved to: $speedup_plot_file")

    # Create time plot with error bars if statistics available
    p2 = plot(df.threads, df.par_time,
        marker=:circle,
        markersize=6,
        linewidth=2,
        label="Measured Time (median)",
        xlabel="Number of Threads",
        ylabel="Time (seconds)",
        title="Barnes-Hut Strong Scaling - Execution Time\n(N = $(df.N[1]) particles, 5 tree configs)",
        legend=:topright,
        xscale=:log2,
        xticks=(df.threads, string.(df.threads)),
        grid=true,
        size=(800, 600)
    )
    
    # Add error bars if statistics available
    if has_stats
        plot!(p2, df.threads, df.par_time, 
              ribbon=(df.par_time .- df.min_time, df.max_time .- df.par_time),
              fillalpha=0.2, label="")
    end

    # Add ideal time line (linear decrease)
    ideal_time = baseline_time ./ ideal_speedup
    plot!(df.threads, ideal_time, linestyle=:dash, linewidth=2, label="Ideal (linear speedup)", color=:green)

    time_plot_file = joinpath(output_dir, "barnes_hut_strong_time_$(timestamp).png")
    savefig(p2, time_plot_file)
    println("Time plot saved to: $time_plot_file")

    # Calculate parallel efficiency
    efficiency = speedup ./ df.threads * 100

    # Create efficiency plot
    p3 = plot(df.threads, efficiency,
        marker=:square,
        markersize=6,
        linewidth=2,
        label="Parallel Efficiency",
        xlabel="Number of Threads",
        ylabel="Parallel Efficiency (%)",
        title="Barnes-Hut Strong Scaling Efficiency",
        legend=:topright,
        xscale=:log2,
        xticks=(df.threads, string.(df.threads)),
        ylim=(0, max(120, maximum(efficiency) + 10)),
        grid=true,
        size=(800, 600),
        color=:orange
    )

    hline!([100], linestyle=:dash, linewidth=2, label="Ideal (100%)", color=:green)

    efficiency_plot_file = joinpath(output_dir, "barnes_hut_strong_efficiency_$(timestamp).png")
    savefig(p3, efficiency_plot_file)
    println("Efficiency plot saved to: $efficiency_plot_file")

    # Print summary table
    println()
    println("Summary Table:")
    if has_stats
        println("="^100)
        @printf("%-8s | %-10s | %-10s | %-10s | %-10s | %-10s | %-10s\n", 
            "Threads", "Time (s)", "Std (s)", "Min (s)", "Max (s)", "Speedup", "Eff (%)")
        println("-"^100)
        for i in 1:nrow(df)
            @printf("%-8d | %-10.3f | %-10.3f | %-10.3f | %-10.3f | %-10.2f | %-10.1f\n", 
                df.threads[i], df.par_time[i], df.std_time[i], df.min_time[i], df.max_time[i],
                speedup[i], efficiency[i])
        end
        println("="^100)
    else
        println("="^80)
        @printf("%-10s | %-12s | %-12s | %-12s | %-15s\n", "Threads", "N", "Time (s)", "Speedup", "Efficiency (%)")
        println("-"^80)
        for i in 1:nrow(df)
            @printf("%-10d | %-12d | %-12.3f | %-12.2f | %-15.1f\n", 
                df.threads[i], df.N[i], df.par_time[i], speedup[i], efficiency[i])
        end
        println("="^80)
    end

    # Save summary to text file
    summary_file = joinpath(output_dir, "barnes_hut_strong_summary_$(timestamp).txt")
    open(summary_file, "w") do io
        println(io, "Barnes-Hut Strong Scaling Summary")
        println(io, "="^80)
        println(io, "Fixed problem size: N = $(df.N[1])")
        println(io, "Baseline time (1 thread): $(baseline_time) seconds")
        println(io)
        @printf(io, "%-10s | %-12s | %-12s | %-12s | %-15s\n", "Threads", "N", "Time (s)", "Speedup", "Efficiency (%)")
        println(io, "-"^80)
        for i in 1:nrow(df)
            @printf(io, "%-10d | %-12d | %-12.3f | %-12.2f | %-15.1f\n", 
                df.threads[i], df.N[i], df.par_time[i], speedup[i], efficiency[i])
        end
        println(io, "="^80)
    end
    println("\nSummary saved to: $summary_file")

    println("\nDone!")
end

main()
