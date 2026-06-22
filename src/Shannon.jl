"""
    Shannon

Implementation of the Shannon-Switching game (TU Berlin, CoMa II project):
data structures, game logic, a Gtk4 visualisation, optimal strategies for the
classic unweighted game and heuristic strategies for the weighted competition.
"""
module Shannon

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
    global run_game(args...) = error(
        "GUI unavailable. Add Gtk4, GtkObservables and Cairo to the active " *
        "environment and reload Shannon to enable run_game.")
end

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
