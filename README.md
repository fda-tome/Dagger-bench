# Dagger-bench

## Overview

This repository contains a comprehensive collection of **benchmarks and demonstrations** for [Dagger.jl](https://github.com/JuliaParallel/Dagger.jl), a framework for out-of-core and parallel computation in Julia. These benchmarks and demos serve as the **official artifacts** accompanying our research paper on parallel computing patterns and performance analysis in Julia.

## About Dagger.jl

[Dagger.jl](https://github.com/JuliaParallel/Dagger.jl) is a powerful Julia package that provides:

- **Task-based parallelism**: Execute computations across multiple processors and machines
- **Out-of-core computing**: Handle datasets larger than available memory
- **Dynamic scheduling**: Intelligently distribute work across available resources
- **Heterogeneous computing**: Support for CPUs, GPUs, and distributed systems
- **Automatic dependency management**: Build complex computational graphs with ease

## Repository Purpose

This repository serves multiple purposes:

1. **Performance Benchmarking**: Systematic evaluation of Dagger.jl's performance characteristics across various workload patterns and system configurations
2. **Demonstration Suite**: Practical examples showcasing Dagger.jl's capabilities and best practices
3. **Reproducible Research**: Complete artifacts enabling reproduction of results presented in our paper
4. **Educational Resource**: Learning materials for developers interested in parallel computing with Julia

## Structure

The repository is organized to facilitate easy navigation and reproduction of results:

```
Dagger-bench/
├── benchmarks/          # Performance benchmarks
│   ├── scalability/     # Scalability analysis
│   ├── throughput/      # Throughput measurements
│   ├── memory/          # Memory usage benchmarks
│   └── comparison/      # Comparisons with other frameworks
├── demos/               # Demonstration applications
│   ├── basic/           # Basic usage examples
│   ├── advanced/        # Advanced patterns and techniques
│   └── real-world/      # Real-world application scenarios
├── data/                # Sample datasets and results
├── scripts/             # Utility scripts for running benchmarks
└── results/             # Benchmark results and analysis
```

## Getting Started

### Prerequisites

- Julia 1.6 or higher
- Dagger.jl package and its dependencies
- (Optional) Multi-core processor or cluster for distributed benchmarks

### Installation

1. Clone this repository:
```bash
git clone https://github.com/fda-tome/Dagger-bench.git
cd Dagger-bench
```

2. Install required Julia packages:
```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

### Running Benchmarks

Each benchmark can be run independently using Julia:

```julia
# Example: Run a specific benchmark
include("benchmarks/scalability/strong_scaling.jl")
```

For batch execution of all benchmarks:
```julia
include("scripts/run_all_benchmarks.jl")
```

## Benchmark Categories

### Scalability Benchmarks
- **Strong Scaling**: Fixed problem size with increasing processors
- **Weak Scaling**: Proportional problem size with increasing processors
- **Efficiency Analysis**: Resource utilization and overhead measurements

### Workload Patterns
- **Embarrassingly Parallel**: Independent task execution
- **Pipeline Processing**: Sequential stage processing
- **MapReduce**: Data-parallel transformations and reductions
- **Graph Computations**: Complex dependency graphs

### System Configurations
- Single-node multi-core
- Multi-node distributed systems
- Heterogeneous computing (CPU + GPU)
- Memory-constrained environments

## Paper Artifacts

This repository contains all artifacts referenced in our paper:

- **Benchmark Code**: All source code for performance measurements
- **Raw Results**: Complete benchmark outputs and measurements
- **Analysis Scripts**: Data processing and visualization code
- **Figures and Tables**: Reproducible generation of all paper figures
- **Environment Specifications**: Complete system configuration details

Results can be reproduced by following the instructions in each benchmark directory.

## Results and Analysis

Benchmark results are stored in the `results/` directory with the following organization:

- Raw data files (CSV, JSON)
- Processed analysis outputs
- Generated plots and visualizations
- Statistical summaries

See `results/README.md` for detailed information about interpreting and reproducing results.

## Contributing

We welcome contributions to improve and extend these benchmarks:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-benchmark`)
3. Add your benchmark or demo with appropriate documentation
4. Ensure code follows Julia best practices
5. Submit a pull request

Please include:
- Clear documentation of what the benchmark measures
- Expected runtime and resource requirements
- Instructions for interpretation of results

## Citation

If you use these benchmarks or build upon this work, please cite our paper:

```bibtex
@article{dagger-bench-2024,
  title={Performance Analysis of Dagger.jl: A Study in Task-Based Parallel Computing},
  author={[Authors]},
  journal={[Journal/Conference]},
  year={2024},
  note={Artifacts available at: https://github.com/fda-tome/Dagger-bench}
}
```

## Acknowledgments

- The [Dagger.jl](https://github.com/JuliaParallel/Dagger.jl) development team
- The Julia parallel computing community
- Contributors to this benchmark suite

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contact

For questions, issues, or suggestions:
- Open an issue on [GitHub](https://github.com/fda-tome/Dagger-bench/issues)
- Contact the maintainers through the issue tracker

## Related Resources

- [Dagger.jl Documentation](https://juliaparallel.org/Dagger.jl/stable/)
- [Julia Parallel Computing](https://docs.julialang.org/en/v1/manual/parallel-computing/)
- [JuliaParallel Organization](https://github.com/JuliaParallel)

---

**Note**: This repository is actively maintained as part of ongoing research. Benchmarks and demos are regularly updated to reflect the latest Dagger.jl capabilities and best practices.