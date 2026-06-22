# Heuristic strategies for the weighted game (competition part, project spec §5).
#
# Short minimises the total weight of its final s-t path; Cut maximises it. The
# game is played to the very last neutral edge, then Short's score is the
# cheapest s-t path among Short-claimed edges (a high penalty if disconnected).
#
# Guiding proxy: the cheapest s-t path in G′ = (neutral ∪ Short) where Short
# edges cost 0 (already owned) and neutral edges cost their weight. Short tries
# to lock in that cheap path by securing its most fragile (critical) edge; Cut
# tries to push that cheapest cost up (or disconnect s-t entirely).

"""
    TEAM_NAME

Competition team name. **Replace `"???"` with your real team name before
submitting via `comajudge`.**
"""
const TEAM_NAME = "OSA"

# Dijkstra over allowed edges; Short-claimed edges cost 0, neutral edges cost
# their weight. Returns (cost, path_edges). cost == Inf means no s-t path.
# `forbidden` edge ids are treated as removed. O(V^2), dependency-free.
function _cheapest_st(g::GameGraph; forbidden::Set{Int}=Set{Int}())
    INF = Inf
    s = g.s.id; t = g.t.id
    adj = Dict{Int,Vector{Tuple{Int,Edge}}}()
    for v in g.vertices
        adj[v.id] = Tuple{Int,Edge}[]
    end
    for e in g.edges
        (e.state == :neutral || e.state == :short) || continue
        e.id in forbidden && continue
        push!(adj[e.u.id], (e.v.id, e))
        push!(adj[e.v.id], (e.u.id, e))
    end
    dist = Dict{Int,Float64}(v.id => INF for v in g.vertices)
    prev = Dict{Int,Tuple{Int,Edge}}()
    done = Dict{Int,Bool}(v.id => false for v in g.vertices)
    dist[s] = 0.0
    while true
        u = -1; best = INF
        for v in g.vertices
            if !done[v.id] && dist[v.id] < best
                best = dist[v.id]; u = v.id
            end
        end
        u == -1 && break
        done[u] = true
        u == t && break
        for (nb, e) in adj[u]
            w = e.state == :short ? 0.0 : e.weight
            if dist[u] + w < dist[nb]
                dist[nb] = dist[u] + w
                prev[nb] = (u, e)
            end
        end
    end
    dist[t] == INF && return (INF, Edge[])
    path = Edge[]
    cur = t
    while cur != s
        (p, e) = prev[cur]
        push!(path, e)
        cur = p
    end
    return (dist[t], path)
end

# --- Short ------------------------------------------------------------------

"""
    weighted_short(state::GameState) -> Edge

Claim the most *critical* neutral edge on the current cheapest s-t path — the
edge whose loss would raise the cheapest-path cost the most — locking in the
cheap connection before Cut can break it. Falls back to the cheapest neutral
edge when no s-t path remains.
"""
function weighted_short(state::GameState)::Edge
    g = state.graph
    moves = valid_moves(state)
    isempty(moves) && throw(ArgumentError("no neutral edges left"))

    base, path = _cheapest_st(g)
    neutral_on_path = [e for e in path if e.state == :neutral]
    if isempty(neutral_on_path)
        # No path, or path already fully Short-owned. If there is a path it is
        # secured; otherwise grab the globally cheapest neutral edge to keep
        # building toward a connection.
        base == Inf || return first(moves)
        return argmin_by(moves, e -> e.weight)
    end

    # Secure the edge whose removal hurts the cheapest path most.
    best = first(neutral_on_path)
    best_gain = -1.0
    for e in neutral_on_path
        alt, _ = _cheapest_st(g; forbidden=Set((e.id,)))
        gain = (alt == Inf ? 1e9 : alt) - base
        # Prefer larger damage-if-lost; tie-break toward heavier edge (more at
        # risk of being targeted by Cut).
        if gain > best_gain + 1e-12 ||
           (abs(gain - best_gain) <= 1e-12 && e.weight > best.weight)
            best = e; best_gain = gain
        end
    end
    return best
end

# --- Cut --------------------------------------------------------------------

"""
    weighted_cut(state::GameState) -> Edge

Remove the neutral edge that most increases Short's cheapest s-t path cost
(disconnecting s and t outright is best of all). Candidates are restricted to
the current cheapest path plus a minimum-cut set, keeping each move fast.
Falls back to any legal move.
"""
function weighted_cut(state::GameState)::Edge
    g = state.graph
    moves = valid_moves(state)
    isempty(moves) && throw(ArgumentError("no neutral edges left"))

    base, path = _cheapest_st(g)
    base == Inf && return first(moves)        # Short already cannot connect

    candidates = Set{Int}()
    for e in path
        e.state == :neutral && push!(candidates, e.id)
    end
    for id in min_cut_neutral_edges(g)
        push!(candidates, id)
    end
    isempty(candidates) && return first(moves)

    by_id = Dict(e.id => e for e in g.edges)
    best = by_id[first(candidates)]
    best_cost = -1.0
    for id in candidates
        haskey(by_id, id) || continue
        by_id[id].state == :neutral || continue
        c, _ = _cheapest_st(g; forbidden=Set((id,)))
        cost = c == Inf ? 1e9 : c            # disconnection dominates
        if cost > best_cost + 1e-12
            best = by_id[id]; best_cost = cost
        end
    end
    return best
end

# Small helper: argmin of `f` over a non-empty collection.
function argmin_by(xs, f)
    best = first(xs); bv = f(best)
    for x in xs
        v = f(x)
        if v < bv; best = x; bv = v; end
    end
    return best
end
