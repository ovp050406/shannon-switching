# Game rules: state creation, legal moves, move execution and win detection.

const SHORT = :short
const CUT   = :cut

"""
    new_game(g::GameGraph) -> GameState

Create a fresh game state for graph `g`: every edge is reset to `:neutral`,
Short is to move, history is empty and there is no winner yet.
"""
function new_game(g::GameGraph)::GameState
    for e in g.edges
        e.state = :neutral
    end
    return GameState(g, SHORT, Tuple{Symbol,Edge}[], nothing)
end

"""
    valid_moves(state::GameState) -> Vector{Edge}

Return all neutral edges, i.e. the moves the current player may legally make.
The same vector is valid for either player (both choose among neutral edges).
"""
function valid_moves(state::GameState)::Vector{Edge}
    return [e for e in state.graph.edges if e.state == :neutral]
end

"""
    check_winner(state::GameState) -> Union{Symbol,Nothing}

Determine the winner of the current position:

- `:short` — Short's claimed (`:short`) edges already contain an `s`–`t` path.
- `:cut` — in the remaining graph (`:short` ∪ `:neutral` edges) there is no
  `s`–`t` path, so Short can never connect.
- `nothing` — the game is still undecided.
"""
function check_winner(state::GameState)::Union{Symbol,Nothing}
    g = state.graph
    if is_connected_st(g, (:short,))
        return :short
    elseif !is_connected_st(g, (:short, :neutral))
        return :cut
    else
        return nothing
    end
end

"""
    make_move!(state::GameState, e::Edge) -> Nothing

Execute the current player's move on neutral edge `e`: Short sets
`e.state = :short`, Cut sets `e.state = :cut`. The move is appended to
`history`, the winner field is refreshed via [`check_winner`](@ref) and the
turn passes to the other player.

`make_move!` always advances `current_player` and never stops the game on its
own — termination is the caller's responsibility. Interactive play stops once
`state.winner !== nothing`; the competition harness keeps playing until no
neutral edge remains (project spec §5). This supports both modes uniformly.

Throws an `AssertionError` if `e` is not neutral.
"""
function make_move!(state::GameState, e::Edge)::Nothing
    @assert e.state == :neutral "Edge $(e.id) is not neutral (state=$(e.state))"

    e.state = state.current_player == SHORT ? :short : :cut
    push!(state.history, (state.current_player, e))
    state.winner = check_winner(state)
    state.current_player = state.current_player == SHORT ? CUT : SHORT
    return nothing
end
