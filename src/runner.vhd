library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.runner_pkg.all;

entity runner is
  generic (
    G_MAX   : natural := 8;
    G_DEBUG : boolean := false);
  port (
    clk, rst  : in  std_logic;
    runi      : in  runner_in_type;
    runo      : out runner_out_type;
    state_dbg : out std_logic_vector(1 downto 0));
end entity runner;

architecture rtl of runner is
  type state_t is (IDLE, RUNNING, DONE);
  type reg_type is record
    state : state_t;
    count : unsigned(15 downto 0);
    busy  : std_logic;
    done  : std_logic;
  end record;

  constant c_reg_rst : reg_type := (
    state => IDLE,
    count => (others => '0'),
    busy  => '0',
    done  => '0');

  signal r, rin : reg_type;

begin

  comb : process(runi, r)
    variable v : reg_type;
  begin
    v      := r;
    v.done := '0';

    case r.state is
      when IDLE =>
        v.busy := '0';
        if runi.start = '1' then
          v.state := RUNNING;
          v.busy  := '1';
          v.count := (others => '0');
        end if;
      when RUNNING =>
        v.busy  := '1';
        v.count := r.count + 1;
        if r.count = to_unsigned(G_MAX -1, r.count'length) then
          v.state := DONE;
        end if;
      when DONE =>
        v.busy  := '0';
        v.done  := '1';
        v.state := IDLE;
    end case;

    if rst = '1' then v := c_reg_rst; end if;

    rin       <= v;
    runo.busy <= r.busy;
    runo.done <= r.done;

    if G_DEBUG then
      state_dbg <= std_logic_vector(to_unsigned(state_t'pos(r.state), 2));
    else
      state_dbg <= "00";
    end if;
  end process comb;

  regs : process(clk)
  begin
    if rising_edge(clk) then r <= rin; end if;
  end process regs;
end architecture rtl;
