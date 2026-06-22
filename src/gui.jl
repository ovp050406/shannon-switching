# Playable Gtk4 / Cairo visualisation of the Shannon-Switching game.
#
# Mirrors the patterns of the course's Tic-Tac-Toe template:
#   * an `Observable{GameState}` as the single source of truth,
#   * `on(obs) do … end` to keep canvas + label in sync,
#   * `GtkGestureClick` for picking the nearest edge,
#   * Cairo drawing on a `GtkCanvas`,
#   * `@idle_add` to drive computer moves,
#   * `Gtk4.start_main_loop()` + a close-request `Channel` to block when run
#     as a script.

using Gtk4
using GtkObservables
using Cairo

const CANVAS_W = 760
const CANVAS_H = 600
const NODE_R   = 20.0
const PICK_TOL = 14.0

# --- predefined graphs -------------------------------------------------------

"""
    predefined_graphs() -> Vector{Pair{String,GameGraph}}

A small library of named example graphs for the GUI's "Load" control.
"""
function predefined_graphs()::Vector{Pair{String,GameGraph}}
    [
        "Diamant (Abb. 1)" => _diamond(),
        "K4"               => _complete(4),
        "Zufall 6/9 (gew.)" => random_graph(6, 9; weighted=true),
        "Zufall 8/14"      => random_graph(8, 14; weighted=false),
    ]
end

function _diamond()::GameGraph
    v = [Vertex(i) for i in 1:4]                 # 1=s, 4=t, 2=a, 3=b
    e = [
        Edge(1, v[1], v[2], 0.0, :neutral),
        Edge(2, v[2], v[4], 0.0, :neutral),
        Edge(3, v[1], v[3], 0.0, :neutral),
        Edge(4, v[3], v[4], 0.0, :neutral),
    ]
    return GameGraph(v, e, v[1], v[4])
end

function _complete(n::Int)::GameGraph
    v = [Vertex(i) for i in 1:n]
    e = Edge[]
    id = 0
    for i in 1:n, j in (i+1):n
        id += 1
        push!(e, Edge(id, v[i], v[j], 0.0, :neutral))
    end
    return GameGraph(v, e, v[1], v[n])
end

# --- layout ------------------------------------------------------------------

# Place vertices evenly on a circle. Deterministic; good enough for picking.
function _layout(g::GameGraph)::Dict{Int,Tuple{Float64,Float64}}
    n = length(g.vertices)
    cx, cy = CANVAS_W / 2, CANVAS_H / 2
    r = min(CANVAS_W, CANVAS_H) / 2 - 2 * NODE_R - 10
    pos = Dict{Int,Tuple{Float64,Float64}}()
    for (i, v) in enumerate(g.vertices)
        θ = 2π * (i - 1) / n - π / 2
        pos[v.id] = (cx + r * cos(θ), cy + r * sin(θ))
    end
    return pos
end

# Distance from point p to segment ab.
function _point_segment_dist(px, py, ax, ay, bx, by)::Float64
    dx, dy = bx - ax, by - ay
    len2 = dx * dx + dy * dy
    len2 == 0 && return hypot(px - ax, py - ay)
    t = clamp(((px - ax) * dx + (py - ay) * dy) / len2, 0.0, 1.0)
    return hypot(px - (ax + t * dx), py - (ay + t * dy))
end

# --- drawing -----------------------------------------------------------------

function _status_string(state::GameState, weighted::Bool)::String
    if state.winner === :short
        return "SHORT gewinnt — s-t verbunden"
    elseif state.winner === :cut
        return "CUT gewinnt — s-t getrennt"
    end
    who = state.current_player === :short ? "Short (Verbinden)" : "Cut (Trennen)"
    if weighted
        cost, _ = _cheapest_st(state.graph)
        c = cost == Inf ? "∞" : string(round(cost; digits=1))
        return "Am Zug: $who   ·   günstigster s-t-Weg: $c"
    end
    return "Am Zug: $who"
end

function _draw_graph(ctx, state::GameState, pos, weighted::Bool)
    set_source_rgb(ctx, 0.98, 0.98, 0.96)
    paint(ctx)

    # edges
    select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
    set_font_size(ctx, 13.0)
    for e in state.graph.edges
        (ax, ay) = pos[e.u.id]
        (bx, by) = pos[e.v.id]
        if e.state == :cut
            set_source_rgba(ctx, 0.80, 0.20, 0.20, 0.35)
            set_line_width(ctx, 1.5)
            set_dash(ctx, [6.0, 5.0], 0.0)
        elseif e.state == :short
            set_source_rgb(ctx, 0.10, 0.35, 0.85)
            set_line_width(ctx, 6.0)
            set_dash(ctx, Float64[], 0.0)
        else
            set_source_rgb(ctx, 0.55, 0.55, 0.55)
            set_line_width(ctx, 2.5)
            set_dash(ctx, Float64[], 0.0)
        end
        move_to(ctx, ax, ay); line_to(ctx, bx, by); stroke(ctx)
        set_dash(ctx, Float64[], 0.0)
        if weighted && e.weight > 0 && e.state != :cut
            mx, my = (ax + bx) / 2, (ay + by) / 2
            set_source_rgb(ctx, 0.15, 0.15, 0.15)
            move_to(ctx, mx + 4, my - 4)
            show_text(ctx, string(round(e.weight; digits=1)))
        end
    end

    # vertices
    for v in state.graph.vertices
        (x, y) = pos[v.id]
        if v.id == state.graph.s.id
            set_source_rgb(ctx, 0.20, 0.65, 0.30)
        elseif v.id == state.graph.t.id
            set_source_rgb(ctx, 0.95, 0.55, 0.10)
        else
            set_source_rgb(ctx, 0.88, 0.88, 0.90)
        end
        arc(ctx, x, y, NODE_R, 0.0, 2π); fill_preserve(ctx)
        set_source_rgb(ctx, 0.25, 0.25, 0.25); set_line_width(ctx, 1.5); stroke(ctx)

        label = v.id == state.graph.s.id ? "s" :
                v.id == state.graph.t.id ? "t" : string(v.id)
        set_source_rgb(ctx, 0.10, 0.10, 0.10)
        select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)
        set_font_size(ctx, 16.0)
        te = text_extents(ctx, label)
        move_to(ctx, x - te[3] / 2 - te[1], y - te[4] / 2 - te[2])
        show_text(ctx, label)
    end
