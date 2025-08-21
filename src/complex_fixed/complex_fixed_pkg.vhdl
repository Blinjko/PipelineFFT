-- This file contains the type definition and operator functions for the complex_fixed data type
-- Simply just uses sfixed numbers in pairs, 1 part real, 1 part imaginary, the code below should be self-explanatory

-- To alter the precision keep reading

library ieee;
use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

package complex_fixed_pkg is

    -- Change these  to alter the size of the numbers and the precision
    -- Note high is 1 less than amount of bits on the high end
    constant high : integer :=  4;
    constant low  : integer := -11;

    -- Round styles, change if you want
    constant round_style    : fixed_round_style_type := fixed_round;
    constant overflow_style : fixed_overflow_style_type := fixed_saturate;

type complex_fixed is record
    re : sfixed(high downto low);
    im : sfixed(high downto low);
end record;

function "+" (a, b : complex_fixed) return complex_fixed;
function "-" (a, b : complex_fixed) return complex_fixed;

function "*" (a, b : complex_fixed) return complex_fixed;
end package;

package body complex_fixed_pkg is

    function "+" (a, b : complex_fixed) return complex_fixed is
        variable result : complex_fixed;
    begin
        result.re := resize(a.re + b.re, a.re'high, a.re'low, overflow_style => overflow_style, round_style => round_style);
        result.im := resize(a.im + b.im, a.im'high, a.im'low, overflow_style => overflow_style, round_style => round_style);

        return result;
    end function;

    function "-" (a, b : complex_fixed) return complex_fixed is
        variable result : complex_fixed;
    begin
        result.re := resize(a.re - b.re, a.re'high, a.re'low, overflow_style => overflow_style, round_style => round_style);
        result.im := resize(a.im - b.im, a.im'high, a.im'low, overflow_style => overflow_style, round_style => round_style);

        return result;
    end function;

    function "*" (a, b : complex_fixed) return complex_fixed is
        variable result : complex_fixed;
    begin
        result.re := resize(
        resize(a.re * b.re, a.re'high, a.re'low, overflow_style => overflow_style, round_style => round_style) -
        resize(a.im * b.im, a.re'high, a.re'low, overflow_style => overflow_style, round_style => round_style),
        a.re'high, a.re'low, overflow_style => fixed_wrap, round_style => fixed_truncate);

        result.im := resize(
        resize(a.re * b.im, a.im'high, a.im'low, overflow_style => overflow_style, round_style => round_style) +
        resize(a.im * b.re, a.im'high, a.im'low, overflow_style => overflow_style, round_style => round_style),
        a.im'high, a.im'low);

        return result;
    end function;



end package body;
