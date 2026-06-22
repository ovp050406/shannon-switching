# Core data structures for the Shannon-Switching game (project spec §2.1).
#
# NOTE on mutability: the project interface *mandates* a mutable `Edge` and a
# mutating `make_move!`. This deliberately overrides the general immutability
# rule for the game state itself. Strategy helpers below still avoid in-place
# graph edits and build fresh collections instead.

"""
    Vertex

A graph vertex. Immutable, so two `Vertex` values with the same `id` compare
equal and hash equal — safe to use as a dictionary key.

# Fields
- `id::Int`: unique vertex identifier.
"""
struct Vertex
    id::Int
end

"""
    Edge

An undirected, weighted edge with a mutable game state.

`Edge` is a *mutable* struct, so distinct `Edge` objects are compared by
identity. The graph owns one canonical `Edge` instance per edge; all code
references those same instances, which makes identity-based `Set{Edge}`/`Dict`
usage correct and cheap.

# Fields
- `id::Int`: unique edge identifier.
- `u::Vertex`, `v::Vertex`: the two endpoints (order is irrelevant).
- `weight::Float64`: edge weight (`0.0` for the unweighted game).
- `state::Symbol`: one of `:neutral`, `:short` (claimed) or `:cut` (removed).
"""
mutable struct Edge
    id::Int
    u::Vertex
    v::Vertex
    weight::Float64
    state::Symbol # :neutral, :short, :cut
end

"""
    GameGraph

A static game graph: its vertex/edge *sets* never change, only the `state` of
individual edges does (through `make_move!`).

# Fields
- `vertices::Vector{Vertex}`: all vertices.
- `edges::Vector{Edge}`: all edges.
- `s::Vertex`: source terminal.
- `t::Vertex`: target terminal.
"""
struct GameGraph
    vertices::Vector{Vertex}
    edges::Vector{Edge}
    s::Vertex
    t::Vertex
end

"""
    GameState

The full, mutable state of an in-progress game.

# Fields
- `graph::GameGraph`: the game graph (with mutable edge states).
- `current_player::Symbol`: whose turn it is, `:short` or `:cut`.
- `history::Vector{Tuple{Symbol,Edge}}`: every move so far, in order, as
  `(player, edge)` pairs.
- `winner::Union{Symbol,Nothing}`: `:short`, `:cut`, or `nothing` while the
  game is still undecided.
"""
mutable struct GameState
    graph::GameGraph
    current_player::Symbol
    history::Vector{Tuple{Symbol,Edge}}
    winner::Union{Symbol,Nothing}
end
