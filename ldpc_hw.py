# time_distributed_minsum.py
# Simulate time-distributed Min-Sum (column-by-column) for QC matrix
# Prints m_cv (CN->VN) per PE after each cycle.
#
# Assumptions:
# - QC matrix: #macrocolumns = 4, q = 3 (so n_v = 12)
# - H is n_c x n_v (9 x 12 for your case)
# - Initial L_vc (VN->CN) set to Qv (iter_flag behavior)
# - Min-sum (no offset), integer arithmetic
# - Iterations: you can choose number_of_iterations

from typing import List, Tuple
import math, copy

# ---------- helper utils ----------
def hex5_to_signed(v:int) -> int:
    v &= 0x1F
    return v-32 if (v & 0x10) else v

INF = 10**9

# ---------- User-editable: put your H matrix here (9 rows x 12 cols) ----------
# Replace the placeholder rows below by typing each CN row as a list of 12 zeros/ones.
H = [
    # example rows (replace these with exact rows from your notebook image)
    [0,1,0,1,0,0,0,0,1,0,1,0],  # CN0
    [0,0,1,0,1,0,0,0,0,1,0,0],  # CN1
    [1,0,0,0,0,1,0,0,0,0,1,0],  # CN2
    [0,0,0,0,0,1,0,1,0,0,1,0],  # CN3
    [0,0,0,1,0,0,1,0,1,0,0,0],  # CN4
    [0,0,0,0,1,0,0,1,0,1,0,0],  # CN5
    [0,1,0,1,0,1,0,0,1,0,0,0],  # CN6
    [0,0,1,0,1,0,1,0,0,1,0,0],  # CN7
    [1,0,0,1,0,1,0,1,0,0,1,0],  # CN8
]
# ---------- end H ----------

# Qv ROM values (5-bit hex values you provided)
Qv_hex = [0x07, 0x1A, 0x02, 0x1F, 0x0C, 0x14, 0x00, 0x0E, 0x11, 0x05, 0x18, 0x09]
Qv = [hex5_to_signed(x) for x in Qv_hex]

# Derived sizes
n_c = len(H)
n_v = len(H[0])
# macrocolumns (given) = 4 in your design
num_macrocolumns = 4
q = n_v // num_macrocolumns
assert q * num_macrocolumns == n_v, "n_v must equal q * num_macrocolumns"

# Build adjacency lists
vn_to_cns = {v: [c for c in range(n_c) if H[c][v]] for v in range(n_v)}
cn_to_vns = {c: [v for v in range(n_v) if H[c][v]] for c in range(n_c)}

# initialize L_vc (VN->CN) messages: at iteration start these are Qv
Lvc = {}  # keyed by (v,c)
for c in range(n_c):
    for v in cn_to_vns[c]:
        Lvc[(v,c)] = Qv[v]  # iter_flag==1 behavior (first iter)

def reset_cn_states():
    # for each CN store (sc, min1, min2, parity)
    # sc = product of signs (1 or -1), initialize to +1
    return {c: {'sc':1, 'min1':INF, 'min2':INF, 'pc':0} for c in range(n_c)}

def sign(x): return 1 if x >= 0 else -1
def hardbit_from_llr(x): return 0 if x >= 0 else 1

def process_cn_update_for_v(cn_state, v, c):
    """Given CN c's state and VN v with Lvc[(v,c)], update state in-place."""
    L = Lvc[(v,c)]
    s = sign(L)
    mag = abs(L)
    # update sign product
    cn_state['sc'] *= s
    # update mins
    if mag < cn_state['min1']:
        cn_state['min2'] = cn_state['min1']
        cn_state['min1'] = mag
    elif mag < cn_state['min2']:
        cn_state['min2'] = mag
    # update parity (using hard decision on L)
    cn_state['pc'] ^= hardbit_from_llr(L)

def compute_mcv_from_cn_state(c_state, Lvc_vc):
    """Given a CN final state and local Lvc (for the target VN),
       compute CN->VN message (signed int) per min-sum rule."""
    sc_total = c_state['sc']   # product of signs of all
    mag = abs(Lvc_vc)
    # determine magnitude to use (if Lvc_vc mag == min1, use min2 else min1)
    use_mag = c_state['min2'] if mag == c_state['min1'] else c_state['min1']
    # if CN degree is 1 (no other neighbours), use 0
    if use_mag == INF:
        use_mag = 0
    # sign excluding this VN = sc_total * sign(Lvc_vc)
    sign_excl = sc_total * sign(Lvc_vc)
    return sign_excl * use_mag

