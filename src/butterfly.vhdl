library ieee;
use ieee.std_logic_1164.all;

library complex;
use complex.complex_fixed_pkg.all;

entity BUTTERFLY is 
    port (EVEN    : in  complex_fixed;
          ODD     : in  complex_fixed;
          TWIDDLE : in  complex_fixed;
          OUT_A   : out complex_fixed; 
          OUT_B   : out complex_fixed);
end BUTTERFLY;

architecture behav of BUTTERFLY is
begin
    OUT_A <= EVEN + ODD;
    OUT_B <= (EVEN - ODD)*TWIDDLE;
end behav;
