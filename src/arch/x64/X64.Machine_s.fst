module X64.Machine_s

open FStar.BaseTypes
open FStar.Map

module M = TransparentMap

(* Define some transparently refined int types,
   since we only use them in specs, not in emitted code *)
unfold let nat32_max = 0x100000000
unfold let nat64_max = 0x10000000000000000
let _ = assert_norm (pow2 32 = nat32_max)    (* Sanity check our constant *)
let _ = assert_norm (pow2 64 = nat64_max)    (* Sanity check our constant *)
type nat64 = x:nat{x < nat64_max}
type uint64 = FStar.UInt64.t

(* map type from the F* library, it needs the key type to have decidable equality, not an issue here *)
let map (key:eqtype) (value:Type) = FStar.Map.t key value

// [@"opaque_to_smt"]
let tmap (key:eqtype) (value:Type) = M.map key value
// [@"opaque_to_smt"]
let tsel = M.sel
// [@"opaque_to_smt"]
let tupd = M.upd 

(* syntax for map accesses, m.[key] and m.[key] <- value *)
(* as we are mostly interested in register maps in this branch, 
   they get the fancy notation treatment*)
unfold
let op_String_Access     = tsel
unfold
let op_String_Assignment = tupd

(* Define the operators we support *)
type reg =
  | Rax
  | Rbx
  | Rcx
  | Rdx
  | Rsi
  | Rdi
  | Rbp
  | Rsp
  | R8
  | R9
  | R10
  | R11
  | R12
  | R13
  | R14
  | R15

unfold
let reg_to_int (r : reg) : int =
  match r with
  | Rax -> 0
  | Rbx -> 1
  | Rcx -> 2
  | Rdx -> 3
  | Rsi -> 4
  | Rdi -> 5
  | Rbp -> 6
  | Rsp -> 7
  | R8 -> 8
  | R9 -> 9
  | R10 -> 10
  | R11 -> 11
  | R12 -> 12
  | R13 -> 13
  | R14 -> 14
  | R15 -> 15

type maddr =
  | MConst : n:nat -> maddr
  | MReg   : r:reg -> offset:int -> maddr
  | MIndex : base:reg -> scale:int -> index:reg -> offset:int -> maddr

type operand =
  | OConst: n:uint64 -> operand
  | OReg  : r:reg -> operand
  | OMem  : m:maddr -> operand

type precode (t_ins:Type0) (t_ocmp:Type0) =
  | Ins   : ins:t_ins -> precode t_ins t_ocmp
  | Block : block:list (precode t_ins t_ocmp) -> precode t_ins t_ocmp
  | IfElse: ifCond:t_ocmp -> ifTrue:precode t_ins t_ocmp -> ifFalse:precode t_ins t_ocmp -> precode t_ins t_ocmp
  | While : whileCond:t_ocmp -> whileBody:precode t_ins t_ocmp -> inv:operand -> precode t_ins t_ocmp

let valid_dst (o:operand) : bool =
  not(OConst? o || (OReg? o && Rsp? (OReg?.r o)))

type dst_op = o:operand { valid_dst o }

(* TODO: Eventually this should be a map to bytes.  Simplifying for now *)
type mem = map int uint64

(* state type, noeq qualifier means that this type does not have decidable equality (because of the maps) *)
noeq type state = {
  ok  :bool;
  regs: tmap int uint64;
  flags:uint64;
  mem :mem;
}

(*
 * writing all the functions as Tot functions
 *)
unfold let eval_reg (r:reg) (s:state) :uint64 =
  s.regs.[reg_to_int r]

(*
let valid_resolved_addr (ptr:int) (m:mem) :bool =
  m `contains` ptr /\
  m `contains` ptr + 1 /\
  m `contains` ptr + 2 /\
  m `contains` ptr + 3
*)

unfold let eval_mem (ptr:int) (s:state) :uint64 =
  sel s.mem ptr

let eval_maddr (m:maddr) (s:state) :int =
  let open FStar.UInt64 in
  let open FStar.Mul in
    match m with
    | MConst n -> n
    | MReg reg offset -> v (eval_reg reg s) + offset
    | MIndex base scale index offset -> v (eval_reg base s) + scale * v (eval_reg index s) + offset

let eval_operand (o:operand) (s:state) :uint64 =
  match o with
  | OConst n -> n
  | OReg r   -> eval_reg r s
  | OMem m   -> eval_mem (eval_maddr m s) s

let update_reg' (r:reg) (v:uint64) (s:state) :state = { s with regs = s.regs.[reg_to_int r] <- v }

let update_mem (ptr:int) (v:uint64) (s:state) :state = { s with mem = upd s.mem ptr v }

let valid_maddr (m:maddr) (s:state) :bool =
  s.mem `contains` (eval_maddr m s)

let valid_operand (o:operand) (s:state) :bool =
  not (OMem? o) || (OMem? o && valid_maddr (OMem?.m o) s)

(*
 * while construct has a loop invariant
 * currently it is a mem_opr, but we could introduce an expression language to enrich it
 *)
