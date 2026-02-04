module DaggerAppsBenchmarks

export run_seam_carving, load_seam_carving

const _seam_loaded = Ref(false)
const _seam_run = Ref{Union{Nothing, Function}}(nothing)

function load_seam_carving()
    if !_seam_loaded[]
        Base.include(@__MODULE__, joinpath(@__DIR__, "..", "seam-carving.jl"))
        _seam_run[] = Core.eval(@__MODULE__, :run_benchmark)
        _seam_loaded[] = true
    end
    return nothing
end

function run_seam_carving(; kwargs...)
    load_seam_carving()
    runner = _seam_run[]
    runner === nothing && error("run_benchmark was not loaded for seam-carving.")
    return Base.invokelatest(runner; kwargs...)
end

end
