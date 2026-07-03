# Heuristic strategies for the weighted game.
#
# Short wants to build a cheap path from s to t.
# Cut wants to make this path more expensive or disconnect it.
#
# We use the current cheapest possible s-t path as a guide.
# Short protects an important edge on this path.
# Cut tries to remove an edge that hurts this path the most.

"""
    TEAM_NAME

Team name constant required by the comajudge competition (project spec §5.2).
"""
const TEAM_NAME = "OSA"

# Find the cheapest possible path from s to t.
# Short-owned edges have cost 0 and neutral edges use their weight.
# Edges in `forbidden` are treated as removed.
# Returns the path cost and the Kanten on that path.
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

Choose an important neutral edge on the current cheapest s-t path.

For every neutral edge on this path, we check how expensive the path would
be if this edge was removed. Short claims the edge with the largest increase.
"""
function weighted_short(state::GameState)::Edge
    g = state.graph
    moves = valid_moves(state)
    isempty(moves) && throw(ArgumentError("no neutral edges left"))

    base, path = _cheapest_st(g)
    neutral_on_path = [e for e in path if e.state == :neutral]
    if isempty(neutral_on_path)
        # There is no neutral edge on the cheapest path.
        # Either the path is already secured or no path is available.
        base == Inf || return first(moves)
        return argmin_by(moves, e -> e.weight)
    end

# Choose the edge whose removal would increase the path cost the most.
    best = first(neutral_on_path)
    best_gain = -1.0
    for e in neutral_on_path
        alt, _ = _cheapest_st(g; forbidden=Set((e.id,)))
        gain = (alt == Inf ? 1e9 : alt) - base
        # If two edges are equally important, prefer the heavier one.
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

Remove a neutral edge that makes Short's cheapest possible path as expensive
as possible.

We check edges on the current cheapest path and edges from a minimum cut.
This keeps the number of tested moves small and fast.
"""
function weighted_cut(state::GameState)::Edge
    g = state.graph
    moves = valid_moves(state)
    isempty(moves) && throw(ArgumentError("no neutral edges left"))

    base, path = _cheapest_st(g)
    base == Inf && return first(moves)        # Short has no possible s-t path left.

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
        cost = c == Inf ? 1e9 : c            # Disconnecting Short is the best result.
        if cost > best_cost + 1e-12
            best = by_id[id]; best_cost = cost
        end
    end
    return best
end

# Return the element with the smallest value of f.
function argmin_by(xs, f)
    best = first(xs); bv = f(best)
    for x in xs
        v = f(x)
        if v < bv; best = x; bv = v; end
    end
    return best
end
