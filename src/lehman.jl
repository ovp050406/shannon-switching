# Lehman / Kishi-Kajitani machinery for the classic (unweighted) game — the
# polynomial algorithm taught in the lecture (Übung 22) and required by the
# project spec §4.1 / Anhang A.
#
# Lehman's characterisation (lecture slide "Lehmans Charakterisierung"):
#   Short wins as the *second* player  ⇔  G contains two trees (U, A), (U, B)
#   with the same vertex set U ⊇ {s, t} and disjoint edge sets A ∩ B = ∅.
#   (Bemerkung, slide 71: only the *connectivity* of (U,A),(U,B) matters, not
#   acyclicity — so "two edge-disjoint connected sub-graphs on a common U" is the
#   real condition; trees are just the canonical witnesses.)
#
# Computing that certificate (lecture: "Berechnung zweier disjunkter Bäume"):
#   1. take two spanning trees of the s-t component;
#   2. minimise their overlap |A ∩ B| with `fix(e)` (fundamental-circuit swaps);
#   3. add the virtual edge e* = {s, t} and run `fix(e*)`:
#         e* absorbed  → Short has no winning strategy;
#         e* not absorbed → Short wins, U = endpoints of the visited edges Lₖ.
#
# Everything here works on a *contracted* graph: nodes `1:nnodes`, edges as a
# `Vector{Tuple{Int,Int,Int}}` of `(edge_id, node_a, node_b)` (parallel edges
# and arbitrary ids allowed). The strategy layer (strategies_classic.jl) maps
# the real `GameGraph` onto this form, contracting Short-claimed edges.
#
# `forest_path` (spanning_trees.jl) supplies the fundamental circuit FC(e, F):
# the unique cycle in F ∪ {e} is exactly the F-path between e's endpoints.

# --- small graph helpers (contracted representation) -------------------------

# Connected component (set of node ids) containing `src`, over `edges`.
function _component(nnodes::Int, edges::Vector{Tuple{Int,Int,Int}}, src::Int)::Set{Int}
    adj = Dict{Int,Vector{Int}}()
    for (_id, a, b) in edges
        push!(get!(adj, a, Int[]), b)
        push!(get!(adj, b, Int[]), a)
    end
    seen = Set{Int}((src,))
    stack = Int[src]
    while !isempty(stack)
        x = pop!(stack)
        for y in get(adj, x, ())
            if y ∉ seen
                push!(seen, y)
                push!(stack, y)
            end
        end
    end
    return seen
end

# A spanning tree (edge-id set) of the connected graph `(nnodes, edges)` via
# union-find, or `nothing` if the graph is not connected.
function _spanning_tree(nnodes::Int,
        edges::Vector{Tuple{Int,Int,Int}})::Union{Set{Int},Nothing}
    parent = collect(1:nnodes)
    find(x) = (while parent[x] != x; parent[x] = parent[parent[x]]; x = parent[x]; end; x)
    tree = Set{Int}()
    for (id, a, b) in edges
        ra, rb = find(a), find(b)
        ra == rb && continue
        parent[ra] = rb
        push!(tree, id)
    end
    return length(tree) == nnodes - 1 ? tree : nothing
end

# Is `tree` a spanning tree of `(nnodes, edges)` (size n-1 and connected)?
function _is_spanning_tree(tree::Set{Int}, edge_of::Dict{Int,Tuple{Int,Int}}, nnodes::Int)::Bool
    length(tree) == nnodes - 1 || return false
    parent = collect(1:nnodes)
    find(x) = (while parent[x] != x; parent[x] = parent[parent[x]]; x = parent[x]; end; x)
    for id in tree
        (a, b) = edge_of[id]
        ra, rb = find(a), find(b)
        ra == rb && return false        # a cycle ⇒ not a tree
        parent[ra] = rb
    end
    return true
end

_overlap(A::Set{Int}, B::Set{Int}) = count(in(B), A)

