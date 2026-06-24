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

# Order the vertices around the drawing circle by a DFS pre-order from s, so the
# graph's cycles land between circle-adjacent nodes. This removes the crossings
# a naive index order produces (e.g. the diamond becomes a clean ◇ instead of an
# X). Deterministic; unreached vertices are appended.
function _circle_order(g::GameGraph)::Vector{Int}
    adj = Dict{Int,Vector{Int}}(v.id => Int[] for v in g.vertices)
    for e in g.edges
        push!(adj[e.u.id], e.v.id)
        push!(adj[e.v.id], e.u.id)
    end
    order = Int[]
    seen = Set{Int}()
    stack = Int[g.s.id]
    while !isempty(stack)
        x = pop!(stack)
        x in seen && continue
        push!(seen, x)
        push!(order, x)
        for y in sort(unique(adj[x]); rev=true)   # deterministic neighbour order
            y in seen || push!(stack, y)
        end
    end
    for v in g.vertices
        v.id in seen || push!(order, v.id)
    end
    return order
end

# Place vertices evenly on a circle in `_circle_order`, with s pinned to the top.
# Deterministic; good enough for picking.
function _layout(g::GameGraph)::Dict{Int,Tuple{Float64,Float64}}
    order = _circle_order(g)
    n = length(order)
    cx, cy = CANVAS_W / 2, CANVAS_H / 2
    r = min(CANVAS_W, CANVAS_H) / 2 - 2 * NODE_R - 16
    pos = Dict{Int,Tuple{Float64,Float64}}()
    for (i, id) in enumerate(order)
        θ = 2π * (i - 1) / n - π / 2
        pos[id] = (cx + r * cos(θ), cy + r * sin(θ))
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
    # background — cool, very light grey
    set_source_rgb(ctx, 0.965, 0.970, 0.978)
    paint(ctx)

    Cairo.set_line_cap(ctx, Cairo.CAIRO_LINE_CAP_ROUND)
    Cairo.set_line_join(ctx, Cairo.CAIRO_LINE_JOIN_ROUND)
    select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
    set_font_size(ctx, 13.0)

    # edges — drawn trimmed to the node boundary so lines meet the rings cleanly
    for e in state.graph.edges
        (ax, ay) = pos[e.u.id]
        (bx, by) = pos[e.v.id]
        dx, dy = bx - ax, by - ay
        L = hypot(dx, dy)
        if L > 1e-9
            ux, uy = dx / L, dy / L
            ax += ux * NODE_R; ay += uy * NODE_R
            bx -= ux * NODE_R; by -= uy * NODE_R
        end

        if e.state == :cut
            # removed edge: faint muted dotted line so it reads as "gone"
            set_source_rgba(ctx, 0.55, 0.40, 0.42, 0.45)
            set_line_width(ctx, 1.5)
            set_dash(ctx, [2.0, 6.0], 0.0)
        elseif e.state == :short
            # soft glow underneath, then a crisp blue core
            set_source_rgba(ctx, 0.16, 0.45, 0.95, 0.18)
            set_line_width(ctx, 12.0)
            set_dash(ctx, Float64[], 0.0)
            move_to(ctx, ax, ay); line_to(ctx, bx, by); stroke(ctx)
            set_source_rgb(ctx, 0.13, 0.40, 0.92)
            set_line_width(ctx, 5.0)
        else
            set_source_rgb(ctx, 0.62, 0.64, 0.69)
            set_line_width(ctx, 3.0)
            set_dash(ctx, Float64[], 0.0)
        end
        move_to(ctx, ax, ay); line_to(ctx, bx, by); stroke(ctx)
        set_dash(ctx, Float64[], 0.0)

        if weighted && e.weight > 0 && e.state != :cut
            mx, my = (ax + bx) / 2, (ay + by) / 2
            txt = string(round(e.weight; digits=1))
            te = text_extents(ctx, txt)
            set_source_rgba(ctx, 1.0, 1.0, 1.0, 0.88)        # legibility pill
            rectangle(ctx, mx - te[3] / 2 - 3, my - te[4] / 2 - 2, te[3] + 6, te[4] + 4)
            fill(ctx)
            set_source_rgb(ctx, 0.20, 0.20, 0.20)
            move_to(ctx, mx - te[3] / 2 - te[1], my - te[4] / 2 - te[2])
            show_text(ctx, txt)
        end
    end

    # vertices — white disc with a coloured ring (s green, t orange, rest grey)
    for v in state.graph.vertices
        (x, y) = pos[v.id]
        is_s = v.id == state.graph.s.id
        is_t = v.id == state.graph.t.id
        ring = is_s ? (0.18, 0.62, 0.30) :
               is_t ? (0.95, 0.52, 0.10) : (0.55, 0.58, 0.66)

        set_source_rgb(ctx, 1.0, 1.0, 1.0)
        Cairo.new_sub_path(ctx)        # detach: else arc() links a stray line from
        arc(ctx, x, y, NODE_R, 0.0, 2π); fill_preserve(ctx)   # the previous label
        set_source_rgb(ctx, ring...)
        set_line_width(ctx, (is_s || is_t) ? 3.5 : 2.5)
        stroke(ctx)

        label = is_s ? "s" : is_t ? "t" : string(v.id)
        set_source_rgb(ctx, 0.12, 0.12, 0.14)
        select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)
        set_font_size(ctx, 16.0)
        te = text_extents(ctx, label)
        move_to(ctx, x - te[3] / 2 - te[1], y - te[4] / 2 - te[2])
        show_text(ctx, label)
        select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
        set_font_size(ctx, 13.0)
    end
