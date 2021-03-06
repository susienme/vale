include "leakage.s.dfy"
include "../../lib/util/operations.i.dfy"

module x86_leakage_helpers {

import opened x86_def_s
import opened x86_leakage_s
import opened operations_i

function method domain<U, V>(m: map<U,V>): set<U>
    ensures forall i :: i in domain(m) <==> i in m;
{
    set s | s in m
}

predicate taintStateModInvariant(ts:taintState, ts':taintState)
{
       (forall r :: r in ts.regTaint ==> r in ts'.regTaint)
    && (forall s :: s in ts.stackTaint ==> s in ts'.stackTaint)
    && (forall x :: x in ts.xmmTaint ==> x in ts'.xmmTaint)
}

predicate insPostconditions(ins:ins, ts:taintState, ts':taintState,
        fixedTime:bool)
{
    fixedTime ==>
           (taintStateModInvariant(ts, ts')
        && forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2'))
}

predicate blockPostconditions(block:codes, ts:taintState, ts':taintState,
        fixedTime:bool)
{
    fixedTime ==>
           (taintStateModInvariant(ts, ts')
        && forall state1, state2, state1', state2' ::
            (evalBlock(block, state1, state1')
            && evalBlock(block, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2'))
}

predicate codePostconditions(code:code, ts:taintState, ts':taintState,
        fixedTime:bool)
{
    fixedTime ==>
           (taintStateModInvariant(ts, ts')
        && forall state1, state2, state1', state2' ::
            (evalCode(code, state1, state1')
            && evalCode(code, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2'))
}

predicate specTaintCheckIns(ins:ins, ts:taintState, ts':taintState,
        fixedTime:bool)
{
    insPostconditions(ins, ts, ts', fixedTime)
}

predicate specTaintCheckBlock(block:codes, ts:taintState, ts':taintState,
        fixedTime:bool)
{
    blockPostconditions(block, ts, ts', fixedTime)
    && if block.CNil? then
        fixedTime == true && ts' == ts
    else
        exists ts_int ::
            specTaintCheckCode(block.hd, ts, ts_int, fixedTime)
            && specTaintCheckBlock(block.tl, ts_int, ts', fixedTime)
}

predicate specTaintCheckCode(code:code, ts:taintState, ts':taintState,
        fixedTime:bool)
    decreases code, 0
{
       codePostconditions(code, ts, ts', fixedTime)
    && (code.Block? ==> specTaintCheckBlock(code.block, ts, ts', fixedTime))
}

function specMergeTaint(t1:taint, t2:taint) : taint
    ensures specMergeTaint(t1, t2).Public? ==> t1.Public? && t2.Public?;
{
    if t1.Secret? || t2.Secret? then
        Secret
    else
        Public
}

predicate specCombineTaints<T>(t1:map<T,taint>, t2:map<T,taint>,
        t:map<T,taint>)
{
    forall elem :: elem in t
        ==> (((elem in t1 || elem in t2)
                && (elem in t1 && elem in t2 ==>
                        t[elem] == specMergeTaint(t1[elem], t2[elem]))
                && (elem in t1 && elem !in t2 ==> t[elem].Secret?)
                && (elem in t2 && elem !in t1 ==> t[elem].Secret?))
            && (t[elem].Public? ==> ((elem in t1 ==> t1[elem].Public?)
                && (elem in t2 ==> t2[elem].Public?))))
}

predicate specCombineTaintStates(ts1:taintState, ts2:taintState,
        ts:taintState)
{
       specCombineTaints(ts1.regTaint, ts2.regTaint, ts.regTaint)
    && specCombineTaints(ts1.stackTaint, ts2.stackTaint, ts.stackTaint)
    && specCombineTaints(ts1.xmmTaint, ts2.xmmTaint, ts.xmmTaint)
    && ts.flagsTaint == specMergeTaint(ts1.flagsTaint, ts2.flagsTaint)
    && taintStateModInvariant(ts1, ts)
    && taintStateModInvariant(ts2, ts)
}

predicate taintSubset<T>(t1:map<T, taint>, t2:map<T, taint>)
{
    forall elem :: elem in t2 && t2[elem].Public? ==> elem in t1 && t1[elem].Public?
}

predicate taintStateSubset(ts1:taintState, ts2:taintState)
{
       taintSubset(ts1.regTaint, ts2.regTaint)
    && taintSubset(ts1.stackTaint, ts2.stackTaint)
    && taintSubset(ts1.xmmTaint, ts2.xmmTaint)
    && (ts2.flagsTaint.Public? ==> ts1.flagsTaint.Public?)
}

lemma lemma_CombiningTaintsProducesSuperset<T>(t1:map<T, taint>, t2:map<T, taint>, t':map<T, taint>)
    requires specCombineTaints(t1, t2, t');
    ensures  taintSubset(t1, t');
    ensures  taintSubset(t2, t');
{
}

lemma lemma_CombiningTaintStatesProducesSuperset(ts1:taintState, ts2:taintState, ts':taintState)
    requires specCombineTaintStates(ts1, ts2, ts');
    ensures  taintStateSubset(ts1, ts');
    ensures  taintStateSubset(ts2, ts');
{
    lemma_CombiningTaintsProducesSuperset(ts1.regTaint, ts2.regTaint, ts'.regTaint);
    lemma_CombiningTaintsProducesSuperset(ts1.stackTaint, ts2.stackTaint, ts'.stackTaint);
    lemma_CombiningTaintsProducesSuperset(ts1.xmmTaint, ts2.xmmTaint, ts'.xmmTaint);
}

lemma lemma_TaintSupersetImpliesPublicValuesAreSameIsPreserved(ts:taintState, ts':taintState, s1:state, s2:state)
    requires publicValuesAreSame(ts, s1, s2);
    requires taintStateSubset(ts, ts');
    ensures  publicValuesAreSame(ts', s1, s2);
{
}

function specOperandTaint(op:operand, ts:taintState) : taint
{
    match op {
        case OConst(_)            => Public
        case OReg(reg)            =>
            if reg.X86Xmm? && reg.xmm in ts.xmmTaint then
                ts.xmmTaint[reg.xmm]
            else if reg.X86Xmm? then
                Secret
            else if reg in ts.regTaint then
                ts.regTaint[reg]
            else
                Secret
        case OStack(slot)          =>
            if slot in ts.stackTaint then
                ts.stackTaint[slot]
            else
                Secret
        case OHeap(addr, taint)    =>
            taint
    }
}

function specTaint(value:Value, ts:taintState) : taint
{
    if value.Operand? then
        specOperandTaint(value.o, ts)
    else
        specMergeTaint(specOperandTaint(value.p.o1, ts), specOperandTaint(value.p.o2, ts))

}

predicate specOperandDoesNotUseSecrets(o:operand, ts:taintState)
{
    if o.OConst? || o.OReg? || o.OStack? then
        true
    else
        assert o.OHeap?;

        var addr := o.addr;
        if addr.MConst? then
            true
        else if addr.MReg? then
            var reg_operand := OReg(addr.reg);
            var regTaint := specOperandTaint(reg_operand, ts);
            regTaint.Public?
        else
            assert addr.MIndex?;

            var base_operand := OReg(addr.base);
            var base_taint := specOperandTaint(base_operand, ts);

            var index_operand := OReg(addr.index);
            var index_taint := specOperandTaint(index_operand, ts);

            base_taint.Public? && index_taint.Public?
}

// Used by AddCarry.
predicate assertionsWithFlags(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
{
     var ftSrc := specOperandDoesNotUseSecrets(src, ts);
     var ftDst := specOperandDoesNotUseSecrets(dst, ts);

     var srcTaint := specOperandTaint(src, ts);
     var dstTaint := specOperandTaint(dst, ts);
     var flagTaint := ts.flagsTaint;

     var srcDstTaint := specMergeTaint(srcTaint, dstTaint);
     var mergedTaint := specMergeTaint(srcDstTaint, flagTaint);

    match dst
        case OStack(st) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(flagsTaint := Secret,
                    stackTaint := ts.stackTaint[dst.s := mergedTaint])
        case OHeap(h, t) =>
            (fixedTime == (ftSrc && ftDst && !(mergedTaint.Secret? && dst.taint.Public?)))
            && ts' == ts.(flagsTaint := Secret)
        case OReg(r) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(regTaint := ts.regTaint[dst.r := mergedTaint],
                    flagsTaint := Secret)
        case OConst(_) =>
            fixedTime == false && ts' == ts
}

predicate assertionsGetCf(dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
{
     var ftDst := specOperandDoesNotUseSecrets(dst, ts);
     var dstTaint := specOperandTaint(dst, ts);
     var flagTaint := ts.flagsTaint;
     var mergedTaint := specMergeTaint(dstTaint, flagTaint);

    match dst
        case OStack(st) =>
            ((fixedTime == ftDst)
            && ts' == ts.(stackTaint := ts.stackTaint[dst.s := mergedTaint]))
        case OHeap(h, t) =>
            ((fixedTime == (ftDst && !(mergedTaint.Secret? && dst.taint.Public?)))
            && ts' == ts)
        case OReg(r) =>
            ((fixedTime == ftDst)
            && ts' == ts.(regTaint := ts.regTaint[dst.r := mergedTaint]))
        case OConst(_) =>
            fixedTime == false && ts' == ts
}

predicate assertionsNot(dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
{
     var ftDst := specOperandDoesNotUseSecrets(dst, ts);
     var dstTaint := specOperandTaint(dst, ts);

    match dst
        case OStack(st) =>
            ((fixedTime == ftDst)
            && ts' == ts.(flagsTaint := Secret))
        case OHeap(h, t) =>
            ((fixedTime == ftDst)
            && ts' == ts.(flagsTaint := Secret))
        case OReg(r) =>
            ((fixedTime == ftDst)
            && ts' == ts.(flagsTaint := Secret))
        case OConst(_) =>
            fixedTime == false && ts' == ts
}

// Used by Mov.
predicate assertionsCopy(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
{
     var ftSrc := specOperandDoesNotUseSecrets(src, ts);
     var ftDst := specOperandDoesNotUseSecrets(dst, ts);

     var srcTaint := specOperandTaint(src, ts);

    match dst
        case OHeap(h, t) =>
            (fixedTime == ((ftSrc && ftDst)
                    && !(srcTaint.Secret? && dst.taint.Public?))
            && ts' == ts)
        case OReg(r) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(regTaint := ts.regTaint[dst.r := srcTaint])
        case OStack(st) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(stackTaint := ts.stackTaint[dst.s := srcTaint])
        case OConst(_) =>
            fixedTime == false && ts' == ts
}

// Used by Add, Sub, Xor, And, Rol, Ror, Shl, and Shr.
predicate assertionsWithoutFlags(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
{
     var ftSrc := specOperandDoesNotUseSecrets(src, ts);
     var ftDst := specOperandDoesNotUseSecrets(dst, ts);

     var srcTaint := specOperandTaint(src, ts);
     var dstTaint := specOperandTaint(dst, ts);

     var mergedTaint := specMergeTaint(srcTaint, dstTaint);

    match dst
        case OStack(st) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(flagsTaint := Secret,
                    stackTaint := ts.stackTaint[dst.s := mergedTaint])
        case OHeap(h, t) =>
            (fixedTime == (ftSrc && ftDst && !(mergedTaint.Secret? && dst.taint.Public?)))
            && ts' == ts.(flagsTaint := Secret)
        case OReg(r) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(regTaint := ts.regTaint[dst.r := mergedTaint],
                    flagsTaint := Secret)
        case OConst(_) =>
            fixedTime == false && ts' == ts
}


predicate assertionsXor32(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
{
     var ftSrc := specOperandDoesNotUseSecrets(src, ts);
     var ftDst := specOperandDoesNotUseSecrets(dst, ts);

     var srcTaint := specOperandTaint(src, ts);
     var dstTaint := specOperandTaint(dst, ts);

     var mergedTaint := specMergeTaint(srcTaint, dstTaint);

    match dst
        case OStack(st) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(flagsTaint := Secret,
                    stackTaint := ts.stackTaint[dst.s := mergedTaint])
        case OHeap(h, t) =>
            (fixedTime == (ftSrc && ftDst && !(mergedTaint.Secret? && dst.taint.Public?)))
            && ts' == ts.(flagsTaint := Secret)
        case OReg(r) =>
            (src.OReg? && src == dst && fixedTime == true && ts' == ts.(regTaint := ts.regTaint[dst.r := Public], 
                    flagsTaint := Secret))
            || ((fixedTime == (ftSrc && ftDst))
            && ts' == ts.(regTaint := ts.regTaint[dst.r := mergedTaint],
                    flagsTaint := Secret))
        case OConst(_) =>
            fixedTime == false && ts' == ts
}

predicate assertionsMul(src:operand, ts:taintState, fixedTime:bool, ts':taintState)
{
    var srcTaint := specOperandTaint(src, ts);
    var eaxTaint := specOperandTaint(OReg(X86Eax), ts);
    var taint := specMergeTaint(srcTaint, eaxTaint);

    var ts_int := ts.(regTaint := ts.regTaint[X86Eax := taint]);
    var ts_int_int := ts_int.(regTaint := ts_int.regTaint[X86Edx := taint]);

    fixedTime == specOperandDoesNotUseSecrets(src, ts)
    && ts' == ts_int_int.(flagsTaint := Secret)
}

// Used by MOVDQU
predicate assertionsMoveXmm(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
    requires !src.OStack? && !dst.OStack?;
    requires src.OReg? ==> src.r.X86Xmm?;
    requires dst.OReg? ==> dst.r.X86Xmm?;
    requires src.OReg? || dst.OReg?;
{
     var ftSrc := specOperandDoesNotUseSecrets(src, ts);
     var ftDst := specOperandDoesNotUseSecrets(dst, ts);

     var srcTaint := specOperandTaint(src, ts);

    match dst
        case OHeap(h, t) =>
            (fixedTime == ((ftSrc && ftDst)
                    && !(srcTaint.Secret? && dst.taint.Public?))
            && ts' == ts.(flagsTaint := Secret))
        case OReg(r) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(xmmTaint := ts.xmmTaint[dst.r.xmm := srcTaint], flagsTaint := Secret)
        case OStack(st) =>
            (fixedTime == (ftSrc && ftDst))
            && ts' == ts.(stackTaint := ts.stackTaint[dst.s := srcTaint], flagsTaint := Secret)
        case OConst(_) =>
            fixedTime == false && ts' == ts
}

// Used by AESNI_imc, VPSLLDQ, Pshufd, and AESNI_keygen_assist.
predicate assertionsCopyXmmWithFlags(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
    requires src.OReg? && src.r.X86Xmm?;
    requires dst.OReg? && dst.r.X86Xmm?;
{
    var srcTaint := specOperandTaint(src, ts);

    fixedTime == true
    && ts' == ts.(xmmTaint := ts.xmmTaint[dst.r.xmm := srcTaint],
                  flagsTaint := Secret)
}

// Used by AESNI_enc, AESNI_enc_last, AESNI_dec, AESNI_dec_last.
predicate assertionsXmmWithFlags(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
    requires src.OReg? && src.r.X86Xmm?;
    requires dst.OReg? && dst.r.X86Xmm?;
{
    var srcTaint := specOperandTaint(src, ts);
    var dstTaint := specOperandTaint(dst, ts);
    var mergedTaint := specMergeTaint(srcTaint, dstTaint);

    fixedTime == true
    && ts' == ts.(xmmTaint := ts.xmmTaint[dst.r.xmm := mergedTaint],
                  flagsTaint := Secret)
}

predicate assertionsPxorXmmWithFlags(src:operand, dst:operand, ts:taintState, fixedTime:bool, ts':taintState)
    requires src.OReg? && src.r.X86Xmm?;
    requires dst.OReg? && dst.r.X86Xmm?;
{
    var srcTaint := specOperandTaint(src, ts);
    var dstTaint := specOperandTaint(dst, ts);
    var mergedTaint := specMergeTaint(srcTaint, dstTaint);

    fixedTime == true
    && ((dst == src && ts' == ts.(xmmTaint := ts.xmmTaint[dst.r.xmm := Public],
                  flagsTaint := Secret))
        || (ts' == ts.(xmmTaint := ts.xmmTaint[dst.r.xmm := mergedTaint],
                  flagsTaint := Secret)))
}


lemma lemma_ValiditiesOfPublic32BitOperandAreSame(ts:taintState, s1:state, s2:state, op:operand)
    ensures    specOperandDoesNotUseSecrets(op, ts)
            && specOperandTaint(op, ts).Public?
            && publicValuesAreSame(ts, s1, s2)
            && ValidSourceOperand(s1, 32, op)
            ==> ValidSourceOperand(s2, 32, op);
{
    if    specOperandDoesNotUseSecrets(op, ts)
       && specOperandTaint(op, ts).Public?
       && publicValuesAreSame(ts, s1, s2)
       && ValidSourceOperand(s1, 32, op)
       && op.OHeap?
    {
        var resolved_addr1 := EvalMemAddr(s1.regs, op.addr);
        var resolved_addr2 := EvalMemAddr(s2.regs, op.addr);
        assert resolved_addr1 == resolved_addr2;
        assert s1.heap[resolved_addr1+0] == s2.heap[resolved_addr1+0];
    }
}

lemma lemma_ValiditiesOfPublic128BitOperandAreSame(ts:taintState, s1:state, s2:state, op:operand)
    requires !op.OStack?;
    ensures    specOperandDoesNotUseSecrets(op, ts)
            && specOperandTaint(op, ts).Public?
            && publicValuesAreSame(ts, s1, s2)
            && ValidSourceOperand(s1, 128, op)
            ==> ValidSourceOperand(s2, 128, op);
{
    if    specOperandDoesNotUseSecrets(op, ts)
       && specOperandTaint(op, ts).Public?
       && publicValuesAreSame(ts, s1, s2)
       && ValidSourceOperand(s1, 128, op)
    {
        if op.OHeap? {
            var resolved_addr1 := EvalMemAddr(s1.regs, op.addr);
            var resolved_addr2 := EvalMemAddr(s2.regs, op.addr);
            assert resolved_addr1 == resolved_addr2;
            assert s1.heap[resolved_addr1+0] == s2.heap[resolved_addr1+0];
            assert s1.heap[resolved_addr1+1] == s2.heap[resolved_addr1+1];
            assert s1.heap[resolved_addr1+2] == s2.heap[resolved_addr1+2];
            assert s1.heap[resolved_addr1+3] == s2.heap[resolved_addr1+3];
            assert s1.heap[resolved_addr1+4] == s2.heap[resolved_addr1+4];
            assert s1.heap[resolved_addr1+5] == s2.heap[resolved_addr1+5];
            assert s1.heap[resolved_addr1+6] == s2.heap[resolved_addr1+6];
            assert s1.heap[resolved_addr1+7] == s2.heap[resolved_addr1+7];
            assert s1.heap[resolved_addr1+8] == s2.heap[resolved_addr1+8];
            assert s1.heap[resolved_addr1+9] == s2.heap[resolved_addr1+9];
            assert s1.heap[resolved_addr1+10] == s2.heap[resolved_addr1+10];
            assert s1.heap[resolved_addr1+11] == s2.heap[resolved_addr1+11];
            assert s1.heap[resolved_addr1+12] == s2.heap[resolved_addr1+12];
            assert s1.heap[resolved_addr1+13] == s2.heap[resolved_addr1+13];
            assert s1.heap[resolved_addr1+14] == s2.heap[resolved_addr1+14];
            assert s1.heap[resolved_addr1+15] == s2.heap[resolved_addr1+15];
        }
    }
}

lemma lemma_ValuesOfPublic32BitOperandAreSame(ts:taintState, s1:state, s2:state, op:operand)
    ensures    specOperandDoesNotUseSecrets(op, ts)
            && specOperandTaint(op, ts).Public?
            && publicValuesAreSame(ts, s1, s2)
            && ValidSourceOperand(s1, 32, op)
            ==>    ValidSourceOperand(s2, 32, op)
                && eval_op(s1, op) == eval_op(s2, op);
{
    lemma_ValiditiesOfPublic32BitOperandAreSame(ts, s1, s2, op);

    if    specOperandDoesNotUseSecrets(op, ts)
       && specOperandTaint(op, ts).Public?
       && publicValuesAreSame(ts, s1, s2)
       && ValidSourceOperand(s1, 32, op)
       && op.OHeap? {
        assert ValidSourceOperand(s2, 32, op);
        var resolved_addr1 := EvalMemAddr(s1.regs, op.addr);
        var resolved_addr2 := EvalMemAddr(s2.regs, op.addr);
        assert resolved_addr1 == resolved_addr2;
        assert s1.heap[resolved_addr1+0] == s2.heap[resolved_addr1+0];
    }
}

lemma lemma_ValuesOfPublic128BitOperandAreSame(ts:taintState, s1:state, s2:state, op:operand)
    requires !op.OStack?;
    ensures    specOperandDoesNotUseSecrets(op, ts)
            && specOperandTaint(op, ts).Public?
            && publicValuesAreSame(ts, s1, s2)
            && ValidSourceOperand(s1, 128, op)
            ==>    ValidSourceOperand(s2, 128, op)
                && Eval128BitOperand(s1, op) == Eval128BitOperand(s2, op);
{
    lemma_ValiditiesOfPublic128BitOperandAreSame(ts, s1, s2, op);

    if    specOperandDoesNotUseSecrets(op, ts)
       && specOperandTaint(op, ts).Public?
       && publicValuesAreSame(ts, s1, s2)
       && ValidSourceOperand(s1, 128, op)
       && op.OHeap? {
        assert ValidSourceOperand(s2, 128, op);
        var resolved_addr1 := EvalMemAddr(s1.regs, op.addr);
        var resolved_addr2 := EvalMemAddr(s2.regs, op.addr);
        assert resolved_addr1 == resolved_addr2;
        assert s1.heap[resolved_addr1+0] == s2.heap[resolved_addr1+0];
        assert s1.heap[resolved_addr1+1] == s2.heap[resolved_addr1+1];
        assert s1.heap[resolved_addr1+2] == s2.heap[resolved_addr1+2];
        assert s1.heap[resolved_addr1+3] == s2.heap[resolved_addr1+3];
        assert s1.heap[resolved_addr1+4] == s2.heap[resolved_addr1+4];
        assert s1.heap[resolved_addr1+5] == s2.heap[resolved_addr1+5];
        assert s1.heap[resolved_addr1+6] == s2.heap[resolved_addr1+6];
        assert s1.heap[resolved_addr1+7] == s2.heap[resolved_addr1+7];
        assert s1.heap[resolved_addr1+8] == s2.heap[resolved_addr1+8];
        assert s1.heap[resolved_addr1+9] == s2.heap[resolved_addr1+9];
        assert s1.heap[resolved_addr1+10] == s2.heap[resolved_addr1+10];
        assert s1.heap[resolved_addr1+11] == s2.heap[resolved_addr1+11];
        assert s1.heap[resolved_addr1+12] == s2.heap[resolved_addr1+12];
        assert s1.heap[resolved_addr1+13] == s2.heap[resolved_addr1+13];
        assert s1.heap[resolved_addr1+14] == s2.heap[resolved_addr1+14];
        assert s1.heap[resolved_addr1+15] == s2.heap[resolved_addr1+15];
    }
}

lemma { :timeLimitMultiplier 3 } lemma_Mov32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Mov32?;
    requires assertionsCopy(ins.srcMov, ins.dstMov, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcMov;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
    }
}

lemma {:timeLimitMultiplier 3} lemma_Add32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Add32?;
    requires assertionsWithoutFlags(ins.srcAdd, ins.dstAdd, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcAdd;
        var dst:operand := ins.dstAdd;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma {:timeLimitMultiplier 2} lemma_Sub32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Sub32?;
    requires assertionsWithoutFlags(ins.srcSub, ins.dstSub, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcSub;
        var dst:operand := ins.dstSub;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma {:timeLimitMultiplier 3} lemma_Xor32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Xor32?;
    requires assertionsXor32(ins.srcXor, ins.dstXor, ts, fixedTime, ts');
    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcXor;
        var dst:operand := ins.dstXor;
        if (src.OReg? && dst.OReg? && src == dst) {
            var s1 := state1;
            var s2 := state2;

            var obs := insObs(s1, ins);
            var obs2 := insObs(s2, ins);

            var v := xor32(eval_op(s1, dst), eval_op(s1, src));
            var v2 := xor32(eval_op(s2, dst), eval_op(s2, src));

            assert evalUpdateAndHavocFlags(state1, dst, v, state1', obs);
            assert state1' == state1.(regs := state1.regs[dst.r := v], flags := state1'.flags, trace := state1.trace + obs);
            assert state2' == state2.(regs := state2.regs[dst.r := v2], flags := state2'.flags, trace := state2.trace + obs2);

            assert state1'.regs[dst.r] == BitwiseXor(s1.regs[src.r], s1.regs[src.r]);
            assert state2'.regs[dst.r] == BitwiseXor(s2.regs[src.r], s2.regs[src.r]);

            lemma_BitwiseXorWithItself(s1.regs[src.r]);
            lemma_BitwiseXorWithItself(s2.regs[src.r]);

            assert state1'.regs[dst.r] == 0;
            assert state2'.regs[dst.r] == 0;
            assert state1'.regs[dst.r] == state2'.regs[dst.r];

            lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
            lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);


        } else {
            lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
            lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
        }
    }
}

lemma {:timeLimitMultiplier 3} lemma_And32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.And32?;
    requires assertionsWithoutFlags(ins.srcAnd, ins.dstAnd, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcAnd;
        var dst:operand := ins.dstAnd;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma lemma_Rol32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Rol32?;
    requires assertionsWithoutFlags(ins.amountRolConst, ins.dstRolConst, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.amountRolConst;
        var dst:operand := ins.dstRolConst;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma lemma_Ror32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Ror32?;
    requires assertionsWithoutFlags(ins.amountRorConst, ins.dstRorConst, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.amountRorConst;
        var dst:operand := ins.dstRorConst;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma lemma_Shl32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Shl32?;
    requires assertionsWithoutFlags(ins.amountShlConst, ins.dstShlConst, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.amountShlConst;
        var dst:operand := ins.dstShlConst;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma lemma_Shr32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Shr32?;
    requires assertionsWithoutFlags(ins.amountShrConst, ins.dstShrConst, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.amountShrConst;
        var dst:operand := ins.dstShrConst;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma lemma_Mov32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Mov32?;
    requires assertionsCopy(ins.srcMov, ins.dstMov, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Add32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Add32?;
    requires assertionsWithoutFlags(ins.srcAdd, ins.dstAdd, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Sub32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Sub32?;
    requires assertionsWithoutFlags(ins.srcSub, ins.dstSub, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Xor32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Xor32?;
    requires assertionsXor32(ins.srcXor, ins.dstXor, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_And32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.And32?;
    requires assertionsWithoutFlags(ins.srcAnd, ins.dstAnd, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Rol32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Rol32?;
    requires assertionsWithoutFlags(ins.amountRolConst, ins.dstRolConst, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Ror32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Ror32?;
    requires assertionsWithoutFlags(ins.amountRorConst, ins.dstRorConst, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Shl32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Shl32?;
    requires assertionsWithoutFlags(ins.amountShlConst, ins.dstShlConst, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Shr32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Shr32?;
    requires assertionsWithoutFlags(ins.amountShrConst, ins.dstShrConst, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Mul32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Mul32?;
    requires assertionsMul(ins.srcMul, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    var code := Ins(ins);
    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2')
    ensures state1'.trace == state2'.trace;
    {
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, ins.srcMul);
    }
}

lemma lemma_Mul32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Mul32?;
    requires assertionsMul(ins.srcMul, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma { :timeLimitMultiplier 3 } lemma_AddCarryHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AddCarry?;
    requires assertionsWithFlags(ins.srcAddCarry, ins.dstAddCarry, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcAddCarry;
        var dst:operand := ins.dstAddCarry;

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, src);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, dst);
    }
}

lemma lemma_AddCarryHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AddCarry?;
    requires assertionsWithFlags(ins.srcAddCarry, ins.dstAddCarry, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_Not32Helper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Not32?;
    requires assertionsNot(ins.dstNot, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2')
    ensures state1'.trace == state2'.trace;
    {
        if specOperandTaint(ins.dstNot, ts).Public? {
            lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, ins.dstNot);
        }
    }
}

lemma lemma_Not32Helper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Not32?;
    requires assertionsNot(ins.dstNot, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_GetCfHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.GetCf?;
    requires assertionsGetCf(ins.dstCf, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2')
    ensures state1'.trace == state2'.trace;
    {
        if specOperandTaint(ins.dstCf, ts).Public? {
            lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, ins.dstCf);
        }
    }
}

lemma lemma_GetCfHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.GetCf?;
    requires assertionsGetCf(ins.dstCf, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_AESNI_encHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_enc?;
    requires ins.srcEnc.OReg? && ins.srcEnc.r.X86Xmm?;
    requires ins.dstEnc.OReg? && ins.dstEnc.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcEnc, ins.dstEnc, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_AESNI_encHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_enc?;
    requires ins.srcEnc.OReg? && ins.srcEnc.r.X86Xmm?;
    requires ins.dstEnc.OReg? && ins.dstEnc.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcEnc, ins.dstEnc, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_AESNI_enc_lastHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_enc_last?;
    requires ins.srcEncLast.OReg? && ins.srcEncLast.r.X86Xmm?;
    requires ins.dstEncLast.OReg? && ins.dstEncLast.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcEncLast, ins.dstEncLast, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_AESNI_enc_lastHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_enc_last?;
    requires ins.srcEncLast.OReg? && ins.srcEncLast.r.X86Xmm?;
    requires ins.dstEncLast.OReg? && ins.dstEncLast.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcEncLast, ins.dstEncLast, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_AESNI_decHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_dec?;
    requires ins.srcDec.OReg? && ins.srcDec.r.X86Xmm?;
    requires ins.dstDec.OReg? && ins.dstDec.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcDec, ins.dstDec, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_AESNI_decHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_dec?;
    requires ins.srcDec.OReg? && ins.srcDec.r.X86Xmm?;
    requires ins.dstDec.OReg? && ins.dstDec.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcDec, ins.dstDec, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_AESNI_dec_lastHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_dec_last?;
    requires ins.srcDecLast.OReg? && ins.srcDecLast.r.X86Xmm?;
    requires ins.dstDecLast.OReg? && ins.dstDecLast.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcDecLast, ins.dstDecLast, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_AESNI_dec_lastHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_dec_last?;
    requires ins.srcDecLast.OReg? && ins.srcDecLast.r.X86Xmm?;
    requires ins.dstDecLast.OReg? && ins.dstDecLast.r.X86Xmm?;
    requires assertionsXmmWithFlags(ins.srcDecLast, ins.dstDecLast, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_AESNI_imcHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_imc?;
    requires ins.srcImc.OReg? && ins.srcImc.r.X86Xmm?;
    requires ins.dstImc.OReg? && ins.dstImc.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcImc, ins.dstImc, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_AESNI_imcHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_imc?;
    requires ins.srcImc.OReg? && ins.srcImc.r.X86Xmm?;
    requires ins.dstImc.OReg? && ins.dstImc.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcImc, ins.dstImc, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma { :timeLimitMultiplier 3 } lemma_MOVDQUHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.MOVDQU?;
    requires !ins.srcMovdqu.OStack?;
    requires !ins.dstMovdqu.OStack?;
    requires ins.srcMovdqu.OReg? || ins.dstMovdqu.OReg?;
    requires ins.srcMovdqu.OReg? ==> ins.srcMovdqu.r.X86Xmm?;
    requires ins.dstMovdqu.OReg? ==> ins.dstMovdqu.r.X86Xmm?;
    requires assertionsMoveXmm(ins.srcMovdqu, ins.dstMovdqu, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcMovdqu;
        lemma_ValuesOfPublic128BitOperandAreSame(ts, state1, state2, src);
    }
}

lemma lemma_MOVDQUHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.MOVDQU?;
    requires !ins.srcMovdqu.OStack?;
    requires !ins.dstMovdqu.OStack?;
    requires ins.srcMovdqu.OReg? || ins.dstMovdqu.OReg?;
    requires ins.srcMovdqu.OReg? ==> ins.srcMovdqu.r.X86Xmm?;
    requires ins.dstMovdqu.OReg? ==> ins.dstMovdqu.r.X86Xmm?;
    requires assertionsMoveXmm(ins.srcMovdqu, ins.dstMovdqu, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_VPSLLDQHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.VPSLLDQ?;
    requires ins.srcVPSLLDQ.OReg? && ins.srcVPSLLDQ.r.X86Xmm?;
    requires ins.dstVPSLLDQ.OReg? && ins.dstVPSLLDQ.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcVPSLLDQ, ins.dstVPSLLDQ, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_VPSLLDQHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.VPSLLDQ?;
    requires ins.srcVPSLLDQ.OReg? && ins.srcVPSLLDQ.r.X86Xmm?;
    requires ins.dstVPSLLDQ.OReg? && ins.dstVPSLLDQ.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcVPSLLDQ, ins.dstVPSLLDQ, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_PshufdHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Pshufd?;
    requires ins.srcPshufd.OReg? && ins.srcPshufd.r.X86Xmm?;
    requires ins.dstPshufd.OReg? && ins.dstPshufd.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcPshufd, ins.dstPshufd, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_PshufdHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Pshufd?;
    requires ins.srcPshufd.OReg? && ins.srcPshufd.r.X86Xmm?;
    requires ins.dstPshufd.OReg? && ins.dstPshufd.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcPshufd, ins.dstPshufd, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_PxorHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Pxor?;
    requires ins.srcPXor.OReg? && ins.srcPXor.r.X86Xmm?;
    requires ins.dstPXor.OReg? && ins.dstPXor.r.X86Xmm?;
    requires assertionsPxorXmmWithFlags(ins.srcPXor, ins.dstPXor, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var src:operand := ins.srcPXor;
        var dst:operand := ins.dstPXor;
        if (src == dst) {
            var s1 := state1;
            var s2 := state2;
            var s1' := state1';
            var s2' := state2';

            var obs := insObs(s1, ins);
            var obs2 := insObs(s2, ins);

            var v := QuadwordXor(s1.xmms[dst.r.xmm], s1.xmms[src.r.xmm]);
            var v2 := QuadwordXor(s2.xmms[dst.r.xmm], s2.xmms[src.r.xmm]);

            assert evalUpdateXmmsAndHavocFlags(state1, dst, v, state1', obs);
            assert state1' == state1.(xmms := s1.xmms[dst.r.xmm := v], flags := state1'.flags, trace := state1.trace + obs);
            assert state2' == state2.(xmms := s2.xmms[dst.r.xmm := v2], flags := state2'.flags, trace := state2.trace + obs2);

            assert state1'.xmms[dst.r.xmm] == QuadwordXor(s1.xmms[src.r.xmm], s1.xmms[src.r.xmm]);
            assert state2'.xmms[dst.r.xmm] == QuadwordXor(s2.xmms[src.r.xmm], s2.xmms[src.r.xmm]);

            lemma_QuadwordXorWithItself(s1.xmms[src.r.xmm]);
            lemma_QuadwordXorWithItself(s2.xmms[src.r.xmm]);

            assert state1'.xmms[dst.r.xmm] == Quadword(0, 0, 0, 0);
            assert state2'.xmms[dst.r.xmm] == Quadword(0, 0, 0, 0);
            assert state1'.xmms[dst.r.xmm] == state2'.xmms[dst.r.xmm];
        }
    }
}

lemma lemma_PxorHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.Pxor?;
    requires ins.srcPXor.OReg? && ins.srcPXor.r.X86Xmm?;
    requires ins.dstPXor.OReg? && ins.dstPXor.r.X86Xmm?;
    requires assertionsPxorXmmWithFlags(ins.srcPXor, ins.dstPXor, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

lemma lemma_AESNI_keygen_assistHelper1(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_keygen_assist?;
    requires ins.srcKeygenAssist.OReg? && ins.srcKeygenAssist.r.X86Xmm?;
    requires ins.dstKeygenAssist.OReg? && ins.dstKeygenAssist.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcKeygenAssist, ins.dstKeygenAssist, ts, fixedTime, ts');

    ensures  fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> (constTimeInvariant(ts', state1', state2')
                    && state1'.trace == state2'.trace);
{
    if fixedTime == false {
        return;
    }

    forall state1, state2, state1', state2' |
        (evalIns(ins, state1, state1')
        && evalIns(ins, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2))
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
    }
}

lemma lemma_AESNI_keygen_assistHelper2(ins:ins, fixedTime:bool, ts:taintState, ts':taintState)
    requires ins.AESNI_keygen_assist?;
    requires ins.srcKeygenAssist.OReg? && ins.srcKeygenAssist.r.X86Xmm?;
    requires ins.dstKeygenAssist.OReg? && ins.dstKeygenAssist.r.X86Xmm?;
    requires assertionsCopyXmmWithFlags(ins.srcKeygenAssist, ins.dstKeygenAssist, ts, fixedTime, ts');
    requires fixedTime ==>
        forall state1, state2, state1', state2' ::
            (evalIns(ins, state1, state1')
            && evalIns(ins, state2, state2')
            && state1.ok && state1'.ok
            && state2.ok && state2'.ok
            && constTimeInvariant(ts, state1, state2))
                ==> constTimeInvariant(ts', state1', state2');

    ensures specTaintCheckIns(ins, ts, ts', fixedTime)
{
}

predicate method ValidRegsInXmmIns(ins:ins)
{
    match ins {
        case Mov32(dst,src)     =>  true
        case Rand(x)            =>  true
        case Add32(dst, src)    =>  true
        case Sub32(dst, src)    =>  true
        case Mul32(src)         =>  true
        case AddCarry(dst, src) =>  true
        case Xor32(dst, src)    =>  true
        case And32(dst, src)    =>  true
        case Not32(dst)         =>  true
        case GetCf(dst)         =>  true
        case Rol32(dst, amount) =>  true
        case Ror32(dst, amount) =>  true
        case Shl32(dst, amount) =>  true
        case Shr32(dst, amount) =>  true
        case BSwap32(dst) => true
        case AESNI_enc(dst, src)                => IsXmmOperand(dst) && IsXmmOperand(src)
        case AESNI_enc_last(dst, src)           => IsXmmOperand(dst) && IsXmmOperand(src)
        case AESNI_dec(dst, src)                => IsXmmOperand(dst) && IsXmmOperand(src)
        case AESNI_dec_last(dst, src)           => IsXmmOperand(dst) && IsXmmOperand(src)
        case AESNI_imc(dst, src)                => IsXmmOperand(dst) && IsXmmOperand(src)
        case AESNI_keygen_assist(dst, src, imm) => IsXmmOperand(dst) && IsXmmOperand(src) && imm.OConst?
        case Pxor(dst, src)                     => IsXmmOperand(dst) && IsXmmOperand(src)
        case Pshufd(dst, src, perm)             => IsXmmOperand(dst) && IsXmmOperand(src) && perm.OConst?
        case VPSLLDQ(dst, src, count)           => IsXmmOperand(dst) && IsXmmOperand(src)
        case MOVDQU(dst, src)                   => !src.OStack? && !dst.OStack? && (src.OReg? || dst.OReg?) && (src.OReg? ==> src.r.X86Xmm?) && (dst.OReg? ==> dst.r.X86Xmm?)
    }
}

predicate AddrDoesNotUseXmmRegs(addr:maddr)
{
    if addr.MReg? then
        !addr.reg.X86Xmm?
    else if addr.MIndex? then
        !addr.base.X86Xmm? && !addr.index.X86Xmm?
    else
        true
}

predicate OpAddrDoesNotUseXmmRegs(op:operand)
{
    op.OHeap? ==> AddrDoesNotUseXmmRegs(op.addr)
}

predicate AddrDoesNotUseXmmRegsInIns(ins:ins)
{
    match ins {
        case Mov32(dst,src)     => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case Rand(x)            => OpAddrDoesNotUseXmmRegs(x)
        case Add32(dst, src)    => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case Sub32(dst, src)    => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case Mul32(src)         => OpAddrDoesNotUseXmmRegs(src)
        case AddCarry(dst, src) => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case Xor32(dst, src)    => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case And32(dst, src)    => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case Not32(dst)         => OpAddrDoesNotUseXmmRegs(dst)
        case GetCf(dst)         => OpAddrDoesNotUseXmmRegs(dst)
        case Rol32(dst, amount) => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(amount)
        case Ror32(dst, amount) => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(amount)
        case Shl32(dst, amount) => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(amount)
        case Shr32(dst, amount) => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(amount)
        case BSwap32(dst)            => OpAddrDoesNotUseXmmRegs(dst)
        case AESNI_enc(dst, src)                => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case AESNI_enc_last(dst, src)           => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case AESNI_dec(dst, src)                => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case AESNI_dec_last(dst, src)           => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case AESNI_imc(dst, src)                => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case AESNI_keygen_assist(dst, src, imm) => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src) && OpAddrDoesNotUseXmmRegs(imm)
        case Pxor(dst, src)                     => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
        case Pshufd(dst, src, perm)             => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src) && OpAddrDoesNotUseXmmRegs(perm)
        case VPSLLDQ(dst, src, count)           => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src) && OpAddrDoesNotUseXmmRegs(count)
        case MOVDQU(dst, src)                   => OpAddrDoesNotUseXmmRegs(dst) && OpAddrDoesNotUseXmmRegs(src)
    }
}

predicate ValidOperandsInBlock(block:codes)
{
    if block.CNil? then
        true
    else
        ValidOperandsInCode(block.hd)
        && ValidOperandsInBlock(block.tl)
}

predicate ValidOperandsInCode(code:code)
{
    match code {
        case Ins(ins)               =>
            ValidRegsInXmmIns(ins)
            && AddrDoesNotUseXmmRegsInIns(ins)
        case Block(block)           =>
            ValidOperandsInBlock(block)
        case IfElse(pred, ift, iff) =>
            OpAddrDoesNotUseXmmRegs(pred.o1)
            && OpAddrDoesNotUseXmmRegs(pred.o2)
            && ValidOperandsInCode(ift)
            && ValidOperandsInCode(iff)
        case While(pred, block)     =>
            OpAddrDoesNotUseXmmRegs(pred.o1)
            && OpAddrDoesNotUseXmmRegs(pred.o2)
            && ValidOperandsInCode(block)
    }
}

lemma lemma_oBoolEvaluation(pred:obool, ift:code, iff:code, fixedTime:bool, ts:taintState)
    requires specOperandTaint(pred.o1, ts).Public?
        && specOperandTaint(pred.o2, ts).Public?
        && specOperandDoesNotUseSecrets(pred.o1, ts)
        && specOperandDoesNotUseSecrets(pred.o2, ts);

    ensures fixedTime ==> (forall state1, state2, state1', state2' ::
           evalIfElse(pred, ift, iff, state1, state1')
        && evalIfElse(pred, ift, iff, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2)
            ==> evalOBool(state1, pred) == evalOBool(state2, pred));
{
    forall state1, state2, state1', state2' |
           evalIfElse(pred, ift, iff, state1, state1')
        && evalIfElse(pred, ift, iff, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2)
    ensures evalOBool(state1, pred) == evalOBool(state2, pred);
    {
        var state1_int :|
            branchRelation(state1, state1_int, evalOBool(state1, pred))
            && state1_int.ok
            && (if evalOBool(state1, pred) then
                    evalCode(ift, state1_int, state1')
                else
                    evalCode(iff, state1_int, state1'));

        var state2_int :|
            branchRelation(state2, state2_int, evalOBool(state2, pred))
            && state2_int.ok
            && (if evalOBool(state2, pred) then
                    evalCode(ift, state2_int, state2')
                else
                    evalCode(iff, state2_int, state2'));

        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, pred.o1);
        lemma_ValuesOfPublic32BitOperandAreSame(ts, state1, state2, pred.o2);

        assert evalOBool(state1, pred) == evalOBool(state2, pred);
    }
}

lemma lemma_ifElse(pred:obool, ift:code, iff:code, fixedTime:bool,
        ts:taintState, tsIft:taintState, tsIff:taintState, ts':taintState)
    requires specOperandTaint(pred.o1, ts).Public?
        && specOperandTaint(pred.o2, ts).Public?
        && specOperandDoesNotUseSecrets(pred.o1, ts)
        && specOperandDoesNotUseSecrets(pred.o2, ts);

    requires specTaintCheckCode(ift, ts, tsIft, fixedTime);
    requires specTaintCheckCode(iff, ts, tsIff, fixedTime);
    requires specCombineTaintStates(tsIft, tsIff, ts');

    requires forall state1, state2, state1', state2' ::
        evalCode(ift, state1, state1')
        && evalCode(ift, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2)
    ==> constTimeInvariant(tsIft, state1', state2');

    requires forall state1, state2, state1', state2' ::
        evalCode(iff, state1, state1')
        && evalCode(iff, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2)
    ==> constTimeInvariant(tsIff, state1', state2');

    ensures fixedTime ==> taintStateModInvariant(ts, ts');
    ensures codePostconditions(IfElse(pred, ift, iff), ts, ts', fixedTime);
    ensures fixedTime ==> isConstantTime(IfElse(pred, ift, iff), ts);
    ensures specTaintCheckCode(IfElse(pred, ift, iff), ts, ts', fixedTime);
    ensures fixedTime ==> isLeakageFree(IfElse(pred, ift, iff), ts, ts');
{
    if fixedTime == false {
        return;
    }

    lemma_oBoolEvaluation(pred, ift, iff, fixedTime, ts);

    forall state1, state2, state1', state2' |
           evalIfElse(pred, ift, iff, state1, state1')
        && evalIfElse(pred, ift, iff, state2, state2')
        && state1.ok && state1'.ok
        && state2.ok && state2'.ok
        && constTimeInvariant(ts, state1, state2)
    ensures constTimeInvariant(ts', state1', state2');
    ensures state1'.trace == state2'.trace;
    {
        var state1_int :|
            branchRelation(state1, state1_int, evalOBool(state1, pred)) && state1_int.ok
            && (if evalOBool(state1, pred) then evalCode(ift, state1_int, state1') else evalCode(iff, state1_int, state1'));

        var state2_int :|
            branchRelation(state2, state2_int, evalOBool(state2, pred)) && state2_int.ok
            && (if evalOBool(state2, pred) then evalCode(ift, state2_int, state2') else evalCode(iff, state2_int, state2'));

        assert evalOBool(state1, pred) == evalOBool(state2, pred);
        if evalOBool(state1, pred) {
            assert evalCode(ift, state1_int, state1');
            assert evalCode(ift, state2_int, state2');
            assert state1_int.ok && state1'.ok;
            assert state2_int.ok && state2'.ok;
            assert constTimeInvariant(ts, state1_int, state2_int);
            assert constTimeInvariant(tsIft, state1', state2');
        } else {
            assert evalCode(iff, state1_int, state1');
            assert evalCode(iff, state2_int, state2');
            assert state1_int.ok && state1'.ok;
            assert state2_int.ok && state2'.ok;
            assert constTimeInvariant(ts, state1_int, state2_int);
            assert constTimeInvariant(tsIff, state1', state2');
        }

        assert evalOBool(state1, pred) ==> publicValuesAreSame(tsIft, state1', state2');
        assert (evalOBool(state1, pred) == false) ==> publicValuesAreSame(tsIff, state1', state2');

        forall
        ensures publicFlagValuesAreSame(ts', state1', state2')
        {
        }

        forall
        ensures publicRegisterValuesAreSame(ts', state1', state2');
        ensures publicStackValuesAreSame(ts', state1', state2');
        ensures publicHeapValuesAreSame(state1', state2');
        ensures publicXMMValuesAreSame(ts', state1', state2');
        {
        }

        assert evalCode(IfElse(pred, ift, iff), state1, state1');
        assert evalCode(IfElse(pred, ift, iff), state2, state2');

        assert state1'.trace == state2'.trace;
        assert constTimeInvariant(ts', state1', state2');
    }

    forall
    ensures taintStateModInvariant(tsIft, ts');
    ensures taintStateModInvariant(tsIff, ts');
    ensures taintStateModInvariant(ts, ts');
    {
    }
}

predicate method publicXMMTaintsAreAsExpected(tsAnalysis:taintState, tsExpected:taintState)
{
    forall x :: x in tsExpected.xmmTaint && tsExpected.xmmTaint[x].Public?
        ==> (x in tsAnalysis.xmmTaint && tsAnalysis.xmmTaint[x].Public?)
}
 
predicate method publicFlagTaintsAreAsExpected(tsAnalysis:taintState, tsExpected:taintState)

{
    tsExpected.flagsTaint == Public
        ==> tsAnalysis.flagsTaint == Public
}
 
predicate method publicStackTaintsAreAsExpected(tsAnalysis:taintState, tsExpected:taintState)
{
    forall s :: s in tsExpected.stackTaint && tsExpected.stackTaint[s].Public?
        ==> (s in tsAnalysis.stackTaint && tsAnalysis.stackTaint[s].Public?)
}
 
predicate method publicRegisterTaintsAreAsExpected(tsAnalysis:taintState, tsExpected:taintState)
{
    forall r :: r in tsExpected.regTaint && tsExpected.regTaint[r].Public?
        ==> (r in tsAnalysis.regTaint && tsAnalysis.regTaint[r].Public?)
}

predicate method publicTaintsAreAsExpected(tsAnalysis:taintState, tsExpected:taintState)
{
       publicXMMTaintsAreAsExpected(tsAnalysis, tsExpected)
    && publicFlagTaintsAreAsExpected(tsAnalysis, tsExpected)
    && publicStackTaintsAreAsExpected(tsAnalysis, tsExpected)
    && publicRegisterTaintsAreAsExpected(tsAnalysis, tsExpected)
}

lemma lemma_ConsequencesOfIsLeakageFreeGivenStates(code:code, ts:taintState, ts':taintState)
    requires (forall s1, s2, r1, r2 :: isExplicitLeakageFreeGivenStates(code, ts, ts', s1, s2, r1, r2));
    ensures forall s1, s2, r1, r2 :: (evalCode(code, s1, r1)
            && evalCode(code, s2, r2)
            && s1.ok && r1.ok
            && s2.ok && r2.ok
            && constTimeInvariant(ts, s1, s2))
            ==> publicValuesAreSame(ts', r1, r2); 
{
    forall s1, s2, r1, r2 
        ensures (evalCode(code, s1, r1)
            && evalCode(code, s2, r2)
            && s1.ok && r1.ok
            && s2.ok && r2.ok
            && constTimeInvariant(ts, s1, s2))
            ==> publicValuesAreSame(ts', r1, r2);
    {
        assert isExplicitLeakageFreeGivenStates(code, ts, ts', s1, s2, r1, r2);
    }
}
}