"""
    fundamental_circuit(tree, edge_of, e) -> Vector{Int}

The fundamental circuit FC(e, tree): the edge ids of the unique cycle in
`tree ∪ {e}` for a chord `e ∉ tree`. These are exactly the tree edges on the
tree-path between `e`'s endpoints. Returns `Int[]` if the endpoints coincide.
"""
function fundamental_circuit(tree::Set{Int}, edge_of::Dict{Int,Tuple{Int,Int}}, e::Int)::Vector{Int}
    (a, b) = edge_of[e]
    p = forest_path(tree, edge_of, a, b)
    return p === nothing ? Int[] : p
end

# --- fix(e): overlap-reducing fundamental-circuit swap (lecture slide 39) -----

# Apply the alternating swap chain that ends at the doubled edge `f`, reachable
# from chord `e`. `parent[x] = (predecessor, parity)` means `x ∈ FC(predecessor,
# Fₚₐᵣᵢₜᵧ)`. Walking f → e and, in each tree, replacing the visited edge by its
# predecessor incorporates `e` and frees one membership of `f` (overlap −1).
function _apply_chain!(A::Set{Int}, B::Set{Int}, e::Int, f::Int,
                       parent::Dict{Int,Tuple{Int,Int}})
    cur = f
    while cur != e
        (pred, par) = parent[cur]
        if par == 0
            delete!(A, cur); push!(A, pred)
        else
            delete!(B, cur); push!(B, pred)
        end
        cur = pred
    end
end

# Try to reduce |A ∩ B| using chord `e ∉ A ∪ B`, via fix(e) (slide 39): an
# alternating breadth-first search over fundamental circuits (F = A on even
# layers, F = B on odd layers) seeking a doubled edge f ∈ A ∩ B. On success the
# swap chain is applied; the result is verified to be two spanning trees of
# strictly smaller overlap and rolled back otherwise. Returns whether it
# reduced the overlap.
function _fix_reduce!(A::Set{Int}, B::Set{Int}, edge_of::Dict{Int,Tuple{Int,Int}},
                      nnodes::Int, e::Int)::Bool
    doubled = Set{Int}(f for f in A if f in B)
    isempty(doubled) && return false

    parent = Dict{Int,Tuple{Int,Int}}()
    visited = Set{Int}((e,))
    frontier = Int[e]
    parity = 0                                  # 0 ⇒ F = A, 1 ⇒ F = B
    found = 0
    while !isempty(frontier) && found == 0
        F = parity == 0 ? A : B
        nextf = Int[]
        for ep in frontier
            ep in F && continue                 # e' ∈ Lₖ \ F
            for f in fundamental_circuit(F, edge_of, ep)
                if f in doubled && !haskey(parent, f)
                    parent[f] = (ep, parity)
                    found = f
                    break
                elseif f ∉ visited
                    push!(visited, f)
                    parent[f] = (ep, parity)
                    push!(nextf, f)
                end
            end
            found == 0 || break
        end
        frontier = nextf
        parity = 1 - parity
    end
    found == 0 && return false

    before = _overlap(A, B)
    Asnap = copy(A); Bsnap = copy(B)
    _apply_chain!(A, B, e, found, parent)
    if _overlap(A, B) < before &&
       _is_spanning_tree(A, edge_of, nnodes) && _is_spanning_tree(B, edge_of, nnodes)
        return true
    end
    empty!(A); union!(A, Asnap); empty!(B); union!(B, Bsnap)   # roll back
    return false
end

