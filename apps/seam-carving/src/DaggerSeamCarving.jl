module DaggerSeamCarving

using Dagger
using KernelAbstractions

const DEFAULT_THREADS = 256

@inline clampi(x, lo, hi) = x < lo ? lo : (x > hi ? hi : x)

function energy_cpu(img::AbstractMatrix{T}) where T
    H, W = size(img)
    ET = promote_type(T, Float32)
    E = Array{ET}(undef, H, W)
    Threads.@threads for y in 1:H
        ym = y == 1 ? 1 : y - 1
        yp = y == H ? H : y + 1
        @inbounds for x in 1:W
            xm = x == 1 ? 1 : x - 1
            xp = x == W ? W : x + 1
            dx = abs(ET(img[y, xp]) - ET(img[y, xm]))
            dy = abs(ET(img[yp, x]) - ET(img[ym, x]))
            E[y, x] = dx + dy
        end
    end
    return E
end

function cumulative_energy_cpu(E::AbstractMatrix{T}) where T
    H, W = size(E)
    M = Array{T}(undef, H, W)
    B = Array{Int8}(undef, H, W)
    @inbounds begin
        M[1, :] .= E[1, :]
        B[1, :] .= 0
    end
    for y in 2:H
        Threads.@threads for x in 1:W
            @inbounds begin
                left = x > 1 ? M[y - 1, x - 1] : typemax(T)
                mid = M[y - 1, x]
                right = x < W ? M[y - 1, x + 1] : typemax(T)
                if left <= mid && left <= right
                    M[y, x] = E[y, x] + left
                    B[y, x] = -1
                elseif mid <= right
                    M[y, x] = E[y, x] + mid
                    B[y, x] = 0
                else
                    M[y, x] = E[y, x] + right
                    B[y, x] = 1
                end
            end
        end
    end
    return M, B
end

function dp_tile!(E::AbstractMatrix{T}, M::AbstractMatrix{T}, B::AbstractMatrix{Int8},
                  y1::Int, y2::Int, x1::Int, x2::Int) where T
    H, W = size(E)
    @inbounds for y in y1:y2
        if y == 1
            for x in x1:x2
                M[1, x] = E[1, x]
                B[1, x] = 0
            end
            continue
        end
        for x in x1:x2
            left = x > 1 ? M[y - 1, x - 1] : typemax(T)
            mid = M[y - 1, x]
            right = x < W ? M[y - 1, x + 1] : typemax(T)
            if left <= mid && left <= right
                M[y, x] = E[y, x] + left
                B[y, x] = -1
            elseif mid <= right
                M[y, x] = E[y, x] + mid
                B[y, x] = 0
            else
                M[y, x] = E[y, x] + right
                B[y, x] = 1
            end
        end
    end
    return nothing
end

@inline function dp_tile_wait(::Tuple, E, M, B, y1::Int, y2::Int, x1::Int, x2::Int)
    dp_tile!(E, M, B, y1, y2, x1, x2)
    return nothing
end

function cumulative_energy_cpu_wavefront(E::AbstractMatrix{T}; tile_h::Int = 64, tile_w::Int = 64) where T
    H, W = size(E)
    M = Array{T}(undef, H, W)
    B = Array{Int8}(undef, H, W)
    nty = cld(H, tile_h)
    ntx = cld(W, tile_w)
    tasks = Array{Any}(undef, nty, ntx)
    for ty in 1:nty
        y1 = (ty - 1) * tile_h + 1
        y2 = min(ty * tile_h, H)
        for tx in 1:ntx
            x1 = (tx - 1) * tile_w + 1
            x2 = min(tx * tile_w, W)
            if ty == 1
                tasks[ty, tx] = Dagger.@spawn dp_tile!(E, M, B, y1, y2, x1, x2)
            else
                deps = Any[tasks[ty - 1, tx]]
                if tx > 1
                    push!(deps, tasks[ty - 1, tx - 1])
                end
                if tx < ntx
                    push!(deps, tasks[ty - 1, tx + 1])
                end
                tasks[ty, tx] = Dagger.@spawn dp_tile_wait(tuple(deps...), E, M, B, y1, y2, x1, x2)
            end
        end
    end
    for tx in 1:ntx
        Dagger.fetch(tasks[nty, tx])
    end
    return M, B
