# Two edge-disjoint spanning trees via matroid-union augmenting paths.
#
# This is the algorithmic core of the classic (unweighted) optimal strategy
# (project spec §4.1 / Anhang A). The textbook presents the Kishi-Kajitani
# "maximally distant trees" augmentation; the matroid-union augmenting-path
# formulation below computes the same object (two edge-disjoint spanning trees
# when they exist) and is easier to implement correctly.
#
# All functions here work on an abstract *contracted* graph: `nnodes` nodes
# numbered `1:nnodes` and an edge list `Vector{Tuple{Int,Int,Int}}` of
# `(edge_id, a, b)` triples. The strategy layer maps real `Edge`s onto this
# representation (contracting Short-claimed edges into super-nodes).

"""
    forest_path(forest, edge_of, a, b) -> Union{Vector{Int},Nothing}

Edge ids on the unique path between nodes `a` and `b` inside the forest given
by the id-set `forest`. `edge_of` maps an edge id to its `(a,b)` endpoints.
Returns `Int[]` if `a == b`, or `nothing` if `a` and `b` are in different
forest components.
"""
function forest_path(forest, edge_of, a::Int, b::Int)::Union{Vector{Int},Nothing}
    a == b && return Int[]
    adj = Dict{Int,Vector{Tuple{Int,Int}}}()
    for id in forest
        (u, v) = edge_of[id]
        push!(get!(adj, u, Tuple{Int,Int}[]), (v, id))
        push!(get!(adj, v, Tuple{Int,Int}[]), (u, id))
    end
    haskey(adj, a) || return nothing
    prev = Dict{Int,Tuple{Int,Int}}()      # node => (prev_node, edge_id)
    seen = Set{Int}((a,))
    queue = Int[a]
    while !isempty(queue)
        x = popfirst!(queue)
        x == b && break
        for (y, id) in get(adj, x, ())
            if y ∉ seen
                push!(seen, y)
                prev[y] = (x, id)
                push!(queue, y)
            end
        end
    end
    b in seen || return nothing
    path = Int[]
    cur = b
    while cur != a
        (p, id) = prev[cur]
        push!(path, id)
        cur = p
    end
    return path
end

# True iff `a` and `b` lie in the same component of `forest`.
function _same_component(forest, edge_of, a::Int, b::Int)::Bool
    a == b && return true
    return forest_path(forest, edge_of, a, b) !== nothing
end

# Try to grow A∪B by routing the unplaced edge `e0` into one of the two forests
# via a shortest matroid-union augmenting path (BFS over (edge,target_forest)).
# Mutates A and B on success. Returns whether augmentation succeeded.
function _augment!(A::Set{Int}, B::Set{Int}, edge_of, e0::Int)::Bool
    target(t) = t === :A ? A : B
    placeable(id, t) = !_same_component(target(t), edge_of, edge_of[id][1], edge_of[id][2])

    parent = Dict{Tuple{Int,Symbol},Union{Nothing,Tuple{Int,Symbol}}}()
    queue = Tuple{Int,Symbol}[]
    for t in (:A, :B)
        node = (e0, t)
        parent[node] = nothing
        push!(queue, node)
    end

    found = nothing
    while !isempty(queue)
        (id, t) = popfirst!(queue)
        if placeable(id, t)
            found = (id, t)
            break
        end
        (a, b) = edge_of[id]
        cyc = forest_path(target(t), edge_of, a, b)  # edges of forest t on the cycle
        cyc === nothing && continue
        for f in cyc
            node = (f, t === :A ? :B : :A)
            if !haskey(parent, node)
                parent[node] = (id, t)
                push!(queue, node)
            end
        end
    end
    found === nothing && return false

    # Walk root→found and apply the swaps: each visited (id,t) ends up in forest t.
    chain = Tuple{Int,Symbol}[]
    cur = found
    while cur !== nothing
        push!(chain, cur)
        cur = parent[cur]
    end
    for (id, t) in chain
        if t === :A
            push!(A, id); delete!(B, id)
        else
            push!(B, id); delete!(A, id)
        end
    end
    return true
end

"""
    max_two_forests(nnodes, edges) -> Tuple{Set{Int},Set{Int}}

Pack the given `edges` into two edge-disjoint forests `(A, B)` of maximum total
size via matroid-union augmenting paths. Always succeeds (the forests may be
non-spanning). `edge_of` keys must be unique edge ids.
"""
function max_two_forests(nnodes::Int,
        edges::Vector{Tuple{Int,Int,Int}})::Tuple{Set{Int},Set{Int}}
    edge_of = Dict{Int,Tuple{Int,Int}}(id => (a, b) for (id, a, b) in edges)
    A = Set{Int}(); B = Set{Int}()
    nnodes <= 1 && return (A, B)
    cap = 2 * (nnodes - 1)
    for (id, _a, _b) in edges
        (id in A || id in B) && continue
        _augment!(A, B, edge_of, id)
        (length(A) + length(B)) == cap && break
    end
    return (A, B)
end

"""
    two_disjoint_spanning_trees(nnodes, edges) -> Union{Tuple{Set{Int},Set{Int}},Nothing}

Find two edge-disjoint spanning trees of the contracted graph on `nnodes`
nodes. Returns `(A, B)` (each of size `nnodes-1`) or `nothing` if none exist.
"""
function two_disjoint_spanning_trees(nnodes::Int,
        edges::Vector{Tuple{Int,Int,Int}})::Union{Tuple{Set{Int},Set{Int}},Nothing}
    nnodes <= 1 && return (Set{Int}(), Set{Int}())
    A, B = max_two_forests(nnodes, edges)
    target = nnodes - 1
    return (length(A) == target && length(B) == target) ? (A, B) : nothing
end

