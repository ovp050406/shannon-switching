"""
    Shannon

Implementation of the Shannon-Switching game (TU Berlin, CoMa II project):
data structures, game logic, a Gtk4 visualisation, optimal strategies for the
classic unweighted game and heuristic strategies for the weighted competition.
"""
module Shannon

# Includes are ordered by dependency: each file may use everything included
# above it, never below — do not reorder (e.g. game.jl calls into graph.jl,
# lehman.jl builds on spanning_trees.jl, the strategies build on lehman/cuts).
include("structs.jl")
include("graph.jl")
include("game.jl")
include("spanning_trees.jl")
include("lehman.jl")
include("cuts.jl")
include("strategies_classic.jl")
include("strategies_weighted.jl")

# The GUI pulls in the (heavy) Gtk stack. Load it optionally so the rest of the
# package — and the test suite — work even where Gtk binaries are unavailable.
const GUI_AVAILABLE = Ref(false)
try
    include("gui.jl")
    GUI_AVAILABLE[] = true
catch err
    @warn "GUI not loaded (Gtk stack unavailable); `run_game` is disabled." exception = (err, catch_backtrace())
    # Stub with the same name so `export run_game` still succeeds and a caller
    # gets a clear instruction instead of an UndefVarError.
    global run_game(args...) = error(
        "GUI unavailable. Add Gtk4, GtkObservables and Cairo to the active " *
        "environment and reload Shannon to enable run_game.")
end

# Public API. Underscore-prefixed internals (short_certificate, _cheapest_st,
# _short_waits_and_wins, …) are intentionally NOT exported — reach them via
# `Shannon.<name>` (as scripts/validate_classic.jl does when testing the engine).
# core data structures
export Vertex, Edge, GameGraph, GameState
# game logic
export new_game, valid_moves, make_move!, check_winner
export random_graph, is_connected_st, st_path_edges
# classic optimal strategies
export short_strategy, cut_strategy
# weighted competition strategies
export weighted_short, weighted_cut, TEAM_NAME
# visualisation
export run_game

end # module Shannon
