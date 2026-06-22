# Cross-check the classic strategies against a brute-force minimax oracle on
# random small graphs. Run from the package root:
#
#     julia --project=. scripts/validate_classic.jl
#
# Confirms `short_strategy` beats an optimal Cut on every Short-win graph and
# `cut_strategy` beats an optimal Short on every Cut-win graph.

using Shannon
using Random

# Can the player to move force Short to connect s-t under optimal play?
function short_can_win(state::GameState)::Bool
    w = check_winner(state)
    w === :short && return true
    w === :cut && return false
    moves = valid_moves(state)
    isempty(moves) && return false
    if state.current_player == :short
        for e in moves
            e.state = :short
            r = short_can_win(GameState(state.graph, :cut, state.history, nothing))
            e.state = :neutral
            r && return true
        end
        return false
    else
        for e in moves
            e.state = :cut
            r = short_can_win(GameState(state.graph, :short, state.history, nothing))
            e.state = :neutral
            r || return false
        end
        return true
    end
end

function optimal_move(state::GameState)::Edge
    moves = valid_moves(state)
    want_short = state.current_player == :short
    for e in moves
        e.state = want_short ? :short : :cut
        nxt = want_short ? :cut : :short
        r = short_can_win(GameState(state.graph, nxt, state.history, nothing))
        e.state = :neutral
        (want_short ? r : !r) && return e
    end
    return first(moves)
end

function play(g, short_fn, cut_fn)
    st = new_game(g)
    while true
        w = check_winner(st)
        w !== nothing && return w
        ms = valid_moves(st)
        isempty(ms) && return :cut
        e = st.current_player === :short ? short_fn(st) : cut_fn(st)
        make_move!(st, e)
    end
end

# Predict the winner-with-Short-to-move via Shannon's internal Lehman engine,
# mirroring the strategy layer: Short (to move) wins iff some neutral claim
# connects s-t or keeps the second-player certificate.
function lehman_short_to_move_wins(g::GameGraph)::Bool
    Shannon.is_connected_st(g, (:short,)) && return true
    Shannon.is_connected_st(g, (:short, :neutral)) || return false
    for e in g.edges
        e.state == :neutral || continue
        if Shannon._short_waits_and_wins(g; claim=e)
            return true
        end
    end
    return false
end

# Walk a random partial play and, at each position with Short to move, compare
# the Lehman engine's verdict against the brute-force minimax oracle.
function probe_positions(g::GameGraph, rng)::Tuple{Int,Int}
    checked = 0; mism = 0
    st = new_game(g)
    while true
        if st.current_player == :short && check_winner(st) === nothing
            want = short_can_win(GameState(g, :short, st.history, nothing))
            got = lehman_short_to_move_wins(g)
            checked += 1
            want == got || (mism += 1;
                println("ENGINE MISMATCH want=$want got=$got states=$([e.state for e in g.edges])"))
        end
        check_winner(st) === nothing || break
        ms = valid_moves(st)
        isempty(ms) && break
        make_move!(st, rand(rng, ms))
    end
    return (checked, mism)
end

Random.seed!(2026)
rng = Random.MersenneTwister(7)
nt = 0; short_ok = 0; cut_ok = 0; bad = 0
pos_checked = 0; pos_mism = 0
for _ in 1:1500
    n = rand(2:6); m = rand((n-1):(n*(n-1)÷2))
    g = random_graph(n, m; weighted=false)
    for e in g.edges; e.state = :neutral; end

    (c, mm) = probe_positions(g, rng)
    global pos_checked += c; global pos_mism += mm
    for e in g.edges; e.state = :neutral; end

    theory_short = short_can_win(new_game(g))
    global nt += 1
    if theory_short
        for e in g.edges; e.state = :neutral; end
        w = play(g, short_strategy, optimal_move)
        w == :short ? (global short_ok += 1) : (global bad += 1;
            println("SHORT FAIL n=$n m=$m E=$([(e.u.id,e.v.id) for e in g.edges])"))
    else
        for e in g.edges; e.state = :neutral; end
        w = play(g, optimal_move, cut_strategy)
        w == :cut ? (global cut_ok += 1) : (global bad += 1;
            println("CUT FAIL n=$n m=$m E=$([(e.u.id,e.v.id) for e in g.edges])"))
    end
end
println("games=$nt  short_strategy_ok=$short_ok  cut_strategy_ok=$cut_ok  FAIL=$bad")
println("engine positions checked=$pos_checked  mismatches=$pos_mism")
