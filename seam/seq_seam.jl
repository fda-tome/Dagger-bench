# Main script to seam carve 'philip.jpg'

function main()
	img = load_color_image("philip.jpg")
	carved = transpose(img)
	requested = 800  # Number of seams to remove (adjust as needed)
	# Clamp to available columns - 1 to avoid empty image
	num_seams = min(requested, size(carved, 2) - 1)
	for i in 1:num_seams
		e = energy_map(carved)
		@time seam = find_vertical_seam(e)
		carved = remove_vertical_seam(carved, seam)
		println("Removed seam $i")
	end
	save("philip_carved.jpg", transpose(carved))
	println("Saved carved color image as philip_carved.jpg")
end

using Dagger
using Images
using FileIO
using ImageFiltering

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

# Find vertical seam with lowest energy (dynamic programming)
function find_vertical_seam(energy)
	rows, cols = size(energy)
	cost = copy(energy)
	backtrack = zeros(Int, size(energy))
	for i in 2:rows
		for j in 1:cols
			left = j > 1 ? cost[i-1, j-1] : Inf
			up = cost[i-1, j]
			right = j < cols ? cost[i-1, j+1] : Inf
			min_val, idx = findmin([left, up, right])
			cost[i, j] += min_val
			backtrack[i, j] = j + (idx - 2)
		end
	end
	# Backtrack to find seam
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

main()

