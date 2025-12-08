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
    buildTree(root, points, masses, bounding_box)
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
    subtrees = []
    for (i, subtree) in enumerate(queue)
        push!(subtrees, Dagger.@spawn buildTree(subtree, queuepoints[i], queuemass[i], queuebound[i]))
    end
    subtrees = fetch.(subtrees)
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
function buildTree(root, points, masses, bounding_box::Vector{Vector{Float64}}) 
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
end



function bmark(N, theta)
    points = [rand(3) * 100 for _ in 1:N]
    masses = rand(N) * 10
    bounding_box = [[0.0, 0.0, 0.0], [100.0, 100.0, 100.0]]
    rootp = buildTreeP(points, masses, bounding_box)
    for point in points
        forcep = calculateForceP(rootp, point, theta)
    end
end


function bmark_seq(N, theta)
    points = [rand(3) * 100 for _ in 1:N]
    masses = rand(N) * 10
    bounding_box = [[0.0, 0.0, 0.0], [100.0, 100.0, 100.0]]
    root = buildTree(points, masses, bounding_box)
    for point in points
        force = calculateForce(root, point, theta)
    end
end
