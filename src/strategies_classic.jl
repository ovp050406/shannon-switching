# Optimal strategies for the classic (unweighted) Shannon-Switching game,
# following the lecture's polynomial algorithm (Übung 22, project spec §4.1).
#
# Short's winning condition is Lehman's characterisation (lehman.jl): Short (as
# the waiting player) wins exactly when the available graph — Short-claimed edges
# contracted, Cut edges deleted — contains two edge-disjoint connected sub-graphs
# on a common vertex set U ∋ {s, t}.  `short_certificate` decides this in
# polynomial time via two minimal-overlap spanning trees and the e* probe.
#
# Both strategies are then realised by *staying in the winning region*, which is
# the move-by-move content of the lectured pairing strategies:
#
#   * Short (slides "Shorts Strategie"): after Cut deletes an edge of one tree,
#     claim a neutral edge that restores the two-disjoint-trees certificate. Any
#     such edge keeps Short winning; equivalently, claim a neutral edge after
#     which `short_certificate` still holds.
#   * Cut (slides "Cuts Strategie", the planar-dual / feedback-edge-set argument):
#     Cut wins exactly when Short has *no* certificate, i.e. Cut owns two disjoint
#     feedback-edge-sets A, B such that every s-t path and every relevant cycle
#     meets both. Maintaining that is dual to denying Short the certificate:
#     delete a neutral edge after which Short (to move) can no longer win.
#
# Because the certificate is polynomial there is no game-tree blow-up and no size
# limit; `scripts/validate_classic.jl` cross-checks every move against a
# brute-force minimax oracle.

# --- contracted-graph view of a position -------------------------------------

# Build the contracted available graph for strategy analysis:
#   * Short-claimed edges (plus an optional extra `claim`) are contracted —
#     their endpoints merge into one node, since Short already owns them;
#   * Cut edges and an optional `remove`d edge are dropped;
#   * the remaining neutral edges become the contracted edge list.
# Returns `(:connected, …)` when s and t are already joined by Short edges,
# otherwise `(:ok, nnodes, edges, sc, tc)` with compact node ids `1:nnodes`.
function _contracted(g::GameGraph; claim::Union{Edge,Nothing}=nothing,
                     remove::Union{Edge,Nothing}=nothing)
    vids = [v.id for v in g.vertices]
    pos = Dict(id => i for (i, id) in enumerate(vids))
    parent = collect(1:length(vids))
    find(x) = (while parent[x] != x; parent[x] = parent[parent[x]]; x = parent[x]; end; x)
    unite(a, b) = (ra = find(pos[a]); rb = find(pos[b]); ra == rb || (parent[ra] = rb))

    for e in g.edges
        e.state == :short && unite(e.u.id, e.v.id)
    end
    claim === nothing || unite(claim.u.id, claim.v.id)

    sc = find(pos[g.s.id]); tc = find(pos[g.t.id])
    sc == tc && return (:connected, 0, Tuple{Int,Int,Int}[], 0, 0)

    roots = unique(find(i) for i in 1:length(vids))
    compact = Dict(r => i for (i, r) in enumerate(roots))
    edges = Tuple{Int,Int,Int}[]
    for e in g.edges
        e.state == :neutral || continue
        (remove !== nothing && e.id == remove.id) && continue
        (claim !== nothing && e.id == claim.id) && continue
        a = compact[find(pos[e.u.id])]; b = compact[find(pos[e.v.id])]
        a == b && continue                       # self-loop inside a Short blob
        push!(edges, (e.id, a, b))
    end
    return (:ok, length(roots), edges, compact[sc], compact[tc])
end

# Does Short, as the waiting player, hold the Lehman certificate after the given
# claim/remove is applied? (`:connected` ⇒ s-t already joined by Short ⇒ yes.)
function _short_waits_and_wins(g::GameGraph; claim::Union{Edge,Nothing}=nothing,
                               remove::Union{Edge,Nothing}=nothing)::Bool
    (tag, nn, edges, sc, tc) = _contracted(g; claim=claim, remove=remove)
    tag === :connected && return true
    return short_certificate(nn, edges, sc, tc)
end

# Can Short, *to move*, force a win from the current position? Short wins iff some
# neutral claim either connects s-t outright or leaves Short with the certificate.
function _short_to_move_wins(g::GameGraph; remove::Union{Edge,Nothing}=nothing)::Bool
    (tag, _nn, _e, _sc, _tc) = _contracted(g; remove=remove)
    tag === :connected && return true
    for e in g.edges
        e.state == :neutral || continue
        (remove !== nothing && e.id == remove.id) && continue
        if _short_waits_and_wins(g; claim=e, remove=remove)
            return true
        end
    end
    return false