"""
    min_overlap_two_trees(nnodes, edges) -> Union{Tuple{Set{Int},Set{Int}},Nothing}

Two spanning trees `(A, B)` of the connected graph `(nnodes, edges)` with the
smallest possible overlap `|A ∩ B|`, computed by repeated `fix(e)` reduction
over every chord until none reduces further (lecture: minimal overlap is reached
exactly when no chord can be swapped, slide "Korrektheit des Algorithmus").
Returns `nothing` if the graph is not connected.
"""
function min_overlap_two_trees(nnodes::Int,
        edges::Vector{Tuple{Int,Int,Int}})::Union{Tuple{Set{Int},Set{Int}},Nothing}
    nnodes <= 1 && return (Set{Int}(), Set{Int}())
    t = _spanning_tree(nnodes, edges)
    t === nothing && return nothing
    A = copy(t); B = copy(t)                    # start identical, overlap maximal
    edge_of = Dict{Int,Tuple{Int,Int}}(id => (a, b) for (id, a, b) in edges)
    ids = [id for (id, _a, _b) in edges]
    changed = true
    while changed
        changed = false
        for e in ids
            (e in A || e in B) && continue
            _fix_reduce!(A, B, edge_of, nnodes, e) && (changed = true)
        end
    end
    return (A, B)
end

# --- fix(e*): U-extraction / win-loss decision (lecture slides 63-70) ---------

# Run fix(e*) for the virtual edge e* = {s, t} over minimal-overlap trees A, B.
# Returns `(short_wins, U)`. `short_wins` is false iff e* is absorbed (a doubled
# edge is alternating-reachable from e*), i.e. the real edges alone cannot supply
# two disjoint connected sub-graphs spanning s and t. When Short wins, `U` is the
# set of endpoints of every visited edge (the lecture's Lₖ), with s, t ∈ U.
function _fix_estar(edge_of::Dict{Int,Tuple{Int,Int}}, A::Set{Int}, B::Set{Int},
                    s::Int, t::Int)::Tuple{Bool,Set{Int}}
    s == t && return (true, Set{Int}((s,)))
    doubled = Set{Int}(f for f in A if f in B)
    estar = 0                                   # fresh id (real ids are ≥ 1)
    eo = copy(edge_of); eo[estar] = (s, t)
    visited = Set{Int}((estar,))
    frontier = Int[estar]
    parity = 0
    while !isempty(frontier)
        F = parity == 0 ? A : B
        nextf = Int[]
        for ep in frontier
            ep in F && continue
            for f in fundamental_circuit(F, eo, ep)
                f in doubled && return (false, Set{Int}())   # absorbed ⇒ Short loses
                if f ∉ visited
                    push!(visited, f)
                    push!(nextf, f)
                end
            end
        end
        frontier = nextf
        parity = 1 - parity
    end
    U = Set{Int}()
    for id in visited
        (a, b) = eo[id]
        push!(U, a); push!(U, b)
    end
    return (true, U)
end

"""
    short_certificate(nnodes, edges, s, t) -> Bool

Lehman's second-player test: does the contracted graph `(nnodes, edges)` contain
two edge-disjoint connected sub-graphs on a common vertex set `U ∋ {s, t}`?
This is exactly "Short wins as the waiting player from this position".

Implements the lectured pipeline: restrict to the s-t component, minimise the
overlap of two spanning trees, then probe with the virtual edge e* = {s, t}.
"""
function short_certificate(nnodes::Int, edges::Vector{Tuple{Int,Int,Int}},
                           s::Int, t::Int)::Bool
    s == t && return true
    comp = _component(nnodes, edges, s)
    t in comp || return false                   # s, t disconnected ⇒ no certificate

    order = sort!(collect(comp))
    idx = Dict(v => i for (i, v) in enumerate(order))
    cedges = Tuple{Int,Int,Int}[(id, idx[a], idx[b])
                                for (id, a, b) in edges if a in comp && b in comp]
    res = min_overlap_two_trees(length(order), cedges)
    res === nothing && return false
    (A, B) = res
    edge_of = Dict{Int,Tuple{Int,Int}}(id => (a, b) for (id, a, b) in cedges)
    (wins, _U) = _fix_estar(edge_of, A, B, idx[s], idx[t])
    return wins
end