# simulation driver printing per-cycle
def run_time_distributed(H, Qv, Lvc, iterations=15):
    for it in range(1, iterations+1):
        print("\n" + "="*60)
        print(f"ITERATION {it} (time-distributed, {num_macrocolumns} columns, q={q})")
        print("="*60)
        # CN phase: traverse columns 0..num_macrocolumns-1
        cn_state = reset_cn_states()
        for col in range(num_macrocolumns):
            print(f"\nCN CYCLE (col {col})")
            # VNs in this column:
            v_list = [col*q + r for r in range(q)]
            # Process each VN: update all CNs connected to that VN
            for v in v_list:
                for c in vn_to_cns[v]:
                    process_cn_update_for_v(cn_state[c], v, c)
            # Print per-PE view for this column: for each VN (PE) in column print the CN states
            for v in v_list:
                pe_idx = v
                connected = vn_to_cns[v]
                # For each connected CN print its (sc,min1,min2)
                line = f" PE{pe_idx:02d} (VN{pe_idx}): "
                entries = []
                for c in connected:
                    st = cn_state[c]
                    entries.append(f"CN{c}:(sc={st['sc']:+d},min1={st['min1'] if st['min1']<INF else 'inf'},min2={st['min2'] if st['min2']<INF else 'inf'})")
                if not entries:
                    entries = ["(no CN edges)"]
                print(line + " | ".join(entries))
        # After CN phase done, cn_state holds final per-CN stats for this iteration
        print("\n-- CN phase complete. Final CN states:")
        for c in range(n_c):
            st = cn_state[c]
            print(f" CN{c}: sc={st['sc']:+d}, min1={st['min1'] if st['min1']<INF else 'inf'}, min2={st['min2'] if st['min2']<INF else 'inf'}, pc={st['pc']}")

        # VN phase: traverse columns again; on each column compute m_cv for VNs in that column and update L_v, Lvc
        # Note: compute m_cv using final cn_state
        # Precompute all m_cv for all edges (c->v)
        m_cv = {}
        for c in range(n_c):
            for v in cn_to_vns[c]:
                m_cv[(c,v)] = compute_mcv_from_cn_state(cn_state[c], Lvc[(v,c)])

        # we will update per-PE L_v and Lvc when their column is visited
        for col in range(num_macrocolumns):
            print(f"\nVN CYCLE (col {col})")
            v_list = [col*q + r for r in range(q)]
            for v in v_list:
                pe_idx = v
                # sum all incoming m_cv for this VN
                sum_in = 0
                for c in vn_to_cns[v]:
                    sum_in += m_cv[(c,v)]
                L_v = Qv[v] + sum_in
                # compute per-edge extrinsic L_vc = L_v - m_cv(c->v)
                updated_Lvc = {}
                for c in vn_to_cns[v]:
                    updated_Lvc[c] = L_v - m_cv[(c,v)]
                # write updates back to Lvc dict (for next iteration)
                for c in updated_Lvc:
                    Lvc[(v,c)] = updated_Lvc[c]
                # compute hard decision
                hard = 0 if L_v >= 0 else 1
                # Print m_cv for each connected CN for this PE
                entries = []
                for c in vn_to_cns[v]:
                    entries.append(f"CN{c}->VN{v}: m_cv={m_cv[(c,v)]:+d}, updated_Lvc={Lvc[(v,c)]:+d}")
                print(f" PE{pe_idx:02d} (VN{pe_idx}): L_v={L_v:+d}, hard={hard}, " + " | ".join(entries))
        # Optionally, print a compact summary of all VNs at iteration end
        L_v_all = [0]*n_v
        for v in range(n_v):
            # recompute L_v final (should equal Qv + sum m_cv)
            total = Qv[v]
            for c in vn_to_cns[v]:
                total += m_cv[(c,v)]
            L_v_all[v] = total
        hard_all = [0 if lv>=0 else 1 for lv in L_v_all]
        print("\nIteration summary:")
        print("  L_v:", L_v_all)
        print("  hard decisions:", hard_all)
    return

if __name__ == "__main__":
    print("Qv signed:", Qv)
    run_time_distributed(H, Qv, Lvc, iterations=5)  # set iteration count as you like