end

function cumulative_energy_cpu_wavefront_overlap(img::AbstractMatrix{T}; tile_h::Int = 64, tile_w::Int = 64) where T
    H, W = size(img)
    ET = promote_type(T, Float32)
    E = Array{ET}(undef, H, W)
    M = Array{ET}(undef, H, W)
    B = Array{Int8}(undef, H, W)
    nty = cld(H, tile_h)
    ntx = cld(W, tile_w)
    energy_tasks = Array{Any}(undef, nty, ntx)
    dp_tasks = Array{Any}(undef, nty, ntx)
    for ty in 1:nty, tx in 1:ntx
        y1 = (ty - 1) * tile_h + 1
        y2 = min(ty * tile_h, H)
        x1 = (tx - 1) * tile_w + 1
        x2 = min(tx * tile_w, W)
        energy_tasks[ty, tx] = Dagger.@spawn energy_cpu_tile!(E, img, y1, y2, x1, x2)
    end
    for ty in 1:nty, tx in 1:ntx
        y1 = (ty - 1) * tile_h + 1
        y2 = min(ty * tile_h, H)
        x1 = (tx - 1) * tile_w + 1
        x2 = min(tx * tile_w, W)
        deps = Any[energy_tasks[ty, tx]]
        if ty > 1
            push!(deps, dp_tasks[ty - 1, tx])
            if tx > 1
                push!(deps, dp_tasks[ty - 1, tx - 1])
            end
            if tx < ntx
                push!(deps, dp_tasks[ty - 1, tx + 1])
            end
        end
        dp_tasks[ty, tx] = Dagger.@spawn dp_tile_wait(tuple(deps...), E, M, B, y1, y2, x1, x2)
    end
    for tx in 1:ntx
        Dagger.fetch(dp_tasks[nty, tx])
    end
    return M, B
end

function dp_triangle_down!(E::AbstractMatrix{T}, M::AbstractMatrix{T}, B::AbstractMatrix{Int8},
                           y0::Int, y1::Int, x0::Int, x1::Int) where T
    H, W = size(E)
    @inbounds for y in y0:y1
        r = y - y0
        xl = max(1, x0 - r)
        xr = min(W, x1 + r)
        for x in xl:xr
            left = x > 1 ? M[y - 1, x - 1] : typemax(T)
            mid = M[y - 1, x]
            right = x < W ? M[y - 1, x + 1] : typemax(T)
            if left <= mid && left <= right
                M[y, x] = E[y, x] + left
                B[y, x] = -1
            elseif mid <= right
                M[y, x] = E[y, x] + mid
                B[y, x] = 0
            else
                M[y, x] = E[y, x] + right
                B[y, x] = 1
            end
        end
    end
    return nothing
end

function dp_triangle_up!(E::AbstractMatrix{T}, M::AbstractMatrix{T}, B::AbstractMatrix{Int8},
                         y0::Int, y1::Int, x0::Int, x1::Int) where T
    H, W = size(E)
    @inbounds for y in y0:y1
        r = y - y0
        xl = x0 + r
        xr = x1 - r
        if xl > xr
            break
        end
        xl = max(1, xl)
        xr = min(W, xr)
        for x in xl:xr
            left = x > 1 ? M[y - 1, x - 1] : typemax(T)
            mid = M[y - 1, x]
            right = x < W ? M[y - 1, x + 1] : typemax(T)
            if left <= mid && left <= right
                M[y, x] = E[y, x] + left
                B[y, x] = -1
            elseif mid <= right
                M[y, x] = E[y, x] + mid
                B[y, x] = 0
            else
                M[y, x] = E[y, x] + right
                B[y, x] = 1
            end
        end
    end
    return nothing
end

