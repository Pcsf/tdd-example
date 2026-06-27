# `runner` — Module Specification & Behaviour List

Status: authoritative contract for `src/runner.vhd`.
This file is written **before** the RTL and is the source of truth the testbench
encodes. Each TC-NN sentence below maps to one check (or check group) in
`tb/tb_runner.vhd`. A behaviour with no TC does not exist yet.

---

## 1. Purpose

A pulse-triggered run/count FSM. On a single-cycle `start` pulse it runs for a
fixed number of clock cycles (`G_MAX`), asserting `busy` for the duration, then
emits a one-cycle `done` strobe and returns to idle without external
intervention.

---

## 2. Interface contract (ICD)

### Generics

| Generic | Type | Default | Meaning |
|---|---|---|---|
| `G_MAX` | `natural` | 8 | Number of RUNNING cycles before completion. |
| `G_DEBUG` | `boolean` | `false` | When `true`, drives `state_dbg`; when `false`, `state_dbg` is constant `"00"` and the logic is optimised away in synthesis. |

### Ports

`clk`, `rst` are flat `std_logic` (kept out of records for CAD clock-tree /
timing-tool compatibility). All other signals are grouped into records declared
in `runner_pkg`.

| Port | Dir | Type / field | Contract |
|---|---|---|---|
| `clk` | in | `std_logic` | Rising-edge clock. All state updates synchronous to it. |
| `rst` | in | `std_logic` | Synchronous, active-high. Highest priority (overrides all logic in the same cycle). |
| `runi.start` | in | `std_logic` | Single-cycle request pulse. Sampled **only** in IDLE. |
| `runo.busy` | out | `std_logic` | Registered. High while an operation is in progress. |
| `runo.done` | out | `std_logic` | Registered. One-cycle completion strobe. |
| `state_dbg` | out | `slv(1 downto 0)` | Verification-only state observation, gated by `G_DEBUG`. Not a functional output. |

> `state_dbg` exists for functional-coverage sampling, not for downstream logic.
> Treat it as a debug tap: present in simulation (`G_DEBUG => true`), removed in
> synthesis (`G_DEBUG => false`). Do not build product logic against it.

---

## 3. State definitions

| State | `state_t'pos` | `busy` | `done` | Meaning |
|---|---|---|---|---|
| `IDLE` | 0 | 0 | 0 | Waiting for `start`. |
| `RUNNING` | 1 | 1 | 0 | Counting; lasts exactly `G_MAX` cycles. |
| `DONE` | 2 | 1 | 0 | Terminal internal cycle; `done` strobe is emitted on the *following* edge. |

---

## 4. Behavioural requirements (TC list)

```
TC-01: After reset, FSM is IDLE; busy='0' and done='0'.
TC-02: A start pulse sampled in IDLE moves the FSM to RUNNING on the next rising
       edge; busy asserts and is observable within 2 cycles of the start pulse.
TC-03: In RUNNING, the internal counter increments by 1 every clock cycle.
TC-04: RUNNING lasts exactly G_MAX cycles, after which the FSM leaves RUNNING.
TC-05: Completion emits done='1' for exactly one cycle, then done returns to '0'.
TC-06: After completion the FSM returns to IDLE automatically, with busy='0',
       and requires no external trigger to do so.
TC-07: start is ignored while not in IDLE (no re-trigger mid-run). [GAP — see §7]
TC-08: Synchronous reset asserted in any state forces IDLE with outputs low on
       the next edge, overriding all other logic. [PARTIAL — see §7]
```

Each sentence is one behaviour. If a sentence needs an "and" joining two
*independent* effects, it is two behaviours and should be split before coding.

---

## 5. Cycle-accurate reference trace

For `G_MAX = 8`, with a `start` pulse sampled while IDLE at the edge into `t0`.
Columns are the **registered** (externally observable) values at the start of
each cycle; the last column is what `comb` computes for the *next* edge.

| cycle | state | count | busy | done | comb → next |
|---|---|---|---|---|---|
| t0  | IDLE    | 0 | 0 | 0 | start=1 ⇒ RUNNING, busy=1, count←0 |
| t1  | RUNNING | 0 | 1 | 0 | 0≠7 ⇒ count←1 |
| t2  | RUNNING | 1 | 1 | 0 | count←2 |
| t3  | RUNNING | 2 | 1 | 0 | count←3 |
| t4  | RUNNING | 3 | 1 | 0 | count←4 |
| t5  | RUNNING | 4 | 1 | 0 | count←5 |
| t6  | RUNNING | 5 | 1 | 0 | count←6 |
| t7  | RUNNING | 6 | 1 | 0 | count←7 |
| t8  | RUNNING | 7 | 1 | 0 | 7=G_MAX−1 ⇒ DONE, count←8 |
| t9  | DONE    | 8 | 1 | 0 | ⇒ IDLE, busy←0, done←1 |
| t10 | IDLE    | 8 | 0 | 1 | start=0 ⇒ done←0 |
| t11 | IDLE    | 8 | 0 | 0 | idle |

