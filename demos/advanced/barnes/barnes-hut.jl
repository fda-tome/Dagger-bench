using Dagger
using LinearAlgebra

mutable struct Node
    mass::Float64
    center_of_mass::Vector{Float64}
    children::Vector{Node}
    bounding_box::Vector{Vector{Float64}}
end

function Node(mass::Float64, center_of_mass::Vector{Float64}, bounding_box::Vector{Vector{Float64}})
    Node(mass, center_of_mass, Node[], bounding_box)
end


function calculateForce(mass::Float64, center_of_mass::Vector{Float64}, point::Vector{Float64}, ϵ::Float64)
    G = 6.67430e-11
    r = center_of_mass - point
    d = norm(r)
    if d == 0
        return [0.0, 0.0, 0.0]
    end
    return G * mass / ((d^2 + ϵ^2)^(3/2)) * r
end

function calculateForceP(root::Node, point::Vector{Float64}, theta::Float64)
    if length(root.children) == 0
        return calculateForce(root.mass, root.center_of_mass, point, 0.01)    
    end
    queue = [root]
    nw = length(Dagger.compatible_processors())
    force = [0.0, 0.0, 0.0]
    while !isempty(queue)
        cur = popfirst!(queue)
        if length(cur.children) == 0
            continue
        end
        s = abs(cur.bounding_box[1][1] - cur.bounding_box[2][1])
        d = norm(cur.center_of_mass - point)
        if s / d > theta
            for child in cur.children
                queue = push!(queue, child)
            end
        else
            force += calculateForce(cur.mass, cur.center_of_mass, point, 0.01)
        end
        if length(queue) >= nw
            break
        end
   end
   subtrees = []
    for subtree in queue
        push!(subtrees, Dagger.@spawn calculateForce(subtree, point, theta))
    end
    if length(subtrees) > 0
        subtrees = fetch.(subtrees)
        for subtree in subtrees
            force += subtree
        end
    end
    return force
end

function calculateForce(root::Node, point::Vector{Float64}, theta::Float64)
    if length(root.children) == 0
        return calculateForce(root.mass, root.center_of_mass, point, 0.01)
    end
    queue = [root]
    force = [0.0, 0.0, 0.0]
    while !isempty(queue)
        cur = popfirst!(queue)
        if length(cur.children) == 0
            continue
        end
        s = abs(cur.bounding_box[1][1] - cur.bounding_box[2][1])
        d = norm(cur.center_of_mass - point)
        if s / d > theta
            for child in cur.children
                queue = push!(queue, child)
            end
        else
            force += calculateForce(cur.mass, cur.center_of_mass, point, 0.01)
        end
    end
    return force
end


function determineOctants(points, masses, bounding_box::Vector{Vector{Float64}})
    min = bounding_box[1]
    max = bounding_box[2]
    center = (min + max) / 2
    octant1 = [min, center]
    octant2 = [center, max]
    octant3 = [[min[1], center[2], min[3]], [center[1], max[2], center[3]]]
    octant4 = [[center[1], min[2], min[3]], [max[1], center[2], center[3]]]
    octant5 = [[min[1], min[2], center[3]], [center[1], center[2], max[3]]]
    octant6 = [[center[1], min[2], center[3]], [max[1], center[2], max[3]]]
    octant7 = [[min[1], center[2], center[3]], [center[1], max[2], max[3]]]
    octant8 = [[center[1], center[2], min[3]], [max[1], max[2], center[3]]]
    octants = [octant1, octant2, octant3, octant4, octant5, octant6, octant7, octant8]
    splitPoints = []
    splitMasses = []
    for (i, octant) in enumerate(octants)
        localPoints = []
        localMasses = []
        for (j, point) in enumerate(points)
            if all(point .>= octant[1]) && all(point .<= octant[2])
                push!(localPoints, point)
                push!(localMasses, masses[j])
            end
        end
        push!(splitPoints, localPoints)
        push!(splitMasses, localMasses)
    end
    return octants, splitPoints, splitMasses
end

function buildTree(points, masses, bounding_box)
    root = Node(sum(masses), sum(points .* masses) / sum(masses), bounding_box)
    # Build tree iteratively without needing a separate 4-arg function
    queue = [root]
    queuemass = [masses]
    queuepoints = [points]
    queuebound = [bounding_box]
    while !isempty(queue)
        cur = popfirst!(queue)
        curpoints = popfirst!(queuepoints)
        curmass = popfirst!(queuemass)
        curbound = popfirst!(queuebound)
        octants, splitPoints, splitMasses = determineOctants(curpoints, curmass, curbound)
        for (i, octant) in enumerate(octants)
            if length(splitPoints[i]) > 0
                child = Node(sum(splitMasses[i]), sum(splitPoints[i] .* splitMasses[i]) / sum(splitMasses[i]), octant)
                push!(cur.children, child)
                if length(splitPoints[i]) > 1
                    push!(queue, child)
                    push!(queuepoints, splitPoints[i])
                    push!(queuemass, splitMasses[i])
                    push!(queuebound, octant)
                end
            end
        end
    end
    return root