function cumulative_energy_cpu_triangles(E::AbstractMatrix{T}; tile_h::Int = 64, tile_w::Int = 128) where T
    H, W = size(E)
    M = Array{T}(undef, H, W)
    B = Array{Int8}(undef, H, W)
    @inbounds begin
        M[1, :] .= E[1, :]
        B[1, :] .= 0
    end
    if H == 1
        return M, B
    end
    strip_h = tile_h
    base_w = max(tile_w, 2 * strip_h)
    nseg = cld(W, base_w)
    y0 = 2
    while y0 <= H
        y1 = min(y0 + strip_h - 1, H)
        tasks = Any[]
        for seg in 1:nseg
            if isodd(seg)
                x0 = (seg - 1) * base_w + 1
                x1 = min(seg * base_w, W)
                push!(tasks, Dagger.@spawn dp_triangle_down!(E, M, B, y0, y1, x0, x1))
            end
        end
        foreach(Dagger.fetch, tasks)
        empty!(tasks)
        for seg in 2:2:nseg
            x0 = (seg - 1) * base_w + 1
            x1 = min(seg * base_w, W)
            push!(tasks, Dagger.@spawn dp_triangle_up!(E, M, B, y0, y1, x0, x1))
        end
        foreach(Dagger.fetch, tasks)
        y0 = y1 + 1
    end
    return M, B
end

function find_seam(M::AbstractMatrix{T}, B::AbstractMatrix{Int8}) where T
    H, W = size(M)
    seam = Vector{Int}(undef, H)
    minv = M[H, 1]
    idx = 1
    @inbounds for x in 2:W
        if M[H, x] < minv
            minv = M[H, x]
            idx = x
        end
    end
    seam[H] = idx
    @inbounds for y in (H - 1):-1:1
        seam[y] = clampi(seam[y + 1] + B[y + 1, seam[y + 1]], 1, W)
    end
    return seam
end

@inline function find_seam_from_mb(MB)
    M, B = MB
    return find_seam(M, B)
end

function remove_seam(img::AbstractMatrix{T}, seam::Vector{Int}) where T
    H, W = size(img)
    out = Array{T}(undef, H, W - 1)
    Threads.@threads for y in 1:H
        s = seam[y]
        if s > 1
            @inbounds copyto!(view(out, y, 1:s - 1), view(img, y, 1:s - 1))
        end
        if s < W
            @inbounds copyto!(view(out, y, s:W - 1), view(img, y, s + 1:W))
        end
    end
    return out
end

function seam_carve_cpu_dagger(img::AbstractMatrix{T}; k::Int = 1) where T
    img_cur = img
    for _ in 1:k
        E = Dagger.@spawn energy_cpu(img_cur)
        MB = Dagger.@spawn cumulative_energy_cpu(E)
        seam = Dagger.@spawn find_seam_from_mb(MB)
        img_cur = Dagger.@spawn remove_seam(img_cur, seam)
    end
    return Dagger.fetch(img_cur)
end


function energy_cpu_tile(img::AbstractMatrix{T}, y1::Int, y2::Int, x1::Int, x2::Int) where T
    H, W = size(img)
    ET = promote_type(T, Float32)
    tile = Array{ET}(undef, y2 - y1 + 1, x2 - x1 + 1)
    Threads.@threads for y in y1:y2
        ym = y == 1 ? 1 : y - 1
        yp = y == H ? H : y + 1
        @inbounds for x in x1:x2
            xm = x == 1 ? 1 : x - 1
            xp = x == W ? W : x + 1
            dx = abs(ET(img[y, xp]) - ET(img[y, xm]))
            dy = abs(ET(img[yp, x]) - ET(img[ym, x]))
            tile[y - y1 + 1, x - x1 + 1] = dx + dy
        end
    end
    return tile
end

function energy_cpu_tile!(E::AbstractMatrix{ET}, img::AbstractMatrix{T}, y1::Int, y2::Int, x1::Int, x2::Int) where {ET,T}
    H, W = size(img)
    Threads.@threads for y in y1:y2
        ym = y == 1 ? 1 : y - 1
        yp = y == H ? H : y + 1
        @inbounds for x in x1:x2
            xm = x == 1 ? 1 : x - 1
            xp = x == W ? W : x + 1
            dx = abs(ET(img[y, xp]) - ET(img[y, xm]))
            dy = abs(ET(img[yp, x]) - ET(img[ym, x]))
            E[y, x] = dx + dy
        end
    end
    return nothing
end