Read this trace carefully — it pins down three timing facts that are easy to get
wrong and that integration *will* expose:

- **`busy` spans t1…t9 (9 cycles).** It stays high through the terminal `DONE`
  internal cycle (t9) and deasserts at t10. There is no cycle where `busy` and
  `done` are both high; `busy`'s last high cycle (t9) immediately precedes the
  `done` strobe (t10).
- **`done` is a single cycle at t10**, and it appears while the registered state
  is already `IDLE` — because outputs are registered, the `done` strobe trails
  the `DONE` internal state by one cycle. The `DONE` enum state and the `done`
  output pulse are *one cycle apart*, by design.
- **Completion latency is `G_MAX + 2` cycles** from the start-sampling edge
  (t0 → t10 = 10 = 8 + 2): one edge IDLE→RUNNING, `G_MAX` counting cycles
  (t1…t8), one edge RUNNING→DONE-output.

`count` is **not** cleared on completion; it holds at `G_MAX` until the next
`start` (which clears it to 0) or `rst`. This is intentional and harmless — the
counter is only meaningful while RUNNING — but it means `count` is not a reliable
idle-state indicator. Use `state`/`busy` for that.

---

## 6. Reset semantics

Synchronous, active-high, highest priority. In `comb`, the reset assignment is
the **last** statement before the register drive, so it overrides any algorithmic
result computed earlier in the same evaluation:

```
if rst = '1' then v := REG_RESET; end if;
rin <= v;
```

`REG_RESET` defines `IDLE`, `count=0`, `busy='0'`, `done='0'` in one place.
Effect: `rst` high at any edge ⇒ all four register fields take their reset value
on that edge; outputs are low from the following cycle.

---

## 7. Coverage map and known gaps

Honest accounting of what the current `tb_runner.vhd` actually verifies, so the
gaps are visible rather than implied.

| TC | Verified by current TB? | Note |
|---|---|---|
| TC-01 | Yes | Direct `check_value` on busy/done post-reset. |
| TC-02 | Yes | `await_value(busy,'1', … 2 cycles)`. |
| TC-03 | **No (indirect)** | Counter increment is only inferred from completion timing, not checked per-cycle. The TB does not observe `count`. |
| TC-04 | Partial | Completion *timing* is checked via the `done` await window, not the exact RUNNING-cycle count. |
| TC-05 | Yes | `await done='1'`, then next edge `check done='0'`. |
| TC-06 | Yes | Post-done `check busy='0'` confirms auto-return to IDLE. |
| TC-07 | **No** | "start ignored mid-run" is implemented (start is only read in the IDLE branch) but has **no test**. This is the classic no-double-fire gap; an FSM whose contract can't express it is under-specified. Add a TC that pulses `start` during RUNNING and asserts the run length is unchanged. |
| TC-08 | Partial | Reset-to-IDLE is exercised only from IDLE at sim start, not asserted mid-RUNNING. Add a TC that resets during RUNNING and checks IDLE + low outputs on the next edge. |

### Verification notes (act on these)

- The `done` await window in the TB is `(G_MAX + 2) * C_CLK_PERIOD`, which equals
  the **nominal** completion latency exactly (§5). That is a zero-margin timeout —
  it sits on the boundary and is fragile to any one-cycle change. Set the window
  with margin (e.g. `G_MAX + 4`) so a real one-cycle regression fails as a wrong
  *value*, not as a flaky *timeout*.
- TC-03 should sample `count` directly (add it to the `G_DEBUG` tap, or expose it
  the same way as `state_dbg`) rather than inferring it from end-to-end timing.
  Inferred-only coverage is how an off-by-one in the counter survives to silicon.

---

## 8. Functional coverage goals

| Cover-point | Bins | Goal |
|---|---|---|
| FSM state | IDLE, RUNNING, DONE (`bin_range(0,2)`) | 100% — all three states reached |
| `start` sampling | start=0 and start=1 while in IDLE | 100% |
| Run length | one full IDLE→RUNNING→DONE→IDLE traversal | ≥ 1 hit |

State coverage is gated in the TB at ≥ 95%; with only three states the practical
target is 100%. A run that never reaches `DONE` should fail the coverage gate,
not pass quietly.