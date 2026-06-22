# Minimum s-t cut over removable (neutral) edges.
#
# Used by Cut's strategy: Short-claimed edges are *uncuttable* (Cut may only
# remove neutral edges), so they get effectively infinite capacity while every
# neutral edge has unit capacity. A maximum s-t flow then equals the number of
# edge-disjoint s-t paths Cut must still break, and the saturated neutral edges
# on the residual cut are exactly the edges worth removing.

const _INF_CAP = typemax(Int) ÷ 4

# Build a directed residual network (two arcs per undirected edge).
# Returns (heads, caps, firsts, nexts, arc_edge) adjacency in CSR-ish vectors.
struct _FlowNet
    head::Vector{Int}        # arc -> destination node
    cap::Vector{Int}         # arc -> residual capacity
    nxt::Vector{Int}         # arc -> next arc in node's list (0 = end)
    first::Vector{Int}       # node -> first arc (0 = none)
    arc_edge::Vector{Int}    # arc -> originating Edge id (0 for none)
end

function _build_flownet(graph::GameGraph)::_FlowNet
    n = maximum(v.id for v in graph.vertices)
    first = zeros(Int, n)
    head = Int[]; cap = Int[]; nxt = Int[]; arc_edge = Int[]
    add_arc(u, v, c, eid) = begin
        push!(head, v); push!(cap, c); push!(arc_edge, eid)
        push!(nxt, first[u]); first[u] = length(head)
    end
    for e in graph.edges
        e.state == :cut && continue
        c = e.state == :short ? _INF_CAP : 1
        add_arc(e.u.id, e.v.id, c, e.id)
        add_arc(e.v.id, e.u.id, c, e.id)
    end
    return _FlowNet(head, cap, nxt, first, arc_edge)
end

# One BFS augmenting step (unit/large capacities). Returns pushed flow (0 ends).
function _bfs_augment!(fn::_FlowNet, s::Int, t::Int)::Int
    n = length(fn.first)
    parent_arc = zeros(Int, n)
    seen = falses(n)
    seen[s] = true
    queue = Int[s]
    while !isempty(queue)
        u = popfirst!(queue)
        u == t && break
        a = fn.first[u]
        while a != 0
            v = fn.head[a]
            if !seen[v] && fn.cap[a] > 0
                seen[v] = true
                parent_arc[v] = a
                push!(queue, v)
            end
            a = fn.nxt[a]
        end
    end
    seen[t] || return 0
    # bottleneck along the augmenting path
    bott = _INF_CAP
    v = t
    while v != s
        a = parent_arc[v]
        bott = min(bott, fn.cap[a])
        v = _arc_origin(fn, a)
    end
    v = t
    while v != s
        a = parent_arc[v]
        fn.cap[a] -= bott
        fn.cap[_reverse_arc(a)] += bott
        v = _arc_origin(fn, a)
    end
    return bott
end

# Arcs are added in pairs (forward then reverse), so reverse of arc i is i±1.
_reverse_arc(a::Int) = isodd(a) ? a + 1 : a - 1

# Recover the origin node of arc `a` as the destination of its reverse arc.
_arc_origin(fn::_FlowNet, a::Int) = fn.head[_reverse_arc(a)]

"""
    min_cut_neutral_edges(graph) -> Vector{Int}

Return the ids of neutral edges that cross a minimum s-t cut, where Short-owned
edges are uncuttable. An empty result means `s` and `t` are already joined by
Short-claimed edges (Short has effectively won) — there is nothing left to cut.
"""
function min_cut_neutral_edges(graph::GameGraph)::Vector{Int}
    s = graph.s.id; t = graph.t.id
    fn = _build_flownet(graph)
    while _bfs_augment!(fn, s, t) > 0
    end
    # residual reachable set from s
    n = length(fn.first)
    seen = falses(n)
    seen[s] = true
    queue = Int[s]
    while !isempty(queue)
        u = popfirst!(queue)
        a = fn.first[u]
        while a != 0
            v = fn.head[a]
            if !seen[v] && fn.cap[a] > 0
                seen[v] = true
                push!(queue, v)
            end
            a = fn.nxt[a]
        end
    end
    # neutral edges crossing the cut (one endpoint seen, the other not)
    cut = Int[]
    for e in graph.edges
        e.state == :neutral || continue
        if seen[e.u.id] != seen[e.v.id]
            push!(cut, e.id)
        end
    end
    return cut
end
