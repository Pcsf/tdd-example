-------------------------------------------------------------------------------
-- Testbench: tb_runner
-- Verified green against UVVM 2.21.4 / v2_2025.05.11 + GHDL 4.1.0
-- TDD cases: see spec/runner_spec.md
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

use work.runner_pkg.all;

entity tb_runner is
end entity tb_runner;

architecture sim of tb_runner is

  -- 1. PREAMBLE -------------------------------------------------------------
  constant C_CLK_PERIOD : time    := 10 ns;             -- 100 MHz
  constant C_SAMPLE     : time    := C_CLK_PERIOD / 4;  -- off-edge sample offset
  constant C_MAX        : natural := 8;
  constant C_SCOPE      : string  := "TB_RUNNER";

  signal clk_s   : std_logic := '0';
  signal rst_s   : std_logic := '1';
  signal start_s : std_logic := '0';
  signal busy_s  : std_logic;
  signal done_s  : std_logic;
  signal dbg_s   : std_logic_vector(1 downto 0);

  shared variable sv_state_cov : t_coverpoint;

begin

  -- 2. DUT INSTANTIATION ----------------------------------------------------
  dut : entity work.runner(rtl)
    generic map (G_MAX => C_MAX, G_DEBUG => true)
    port map (clk        => clk_s, rst => rst_s,
              runi.start => start_s,
              runo.busy  => busy_s, runo.done => done_s,
              state_dbg  => dbg_s);

  -- 3. CLOCK ----------------------------------------------------------------
  p_clk : process
  begin
    clk_s <= '0'; wait for C_CLK_PERIOD / 2;
    clk_s <= '1'; wait for C_CLK_PERIOD / 2;
  end process p_clk;

  -- 3b. COVERAGE MONITOR (samples off the active edge) ----------------------
  p_cov : process
  begin
    wait until rising_edge(clk_s);
    wait for C_SAMPLE;
    sv_state_cov.sample_coverage(to_integer(unsigned(dbg_s)));
  end process p_cov;

  -- 4. SEQUENCER ------------------------------------------------------------
  p_seq : process
  begin
    set_alert_stop_limit(error, 0);
    disable_log_msg(ALL_MESSAGES);
    enable_log_msg(ID_LOG_HDR);
    sv_state_cov.add_bins(bin_range(0, 2));  -- IDLE / RUNNING / DONE

    -- reset
    log(ID_LOG_HDR, "Applying reset", C_SCOPE);
    rst_s <= '1';
    wait for 4 * C_CLK_PERIOD;
    wait until rising_edge(clk_s);
    rst_s <= '0';
    wait for C_CLK_PERIOD;

    -- TC-01
    log(ID_LOG_HDR, "TC-01: reset -> IDLE, outputs low", C_SCOPE);
    check_value(busy_s, '0', error, "BUSY low after reset", C_SCOPE);
    check_value(done_s, '0', error, "DONE low after reset", C_SCOPE);

    -- TC-02
    log(ID_LOG_HDR, "TC-02: START -> RUNNING, BUSY high", C_SCOPE);
    wait until rising_edge(clk_s); start_s <= '1';
    wait until rising_edge(clk_s); start_s <= '0';
    await_value(busy_s, '1', 0 ns, 2 * C_CLK_PERIOD, error,
                "BUSY must assert within 2 cycles of START", C_SCOPE);

    -- TC-03/04
    log(ID_LOG_HDR, "TC-03/04: count to MAX -> 1-cycle DONE -> IDLE", C_SCOPE);
    await_value(done_s, '1', 0 ns, (C_MAX + 4) * C_CLK_PERIOD, error,
                "DONE must pulse when counter reaches MAX", C_SCOPE);
    wait until rising_edge(clk_s);
    wait for C_SAMPLE;                  -- settle off the active edge
    check_value(done_s, '0', error, "DONE must be a single cycle", C_SCOPE);
    check_value(busy_s, '0', error, "FSM returns to IDLE after DONE", C_SCOPE);

    -- coverage gate
    sv_state_cov.report_coverage(VOID);
    check_value(sv_state_cov.get_coverage(BINS) >= 95.0, error,
                "FSM state coverage must be >= 95%", C_SCOPE);

    -- end
    log(ID_LOG_HDR, "=== Simulation complete ===", C_SCOPE);
    report_alert_counters(FINAL);
    std.env.stop;
  end process p_seq;

end architecture sim;
