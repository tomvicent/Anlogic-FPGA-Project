# clk_reset_gen Behavior Specification

## Requirement Summary

`clk_reset_gen` is the centralized clock/reset generator for the four-axis motor closed-loop control FPGA system. It implements three functions:

1. **Reset synchronization chain**: async assert / sync deassert, guaranteeing all downstream flip-flops exit reset on the same clock edge.
2. **Power-on reset (POR)**: a counter-based POR that guarantees a deterministic reset sequence even when the external reset input is not toggled.
3. **Tick generation**: single-cycle enable pulses for the control loop (1 kHz), debounce sampling (1 ms period), and PWM carrier (always-on).

This module is the **only** module in the entire design that is allowed to reference the raw `i_rst_n` signal (architecture boundary B6).

## Public Interface

| Port | Direction | Width | Active Level | Description |
|------|-----------|-------|--------------|-------------|
| `i_clk` | input | 1 | posedge | 100 MHz main clock (PL_CLK / H16 / bank33 / LVCMOS33) |
| `i_rst_n` | input | 1 | low (async) | External active-low reset, asynchronous; may be tied to 1 (unused) |
| `o_sys_rst_n` | output | 1 | low | Global reset after async assert / sync deassert merge |
| `o_en_ctrl_tick` | output | 1 | high (pulse) | Control cycle single-cycle enable, 1 kHz |
| `o_en_pwm_tick` | output | 1 | high (constant) | PWM carrier advance enable (hardwired 1) |
| `o_en_deb_tick` | output | 1 | high (pulse) | Debounce counter sampling enable, 1 ms period |
| `o_por_done` | output | 1 | high | POR counter completion flag (sticky) |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_FREQ_HZ` | 100000000 | Input clock frequency in Hz |
| `CTRL_TICK_HZ` | 1000 | Closed-loop control tick frequency in Hz |
| `POR_CYCLES` | 1024 | Number of clock cycles the POR counter must count before releasing reset |

Derived localparams:
- `CTRL_DIV = CLK_FREQ_HZ / CTRL_TICK_HZ` (default 100000)
- `DEB_DIV = CLK_FREQ_HZ / 1000` (default 100000, 1 ms period)
- `CTRL_CNT_W = clog2(CTRL_DIV)` (default 17 bits)
- `DEB_CNT_W = clog2(DEB_DIV)` (default 17 bits)
- `POR_CNT_W = clog2(POR_CYCLES + 1)` (default 11 bits)

## Clocking and Reset

- Single clock domain: `i_clk` (100 MHz, 10 ns period).
- Reset input `i_rst_n`: asynchronous, active-low. Used directly as the async clear of the reset synchronizer and the output register `sys_rst_n_r`.
- Reset output `o_sys_rst_n`: asynchronous assert (immediate via `i_rst_n`), synchronous deassert (two-stage FF chain + POR counter merge).
- All tick counters and output registers use `sys_rst_n_r` as their asynchronous reset input (active-low).

## Functional Behavior

### Reset Synchronizer Chain (rst_sync_ff1, rst_sync_ff2)

Cycle-by-cycle behavior when `i_rst_n` transitions from low to high:

| Cycle | `i_rst_n` | `rst_sync_ff1` | `rst_sync_ff2` | Effect |
|-------|-----------|----------------|----------------|--------|
| N     | 0         | 0              | 0              | Both FFs held in reset via async clear |
| N+1   | 1         | 1              | 0              | FF1 captures 1'b1 on rising clock edge |
| N+2   | 1         | 1              | 1              | FF2 captures FF1 output; sync release complete |

When `i_rst_n` goes low at any time, both FFs are immediately cleared (async, clock-independent).

### POR Counter (por_cnt, por_done_raw)

- On FPGA power-up (or `i_rst_n` going low): `por_cnt` resets to 0, `por_done_raw` resets to 0.
- While `por_done_raw == 0`: `por_cnt` increments every clock cycle. When `por_cnt` reaches `POR_CYCLES - 1`, `por_done_raw` is set to 1. The counter stops incrementing.
- After `por_done_raw == 1`: the counter state is frozen (sticky). Only `i_rst_n` going low can reset it.
- POR duration: `POR_CYCLES` clock cycles. Default: 1024 cycles at 100 MHz = 10.24 us.

### Reset Merge (sys_rst_n_r)

```
sys_rst_n_r <= rst_sync_ff2 & por_done_raw
```

Both paths must release before `sys_rst_n_r` goes high. Release timeline:
- If `i_rst_n` was low: `rst_sync_ff2` goes high 2 cycles after `i_rst_n` rises.
- If `por_done_raw` was 0: it goes high after POR_CYCLES cycles.
- `sys_rst_n_r` goes high one cycle after both are high (registered output).
- Total reset hold: `max(2 + 1, POR_CYCLES + 1)` cycles = `POR_CYCLES + 1` cycles (default 1025 cycles, since POR_CYCLES > 2).

`o_por_done` and `o_sys_rst_n` are driven from the same register (`sys_rst_n_r`), guaranteeing that `o_por_done == 0` whenever `o_sys_rst_n == 0`.

### Control Tick (o_en_ctrl_tick)

- `ctrl_cnt` counts from 0 to `CTRL_DIV - 1`, then wraps to 0.
- On the wrap cycle: `en_ctrl_tick_r` is set to 1 (single-cycle pulse).
- On all other cycles: `en_ctrl_tick_r` is 0.
- Pulse width: exactly 1 clock cycle (10 ns).
- Period: `CTRL_DIV` clock cycles (default 100000 cycles = 1 ms = 1 kHz).
- Reset value of `ctrl_cnt`: 0. Reset value of `en_ctrl_tick_r`: 0.

### Debounce Tick (o_en_deb_tick)

- `deb_cnt` counts from 0 to `DEB_DIV - 1`, then wraps to 0.
- On the wrap cycle: `en_deb_tick_r` is set to 1 (single-cycle pulse).
- On all other cycles: `en_deb_tick_r` is 0.
- Pulse width: exactly 1 clock cycle (10 ns).
- Period: `DEB_DIV` clock cycles (default 100000 cycles = 1 ms).
- Convention: downstream debounce module uses `DEBOUNCE_MS` ticks to count. For example, `DEBOUNCE_MS = 10` means 10 ms of consistent sampling before output update.
- Reset value of `deb_cnt`: 0. Reset value of `en_deb_tick_r`: 0.

### PWM Tick (o_en_pwm_tick)

- Combinational output, hardwired to `1'b1`.
- Every clock cycle the carrier counter in `sync_timebase` is allowed to advance.
- Carrier frequency is parameterized in `sync_timebase` via `PWM_CARRIER_HZ`; this module does not need to know it.
- If future designs require carrier speed reduction, a divider can be inserted here without changing the module interface.

