# Graph utilities: adjacency, s-t connectivity (BFS) and random graph generation.

using Random

"""
    build_adjacency(graph, allowed) -> Dict{Int,Vector{Tuple{Int,Edge}}}

Build an adjacency list keyed by vertex id. Only edges whose `state` is in the
`allowed` collection are included. Each entry maps a vertex id to a vector of
`(neighbour_id, edge)` pairs.
"""
function build_adjacency(graph::GameGraph, allowed)::Dict{Int,Vector{Tuple{Int,Edge}}}
    adj = Dict{Int,Vector{Tuple{Int,Edge}}}()
    for v in graph.vertices
        adj[v.id] = Tuple{Int,Edge}[]
    end
    for e in graph.edges
        e.state in allowed || continue
        push!(adj[e.u.id], (e.v.id, e))
        push!(adj[e.v.id], (e.u.id, e))
    end
    return adj
end

"""
    reachable_from(graph, source, allowed) -> Set{Int}

Return the set of vertex ids reachable from `source` using only edges whose
state is in `allowed` (BFS).
"""
function reachable_from(graph::GameGraph, source::Vertex, allowed)::Set{Int}
    adj = build_adjacency(graph, allowed)
    seen = Set{Int}((source.id,))
    queue = Int[source.id]
    while !isempty(queue)
        x = popfirst!(queue)
        for (nb, _e) in adj[x]
            if nb ∉ seen
                push!(seen, nb)
                push!(queue, nb)
            end
        end
    end
    return seen
end

"""
    is_connected_st(graph, allowed) -> Bool

Return `true` iff `graph.t` is reachable from `graph.s` using only edges whose
state is in `allowed`.
"""
function is_connected_st(graph::GameGraph, allowed)::Bool
    return graph.t.id in reachable_from(graph, graph.s, allowed)
end

"""
    st_path_edges(graph, allowed) -> Union{Vector{Edge},Nothing}

Return the edges of some `s`–`t` path using only edges whose state is in
`allowed` (BFS, fewest edges), or `nothing` if no such path exists.
"""
function st_path_edges(graph::GameGraph, allowed)::Union{Vector{Edge},Nothing}
    adj = build_adjacency(graph, allowed)
    s = graph.s.id; t = graph.t.id
    prev = Dict{Int,Tuple{Int,Edge}}()
    seen = Set{Int}((s,))
    queue = Int[s]
    while !isempty(queue)
        x = popfirst!(queue)
        x == t && break
        for (nb, e) in adj[x]
            if nb ∉ seen
                push!(seen, nb)
                prev[nb] = (x, e)
                push!(queue, nb)
            end
        end
    end
    t in seen || return nothing
    path = Edge[]
    cur = t
    while cur != s
        (p, e) = prev[cur]
        push!(path, e)
        cur = p
    end
    return path
end

# --- random graph generation -------------------------------------------------

# Minimal union-find used to build a random connected spanning structure.
mutable struct _DSU
    parent::Vector{Int}
end
_DSU(n::Int) = _DSU(collect(1:n))

function _find(d::_DSU, x::Int)::Int
    while d.parent[x] != x
        d.parent[x] = d.parent[d.parent[x]]
        x = d.parent[x]
    end
    return x
end

function _union!(d::_DSU, a::Int, b::Int)::Bool
    ra, rb = _find(d, a), _find(d, b)
    ra == rb && return false
    d.parent[ra] = rb
    return true
end

"""
    random_graph(n, m; weighted=false, rng=Random.default_rng()) -> GameGraph

Generate a random *connected* simple graph with `n` vertices and `m` edges.
Vertex `1` is the source `s`, vertex `n` is the target `t`.

Connectivity is guaranteed by first laying down a random spanning tree
(`n-1` edges) and then adding `m-(n-1)` further distinct random edges. In the
weighted case edge weights are drawn uniformly from `[1, 10]`; otherwise every
weight is `0.0`.

Requires `n ≥ 2` and `n-1 ≤ m ≤ n(n-1)/2`.
"""
function random_graph(n::Int, m::Int; weighted::Bool=false,
                      rng::Random.AbstractRNG=Random.default_rng())::GameGraph
    n >= 2 || throw(ArgumentError("n must be ≥ 2 (got $n)"))
    max_edges = n * (n - 1) ÷ 2
    (n - 1) <= m <= max_edges ||
        throw(ArgumentError("m must satisfy n-1 ≤ m ≤ n(n-1)/2 = $max_edges (got $m)"))

    verts = [Vertex(i) for i in 1:n]
    weight() = weighted ? round(1.0 + 9.0 * rand(rng), digits=2) : 0.0

    edges = Edge[]
    used = Set{Tuple{Int,Int}}()       # normalized (min,max) endpoint pairs
    key(a, b) = (min(a, b), max(a, b))

    # 1) random spanning tree via union-find over a shuffled candidate order
    order = shuffle(rng, 2:n)
    dsu = _DSU(n)
    nextid = 1
    for v in order
        u = rand(rng, 1:(v - 1))       # connect v to an earlier vertex
        _union!(dsu, u, v)
        push!(edges, Edge(nextid, verts[u], verts[v], weight(), :neutral))
        push!(used, key(u, v))
        nextid += 1
    end

    # 2) add remaining distinct random edges
    remaining = m - (n - 1)
    while remaining > 0
        a = rand(rng, 1:n)
        b = rand(rng, 1:n)
        a == b && continue
        k = key(a, b)
        k in used && continue
        push!(used, k)
        push!(edges, Edge(nextid, verts[a], verts[b], weight(), :neutral))
        nextid += 1
        remaining -= 1
    end

    return GameGraph(verts, edges, verts[1], verts[n])
end
