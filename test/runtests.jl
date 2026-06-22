using Shannon
using Test
using Random

# Build the Abb.1 diamond: 1=s, 4=t, paths s-2-t and s-3-t.
function diamond()
    v = [Vertex(i) for i in 1:4]
    e = [
        Edge(1, v[1], v[2], 0.0, :neutral),
        Edge(2, v[2], v[4], 0.0, :neutral),
        Edge(3, v[1], v[3], 0.0, :neutral),
        Edge(4, v[3], v[4], 0.0, :neutral),
    ]
    return GameGraph(v, e, v[1], v[4])
end

function complete_graph(n)
    v = [Vertex(i) for i in 1:n]
    e = Edge[]; id = 0
    for i in 1:n, j in (i+1):n
        id += 1; push!(e, Edge(id, v[i], v[j], 0.0, :neutral))
    end
    return GameGraph(v, e, v[1], v[n])
end

# Play short_fn (Short) vs cut_fn (Cut) to a decision.
function play(g, short_fn, cut_fn)
    st = new_game(g)
    while true
        w = check_winner(st)
        w !== nothing && return w
        ms = valid_moves(st)
        isempty(ms) && return :cut
        e = st.current_player === :short ? short_fn(st) : cut_fn(st)
        @assert e.state == :neutral
        make_move!(st, e)
    end
end

@testset "Shannon" begin

    @testset "new_game" begin
        s = new_game(diamond())
        @test all(e.state == :neutral for e in s.graph.edges)
        @test s.current_player == :short
        @test isnothing(s.winner)
        @test isempty(s.history)
    end

    @testset "valid_moves" begin
        s = new_game(diamond())
        @test length(valid_moves(s)) == 4
        make_move!(s, s.graph.edges[1])
        @test length(valid_moves(s)) == 3
        @test s.graph.edges[1] ∉ valid_moves(s)
    end

    @testset "make_move! — alternation & history" begin
        s = new_game(diamond())
        make_move!(s, s.graph.edges[1])     # Short
        @test s.graph.edges[1].state == :short
        @test s.current_player == :cut
        @test s.history == [(:short, s.graph.edges[1])]
        make_move!(s, s.graph.edges[3])     # Cut
        @test s.graph.edges[3].state == :cut
        @test s.current_player == :short
        @test length(s.history) == 2
    end

    @testset "make_move! — rejects non-neutral edge" begin
        s = new_game(diamond())
        make_move!(s, s.graph.edges[1])
        @test_throws AssertionError make_move!(s, s.graph.edges[1])
    end

    @testset "check_winner" begin
        # Short connects s-2-t.
        s = new_game(diamond())
        s.graph.edges[1].state = :short      # s-2
        s.graph.edges[2].state = :short      # 2-t
        @test check_winner(s) == :short

        # Cut removes both paths to t.
        s = new_game(diamond())
        s.graph.edges[2].state = :cut        # 2-t
        s.graph.edges[4].state = :cut        # 3-t
        @test check_winner(s) == :cut

        # Undecided.
        @test isnothing(check_winner(new_game(diamond())))
    end

    @testset "random_graph" begin
        rng = MersenneTwister(123)
        for _ in 1:50
            n = rand(rng, 2:8)
            m = rand(rng, (n-1):(n*(n-1)÷2))
            g = random_graph(n, m; weighted=true, rng=rng)
            @test length(g.vertices) == n
            @test length(g.edges) == m
            @test g.s.id == 1 && g.t.id == n
            @test is_connected_st(g, (:neutral,))           # connected
            @test all(1.0 <= e.weight <= 10.0 for e in g.edges)
        end
        g = random_graph(5, 7; weighted=false)
        @test all(e.weight == 0.0 for e in g.edges)
        @test_throws ArgumentError random_graph(4, 2)        # m < n-1
        @test_throws ArgumentError random_graph(4, 99)       # m too large
    end

    @testset "classic optimal strategies" begin
        # Strategies always return a legal (neutral) move.
        s = new_game(complete_graph(4))
        @test short_strategy(s).state == :neutral
        @test cut_strategy(s).state == :neutral

        # Known game values: diamond is a Cut win, K4 is a Short win.
        @test play(diamond(), short_strategy, cut_strategy) == :cut
        @test play(complete_graph(4), short_strategy, cut_strategy) == :short

        # Optimal Short must beat *any* Cut on a Short-win graph (K4).
        rng = MersenneTwister(1)
        randcut(st) = rand(rng, valid_moves(st))
        @test play(complete_graph(4), short_strategy, randcut) == :short
    end

    @testset "weighted strategies" begin
        rng = MersenneTwister(7)
        for _ in 1:20
            n = rand(rng, 3:6)
            m = rand(rng, (n-1):(n*(n-1)÷2))
            g = random_graph(n, m; weighted=true, rng=rng)
            st = new_game(g)
            # plays to the very last edge without error, moves always legal
            while !isempty(valid_moves(st))
                e = st.current_player === :short ? weighted_short(st) : weighted_cut(st)
                @test e.state == :neutral
                make_move!(st, e)
            end
            @test isempty(valid_moves(st))
        end
    end

    @testset "spanning trees" begin
        # K4 (contracted to its 4 vertices) has two edge-disjoint spanning trees.
        g = complete_graph(4)
        edges = [(e.id, e.u.id, e.v.id) for e in g.edges]
        @test Shannon.two_disjoint_spanning_trees(4, edges) !== nothing
        # A triangle does not.
        @test Shannon.two_disjoint_spanning_trees(3, [(1,1,2),(2,2,3),(3,1,3)]) === nothing
    end

end