function energy_cpu_dagger_tiled(img::AbstractMatrix{T}; tile_h::Int = 256, tile_w::Int = 256) where T
    H, W = size(img)
    nty = cld(H, tile_h)
    ntx = cld(W, tile_w)
    tasks = Array{Any}(undef, nty, ntx)
    for ty in 1:nty, tx in 1:ntx
        y1 = (ty - 1) * tile_h + 1
        y2 = min(ty * tile_h, H)
        x1 = (tx - 1) * tile_w + 1
        x2 = min(tx * tile_w, W)
        tasks[ty, tx] = Dagger.@spawn energy_cpu_tile(img, y1, y2, x1, x2)
    end
    E = Array{promote_type(T, Float32)}(undef, H, W)
    for ty in 1:nty, tx in 1:ntx
        y1 = (ty - 1) * tile_h + 1
        y2 = min(ty * tile_h, H)
        x1 = (tx - 1) * tile_w + 1
        x2 = min(tx * tile_w, W)
        tile = Dagger.fetch(tasks[ty, tx])
        @inbounds E[y1:y2, x1:x2] .= tile
    end
    return E
end

function remove_seam_block(img::AbstractMatrix{T}, seam::Vector{Int}, y1::Int, y2::Int) where T
    H, W = size(img)
    block = Array{T}(undef, y2 - y1 + 1, W - 1)
    Threads.@threads for y in y1:y2
        s = seam[y]
        if s > 1
            @inbounds copyto!(view(block, y - y1 + 1, 1:s - 1), view(img, y, 1:s - 1))
        end
        if s < W
            @inbounds copyto!(view(block, y - y1 + 1, s:W - 1), view(img, y, s + 1:W))
        end
    end
    return block
end

function remove_seam_dagger_tiled(img::AbstractMatrix{T}, seam::Vector{Int}; tile_h::Int = 256) where T
    H, W = size(img)
    nty = cld(H, tile_h)
    tasks = Vector{Any}(undef, nty)
    for ty in 1:nty
        y1 = (ty - 1) * tile_h + 1
        y2 = min(ty * tile_h, H)
        tasks[ty] = Dagger.@spawn remove_seam_block(img, seam, y1, y2)
    end
    out = Array{T}(undef, H, W - 1)
    for ty in 1:nty
        y1 = (ty - 1) * tile_h + 1
        y2 = min(ty * tile_h, H)
        block = Dagger.fetch(tasks[ty])
        @inbounds out[y1:y2, :] .= block
    end
    return out
end

function seam_carve_cpu_dagger_tiled(img::AbstractMatrix{T}; k::Int = 1, tile_h::Int = 256, tile_w::Int = 256) where T
    img_cur = img
    for _ in 1:k
        E = energy_cpu_dagger_tiled(img_cur; tile_h=tile_h, tile_w=tile_w)
        M, B = cumulative_energy_cpu(E)
        seam = find_seam(M, B)
        img_cur = remove_seam_dagger_tiled(img_cur, seam; tile_h=tile_h)
    end
    return img_cur
end


function seam_carve_cpu_dagger_wavefront(img::AbstractMatrix{T}; k::Int = 1, tile_h::Int = 64, tile_w::Int = 64) where T
    img_cur = img
    for _ in 1:k
        E = energy_cpu(img_cur)
        M, B = cumulative_energy_cpu_wavefront(E; tile_h=tile_h, tile_w=tile_w)
        seam = find_seam(M, B)
        img_cur = remove_seam(img_cur, seam)
    end
    return img_cur
end

function seam_step_tileoverlap(img::AbstractMatrix{T}; tile_h::Int = 64, tile_w::Int = 64) where T
    M, B = cumulative_energy_cpu_wavefront_overlap(img; tile_h=tile_h, tile_w=tile_w)
    seam = find_seam(M, B)
    return remove_seam(img, seam)
end

function seam_carve_cpu_dagger_tileoverlap(img::AbstractMatrix{T}; k::Int = 1, tile_h::Int = 64, tile_w::Int = 64) where T
    img_cur = img
    for _ in 1:k
        img_cur = seam_step_tileoverlap(img_cur; tile_h=tile_h, tile_w=tile_w)
    end
    return img_cur
end


function seam_carve_cpu_dagger_triangles(img::AbstractMatrix{T}; k::Int = 1, tile_h::Int = 64, tile_w::Int = 128) where T
    img_cur = img
    for _ in 1:k
        E = energy_cpu(img_cur)
        M, B = cumulative_energy_cpu_triangles(E; tile_h=tile_h, tile_w=tile_w)
        seam = find_seam(M, B)
        img_cur = remove_seam(img_cur, seam)
    end
    return img_cur
