using Plots, TimespanLogging, DataFrames
function main()
	img = load_color_image("mirage.jpg")
	carved = transpose(img)
	requested = 800  # Number of seams to remove (adjust as needed)
	base = 200
	# Clamp to available columns - 1 to avoid empty image
	num_seams = min(requested, size(carved, 2) - 1)
    e = energy_map(carved)
    rows, cols = size(e)
    for base in [600, 600]
        for assignment in  [:arbitrary, :cycliccol, :cyclicrow, :blockcol, :blockrow]
            sheight = Int(base / 2 + 1)
            cost = distribute(e, Blocks(sheight, base), assignment)
            backtrack = zeros(Blocks(sheight, base), Int, rows, cols; assignment)
            println("Finding seam with base=$base and assignment=$assignment")
            @time seam = par_find_vseam(base, cost, backtrack)
		    carved = remove_vertical_seam(carved, seam)
        end
	end
	save("mirage_carved.jpg", transpose(carved))
	println("Saved carved color image as mirage_carved.jpg")
end

using Dagger
using Images
using FileIO
using ImageFiltering

function calc_tri_up_first(rightcp, rhalf, backtrackr, bwidth, out_idxr)
	mr, nr = size(rhalf)
	for i in 2:mr
		for j in 1:(1 + i - 2)
			left = j == 1 ? Inf : rhalf[i-1, j-1]
			up = rhalf[i-1, j]
			right = j == nr ? rightcp[i-1] : rhalf[i-1, j+1]
			min_val, idx = findmin(first.([left, up, right]))
			rhalf[i, j] += min_val
			backtrackr[i, j] = (out_idxr[2] + j - 1) + (idx - 1)
		end
	end
end

function calc_tri_up_last(leftcp, lhalf, backtrackl, bwidth, out_idxl)
	ml, nl = size(lhalf)
	h = Int(bwidth / 2)
	jstart = nl < h ? nl : h
    cropped = h - nl + 1

    for i in (2+cropped):ml
		for j in jstart:-1:(jstart - i + 2 + cropped)
			left = j == 1 ? leftcp[i-1] : lhalf[i-1, j-1]
			up = lhalf[i-1, j]
			right = Inf
			min_val, idx = findmin([left, up, right])
			lhalf[i, j] += min_val
			backtrackl[i, j] = (out_idxl[2] + j - 1) + (idx - 1)
		end
	end
end

function calc_tri_up(leftcp, rightcp, lhalf, rhalf, backtrackl, backtrackr, bwidth, out_idxl, out_idxr)
	ml, nl = size(lhalf)
	mr, nr = size(rhalf)
	h = Int(bwidth / 2)
	jstart = nl < h ? nl : h
	jfinish = 1
	cropped = h - nl + 1
	for i in 2:ml
		for j in jstart:-1:jstart - i + 2
			left = j == 1 ? leftcp[i-1] : lhalf[i-1, j-1]
			up = lhalf[i-1, j]
			right = rhalf[i-1, 1]
			min_val, idx = findmin([left, up, right])
			lhalf[i, j] += min_val
			backtrackl[i, j] = (out_idxl[2] + j - 1) + (idx - 2)
		end
		for j in 1:jfinish
			left = j == 1 ? leftcp[i-1] : lhalf[i-1, j-1]
			up = rhalf[i-1, j]
			right = j == nr ? rightcp[i-1] : rhalf[i-1, j+1]
			min_val, idx = findmin([left, up, right])
			rhalf[i, j] += min_val
			backtrackr[i, j] = (out_idxr[2] + j - 1) + (idx - 2)
		end
		if cropped == 0
			jfinish += 1
		else
			cropped -= 1
		end
	end
end

function calc_tri_down(leftl, upl, rightl, cost, backtrack, bwidth, out_idx)
	m, n = size(cost)
	jstart = 1
	jfinish = n
	cropped = bwidth - n + 1
	if cropped == 0
		jfinish -= 1
		cropped -= 1
	end
	for i in 1:m
		for j in jstart:jfinish
			if i == 1
				left = leftl
				up = upl[j]
				right = rightl
			else
				left = j == 1 ? Inf : cost[i-1, j-1]
				up = cost[i-1, j]
				right = j == n ? Inf : cost[i-1, j+1]
			end
			min_val, idx = findmin(first.([left, up, right]))
			cost[i, j] += min_val
			backtrack[i, j] = (out_idx[2] + j - 1) + (idx - 2)
		end
		if cropped == 0
			jfinish -= 1
		else
			cropped -= 1
		end
		jstart += 1
	end
end