end

# --- editor drawing ----------------------------------------------------------

# Draw the interactive graph editor: working nodes/edges with s/t and the current
# selection highlighted. `nodes` are (id, x, y) triples, `edges` are (u_id, v_id)
# pairs; `sid`/`tid`/`sel` are node ids (0 = none).
function _draw_editor(ctx, nodes, edges, sid::Int, tid::Int, sel::Int)
    set_source_rgb(ctx, 0.95, 0.96, 0.92)        # warm tint marks "edit mode"
    paint(ctx)
    Cairo.set_line_cap(ctx, Cairo.CAIRO_LINE_CAP_ROUND)

    posof = Dict{Int,Tuple{Float64,Float64}}(id => (x, y) for (id, x, y) in nodes)

    set_source_rgb(ctx, 0.62, 0.64, 0.69)
    set_line_width(ctx, 3.0)
    for (u, v) in edges
        (haskey(posof, u) && haskey(posof, v)) || continue
        (ax, ay) = posof[u]; (bx, by) = posof[v]
        dx, dy = bx - ax, by - ay; L = hypot(dx, dy)
        if L > 1e-9
            ux, uy = dx / L, dy / L
            ax += ux * NODE_R; ay += uy * NODE_R; bx -= ux * NODE_R; by -= uy * NODE_R
        end
        move_to(ctx, ax, ay); line_to(ctx, bx, by); stroke(ctx)
    end

    for (id, x, y) in nodes
        ring = id == sid ? (0.18, 0.62, 0.30) :
               id == tid ? (0.95, 0.52, 0.10) :
               id == sel ? (0.13, 0.40, 0.92) : (0.55, 0.58, 0.66)
        set_source_rgb(ctx, 1.0, 1.0, 1.0)
        Cairo.new_sub_path(ctx)
        arc(ctx, x, y, NODE_R, 0.0, 2π); fill_preserve(ctx)
        set_source_rgb(ctx, ring...)
        set_line_width(ctx, (id == sid || id == tid || id == sel) ? 3.5 : 2.5)
        stroke(ctx)
        lbl = id == sid ? "s" : id == tid ? "t" : string(id)
        set_source_rgb(ctx, 0.12, 0.12, 0.14)
        select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)
        set_font_size(ctx, 16.0)
        te = text_extents(ctx, lbl)
        move_to(ctx, x - te[3] / 2 - te[1], y - te[4] / 2 - te[2])
        show_text(ctx, lbl)
    end

    set_source_rgb(ctx, 0.42, 0.42, 0.48)
    select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
    set_font_size(ctx, 13.0)
    move_to(ctx, 12, 22)
    show_text(ctx, "Leere Fläche: Knoten · Knoten→Knoten: Kante · auswählen + s/t setzen · Löschen · Spiel starten")
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

    # editor working state (GUI-only; never touches the GameGraph structs)
    edit_ref  = Ref(false)
    ed_nodes  = Ref(Tuple{Int,Float64,Float64}[])   # (id, x, y)
    ed_edges  = Ref(Tuple{Int,Int}[])               # (u_id, v_id)
    ed_s      = Ref(0); ed_t = Ref(0); ed_sel = Ref(0)
    ed_tool   = Ref(:link)                           # :link | :delete
    ed_nextid = Ref(1)

    win    = GtkWindow("Shannon-Switching", CANVAS_W, CANVAS_H + 230)
    vbox   = GtkBox(:v)
    label  = GtkLabel(_status_string(state_obs[], weighted_ref[]))
    canvas = GtkCanvas(CANVAS_W, CANVAS_H)
    row1   = GtkBox(:h); row2 = GtkBox(:h); row3 = GtkBox(:h); row4 = GtkBox(:h)
    ai_s   = GtkCheckButton("Computer Short")
    ai_c   = GtkCheckButton("Computer Cut")
    wmode  = GtkCheckButton("Gewichtete Strategie")
    Gtk4.G_.set_active(wmode, weighted_ref[])
    combo  = GtkComboBoxText()
    for (name, _) in library
        push!(combo, name)
    end
    btn_new = GtkButton("Neues Spiel")
    lbl_n   = GtkLabel("n"); spin_n = GtkSpinButton(2, 30, 1)
    lbl_m   = GtkLabel("m"); spin_m = GtkSpinButton(1, 435, 1)
    Gtk4.G_.set_value(spin_n, 6.0); Gtk4.G_.set_value(spin_m, 9.0)
    btn_rand  = GtkButton("Zufallsgraph")
    btn_edit  = GtkButton("Editor an/aus")
    btn_set_s = GtkButton("s setzen")
    btn_set_t = GtkButton("t setzen")
    btn_del   = GtkButton("Löschen-Modus")
    btn_build = GtkButton("Spiel starten")

    for w in (label,); Gtk4.G_.set_margin_top(w, 8); Gtk4.G_.set_margin_bottom(w, 8); end
    for w in (ai_s, ai_c, wmode, combo, btn_new, lbl_n, spin_n, lbl_m, spin_m,
              btn_rand, btn_edit, btn_set_s, btn_set_t, btn_del, btn_build)
        Gtk4.G_.set_margin_start(w, 6); Gtk4.G_.set_margin_end(w, 6)
    end

    push!(win, vbox)
    push!(vbox, label); push!(vbox, canvas)
    push!(vbox, row1); push!(vbox, row2); push!(vbox, row3); push!(vbox, row4)
    push!(row1, ai_s); push!(row1, ai_c); push!(row1, wmode)
    push!(row2, combo); push!(row2, btn_new)
    push!(row3, lbl_n); push!(row3, spin_n); push!(row3, lbl_m); push!(row3, spin_m)
    push!(row3, btn_rand)
    push!(row4, btn_edit); push!(row4, btn_set_s); push!(row4, btn_set_t)
    push!(row4, btn_del); push!(row4, btn_build)

    pick_strategy(player) = begin
        if weighted_ref[]
            player === :short ? weighted_short : weighted_cut
        else
            player === :short ? short_strategy : cut_strategy
        end
    end

    function maybe_ai_move()
        edit_ref[] && return
        st = state_obs[]
        st.winner === nothing || return
        ai_on = st.current_player === :short ? Gtk4.G_.get_active(ai_s) :
                                               Gtk4.G_.get_active(ai_c)
        ai_on || return
        @idle_add begin
            (!edit_ref[] && state_obs[].winner === nothing &&
             !isempty(valid_moves(state_obs[]))) || return false
            s2 = state_obs[]
            e = pick_strategy(s2.current_player)(s2)
            make_move!(s2, e)
            notify(state_obs)
            maybe_ai_move()
            return false
        end
    end

    # Start a fresh game on `g`. Short always begins (project spec §1.1 / §2.2).
    function start_with(g::GameGraph)
        st = new_game(g)                # new_game sets current_player = :short
        edit_ref[] = false
        state_obs[] = st                # assignment notifies → label + redraw
        maybe_ai_move()
    end

    # --- editor helpers ---
    ed_status() = "Editor — Knoten: $(length(ed_nodes[]))  Kanten: $(length(ed_edges[]))  " *
                  "s=$(ed_s[] == 0 ? "?" : ed_s[])  t=$(ed_t[] == 0 ? "?" : ed_t[])  " *
                  "Werkzeug: $(ed_tool[] === :delete ? "Löschen" : "Knoten/Kante")"
    refresh_editor() = (Gtk4.G_.set_label(label, ed_status()); draw(canvas))

    function editor_click(x, y)
        hit = 0
        for (id, nx, ny) in ed_nodes[]
            if hypot(x - nx, y - ny) <= NODE_R + 4
                hit = id; break
            end
        end
        if ed_tool[] === :delete
            if hit != 0
                filter!(t -> t[1] != hit, ed_nodes[])
                filter!(e -> e[1] != hit && e[2] != hit, ed_edges[])
                ed_s[] == hit && (ed_s[] = 0)
                ed_t[] == hit && (ed_t[] = 0)
                ed_sel[] == hit && (ed_sel[] = 0)
            else
                posof = Dict(id => (nx, ny) for (id, nx, ny) in ed_nodes[])
                besti = 0; bestd = PICK_TOL
                for (i, (u, v)) in enumerate(ed_edges[])
                    (haskey(posof, u) && haskey(posof, v)) || continue
                    (ax, ay) = posof[u]; (bx, by) = posof[v]
                    d = _point_segment_dist(x, y, ax, ay, bx, by)
                    if d < bestd; bestd = d; besti = i; end
                end
                besti != 0 && deleteat!(ed_edges[], besti)
            end
        elseif hit == 0                              # :link, empty space → new node
            push!(ed_nodes[], (ed_nextid[], Float64(x), Float64(y)))
            ed_nextid[] += 1
            ed_sel[] = 0
        elseif ed_sel[] == 0                         # :link, pick a source node
            ed_sel[] = hit
        elseif ed_sel[] == hit                       # click again → deselect
            ed_sel[] = 0
        else                                         # second node → add edge
            a, b = ed_sel[], hit
            any(e -> (e == (a, b) || e == (b, a)), ed_edges[]) || push!(ed_edges[], (a, b))
            ed_sel[] = 0
        end
        refresh_editor()
    end

    function build_game()
        ns = ed_nodes[]
        if length(ns) < 2
            Gtk4.G_.set_label(label, "Editor: mindestens 2 Knoten nötig"); return
        elseif ed_s[] == 0 || ed_t[] == 0
            Gtk4.G_.set_label(label, "Editor: s und t setzen (Knoten auswählen + Taste)"); return
        elseif ed_s[] == ed_t[]
            Gtk4.G_.set_label(label, "Editor: s und t müssen verschieden sein"); return
        end
        ids = [id for (id, _x, _y) in ns]
        remap = Dict(id => i for (i, id) in enumerate(ids))
        verts = [Vertex(i) for i in 1:length(ids)]
        wt = Gtk4.G_.get_active(wmode)
        edges = Edge[]; eid = 0
        for (u, v) in ed_edges[]
            (haskey(remap, u) && haskey(remap, v)) || continue
            eid += 1
            w = wt ? round(1.0 + 9.0 * rand(); digits=2) : 0.0
            push!(edges, Edge(eid, verts[remap[u]], verts[remap[v]], w, :neutral))
        end
        g = GameGraph(verts, edges, verts[remap[ed_s[]]], verts[remap[ed_t[]]])
        posd = Dict{Int,Tuple{Float64,Float64}}()
        for (id, x, y) in ns; posd[remap[id]] = (x, y); end
        pos_ref[] = posd
        weighted_ref[] = wt
        start_with(g)
    end

    function gen_random()
        n = round(Int, Gtk4.G_.get_value(spin_n))
        m = round(Int, Gtk4.G_.get_value(spin_m))
        n = max(n, 2)
        m = clamp(m, n - 1, n * (n - 1) ÷ 2)
        Gtk4.G_.set_value(spin_m, Float64(m))        # reflect clamping
        wt = Gtk4.G_.get_active(wmode)
        g = random_graph(n, m; weighted=wt)
        pos_ref[] = _layout(g)
        weighted_ref[] = wt
        start_with(g)
    end

    function toggle_edit()
        edit_ref[] = !edit_ref[]
        if edit_ref[]
            empty!(ed_nodes[]); empty!(ed_edges[])
            ed_s[] = 0; ed_t[] = 0; ed_sel[] = 0; ed_nextid[] = 1; ed_tool[] = :link
            refresh_editor()
        else
            Gtk4.G_.set_label(label, _status_string(state_obs[], weighted_ref[]))
            draw(canvas)
        end
    end

    @guarded draw(canvas) do widget
        ctx = getgc(widget)
        if edit_ref[]
            _draw_editor(ctx, ed_nodes[], ed_edges[], ed_s[], ed_t[], ed_sel[])
        else
            _draw_graph(ctx, state_obs[], pos_ref[], weighted_ref[])
        end
    end
    on(state_obs) do st
        edit_ref[] && return
        Gtk4.G_.set_label(label, _status_string(st, weighted_ref[]))
        draw(canvas)
    end

    click = GtkGestureClick()
    push!(canvas, click)
    signal_connect(click, "pressed") do _ctrl, _n, x, y
        if edit_ref[]
            editor_click(x, y); return
        end
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
        start_with(g)
    end
    signal_connect(_ -> start_new(),  btn_new,   "clicked")
    signal_connect(_ -> gen_random(), btn_rand,  "clicked")
    signal_connect(_ -> toggle_edit(), btn_edit, "clicked")
    signal_connect(_ -> build_game(),  btn_build, "clicked")
    signal_connect(_ -> (ed_sel[] != 0 && (ed_s[] = ed_sel[];
                         ed_t[] == ed_s[] && (ed_t[] = 0)); refresh_editor()), btn_set_s, "clicked")
    signal_connect(_ -> (ed_sel[] != 0 && (ed_t[] = ed_sel[];
                         ed_s[] == ed_t[] && (ed_s[] = 0)); refresh_editor()), btn_set_t, "clicked")
    signal_connect(_ -> (ed_tool[] = ed_tool[] === :delete ? :link : :delete;
                         refresh_editor()), btn_del, "clicked")

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
