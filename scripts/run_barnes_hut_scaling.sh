#!/bin/bash
# Barnes-Hut Thread Scaling Benchmark
# Runs the benchmark with increasing thread counts (powers of 2)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/barnes_hut_scaling_${TIMESTAMP}.log"
CSV_FILE="${OUTPUT_DIR}/barnes_hut_scaling_${TIMESTAMP}.csv"

# Create results directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Thread counts (powers of 2, plus 104 for full Aurora node)
THREAD_COUNTS=(1 2 4 8 16 32 64 104)

echo "=========================================="
echo "Barnes-Hut Thread Scaling Benchmark"
echo "=========================================="
echo "Start time: $(date)"
echo "Output file: $OUTPUT_FILE"
echo "CSV file: $CSV_FILE"
echo ""

# Header for CSV results
echo "threads,N,theta,par_time" > "$CSV_FILE"

for threads in "${THREAD_COUNTS[@]}"; do
    echo "------------------------------------------"
    echo "Running with $threads thread(s)..."
    echo "------------------------------------------"
    
    # Run Julia with specified thread count and capture output
    OUTPUT=$(julia --threads=$threads --project="$PROJECT_DIR" "$SCRIPT_DIR/barnes_hut_benchmark.jl" 2>&1)
    
    # Save full output to log
    echo "$OUTPUT" >> "$OUTPUT_FILE"
    echo "$OUTPUT"
    
    # Extract CSV line and append to CSV file
    CSV_LINE=$(echo "$OUTPUT" | grep "^CSV_OUTPUT:" | sed 's/CSV_OUTPUT://')
    if [ -n "$CSV_LINE" ]; then
        echo "$CSV_LINE" >> "$CSV_FILE"
    fi
    
    echo ""
done

echo "=========================================="
echo "Benchmark Complete"
echo "End time: $(date)"
echo "Results saved to: $OUTPUT_FILE"
echo "CSV results: $CSV_FILE"
echo "=========================================="

# Generate plot using separate Julia script
echo ""
echo "Generating weak scaling plots..."
julia --project="$PROJECT_DIR" "$SCRIPT_DIR/plot_barnes_hut_scaling.jl" "$CSV_FILE"

echo ""
echo "All done!"