end

# --- shared progress helpers -------------------------------------------------

# A move that makes progress toward s-t: the first neutral edge on an s-t path
# in G′ (neutral ∪ short). Falls back to any legal move.
function _progress_move(state::GameState, moves::Vector{Edge})::Edge
    path = st_path_edges(state.graph, (:neutral, :short))
    if path !== nothing
        for e in path
            e.state == :neutral && return e
        end
    end
    return first(moves)
end

# Neutral edge ids on the s-t path needing the fewest further Short claims (Short
# edges cost 0, neutral cost 1) — Short's nearest-to-complete threat.
function _most_complete_path_neutral(g::GameGraph)::Vector{Int}
    adj = build_adjacency(g, (:neutral, :short))
    s = g.s.id; t = g.t.id
    INF = typemax(Int)
    dist = Dict{Int,Int}(v.id => INF for v in g.vertices)
    prev = Dict{Int,Tuple{Int,Edge}}()
    dist[s] = 0
    dq = Int[s]
    while !isempty(dq)
        x = popfirst!(dq)
        for (nb, e) in adj[x]
            w = e.state == :short ? 0 : 1
            if dist[x] + w < dist[nb]
                dist[nb] = dist[x] + w
                prev[nb] = (x, e)
                w == 0 ? pushfirst!(dq, nb) : push!(dq, nb)
            end
        end
    end
    dist[t] == INF && return Int[]
    out = Int[]
    cur = t
    while cur != s
        (p, e) = prev[cur]
        e.state == :neutral && push!(out, e.id)
        cur = p
    end
    return out
end

# --- Short ------------------------------------------------------------------

"""
    short_strategy(state::GameState) -> Edge

Short's optimal move in the unweighted game. Realises the lectured second-player
pairing strategy: claim a neutral edge after which Short still holds the
two-disjoint-trees certificate (`short_certificate`). Candidate edges are tried
nearest-completion-first, so the maintained edge is one that also drives the s-t
connection. In a lost position returns a progress move.
"""
function short_strategy(state::GameState)::Edge
    g = state.graph
    moves = valid_moves(state)
    isempty(moves) && throw(ArgumentError("no neutral edges left"))
    is_connected_st(g, (:short,)) && return first(moves)   # already won

    on_path = Set(_most_complete_path_neutral(g))
    ordered = sort(moves; by = e -> (e.id in on_path ? 0 : 1, e.id))
    for e in ordered
        # An immediate connection wins; otherwise keep the certificate.
        if _short_waits_and_wins(g; claim=e)
            return e
        end
    end
    return _progress_move(state, moves)        # losing position → make progress
end

# --- Cut --------------------------------------------------------------------

"""
    cut_strategy(state::GameState) -> Edge

Cut's optimal move in the unweighted game. Cut wins exactly when Short holds no
Lehman certificate; equivalently (lecture's planar-dual / feedback-edge-set
argument) Cut keeps two disjoint edge sets meeting every s-t path and every
relevant cycle. Realised by deleting a neutral edge after which Short, to move,
can no longer win. In a lost position falls back to the strongest delaying move
(a minimum-cut edge on Short's nearest-to-complete path).
"""
function cut_strategy(state::GameState)::Edge
    g = state.graph
    moves = valid_moves(state)
    isempty(moves) && throw(ArgumentError("no neutral edges left"))

    # Try cut-relevant edges first: a minimum s-t cut, then the rest.
    cut_first = Set(min_cut_neutral_edges(g))
    ordered = sort(moves; by = e -> (e.id in cut_first ? 0 : 1, e.id))
    for e in ordered
        if !_short_to_move_wins(g; remove=e)   # this deletion denies Short
            return e
        end
    end
    return _cut_heuristic(state, moves)        # losing position → delay
end

# Strongest delaying move: a minimum-cut neutral edge, preferring one on Short's
# nearest-to-complete s-t path.
function _cut_heuristic(state::GameState, moves::Vector{Edge})::Edge
    g = state.graph
    cut = min_cut_neutral_edges(g)
    isempty(cut) && return first(moves)
    cutset = Set(cut)
    by_id = Dict(e.id => e for e in g.edges)
    for id in _most_complete_path_neutral(g)
        id in cutset && return by_id[id]
    end
    return by_id[first(cut)]
end
