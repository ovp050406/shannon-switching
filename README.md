# Shannon — Shannon-Switching-Spiel (CoMa II, TU Berlin, SoSe 2026)

Julia-Paket für das Shannon-Switching-Spiel: Datenstrukturen, Spiellogik, eine
spielbare Gtk4-Visualisierung, eine **optimale** Strategie für das klassische
(ungewichtete) Spiel sowie Heuristiken für den gewichteten Wettbewerb.

## Struktur

```
src/
  Shannon.jl              Modul + Exporte (GUI wird optional geladen)
  structs.jl              Vertex, Edge, GameGraph, GameState (Spec §2.1)
  game.jl                 new_game, valid_moves, make_move!, check_winner
  graph.jl                BFS-Zusammenhang, s-t-Pfade, random_graph
  spanning_trees.jl       zwei kantendisjunkte Spannbäume (Matroid-Union)
  lehman.jl               Lehman/Kishi-Kajitani: FC, fix(e), fix(e*), Zertifikat
  cuts.jl                 minimaler s-t-Schnitt über entfernbare Kanten
  strategies_classic.jl   short_strategy, cut_strategy (Lehman-Strategie)
  strategies_weighted.jl  weighted_short, weighted_cut, TEAM_NAME
  gui.jl                  Gtk4/Cairo-Visualisierung (run_game)
test/runtests.jl          Testsuite
scripts/validate_classic.jl  Brute-Force-Quercheck der klassischen Strategien
submission/comajudge.jl   self-contained Wettbewerbsabgabe (nur Teil 4)
```

## Benutzung

```julia
julia --project=.                 # REPL im Projekt
using Pkg; Pkg.instantiate()      # einmalig: Abhängigkeiten installieren
using Shannon
run_game()                        # GUI öffnen (Diamant-Beispiel)
```

Tests und Quercheck:

```
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=. scripts/validate_classic.jl
```

## Strategien

* **Klassisch (Teil 3).** `short_strategy`/`cut_strategy` setzen den
  **polynomiellen Algorithmus aus der Übung** um (Lehmans Charakterisierung,
  Kishi-Kajitani). Short gewinnt genau dann als wartender Spieler, wenn der
  verfügbare Graph (Short-Kanten kontrahiert, Cut-Kanten gelöscht) zwei
  kantendisjunkte zusammenhängende Teilgraphen auf einer gemeinsamen Knotenmenge
  U ∋ {s,t} besitzt. `short_certificate` (in `lehman.jl`) entscheidet das über
  zwei überschneidungsminimale Spannbäume und die virtuelle Kante e* = {s,t}.
  Beide Strategien ziehen, indem sie in der Gewinnregion bleiben — Short erhält
  das Zertifikat, Cut verweigert es (dual: Feedback-Edge-Sets). Polynomiell,
  daher ohne Spielbaum-Grenze. Quergeprüft Zug für Zug gegen einen Brute-Force-
  Minimax-Orakel (`scripts/validate_classic.jl`, 0 Abweichungen).
* **Gewichtet (Teil 4).** Proxy = günstigster s-t-Weg in G′ (Short-Kanten
  kosten 0). Short sichert die *kritischste* Kante dieses Weges; Cut entfernt die
  Kante, die diese Kosten am stärksten erhöht (bzw. s-t trennt). Jeder Zug nur
  wenige O(V²)-Dijkstra-Auswertungen → deutlich unter dem 2-s-Limit.

## Team

**OSA** — Oleksandr Pistruzhak, Ali Kilinc, Simon Wesendrup.

## Abgabe

```
comajudge submit -t submission/comajudge.jl -p Shannon
comajudge result -p Shannon      # täglich 18 Uhr
```