## Timing, Latency, and Throughput

| Output | Latency from reset release | Period | Pulse width |
|--------|---------------------------|--------|-------------|
| `o_sys_rst_n` | N/A (this IS the reset) | N/A | N/A |
| `o_por_done` | N/A (merged with sys_rst_n) | N/A | N/A |
| `o_en_ctrl_tick` | First pulse at cycle `CTRL_DIV - 1` after reset release | `CTRL_DIV` cycles | 1 cycle |
| `o_en_deb_tick` | First pulse at cycle `DEB_DIV - 1` after reset release | `DEB_DIV` cycles | 1 cycle |
| `o_en_pwm_tick` | Immediate (combinational) | N/A | Constant 1 |

## Assumptions and Chosen Defaults

1. `i_rst_n` may be tied to `1'b1` (external reset not used). The POR counter guarantees a valid reset sequence regardless.
2. `CLK_FREQ_HZ` must be a multiple of both `CTRL_TICK_HZ` and `1000` for integer division. If not, the actual frequency will be slightly off due to integer truncation.
3. `POR_CYCLES` must be at least 2 (minimum meaningful POR duration). The counter uses `>=` comparison which is safe for any positive value.
4. The `clog2_f` function uses a Verilog-2001 compatible `for`-loop implementation to compute `ceil(log2(n))` for counter width derivation.
5. `o_en_ctrl_tick` and `o_en_deb_tick` have the same frequency under default parameters but use independent counters, allowing future parameter divergence without structural changes.
6. `o_por_done` and `o_sys_rst_n` share the same register output, ensuring they release on the exact same clock edge.

