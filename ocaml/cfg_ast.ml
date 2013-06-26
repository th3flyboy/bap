(** Translations between AST programs and AST CFGs.


    TODO: Coalescing; Use BB_Entry when making traces, but avoid joining that
    trace with the trace containing BB_Exit.
*)

open Type
open Ast
open Cfg
open BatListFull

module C = Cfg.AST
module D = Debug.Make(struct let name = "Cfg_ast" and default=`NoDebug end)
open D

type unresolved_edge = C.G.V.t * C.G.E.label * Ast.exp

let v2s v = bbid_to_string(C.G.V.label v)

let create c l stmts =
  let v = C.G.V.create l in
  let c = C.add_vertex c v in
  (C.set_stmts c v stmts, v)

let create_entry g =
  create g BB_Entry [Comment("entry node",[])]

let find_entry g =
  try
    g, C.find_vertex g BB_Entry
  with Not_found ->
    failwith "BB_Entry is missing! This should not happen."

let find_error g =
  try
    g, C.find_vertex g BB_Error
  with Not_found ->
    create g BB_Error [Label(Name("BB_Error"), [SpecialBlock]); Assert(exp_false, [])]

let find_exit g =
  try
    g, C.find_vertex g BB_Exit
  with Not_found ->
    create g BB_Exit [(*Label(Name "BB_Exit", []); *)Comment("exit node",[])]

let find_indirect g =
  try
    g, C.find_vertex g BB_Indirect
  with Not_found ->
    create g BB_Indirect []

(* Add a new bb to the cfg *)
let add_new_bb indirectt c revstmts addpred =
  (* Check for a bb already in the graph that has the same statements.
     This can happen for entry, exit, etc. *)
  let find_duplicate c revstmts stmts = match stmts with
    | Label(l, _)::_ ->
      (try
         let v = C.find_label c l in
         let ostmts = C.get_stmts c v in
           (* At this point, we are redefining a label which is bad.  If
              the existing block and the new block are identical, we'll
              just silently use the old block.  If not, raise an
              exception because we are defining a label twice. *)
         if full_stmts_eq stmts ostmts then
           Some(v) 
         else 
           failwith (Printf.sprintf "Duplicate label usage: label %s" 
                       (Pp.label_to_string l))
       with Not_found -> None) (* The label does not exist *)
    | _ -> None
  in
  let stmts = List.rev revstmts in
  let c,v = match find_duplicate c revstmts stmts with
    | Some(v) ->
      dprintf "Not adding duplicate bb of %s" (v2s v);
      c,v
    | None ->
      let c,v = C.create_vertex c stmts in
      dprintf "of_prog: added vertex %s" (v2s v);
      let c =
        if indirectt then
          let (c, indirect) = find_indirect c in
          C.add_edge c indirect v
        else c
      in
      c,v
  in
  match addpred with
  | None -> (c,v)
  | Some v' -> (C.add_edge c v' v, v)

  (* Decide what to do given the current state and the next stmt.
     indirectt: Should indirect point to this BB?
     nodes: added BBs (in reverse order)
     edges: delayed edges
     c: the cfg so far
     cur: reversed list of statements we will add to the next bb
     onlylabs: true if cur only contains labels (or comments)
     addpred: Add Some v as predecessor
  *)
let f ~special_error (indirectt, nodes, edges, c, cur,onlylabs, addpred) s =
  let indirect_edge_to indirectt = function
    | Addr _ -> true
    | Name _ -> indirectt
  in
  (* Start a new node after s *)
  let g () =
    let (c,v) = add_new_bb indirectt c (s::cur) addpred in
    let for_later ?lab t = (v,lab,t) in
    let edges, c = match s with
      | Jmp(t, _) -> for_later t::edges, c
      (* XXX: This does not structure expressions such that it is
         easy to tell if two expressions are inverted *)
      | CJmp(e,t,f,_) -> for_later ~lab:(true, Ast_convenience.binop EQ e exp_true) t::for_later ~lab:(false, Ast_convenience.binop EQ e exp_false) f::edges, c
      | Special _ -> let c, error = find_error c in
                     edges, C.add_edge c v error
      | Halt _ -> let c, exit = find_exit c in
                  edges, C.add_edge c v exit
      | Assert(e,_) when e === exp_false ->
        let c, error = find_error c in
        edges, if v <> error then C.add_edge c v error else c
      | _ -> failwith "impossible"
    in
    (false, v::nodes, edges, c, [], true, None)
  in
  (* Start a new node including s *)
  let h l =
    let indirectt = indirect_edge_to indirectt l in
    let c,v = add_new_bb indirectt c cur addpred in
    (indirectt, v::nodes, edges, c, [s], true, Some v)
  in
  match s with
  | Jmp _ | CJmp _ | Halt _ ->
    g ()
  | Special _ when special_error ->
    g ()
  | Special _ (* specials are not error *) ->
    (indirectt, nodes, edges, c, s::cur, onlylabs, addpred)
  | Label(l, attrs) when List.mem SpecialBlock attrs ->
    h l
  | Label(l,_) when onlylabs ->
    let indirectt = indirect_edge_to indirectt l in
    (indirectt, nodes, edges, c, s::cur, true, addpred)
  | Label(l,_) ->
    let c,v = add_new_bb indirectt c cur addpred in
    let indirectt = indirect_edge_to false l in
    (indirectt, v::nodes, edges, c, [s], true, Some v)
  | Assert(e,_) when e === exp_false ->
    g ()
  | Move _ | Assert _ | Assume _ ->
    (indirectt, nodes, edges, c, s::cur, false, addpred)
  | Comment _ ->
    (indirectt, nodes, edges, c, s::cur, onlylabs, addpred)

(** Build a CFG from a program *)
let of_prog ?(special_error = true) p =
  let (tmp, entry) = create_entry (C.empty()) in
  let (tmp, exit) = find_exit tmp in
  let (tmp, error) = find_error tmp in
  let (c, indirect) = find_indirect tmp in
  let c = C.add_edge c indirect error in (* indirect jumps could fail *)

  let (indirectt,_nodes,postponed_edges,c,last,_,addpred) = List.fold_left (f ~special_error) (false,[],[],c,[],true,Some entry) p in
  let c = match last with
    | _::_ ->
      let c,v = add_new_bb indirectt c last addpred in
      C.add_edge c v exit
    | [] -> match addpred with
      | None -> c
      | Some v -> C.add_edge c v exit (* Should only happen for empty programs *)
  in
  let make_edge c (v,lab,t) =
    let dst = lab_of_exp t in
    let tgt = match dst with
      | None -> indirect
      | Some l ->
	  try (C.find_label c l)
	  with Not_found ->
	    wprintf "Jumping to unknown label: %s" (Pp.label_to_string l);
	    error
      (* FIXME: should jumping to an unknown address be an error or indirect? *)
    in
    C.add_edge_e c (C.G.E.create v lab tgt)
  in
  let c = List.fold_left make_edge c postponed_edges in
  (* Remove indirect if unused *)
  let c = if C.G.in_degree c indirect = 0 then C.remove_vertex c indirect else c in
  (* Remove error if unused *)
  let c = if C.G.in_degree c error = 0 then C.remove_vertex c error else c in
  (* FIXME: Coalescing *)
  c

(** Add an AST program to an existing CFG. The program will not be
    connected to the rest of the CFG. *)
let add_prog ?(special_error = true) c p =

  let (indirectt,nodes,postponed_edges,c,last,_,addpred) = List.fold_left (f ~special_error) (false,[],[],c,[],true,None) p in
  let fallthrough, c, nodes = match last with
    | _::_ ->
      let c,v = add_new_bb indirectt c last addpred in
      Some v, c, (v::nodes)
    | [] -> match addpred with
      | None -> None, c, nodes
      | Some v -> failwith "add_prog: I do not think this is posible"
  in
  c, postponed_edges, List.rev nodes, fallthrough

(** Convert a CFG back to an AST program.
    This is needed for printing in a way that can be parsed again.
*)
let to_prog c =
  let size = C.G.nb_vertex c in
  let c = C.remove_vertex c (C.G.V.create BB_Indirect) in
  let module BH = Hashtbl.Make(C.G.V) in
  let tails = BH.create size (* maps head vertex to the tail of the trace *)
    (* maps vertex to succ it was joined with, forming a trace *)
  and joined = BH.create size
  and hrevstmts = BH.create size in
  let get_revstmts b =
    try BH.find hrevstmts b
    with Not_found ->
      let s = match C.G.V.label b with
        | BB _ | BB_Error -> List.rev (C.get_stmts c b)
        (* Don't include special node contents *)
        | _ -> []
      in
      BH.add hrevstmts b s;
      s
  in
  C.G.iter_vertex (fun v -> BH.add tails v v) c;
  let bh_find_option h b = try Some(BH.find h b) with Not_found->None in
  let rec grow_trace cond head =
      match bh_find_option tails head with
      | None ->
	  () (* must have already been joined previously *)
      | Some tail ->
	  assert(not(BH.mem joined tail));
	  let rec find_succ = function
	    | [] -> ()
	    | suc::rest ->
		match bh_find_option tails suc with
		| Some succtail when cond head tail suc &&
                                     suc <> head ->
                  assert (succtail <> head);
                  assert (suc <> head);
		    dprintf "to_prog: joining %s .. %s with %s .. %s" (v2s head) (v2s tail) (v2s suc) (v2s succtail);
		    BH.add joined tail suc;
		    BH.replace tails head succtail;
		    BH.remove tails suc;
		    grow_trace cond head
		| _ -> (* suc is part of another trace, or cond failed *)
		    find_succ rest
	  in
	  find_succ (C.G.succ c tail)
  in
  let grow_traces cond =
    let worklist = BH.fold (fun k _ w -> k::w) tails [] in
    List.iter (grow_trace cond) worklist
  in
  let normal v =
    match C.G.V.label v with | BB _ -> true | _ -> false
  in
  let joinable v =
    match C.G.V.label v with | BB _ -> true | BB_Exit -> true | _ -> false
  in
  let has_jump src =
    match get_revstmts src with
      | (Jmp _ | CJmp _)::_ -> true
      | _ -> false
  in
  let labs = BH.create size
  and newlabs = BH.create size in
  let get_label b =
    try BH.find labs b
    with Not_found ->
      let rec find_label = function
	| Label(l,_)::_ -> Some l
	| Comment _ :: xs -> find_label xs
	| _ -> None
      in
      match find_label (C.get_stmts c b) with
      | Some l ->
	  BH.add labs b l;
	  l
      | None ->
	  let l = newlab () in
	  BH.add newlabs b l;
	  BH.add labs b l;
	  l
  in
  let ensure_jump src dst =
    if not(has_jump src)
    then match C.G.succ c src with
	| [d] ->
	    assert (C.G.V.equal dst d);
	    let j = Jmp(exp_of_lab (get_label dst), []) in
	    BH.replace hrevstmts src (j::get_revstmts src)
	| l ->
          let dests = List.fold_left (fun s n -> s^" "^v2s n) "" l in
	    failwith("Cfg_ast.to_prog: no jump at end of block with > 1 succ: "
		     ^ v2s src ^ " points to"^dests)
  in
  (* join traces without jumps *)
  grow_traces (fun _ b suc -> normal b && normal suc && not(has_jump b));
  (* join other traces (if we cared, we could remove some jumps later) *)
  grow_traces (fun _ b suc -> normal b && normal suc);
  (* join the entry node *)
  grow_trace
    (fun h t suc -> (normal t || C.G.V.label t = BB_Entry) && normal suc)
    (C.G.V.create BB_Entry);
  (* now join traces with exit, but do NOT join with the entry trace.
     the entry trace must be printed first, but the exit trace must be
     printed last. *)
  grow_traces (fun h t suc -> normal h && normal t && joinable suc);
  (* Make sure the exit trace is last *)
  let revordered_heads, exittrace =
    BH.fold
      (fun h t (rh,et) ->
	 if C.G.V.label h = BB_Entry then (rh,et)
	 else if C.G.V.label t = BB_Exit then (rh, Some h)
	 else (h::rh, et) )
      tails
      ([C.G.V.create BB_Entry], None)
  in
  let revordered_heads = match exittrace with
    | Some x -> x::revordered_heads
    | None ->
	if C.G.mem_vertex c (C.G.V.create BB_Exit)
	then failwith "brokenness: BB_Exit was missing"
	else revordered_heads
  in
  let revnodes =
    let rec head_to_revnodes h acc =
      match bh_find_option joined h with
      | Some s -> head_to_revnodes s (h::acc)
      | None -> (h::acc)
    in
    List.fold_right head_to_revnodes revordered_heads []
  in
  (* Because the entry trace must go first, and the exit trace must go
     last, they are not joined, since it's not always possible for
     these to happen at the same time.  Sometimes it is possible,
     though, and here we identify the predecessor trace of the exit,
     to avoid a jump to the exit if one is not needed. *)
  let exit_edge = 
    let special v =
      match C.G.V.label v with | BB_Indirect -> false | _ -> true
    in
    match List.filter special revnodes with
    | x::y::_ when C.G.V.label x = BB_Exit -> Some (y, x)
    | _ -> None
  in
  (* add jumps for edges that need them *)
  C.G.iter_vertex 
    (fun b -> 
       C.G.iter_succ (fun s -> if not(BH.mem joined b) && Some(b, s) <> exit_edge then ensure_jump b s) c b
    )
    c;
  let add_stmts stmts b =
    dprintf "to_prog: Adding statements for %s" (v2s b);
    let stmts = List.rev_append (get_revstmts b) stmts in
    try Label(BH.find newlabs b, []) :: stmts with Not_found -> stmts
  in
  List.fold_left add_stmts [] revnodes

