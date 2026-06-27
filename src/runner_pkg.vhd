library ieee;
use ieee.std_logic_1164.all;

package runner_pkg is
  type runner_in_type is record
    start : std_logic;
  end record;

  type runner_out_type is record
    busy : std_logic;
    done : std_logic;
  end record;
end package runner_pkg;
