(** Reachability analysis

$Id$
*)
module type B =
sig
  include Graph.Builder.S
  (* val empty : unit -> G.t *)
  val remove_vertex : G.t -> G.V.t -> G.t
  val copy_map : G.t -> G.t
  (* val add_vertex : G.t -> G.V.t -> G.t *)
  (* val add_edge_e : G.t -> G.E.t -> G.t *)
end

module type Reach =
  sig

    type gt
    type vt

    val iter_reachable : (vt -> unit) -> gt -> vt -> unit
    val iter_unreachable : (vt -> unit) -> gt -> vt -> unit
      
    val fold_reachable : (vt -> 'a -> 'a) -> gt -> vt -> 'a -> 'a
    val fold_unreachable : (vt -> 'a -> 'a) -> gt -> vt -> 'a -> 'a
      
    val reachable : gt -> vt -> vt list
    val unreachable : gt -> vt -> vt list
      
    val remove_unreachable : gt -> vt -> gt      
    val remove_unreachable_copy : gt -> vt -> gt      
  end

module Make :
  functor (BI : B) ->
    Reach with type gt = BI.G.t and type vt = BI.G.V.t

module AST : (Reach with type gt = Cfg.AST.G.t and type vt = Cfg.AST.G.V.t)
module SSA : (Reach with type gt = Cfg.SSA.G.t and type vt = Cfg.SSA.G.V.t)

