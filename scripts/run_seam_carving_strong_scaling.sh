#!/bin/bash
# Seam Carving Strong Scaling Benchmark Runner
# Runs the benchmark across different worker counts with fixed image size

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${BENCH_DIR}/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Configuration
WORKER_COUNTS=(1 2 4 8 16 32 64)
SEAM_ROWS=${SEAM_ROWS:-4096}
SEAM_COLS=${SEAM_COLS:-4096}
SEAM_BLOCK_BASE=${SEAM_BLOCK_BASE:-512}
SEAM_ASSIGNMENT=${SEAM_ASSIGNMENT:-blockcol}
NUM_SAMPLES=${NUM_SAMPLES:-3}

CSV_FILE="${OUTPUT_DIR}/seam_carving_strong_scaling_${TIMESTAMP}.csv"
LOG_FILE="${OUTPUT_DIR}/seam_carving_strong_scaling_${TIMESTAMP}.log"

echo "=============================================="
echo "SEAM CARVING STRONG SCALING BENCHMARK"
echo "=============================================="
echo "Timestamp: $TIMESTAMP"
echo "Fixed image size: ${SEAM_ROWS}x${SEAM_COLS}"
echo "Total pixels: $((SEAM_ROWS * SEAM_COLS))"
echo "Block base: $SEAM_BLOCK_BASE"
echo "Assignment: $SEAM_ASSIGNMENT"
echo "Samples per config: $NUM_SAMPLES"
echo "Worker counts: ${WORKER_COUNTS[*]}"
echo "Output CSV: $CSV_FILE"
echo "Log file: $LOG_FILE"
echo "=============================================="

# Initialize CSV with header
echo "workers,rows,cols,pixels,base,seq_time,par_time,par_mean,par_std,speedup" > "$CSV_FILE"

# Run benchmark for each worker count
for workers in "${WORKER_COUNTS[@]}"; do
    echo ""
    echo "----------------------------------------------"
    echo "Running with $workers workers..."
    echo "----------------------------------------------"
    
    # Run Julia benchmark and capture output
    TARGET_WORKERS=$workers \
    SEAM_ROWS=$SEAM_ROWS \
    SEAM_COLS=$SEAM_COLS \
    SEAM_BLOCK_BASE=$SEAM_BLOCK_BASE \
    SEAM_ASSIGNMENT=$SEAM_ASSIGNMENT \
    NUM_SAMPLES=$NUM_SAMPLES \
    julia --project="$BENCH_DIR" "$SCRIPT_DIR/seam_carving_strong_benchmark.jl" 2>&1 | tee -a "$LOG_FILE" | while read line; do
        echo "$line"
        # Extract CSV output line
        if [[ "$line" == CSV_OUTPUT:* ]]; then
            csv_data="${line#CSV_OUTPUT:}"
            echo "$csv_data" >> "$CSV_FILE"
        fi
    done
    
    echo "Completed $workers workers"
done

echo ""
echo "=============================================="
echo "BENCHMARK COMPLETE"
echo "=============================================="
echo "Results saved to: $CSV_FILE"
echo "Full log saved to: $LOG_FILE"
echo ""

# Display summary
echo "Summary:"
cat "$CSV_FILE"