function par_find_vseam(bwidth, cost, backtrack)
	rows, cols = size(cost)
    costc = cost.chunks
	backtrackc = backtrack.chunks
	mc, nc = size(costc)
	@show rows, cols
	out_idx = Dagger.indexes.(cost.subdomains)
    in_idx = Dagger.indexes.(alignfirst.(cost.subdomains))
	Dagger.spawn_datadeps() do
		for i in 1:mc
			for j in 1:nc
				if i == 1
					idx = in_idx[i,j]
					leftl = Inf
					rightl = Inf
					upl = Array{Float64}(undef, last(last(idx)))
					upl .= Inf
				else
                    if j == 1
					    leftl = Inf
                    else
                        idxl = in_idx[i-1, j-1]
						leftl = @view costc[i-1, j-1][last(first(idxl)), last(last(idxl))]
                    end
                    
                    if j == nc
                        rightl = Inf
                    else
                        idxr = in_idx[i-1, j+1]
						rightl = @view costc[i-1, j+1][last(first(idxr)), first(last(idxr))]
                    end
					idx = in_idx[i-1, j]
					upl = @view costc[i-1, j][last(first(idx)), last(idx)]
				end

                Dagger.@spawn calc_tri_down(In(leftl), In(upl), In(rightl), InOut(costc[i, j]), Out(backtrackc[i, j]), bwidth, first.(out_idx[i,j]))
			end

			h = Int(bwidth / 2)
			idx = in_idx[i, 1]
			n = last(last(idx))
			rcp = Array{Float64}(undef, size(first(idx)))
			if n > h
				viewrcp = @view costc[i, 1][first(idx), h+1]
				Dagger.@spawn copyto!(rcp, In(viewrcp))
			else
				rcp .= Inf
			end

			n = n < h ? n : h
			right = @view costc[i, 1][first(idx), 1:n]
			backtrackr = @view backtrackc[i, 1][first(idx), 1:n]
			Dagger.@spawn calc_tri_up_first(rcp, InOut(right), Out(backtrackr), bwidth, first.(out_idx[i,1]))

			for j in 1:(nc-1)
				idx = in_idx[i, j+1]
				n = last(last(idx))
				rcp = Array{Float64}(undef, size(first(idx)))
				if n > h
					viewrcp = @view costc[i, j+1][first(idx), h+1]
					Dagger.@spawn copyto!(rcp, In(viewrcp))
				else
					rcp .= Inf
				end

				n = n < h ? n : h
				right = @view costc[i, j+1][first(idx), 1:n]
				backtrackr = @view backtrackc[i, j+1][first(idx), 1:n]

				idx = in_idx[i, j]
				lcp = Array{Float64}(undef, size(first(idx)))
				viewlcp = @view costc[i, j][first(idx), last(last(idx))]
				Dagger.@spawn copyto!(lcp, In(viewlcp))
				left = @view costc[i, j][first(idx), h+1:last(last(idx))]
				backtrackl = @view backtrackc[i, j][first(idx), h+1:last(last(idx))]

				Dagger.@spawn calc_tri_up(lcp, rcp, InOut(left), InOut(right), Out(backtrackl), Out(backtrackr), bwidth, first.(out_idx[i,j]), first.(out_idx[i,j+1]))
			end

			idx = in_idx[i, nc]
			n = last(last(idx))
			if n > h 
				lcp = Array{Float64}(undef, size(first(idx)))
				viewlcp = @view costc[i, nc][first(idx), last(last(idx))]
				Dagger.@spawn copyto!(lcp, In(viewlcp))
				left = @view costc[i, nc][first(idx), h+1:last(last(idx))]
				backtrackl = @view backtrackc[i, nc][first(idx), h+1:last(last(idx))]
				Dagger.@spawn calc_tri_up_last(lcp, InOut(left), Out(backtrackl), bwidth, first.(out_idx[i,nc]))
			end
		end

	end
	cost = collect(cost)
	backtrack = collect(backtrack)
	seam = zeros(Int, rows)
	# Convert the last row to a vector to get a single index
	inds = findall(x->x==0, backtrack)
	display(inds)
	seam[rows] = argmin(vec(@view cost[rows, :]))
	for i in rows-1:-1:1
		seam[i] = backtrack[i+1, seam[i+1]]
	end
	return seam
end

function calculate_triangle_down(leftl, upl, rightl, cost, backtrack, bwidth, out_idx)
	m, n = size(cost)
	jstart = 1
	jfinish = n
	cropped = bwidth - n + 1
	if cropped == 0
		jfinish -= 1
		cropped -= 1
	end
	for i in 1:m
		for j in jstart:jfinish
			if i == 1
				left = leftl
				up = upl[j]
				right = rightl
			else
				left = j == 1 ? Inf : cost[i-1, j-1]
				up = cost[i-1, j]
				right = j == n ? Inf : cost[i-1, j+1]
			end
			min_val, idx = findmin(first.([left, up, right]))
			cost[i, j] += min_val
			backtrack[i, j] = (out_idx[2] + j - 1) + (idx - 2)
		end
		if cropped == 0
			jfinish -= 1
		else
			cropped -= 1
		end
		jstart += 1
	end
end