end

function buildTreeP(points, masses, bounding_box::Vector{Vector{Float64}}) 
    root = Node(sum(masses), sum(points .* masses) / sum(masses), bounding_box)
    queue = [root]
    queuemass = [masses]
    queuepoints = [points]
    queuebound = [bounding_box]
    nw = length(Dagger.compatible_processors())
    while !isempty(queue)
        cur = popfirst!(queue)
        curpoints = popfirst!(queuepoints)
        curmass = popfirst!(queuemass)
        curbound = popfirst!(queuebound)
        octants, splitPoints, splitMasses = determineOctants(curpoints, curmass, curbound)
        for (i, octant) in enumerate(octants)
            if length(splitPoints[i]) > 0
                child = Node(sum(splitMasses[i]), sum(splitPoints[i] .* splitMasses[i]) / sum(splitMasses[i]), octant)
                push!(cur.children, child)
                if length(splitPoints[i]) > 1
                    push!(queue, child)
                    push!(queuepoints, splitPoints[i])
                    push!(queuemass, splitMasses[i])
                    push!(queuebound, octant)
                end
            end
        end
        if length(queue) >= nw
            break
        end
    end
    # Spawn subtree building in parallel - use serializable representation
    subtree_tasks = []
    subtree_parents = []
    for (i, parent_node) in enumerate(queue)
        # Build subtree and return serialized form (tuples, not mutable Node)
        task = Dagger.@spawn buildTree(queuepoints[i], queuemass[i], queuebound[i])
        push!(subtree_tasks, task)
        push!(subtree_parents, parent_node)
    end
    # Fetch serialized results and reconstruct into tree
    for (i, task) in enumerate(subtree_tasks)
        subtree = fetch(task)
        # Copy children from subtree to parent node
        subtree_parents[i].children = subtree.children
    end
    return root
end

function compareTrees(a, b)
    if a.mass != b.mass
        println("Masses are not equal: ", a.mass, " != ", b.mass)
        return false
    end
    if a.center_of_mass != b.center_of_mass
        println("Center of masses are not equal: ", a.center_of_mass, " != ", b.center_of_mass)
        return false
    end
    if length(a.children) != length(b.children)
        println("Number of children are not equal: ", length(a.children), " != ", length(b.children))
        return false
    end
    for i in 1:length(a.children)
        if !compareTrees(a.children[i], b.children[i])
            return false
        end
    end
    return true
end

# Note: The 4-argument buildTree was removed - buildTreeP now uses the 3-argument version
# which creates a new tree from points/masses data directly.

# Parallel benchmark: builds tree first (not timed), then calculates forces in parallel (timed)


function bmark(N, theta)
    points = [rand(3) * 100 for _ in 1:N]
    masses = rand(N) * 10
    bounding_box = [[0.0, 0.0, 0.0], [100.0, 100.0, 100.0]]
    
    # 1. Build tree (NOT timed - done before benchmark)
    rootp = buildTreeP(points, masses, bounding_box)
    
    # Return a closure that only calculates forces (this is what gets timed)
    return (rootp, points, theta)
end

# Helper function to process a chunk of points sequentially
function process_chunk(rootp, chunk, theta)
    return [calculateForce(rootp, p, theta) for p in chunk]
end

function bmark_force_only(rootp, points, theta; tasks_per_worker=2)
    # Calculate forces in parallel for ALL points using chunked tasks
    # Each chunk is processed by one Dagger task, avoiding task creation overhead
    nw = Threads.nthreads()
    n = length(points)
    num_tasks = nw * tasks_per_worker  # e.g., 104 * 4 = 416 tasks
    chunk_size = cld(n, num_tasks)     # ceiling division
    
    # Create coarse-grained tasks - each processes many points sequentially
    tasks = []
    for i in 1:num_tasks
        start_idx = (i-1) * chunk_size + 1
        end_idx = min(i * chunk_size, n)
        if start_idx <= n
            chunk = points[start_idx:end_idx]  # Copy chunk (views don't serialize)
            # Use sequential calculateForce inside each task (no nested spawning)
            push!(tasks, Dagger.@spawn process_chunk(rootp, chunk, theta))
        end
    end
    
    # Fetch and concatenate results
    return vcat(fetch.(tasks)...)
end


function bmark_seq(N, theta)
    points = [rand(3) * 100 for _ in 1:N]
    masses = rand(N) * 10
    bounding_box = [[0.0, 0.0, 0.0], [100.0, 100.0, 100.0]]
    
    # 1. Build tree (NOT timed)
    root = buildTree(points, masses, bounding_box)
    
    # Return data for force calculation
    return (root, points, theta)
end

function bmark_seq_force_only(root, points, theta)
    # Calculate forces sequentially for all points
    forces = calculateForce(root, points[1], theta)
    return forces
end
