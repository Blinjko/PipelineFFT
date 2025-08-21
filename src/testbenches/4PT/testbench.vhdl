library ieee;
use ieee.std_logic_1164.all;

entity FPGA_CLOCK is
    port (CLK : out std_logic);
end FPGA_CLOCK;

architecture behav of FPGA_CLOCK is
    constant period : time := 83.33 ns; -- 12 MHz clock
begin

    process
    begin
        CLK <= '0';
        wait for period / 2;
        CLK <= '1';
        wait for period / 2;
    end process;
end behav;



library ieee;
use ieee.std_logic_1164.all;
use ieee.fixed_float_types.all;
use ieee.fixed_pkg.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;
use std.textio.all;

library complex;
use complex.complex_fixed_pkg.all;

library work;
use work.all;

library fft;
use fft.all;

entity testbench is
end testbench;

architecture behav of testbench is

    -- Connections
    signal CLK : std_logic;
    signal RST : std_logic := '0';

    signal SAMPLE_IN : std_logic_vector(15 downto 0) := "0000000000000000";
    signal WE        : std_logic := '0';

    signal SAMPLE_OUT : std_logic_vector(15 downto 0);
    signal OUT_WE     : std_logic;

    signal WRITABLE     : std_logic;
    signal OUT_WRITABLE : std_logic := '1';


    constant period : time := 83.33 ns;

    signal four_current_out, eight_current_out : real;
    signal eight_current_in  : real := 0.0;

    -- Julia code used t make this
    -- x = range(0, 2pi, 8)
    -- y = sin.(x*2*pi*3) -- 3Hz sine wave, the numbers below are y
    signal input : real_vector(0 to 15) := (0.0,
                                            0.0,
                                           -0.9360947368931993,
                                            0.0,
                                            0.658538871241532,
                                            0.0,
                                            0.4728152974900992,
                                            0.0,
                                           -0.991162525710797,
                                            0.0,
                                            0.2244635410437092,
                                            0.0,
                                            0.8332533300620845,
                                            0.0,
                                           -0.8106538974370205,
                                            0.0);


    -- Signals to connect the 4PT to the 8PT
    signal FOUR_OUT_WE     : std_logic;
    signal FOUR_WRITABLE   : std_logic;
    signal FOUR_SAMPLE_OUT : std_logic_vector(15 downto 0);

begin

    fpga: entity FPGA_CLOCK port map (CLK => CLK);


    eight_pt: entity STAGE

        generic map ( n    => 8,
                      head => true)

        port map (CLK => CLK,
                  RST => RST,
                  SAMPLE_IN => SAMPLE_IN,
                  WE => WE,
                  OUT_WRITABLE => FOUR_WRITABLE,
                  SAMPLE_OUT => SAMPLE_OUT,
                  OUT_WE => OUT_WE,
                  WRITABLE => WRITABLE);

    four_pt: entity STAGE

        generic map ( n    => 4,
                      head => false)

        port map (CLK => CLK,
                  RST => RST,
                  SAMPLE_IN => SAMPLE_OUT,
                  WE => OUT_WE,
                  OUT_WRITABLE => OUT_WRITABLE,
                  SAMPLE_OUT => FOUR_SAMPLE_OUT,
                  OUT_WE => FOUR_OUT_WE,
                  WRITABLE => FOUR_WRITABLE);


    main: process
        variable L : line;
    begin


        -- Reset --
        RST <= '1';
        wait for period;
        RST <= '0';

        -- Begin printing the input data out as a Julia ComplexF64 array (so it can be copied easily for testing and comparison)
        -- Also begin feeding the samples to the eight point (head)
        write(L, string'("["));

        for sample in 0 to 7 loop

            eight_current_in <= to_real(to_sfixed(input(sample*2), high, low));
            SAMPLE_IN <= to_slv(to_sfixed(input(sample*2), high, low)); -- high and low are from complex_fixed, and have the amount of bits for the upper and lowe r parts
            while (WRITABLE = '0') loop

                wait for period;

            end loop;

            WE <= '1';

            wait for period;

            WE <= '0';

            write(L, real'image(eight_current_in) & " + ");

            eight_current_in <= to_real(to_sfixed(input(sample*2+1), high, low));

            SAMPLE_IN <= to_slv(to_sfixed(input(sample*2+1), high, low));

            while (WRITABLE = '0') loop

                wait for period;

            end loop;

            WE <= '1';

            wait for period;

            WE <= '0';

            write(L, real'image(eight_current_in) & "im, ");

        end loop;

        write(L, string'("]"));
        writeline(output, L);


        wait for period * 200;

        std.env.stop;
    end process main;


    eight_current_out <= to_real(to_sfixed(SAMPLE_OUT, high, low));
    four_current_out  <= to_real(to_sfixed(FOUR_SAMPLE_OUT, high, low));

    four: process(CLK)

        constant pt : integer := 4;

        variable saved_output : real_vector(0 to pt*4) := (others => 0.0);

        variable index : integer := 0;

        variable current_cycle : integer := 0;

        variable L : line;
    begin

        if (rising_edge(CLK)) then

            if (OUT_WE = '1') then

                -- Replicate the stage's read in sequence so we can send out the samples in the right order
                case(current_cycle) is

                    when 0 =>
                        -- Even real
                        saved_output(index) := eight_current_out;
                        index := index + 2*pt;
                        current_cycle := 1;

                    when 1 => 

                        -- Odd real
                        saved_output(index) := eight_current_out;
                        index := index - 2*pt + 1;
                        current_cycle := 2;

                    when 2 => 

                        -- Even imag
                        saved_output(index) := eight_current_out;
                        index := index + 2*pt;
                        current_cycle := 3;

                    when 3 => 

                        -- odd imag;
                        saved_output(index) := eight_current_out;

                        -- Cycle finished
                        if (index = 4*pt - 1) then

                            write(L, string'("["));

                            for sample in 0 to 2*pt - 1 loop

                                write(L, real'image(saved_output(sample*2)));
                                write(L, string'(" + "));

                                write(L, real'image(saved_output(sample*2+1)));
                                write(L, string'("im, "));

                            end loop;

                            write(L, string'("]"));

                            writeline(output,L);

                            index := 0;

                        else

                            index := index - 2*pt + 1;

                        end if;

                        current_cycle := 0;

                    when others =>
                        current_cycle := 0;
                end case;

            end if;

        end if;

    end process;

end behav;