## Edge Cases and Error Handling

| Scenario | Behavior |
|----------|----------|
| `i_rst_n` toggles low during normal operation | All registers async-clear immediately; POR counter resets; tick outputs go low |
| `i_rst_n` tied permanently to 1 | POR counter provides sole reset mechanism; normal operation after POR_CYCLES |
| `CTRL_TICK_HZ > CLK_FREQ_HZ` | `CTRL_DIV = 0` (integer division), which would cause `CTRL_DIV - 1` to wrap. Counter width would be `clog2(0)` = 0, but localparam guards set width to 1 minimum. This is a parameter validation error; downstream synthesis tools may flag it. |
| `POR_CYCLES = 1` | `por_cnt >= 0` is always true; `por_done_raw` sets on first clock after reset. Minimum useful value. |
| Counter width overflow | Counters use `clog2` of the division ratio, so the maximum count value equals `CTRL_DIV - 1` exactly. No wrap-around ambiguity. |

## Synthesis Notes

- Pure Verilog-2001 syntax. No SystemVerilog constructs (`logic`, `always_ff`, `always_comb`).
- Target toolchain: Anlogic Tang Dynasty (TD).
- No PLL/MMCM used. All timing derived from the 100 MHz input clock.
- Reset synchronizer uses `negedge i_rst_n` as async clear, which is a standard FPGA primitive pattern supported by all synthesis tools.
- The `clog2_f` function is evaluated at elaboration time; it does not generate hardware.
- All registers have defined reset values. No inferred latches.
- No combinational loops. All outputs are either registered or simple combinational assignments.

## Verification Plan

| # | Test Case | Expected Result |
|---|-----------|-----------------|
| 1 | Power-up with `i_rst_n = 1'b1` (no external reset) | `o_sys_rst_n` stays low for `POR_CYCLES + 1` cycles, then goes high |
| 2 | `i_rst_n` driven low for 100 cycles, then released | `o_sys_rst_n` goes low immediately, stays low during reset + 2 sync cycles + 1 merge cycle after release |
| 3 | `i_rst_n` driven low after POR has completed | `o_sys_rst_n` and `o_por_done` both go low immediately; POR counter resets to 0; after release, full POR countdown repeats |
| 4 | Normal operation: verify `o_en_ctrl_tick` pulse | Pulse is exactly 1 cycle wide; period is `CTRL_DIV` cycles |
| 5 | Normal operation: verify `o_en_deb_tick` pulse | Pulse is exactly 1 cycle wide; period is `DEB_DIV` cycles |
| 6 | `o_en_pwm_tick` constant | Always 1, independent of reset state |
| 7 | Verify `o_por_done == 0` when `o_sys_rst_n == 0` | Invariant holds at all times |
| 8 | All tick outputs are 0 during reset | `o_en_ctrl_tick = 0`, `o_en_deb_tick = 0` while `o_sys_rst_n = 0` |
| 9 | Non-default parameters: `CLK_FREQ_HZ=50000000`, `CTRL_TICK_HZ=2000` | `CTRL_DIV = 25000`; tick period and pulse width correct |
| 10 | Rapid reset toggling | Each low pulse resets all state cleanly; no residual state from prior cycle |

## Acceptance Criteria

- `o_sys_rst_n` release is a single, unified event: all downstream logic exits reset on the same clock edge.
- `o_en_ctrl_tick` and `o_en_deb_tick` are single-cycle pulses with no multi-cycle assertion.
- No X-propagation on any output at any time.
- No latch inference, no combinational loops, no multi-driver conflicts.
- `o_por_done` is strictly 0 when `o_sys_rst_n` is 0.
- All counter widths are sufficient (no wrap-around ambiguity for the configured division ratios).
- The module contains no references to signals outside its port list (boundary B6 compliance).