end

# --- entry point -------------------------------------------------------------

"""
    run_game(graph::GameGraph = _diamond())

Open a Gtk4 window to play the Shannon-Switching game on `graph`. Two humans
alternate by clicking edges; tick "Computer Short"/"Computer Cut" to let an
optimal (unweighted) or heuristic (weighted) strategy play that side. Use the
graph dropdown to load examples and "Neues Spiel" to restart.
"""
function run_game(graph::GameGraph = _diamond())
    library = predefined_graphs()
    state_obs = Observable(new_game(graph))
    pos_ref = Ref(_layout(graph))
    weighted_ref = Ref(any(e -> e.weight > 0, graph.edges))

    win    = GtkWindow("Shannon-Switching", CANVAS_W, CANVAS_H + 150)
    vbox   = GtkBox(:v)
    label  = GtkLabel(_status_string(state_obs[], weighted_ref[]))
    canvas = GtkCanvas(CANVAS_W, CANVAS_H)
    row1   = GtkBox(:h)
    row2   = GtkBox(:h)
    ai_s   = GtkCheckButton("Computer Short")
    ai_c   = GtkCheckButton("Computer Cut")
    wmode  = GtkCheckButton("Gewichtete Strategie")
    Gtk4.G_.set_active(wmode, weighted_ref[])
    combo  = GtkComboBoxText()
    for (name, _) in library
        push!(combo, name)
    end
    btn_new = GtkButton("Neues Spiel")

    for w in (label,); Gtk4.G_.set_margin_top(w, 8); Gtk4.G_.set_margin_bottom(w, 8); end
    for w in (ai_s, ai_c, wmode, combo, btn_new)
        Gtk4.G_.set_margin_start(w, 8); Gtk4.G_.set_margin_end(w, 8)
    end

    push!(win, vbox)
    push!(vbox, label); push!(vbox, canvas)
    push!(vbox, row1); push!(vbox, row2)
    push!(row1, ai_s); push!(row1, ai_c); push!(row1, wmode)
    push!(row2, combo); push!(row2, btn_new)

    @guarded draw(canvas) do widget
        _draw_graph(getgc(widget), state_obs[], pos_ref[], weighted_ref[])
    end
    on(state_obs) do st
        Gtk4.G_.set_label(label, _status_string(st, weighted_ref[]))
        draw(canvas)
    end

    pick_strategy(player) = begin
        if weighted_ref[]
            player === :short ? weighted_short : weighted_cut
        else
            player === :short ? short_strategy : cut_strategy
        end
    end

    function maybe_ai_move()
        st = state_obs[]
        st.winner === nothing || return
        ai_on = st.current_player === :short ? Gtk4.G_.get_active(ai_s) :
                                               Gtk4.G_.get_active(ai_c)
        ai_on || return
        @idle_add begin
            s2 = state_obs[]
            (s2.winner === nothing && !isempty(valid_moves(s2))) || return false
            e = pick_strategy(s2.current_player)(s2)
            make_move!(s2, e)
            notify(state_obs)
            maybe_ai_move()
            return false
        end
    end

    click = GtkGestureClick()
    push!(canvas, click)
    signal_connect(click, "pressed") do _ctrl, _n, x, y
        st = state_obs[]
        st.winner === nothing || return
        ai_on = st.current_player === :short ? Gtk4.G_.get_active(ai_s) :
                                               Gtk4.G_.get_active(ai_c)
        ai_on && return                              # computer's turn → ignore clicks
        pos = pos_ref[]
        best = nothing; bestd = PICK_TOL
        for e in st.graph.edges
            e.state == :neutral || continue
            (ax, ay) = pos[e.u.id]; (bx, by) = pos[e.v.id]
            d = _point_segment_dist(x, y, ax, ay, bx, by)
            if d < bestd; bestd = d; best = e; end
        end
        best === nothing && return
        make_move!(st, best)
        notify(state_obs)
        maybe_ai_move()
    end

    start_new() = begin
        idx = Gtk4.G_.get_active(combo)
        g = idx >= 0 ? library[idx + 1][2] : graph
        weighted_ref[] = Gtk4.G_.get_active(wmode)
        pos_ref[] = _layout(g)
        state_obs[] = new_game(g)
        maybe_ai_move()
    end
    signal_connect(_ -> start_new(), btn_new, "clicked")

    show(win)
    maybe_ai_move()
    Gtk4.start_main_loop()
    if !isinteractive()
        done = Channel{Nothing}(1)
        signal_connect(win, "close-request") do _
            isopen(done) && put!(done, nothing)
            return false
        end
        take!(done)
    end
end
