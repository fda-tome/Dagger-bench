#!/bin/bash
# Seam Carving Weak Scaling Benchmark Runner
# Runs the benchmark across different worker counts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${BENCH_DIR}/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Configuration
WORKER_COUNTS=(1 2 4 8 16 32 64)
SEAM_BASE_ROWS=${SEAM_BASE_ROWS:-1024}
SEAM_BASE_COLS=${SEAM_BASE_COLS:-1024}
SEAM_BLOCK_BASE=${SEAM_BLOCK_BASE:-512}
SEAM_ASSIGNMENT=${SEAM_ASSIGNMENT:-blockcol}
NUM_SAMPLES=${NUM_SAMPLES:-3}

CSV_FILE="${OUTPUT_DIR}/seam_carving_weak_scaling_${TIMESTAMP}.csv"
LOG_FILE="${OUTPUT_DIR}/seam_carving_weak_scaling_${TIMESTAMP}.log"

echo "=============================================="
echo "SEAM CARVING WEAK SCALING BENCHMARK"
echo "=============================================="
echo "Timestamp: $TIMESTAMP"
echo "Base size per worker: ${SEAM_BASE_ROWS}x${SEAM_BASE_COLS}"
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
    SEAM_BASE_ROWS=$SEAM_BASE_ROWS \
    SEAM_BASE_COLS=$SEAM_BASE_COLS \
    SEAM_BLOCK_BASE=$SEAM_BLOCK_BASE \
    SEAM_ASSIGNMENT=$SEAM_ASSIGNMENT \
    NUM_SAMPLES=$NUM_SAMPLES \
    julia --project="$BENCH_DIR" "$SCRIPT_DIR/seam_carving_weak_benchmark.jl" 2>&1 | tee -a "$LOG_FILE" | while read line; do
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
