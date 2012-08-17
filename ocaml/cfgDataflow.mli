(** Dataflow module for use with Control Flow Graphs.  Use this module
    to write dataflow analyses in BAP instead of {!GraphDataflow}. *)

open GraphDataflow

(** Types of control flow graph that data flow is defined on *)
module type CFG =
sig
  type exp
  type stmt
  type lang = stmt list
  module G : sig
    type t
    module V : Graph.Sig.COMPARABLE
    module E : Graph.Sig.EDGE with type vertex = V.t and type label = (bool * exp) option
    val pred_e : t -> V.t -> E.t list
    val succ_e : t -> V.t -> E.t list
    val fold_vertex : (V.t -> 'a -> 'a) -> t -> 'a -> 'a
  end
  val get_stmts : G.t -> G.V.t -> lang
end

(** A dataflow problem is defined by a lattice over a CFG. *)
module type DATAFLOW =
sig

  module L : BOUNDED_MEET_SEMILATTICE
  module CFG : CFG

  (** Type of extra information that can be specified each time the
      dataflow analysis is applied. *)
  type options

  (** The transfer function over statements. The second argument
      contains the location of the statement being processed,and is
      generally unused. *)
  val stmt_transfer_function : options -> CFG.G.t -> CFG.G.V.t * int -> CFG.stmt -> L.t -> L.t

  (** The transfer function over edge elements, e.g., conditions. The
      second argument is generally unused. *)
  val edge_transfer_function : options -> CFG.G.t -> CFG.G.E.t -> CFG.exp option -> L.t -> L.t

  (** The starting node for the analysis. *)
  val s0 : options -> CFG.G.t -> CFG.G.V.t

  (** The initial lattice value given to node [s0]. All other nodes
      start out with [Top]. *)
  val init : options -> CFG.G.t -> L.t

  (** The dataflow direction. *)
  val dir : options -> direction
end

(** A dataflow problem with widening. *)
module type DATAFLOW_WITH_WIDENING =
sig

  module L : BOUNDED_MEET_SEMILATTICE_WITH_WIDENING
  module CFG : CFG

  (** Type of extra information that can be specified each time the
      dataflow analysis is applied. *)
  type options

  (** The transfer function over statements. The second argument
      contains the location of the statement being processed,and is
      generally unused. *)
  val stmt_transfer_function : options -> CFG.G.t -> CFG.G.V.t * int -> CFG.stmt -> L.t -> L.t

  (** The transfer function over edge elements, e.g., conditions. The
      second argument is generally unused. *)
  val edge_transfer_function : options -> CFG.G.t -> CFG.G.E.t -> CFG.exp option -> L.t -> L.t

  (** The starting node for the analysis. *)
  val s0 : options -> CFG.G.t -> CFG.G.V.t

  (** The initial lattice value given to node [s0]. All other nodes
      start out with [Top]. *)
  val init : options -> CFG.G.t -> L.t

  (** The dataflow direction. *)
  val dir : options -> direction
end

(** Build a custom dataflow algorithm for the given dataflow problem [D]. *)
module Make :
  functor (D : DATAFLOW) ->
sig
  (** [worklist_iterate g] returns a worklist algorithm for graph [g]
      as a pair of functions [in,out]. [in], when given a node [v],
      computes the lattice value going in to that node, [v]. [out],
      when given a node [v], computes the lattice value exiting
      [v]. *)
  val worklist_iterate : ?init:(D.options -> D.CFG.G.t -> D.L.t) ->
    D.options -> D.CFG.G.t -> (D.CFG.G.V.t -> D.L.t) * (D.CFG.G.V.t -> D.L.t)

  (** Like [worklist_iterate], except the dataflow is done on the
      statement level. A statement [bb,n] is the [n]th stmt
      (zero-indexed) in [bb]. *)
  val worklist_iterate_stmt : ?init:(D.options -> D.CFG.G.t -> D.L.t) ->
    D.options -> D.CFG.G.t -> (D.CFG.G.V.t * int -> D.L.t) * (D.CFG.G.V.t * int -> D.L.t)
end

(** Build a custom dataflow algorithm for the given dataflow problem
    with widening operator [D]. *)
module MakeWide :
  functor (D : DATAFLOW_WITH_WIDENING) ->
sig
  (** Same as [worklist_iterate], but additionally employs the
      widening operator as lattice values propagate over backedges in
      the CFG.  Backedges are identified by observing when lattices
      values flow in cycles.

      @param nmeets The number of times a widening edge should be
      computed using meet.  After this threshold is reached, the widening
      operator will be applied.
  *)
  val worklist_iterate_widen : ?init:(D.options -> D.CFG.G.t -> D.L.t) ->
    ?nmeets:int -> D.options -> D.CFG.G.t -> (D.CFG.G.V.t -> D.L.t) * (D.CFG.G.V.t -> D.L.t)
end
