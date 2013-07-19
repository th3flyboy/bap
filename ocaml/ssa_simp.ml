(** SSA simplifications

    This uses all supported simplifications to try to optimize as much as possible.
*)

module D=Debug.Make(struct let name="Ssa_simp" and default=`NoDebug end)
open Cfg_ssa
open D

let simp_cfg ?(liveout=[]) ?(usedc=true) ?(usesccvn=true) ?(usemisc=true) cfg =
  let cfgref = ref cfg in
  let changed = ref true in
  let iter = ref 0 in
  while !changed do
    dprintf "Starting iteration %d" !iter;
    incr iter;
    let (cfg,c1) = if usesccvn then Sccvn.replacer ~opt:true !cfgref else (!cfgref,false) in
    let (cfg,c2) = if usedc then Deadcode.do_dce ~globals:liveout cfg else (cfg,false) in
    let (cfg,c3) = if usemisc then Ssa_simp_misc.cfg_jumpelim cfg else (cfg,false) in
    cfgref := cfg;
    changed := c1 || c2 || c3;
    (* If we changed things, we might have unreachable nodes *)
    cfgref := if !changed then Prune_unreachable.prune_unreachable_ssa !cfgref else !cfgref;
  done;
  !cfgref

let simp_astcfg ?(liveout=[]) ?usedc ?usesccvn ?usemisc g =
  let {cfg; to_ssavar} = Cfg_ssa.trans_cfg g in
  let cfg = simp_cfg ?usedc ?usesccvn ?usemisc ~liveout:(List.map to_ssavar liveout) cfg in
  Cfg_ssa.to_astcfg cfg
