# ============================================================================
#  Shannon-Switching — weighted competition entry (project spec §5.2/§5.3)
#
#  Submit with:   comajudge submit -t submission/comajudge.jl -p Shannon
#  Leaderboard:   comajudge result -p Shannon
#
#  SELF-CONTAINED on purpose: the judge supplies the Vertex / Edge / GameGraph /
#  GameState types and the game framework, so this file defines ONLY the two
#  required strategy functions, the TEAM_NAME constant and private helpers. It
#  relies solely on the documented struct fields (e.state, e.weight, e.u, e.v,
#  e.id, graph.edges, graph.s, graph.t, state.graph, state.current_player).
#
#  Strategy (proxy = cheapest s-t path in G′ where Short edges cost 0):
#    Short  → secure the most *critical* neutral edge of the cheapest path,
#             i.e. the one whose loss would raise that cost the most.
#    Cut    → remove the neutral edge that most increases the cheapest cost,
#             disconnecting s-t outright when possible.
#  Each move runs a handful of O(V²) Dijkstra evaluations — comfortably within
#  the 2 s / move budget.
# ============================================================================

const TEAM_NAME = "OSA"   # Oleksandr Pistruzhak · Ali Kilinc · Simon Wesendrup

# Cheapest s-t path over (neutral ∪ short); Short edges cost 0, neutral cost
# their weight; `forbidden` ids are treated as removed. Returns (cost, path_ids).
function _cst(g, forbidden::Set{Int})
    s = g.s.id; t = g.t.id
    ids = [v.id for v in g.vertices]
    idx = Dict(id => k for (k, id) in enumerate(ids))
    n = length(ids)
    adj = [Tuple{Int,Float64,Int}[] for _ in 1:n]      # (nbr_idx, cost, edge_id)
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

# All neutral edge ids; convenience lookups.
_neutral_ids(g) = Int[e.id for e in g.edges if e.state == :neutral]
_by_id(g) = Dict(e.id => e for e in g.edges)

# Defensive fallback: always hand back a *legal* (neutral) edge when one exists;
# only the degenerate full-board case (which the harness never reaches) can fall
# through to the first edge.
function _first_neutral(g)
    for e in g.edges
        e.state == :neutral && return e
    end
    return first(g.edges)
end

"""
    weighted_short(state) -> Edge

Claim the neutral edge on the cheapest s-t path whose removal would raise that
cost the most (lock in the cheap connection before Cut breaks it).
"""
function weighted_short(state)
    g = state.graph
    bid = _by_id(g)
    base, path = _cst(g, Set{Int}())
    on_path = [id for id in path if bid[id].state == :neutral]
    if isempty(on_path)
        if base == Inf
            # no s-t path yet → claim globally cheapest neutral edge
            nid = _neutral_ids(g)
            isempty(nid) && return _first_neutral(g)
            return bid[argmin_id(nid, id -> bid[id].weight)]
        end
        # cheap path already fully owned → spend on cheapest neutral edge
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

Remove the neutral edge that most increases Short's cheapest s-t path cost
(disconnecting s-t is best). Candidates: edges on the cheapest path plus all
neutral edges incident to s or t (cheap disconnection checks).
"""
function weighted_cut(state)
    g = state.graph
    bid = _by_id(g)
    base, path = _cst(g, Set{Int}())
    nid = _neutral_ids(g)
    isempty(nid) && return _first_neutral(g)
    base == Inf && return bid[nid[1]]                  # Short already cannot connect

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

# argmin of `f` over a non-empty vector of ids.
function argmin_id(ids, f)
    best = ids[1]; bv = f(best)
    for id in ids
        v = f(id)
        if v < bv; best = id; bv = v; end
    end
    return best
end