function calculate_triangle_up(left, right, lhalf, rhalfcost, backtrack, bwidth, out_idx)
	m, n = size(cost)
	h = Int(bwidth / 2)
    jfinish = n < h ? n : h
	for i in 2:m 
		for j in 1:jfinish
			left = j == 1 ? lneighbor[i-1] : cost[i-1, j-1]
			up = cost[i-1, j]
			right = j == n ? rneighbor[i-1] : cost[i-1, j+1]
			min_val, idx = findmin(first.([left, up, right]))
			cost[i, j] += min_val
			backtrack[i, j] = (out_idx[2] + j - 1) + (idx - 2)
			ridx = bwidth - j + 1
			if ridx <= n
				right = ridx == n ? rneighbor[i-1] : cost[i-1, ridx+1]
				up = cost[i-1, ridx]
				left = ridx == 1 ? lneighbor[i-1] : cost[i-1, ridx-1]
				min_val, idx = findmin(first.([left, up, right]))
				cost[i, ridx] += min_val
				backtrack[i, ridx] = (out_idx[2] + ridx -1) + (idx - 2) 
			end
		end
	end
end

function parallel_find_vertical_seam(bwidth, cost, backtrack)
	rows, cols = size(cost)
    costc = cost.chunks
	backtrackc = backtrack.chunks
	mc, nc = size(costc)
	@show rows, cols
	out_idx = Dagger.indexes.(cost.subdomains)
    in_idx = Dagger.indexes.(alignfirst.(cost.subdomains))
	Dagger.spawn_datadeps() do
		for i in 1:mc
			for j in 1:nc
				if j == 1
					idx = in_idx[i, j]
					lneighbor = Array{Float64}(undef, size(first(idx)))
					lneighbor .= Inf
				else
					idx = in_idx[i, j-1]
					lneighbor = @view costc[i, j-1][first(idx), last(last(idx))]
				end

				if j == nc
					idx = in_idx[i, j]
					rneighbor = Array{Float64}(undef, size(first(idx)))
					rneighbor .= Inf
				else
					idx = in_idx[i, j+1]
					rneighbor = @view costc[i, j+1][first(idx), last(last(idx))]
				end

				if i == 1
					idx = in_idx[i,j]
					leftl = Inf
					rightl = Inf
					upl = Array{Float64}(undef, last(last(idx)))
					upl .= Inf
				else
                    if j == 1
					    leftl = Inf
                    else
                        idxl = in_idx[i-1, j-1]
                        leftl = @view costc[i-1, j-1][last(first(idxl)), last(last(idxl))]
                    end
                    
                    if j == nc
                        rightl = Inf
                    else
                        idxr = in_idx[i-1, j+1]
                        rightl = @view costc[i-1, j+1][last(first(idxr)), first(last(idxr))]
                    end
					idx = in_idx[i-1, j]
					upl = @view costc[i-1, j][last(first(idx)), last(idx)]
				end
                Dagger.@spawn calculate_triangle_down(In(leftl), In(upl), In(rightl), InOut(costc[i, j]), Out(backtrackc[i, j]), bwidth, first.(out_idx[i,j]))
                Dagger.@spawn calculate_triangle_up(In(lneighbor), In(rneighbor), InOut(costc[i, j]), Out(backtrackc[i, j]), bwidth, first.(out_idx[i,j]))
			end
		end
	end
	cost = collect(cost)
	backtrack = collect(backtrack)
	seam = zeros(Int, rows)
	# Convert the last row to a vector to get a single index
	seam[rows] = argmin(vec(@view cost[rows, :]))
	for i in rows-1:-1:1
		seam[i] = backtrack[i+1, seam[i+1]]
	end
	return seam
end

# Remove the found seam from the image
function remove_vertical_seam(img, seam)
	rows, cols = size(img)
	out = similar(img, rows, cols - 1)
	for i in 1:rows
		j = seam[i]
		if j > 1
			@inbounds out[i, 1:j-1] = img[i, 1:j-1]
		end
		if j <= cols - 1
			@inbounds out[i, j:cols-1] = img[i, j+1:cols]
		end
	end
	return out
end

# Load image in color (preserve channels)
function load_color_image(path)
	img = load(path)
	# Ensure a 2D array of RGB colorants
	return RGB.(img)
end

# Compute energy map (simple gradient magnitude)
function energy_map(img)
	# Sobel gradient magnitude summed over RGB channels
	rgb = RGB.(img)
	rows, cols = size(rgb)
	chs = channelview(rgb)  # (3, rows, cols)
	kx = [-1 0 1; -2 0 2; -1 0 1] ./ 8
	ky = [-1 -2 -1; 0 0 0; 1 2 1] ./ 8
	energy = zeros(Float32, rows, cols)
	@inbounds for c in 1:size(chs, 1)
		chan = Float32.(view(chs, c, :, :))
		gx = imfilter(chan, kx)
		gy = imfilter(chan, ky)
		energy .+= abs.(gx) .+ abs.(gy)
	end
	return energy
end

main()