end

function energy_cpu_serial(img::AbstractMatrix{T}) where T
    H, W = size(img)
    ET = promote_type(T, Float32)
    E = Array{ET}(undef, H, W)
    for y in 1:H
        ym = y == 1 ? 1 : y - 1
        yp = y == H ? H : y + 1
        @inbounds for x in 1:W
            xm = x == 1 ? 1 : x - 1
            xp = x == W ? W : x + 1
            dx = abs(ET(img[y, xp]) - ET(img[y, xm]))
            dy = abs(ET(img[yp, x]) - ET(img[ym, x]))
            E[y, x] = dx + dy
        end
    end
    return E
end

function cumulative_energy_cpu_serial(E::AbstractMatrix{T}) where T
    H, W = size(E)
    M = Array{T}(undef, H, W)
    B = Array{Int8}(undef, H, W)
    @inbounds begin
        M[1, :] .= E[1, :]
        B[1, :] .= 0
    end
    for y in 2:H
        @inbounds for x in 1:W
            left = x > 1 ? M[y - 1, x - 1] : typemax(T)
            mid = M[y - 1, x]
            right = x < W ? M[y - 1, x + 1] : typemax(T)
            if left <= mid && left <= right
                M[y, x] = E[y, x] + left
                B[y, x] = -1
            elseif mid <= right
                M[y, x] = E[y, x] + mid
                B[y, x] = 0
            else
                M[y, x] = E[y, x] + right
                B[y, x] = 1
            end
        end
    end
    return M, B
end

function remove_seam_serial(img::AbstractMatrix{T}, seam::Vector{Int}) where T
    H, W = size(img)
    out = Array{T}(undef, H, W - 1)
    for y in 1:H
        s = seam[y]
        if s > 1
            @inbounds copyto!(view(out, y, 1:s - 1), view(img, y, 1:s - 1))
        end
        if s < W
            @inbounds copyto!(view(out, y, s:W - 1), view(img, y, s + 1:W))
        end
    end
    return out
end

function seam_carve_cpu_serial(img::AbstractMatrix{T}; k::Int = 1) where T
    img_cur = img
    for _ in 1:k
        E = energy_cpu_serial(img_cur)
        M, B = cumulative_energy_cpu_serial(E)
        seam = find_seam(M, B)
        img_cur = remove_seam_serial(img_cur, seam)
    end
    return img_cur
end


const KA = KernelAbstractions

@kernel function energy_kernel!(E, I, H::Int, W::Int)
    idx = @index(Global)
    if idx <= H * W
        y = (idx - 1) ÷ W + 1
        x = (idx - 1) % W + 1
        xm = x == 1 ? 1 : x - 1
        xp = x == W ? W : x + 1
        ym = y == 1 ? 1 : y - 1
        yp = y == H ? H : y + 1
        E[y, x] = abs(I[y, xp] - I[y, xm]) + abs(I[yp, x] - I[ym, x])
    end
end

function energy_gpu(img::AbstractArray{T, 2}) where T
    H, W = size(img)
    E = similar(img)
    backend = KA.get_backend(img)
    threads = DEFAULT_THREADS
    energy_kernel!(backend, threads)(E, img, H, W; ndrange=H * W)
    KA.synchronize(backend)
    return E
end

@kernel function dp_row_kernel!(M, B, E, y::Int, W::Int)
    x = @index(Global)
    if x <= W
        left = x > 1 ? M[y - 1, x - 1] : typemax(eltype(M))
        mid = M[y - 1, x]
        right = x < W ? M[y - 1, x + 1] : typemax(eltype(M))
        if left <= mid && left <= right
            M[y, x] = E[y, x] + left
            B[y, x] = Int8(-1)
        elseif mid <= right
            M[y, x] = E[y, x] + mid
            B[y, x] = Int8(0)
        else
            M[y, x] = E[y, x] + right
            B[y, x] = Int8(1)
        end
    end
end

function cumulative_energy_gpu(E::AbstractArray{T, 2}) where T
    H, W = size(E)
    M = similar(E)
    B = similar(E, Int8, H, W)
    M[1, :] .= E[1, :]
    B[1, :] .= 0
    backend = KA.get_backend(E)
    threads = DEFAULT_THREADS
    for y in 2:H
        dp_row_kernel!(backend, threads)(M, B, E, y, W; ndrange=W)
        KA.synchronize(backend)
    end
    return M, B
