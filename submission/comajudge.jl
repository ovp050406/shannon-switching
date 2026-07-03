# ============================================================================
# Shannon-Switching — weighted competition strategy
#
# This file is self-contained because the judge already provides the game
# structs and the game loop.
#
# We use the cheapest possible s-t path as a guide:
# - Short secures an important edge on that path.
# - Cut removes an edge that makes this path more expensive or disconnects it.
#
# The strategy only checks a small number of candidate edges, so it stays fast.
#Edges = Kanten, Vertex = Knoten
#
============================================================================

const TEAM_NAME = "OSA"   # Oleksandr Pistruzhak · Ali Kilinc · Simon Wesendrup

# Find the cheapest path from s to t.
# Short-owned edges have cost 0, neutral edges use their weight.
# Edges in `forbidden` are treated as removed.
# Returns the path cost and the edge ids on that path.
function _cst(g, forbidden::Set{Int})
    s = g.s.id; t = g.t.id
    ids = [v.id for v in g.vertices]
    idx = Dict(id => k for (k, id) in enumerate(ids))
    n = length(ids)
    adj = [Tuple{Int,Float64,Int}[] for _ in 1:n]      # neighbour, cost, edge id    
    for e in g.edges
        (e.state == :neutral || e.state == :short) || continue
        e.id in forbidden && continue
        c = e.state == :short ? 0.0 : e.weight
        push!(adj[idx[e.u.id]], (idx[e.v.id], c, e.id))
        push!(adj[idx[e.v.id]], (idx[e.u.id], c, e.id))
    end
    dist = fill(Inf, n); done = fill(false, n)
    prevn = fill(0, n); preve = fill(0, n)
    si = idx[s]; ti = idx[t]; dist[si] = 0.0
    while true
        u = 0; best = Inf
        for k in 1:n
            if !done[k] && dist[k] < best; best = dist[k]; u = k; end
        end
        u == 0 && break
        done[u] = true
        u == ti && break
        for (w, c, eid) in adj[u]
            if dist[u] + c < dist[w]
                dist[w] = dist[u] + c; prevn[w] = u; preve[w] = eid
            end
        end
    end
    dist[ti] == Inf && return (Inf, Int[])
    path = Int[]; cur = ti
    while cur != si
        push!(path, preve[cur]); cur = prevn[cur]
    end
    return (dist[ti], path)
end

# Small helper functions for neutral edges and edge lookup.
_neutral_ids(g) = Int[e.id for e in g.edges if e.state == :neutral]
_by_id(g) = Dict(e.id => e for e in g.edges)

# Return a legal neutral edge as a fallback.
function _first_neutral(g)
    for e in g.edges
        e.state == :neutral && return e
    end
    return first(g.edges)
end

"""
    weighted_short(state) -> Edge

Choose an important neutral edge on the current cheapest s-t path.

For every neutral edge on this path, we check how expensive the path would
be if Cut removed it. Short claims the edge with the largest increase.
"""
function weighted_short(state)
    g = state.graph
    bid = _by_id(g)
    base, path = _cst(g, Set{Int}())
    on_path = [id for id in path if bid[id].state == :neutral]
    if isempty(on_path)
        if base == Inf
            # No path is available yet, so choose the cheapest neutral edge.
            nid = _neutral_ids(g)
            isempty(nid) && return _first_neutral(g)
            return bid[argmin_id(nid, id -> bid[id].weight)]
        end
        # The cheapest path is already secured, so choose a cheap remaining edge.
        nid = _neutral_ids(g)
        return isempty(nid) ? _first_neutral(g) : bid[argmin_id(nid, id -> bid[id].weight)]
    end
    best = on_path[1]; bestgain = -1.0
    for id in on_path
        alt, _ = _cst(g, Set((id,)))
        gain = (alt == Inf ? 1e9 : alt) - base
        if gain > bestgain + 1e-12 ||
           (abs(gain - bestgain) <= 1e-12 && bid[id].weight > bid[best].weight)
            best = id; bestgain = gain
        end
    end
    return bid[best]
end

"""
    weighted_cut(state) -> Edge

Remove the neutral edge that hurts Short's cheapest possible path the most.

We check edges on the current cheapest path and edges directly connected to
s or t. Disconnecting s and t is always the best result for Cut.
"""
function weighted_cut(state)
    g = state.graph
    bid = _by_id(g)
    base, path = _cst(g, Set{Int}())
    nid = _neutral_ids(g)
    isempty(nid) && return _first_neutral(g)
    base == Inf && return bid[nid[1]]                  # No s-t path is left for Short.

    cands = Set{Int}()
    for id in path
        bid[id].state == :neutral && push!(cands, id)
    end
    s = g.s.id; t = g.t.id
    for e in g.edges
        e.state == :neutral || continue
        (e.u.id == s || e.v.id == s || e.u.id == t || e.v.id == t) && push!(cands, e.id)
    end
    isempty(cands) && return bid[nid[1]]

    best = first(cands); bestcost = -1.0
    for id in cands
        c, _ = _cst(g, Set((id,)))
        cost = c == Inf ? 1e9 : c
        if cost > bestcost + 1e-12; best = id; bestcost = cost; end
    end
    return bid[best]
end

# Return the id with the smallest value of f.
function argmin_id(ids, f)
    best = ids[1]; bv = f(best)
    for id in ids
        v = f(id)
        if v < bv; best = id; bv = v; end
    end
    return best
end