end

@kernel function seam_backtrack_kernel!(seam, M, B, H::Int, W::Int)
    i = @index(Global)
    if i == 1
        minv = M[H, 1]
        idx = 1
        for x in 2:W
            v = M[H, x]
            if v < minv
                minv = v
                idx = x
            end
        end
        seam[H] = idx
        for y in (H - 1):-1:1
            seam[y] = clampi(seam[y + 1] + B[y + 1, seam[y + 1]], 1, W)
        end
    end
end

function find_seam_gpu_device(M::AbstractArray{T, 2}, B::AbstractArray{Int8, 2}) where T
    H, W = size(M)
    seam = similar(M, Int32, H)
    backend = KA.get_backend(M)
    seam_backtrack_kernel!(backend, 1)(seam, M, B, H, W; ndrange=1)
    KA.synchronize(backend)
    return seam
end

function find_seam_gpu(M::AbstractArray{T, 2}, B::AbstractArray{Int8, 2}) where T
    H, W = size(M)
    last = Array(view(M, H, :))
    minv = last[1]
    idx = 1
    @inbounds for x in 2:W
        if last[x] < minv
            minv = last[x]
            idx = x
        end
    end
    B_cpu = Array(B)
    seam = Vector{Int}(undef, H)
    seam[H] = idx
    @inbounds for y in (H - 1):-1:1
        seam[y] = clampi(seam[y + 1] + B_cpu[y + 1, seam[y + 1]], 1, W)
    end
    return seam
end

@inline function find_seam_gpu_from_mb(MB)
    M, B = MB
    return find_seam_gpu(M, B)
end

@kernel function remove_seam_kernel!(out, img, seam, H::Int, W::Int)
    idx = @index(Global)
    if idx <= H * (W - 1)
        y = (idx - 1) ÷ (W - 1) + 1
        x = (idx - 1) % (W - 1) + 1
        s = seam[y]
        srcx = x < s ? x : x + 1
        out[y, x] = img[y, srcx]
    end
end

function remove_seam_gpu(img::AbstractArray{T, 2}, seam::Vector{Int}) where T
    H, W = size(img)
    out = similar(img, T, H, W - 1)
    seam_d = similar(img, Int32, H)
    copyto!(seam_d, Int32.(seam))
    backend = KA.get_backend(img)
    threads = DEFAULT_THREADS
    remove_seam_kernel!(backend, threads)(out, img, seam_d, H, W; ndrange=H * (W - 1))
    KA.synchronize(backend)
    return out
end

function remove_seam_gpu_device(img::AbstractArray{T, 2}, seam_d::AbstractArray{Int32}) where T
    H, W = size(img)
    out = similar(img, T, H, W - 1)
    backend = KA.get_backend(img)
    threads = DEFAULT_THREADS
    remove_seam_kernel!(backend, threads)(out, img, seam_d, H, W; ndrange=H * (W - 1))
    KA.synchronize(backend)
    return out
end

function seam_carve_gpu_dagger(img::AbstractArray{T, 2}; k::Int = 1) where T
    img_cur = img
    for _ in 1:k
        E = Dagger.@spawn energy_gpu(img_cur)
        MB = Dagger.@spawn cumulative_energy_gpu(E)
        seam = Dagger.@spawn find_seam_gpu_from_mb(MB)
        img_cur = Dagger.@spawn remove_seam_gpu(img_cur, seam)
    end
    return Dagger.fetch(img_cur)
end

function seam_carve_gpu_dagger_device(img::AbstractArray{T, 2}; k::Int = 1) where T
    img_cur = img
    for _ in 1:k
        E = Dagger.@spawn energy_gpu(img_cur)
        MB = Dagger.@spawn cumulative_energy_gpu(E)
        seam_d = Dagger.@spawn find_seam_gpu_device_from_mb(MB)
        img_cur = Dagger.@spawn remove_seam_gpu_device(img_cur, seam_d)
    end
    return Dagger.fetch(img_cur)
end

@inline function find_seam_gpu_device_from_mb(MB)
    M, B = MB
    return find_seam_gpu_device(M, B)
end

end
