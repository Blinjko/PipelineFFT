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

    signal OUT_WRITABLE : std_logic := '1';

    signal SIXTEEN_SAMPLE_IN    : std_logic_vector(15 downto 0) := "0000000000000000";
    signal SIXTEEN_WE           : std_logic := '0';

    signal SIXTEEN_OUT_WE       : std_logic;
    signal SIXTEEN_WRITABLE     : std_logic;
    signal SIXTEEN_SAMPLE_OUT   : std_logic_vector(15 downto 0);


    -- Signals to connect the 16PT to the 8PT
    signal EIGHT_OUT_WE     : std_logic;
    signal EIGHT_WRITABLE   : std_logic;
    signal EIGHT_SAMPLE_OUT : std_logic_vector(15 downto 0);

    -- Signals to connect the 4PT to the 8PT
    signal FOUR_OUT_WE     : std_logic;
    signal FOUR_WRITABLE   : std_logic;
    signal FOUR_SAMPLE_OUT : std_logic_vector(15 downto 0);

    -- Signals to connect the 2PT to the 4PT
    signal TWO_OUT_WE     : std_logic;
    signal TWO_WRITABLE   : std_logic;
    signal TWO_SAMPLE_OUT : std_logic_vector(15 downto 0);


    constant period : time := 83.33 ns;

    signal  sixteen_current_out, eight_current_out, four_current_out, two_current_out : real;

    signal  sixteen_current_in : real := 0.0;

    -- Julia code used t make this
    -- x = range(0, 2pi, 16)
    -- y = sin.(x*2*pi*3) -- 3Hz sine wave, the numbers below are y
    signal input : real_vector(0 to 31) := (0.0,
                                            0.0,
                                            0.9991306023192169,
                                            0.0,
                                            -0.08330711201099711,
                                             0.0,
                                             -0.9921844884723351,
                                             0.0,
                                             0.16603505981369143,
                                             0.0,
                                             0.9783405512597778,
                                             0.0,
                                             -0.24760870564088558,
                                             0.0,
                                             -0.9576950359209003,
                                             0.0,
                                             0.3274609366151383,
                                             0.0,
                                             0.930391473341093,
                                             0.0,
                                             -0.4050366074071131,
                                             0.0,
                                             -0.8966196822023825,
                                             0.0,
                                             0.47979639969364135,
                                             0.0,
                                             0.8566144493339561,
                                             0.0,
                                             -0.5512205715839371,
                                             0.0,
                                             -0.8106538974370205,
                                             0.0);




begin

    fpga: entity FPGA_CLOCK port map (CLK => CLK);

    sixteen_pt: entity STAGE

        generic map ( n    => 16,
                      head => true)

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => SIXTEEN_SAMPLE_IN,
                  WE           => SIXTEEN_WE,
                  OUT_WRITABLE => EIGHT_WRITABLE,
                  SAMPLE_OUT   => SIXTEEN_SAMPLE_OUT,
                  OUT_WE       => SIXTEEN_OUT_WE,
                  WRITABLE     => SIXTEEN_WRITABLE);


    eight_pt: entity STAGE

        generic map ( n    => 8,
                      head => false)

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => SIXTEEN_SAMPLE_OUT,
                  WE           => SIXTEEN_OUT_WE,
                  OUT_WRITABLE => FOUR_WRITABLE,
                  SAMPLE_OUT   => EIGHT_SAMPLE_OUT,
                  OUT_WE       => EIGHT_OUT_WE,
                  WRITABLE     => EIGHT_WRITABLE);

    four_pt: entity STAGE

        generic map ( n    => 4,
                      head => false)

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => EIGHT_SAMPLE_OUT,
                  WE           => EIGHT_OUT_WE,
                  OUT_WRITABLE => TWO_WRITABLE,
                  SAMPLE_OUT   => FOUR_SAMPLE_OUT,
                  OUT_WE       => FOUR_OUT_WE,
                  WRITABLE     => FOUR_WRITABLE);

    two_pt: entity STAGE

        generic map ( n    => 2,
                      head => false)

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => FOUR_SAMPLE_OUT,
                  WE           => FOUR_OUT_WE,
                  OUT_WRITABLE => OUT_WRITABLE,
                  SAMPLE_OUT   => TWO_SAMPLE_OUT,
                  OUT_WE       => TWO_OUT_WE,
                  WRITABLE     => TWO_WRITABLE);

    -- Live outputs of each stage, need to be cast to real so that we can see them
    -- As fractional numbers in the waveform viewer

    sixteen_current_out <= to_real(to_sfixed(SIXTEEN_SAMPLE_OUT, high, low));
    eight_current_out   <= to_real(to_sfixed(EIGHT_SAMPLE_OUT, high, low));
    four_current_out    <= to_real(to_sfixed(FOUR_SAMPLE_OUT, high, low));
    two_current_out     <= to_real(to_sfixed(TWO_SAMPLE_OUT, high, low));

    -- Main process
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

        for sample in 0 to 15 loop

            sixteen_current_in <= to_real(to_sfixed(input(sample*2), high, low));

            SIXTEEN_SAMPLE_IN <= to_slv(to_sfixed(input(sample*2), high, low)); -- high and low are from complex_fixed

            while (SIXTEEN_WRITABLE = '0') loop

                wait for period;

            end loop;

            SIXTEEN_WE <= '1';

            wait for period;

            SIXTEEN_WE <= '0';

            write(L, real'image(sixteen_current_in) & " + ");

            sixteen_current_in <= to_real(to_sfixed(input(sample*2+1), high, low));

            SIXTEEN_SAMPLE_IN <= to_slv(to_sfixed(input(sample*2+1), high, low));

            while (SIXTEEN_WRITABLE = '0') loop

                wait for period;

            end loop;

            SIXTEEN_WE <= '1';

            wait for period;

            SIXTEEN_WE <= '0';

            write(L, real'image(SIXTEEN_current_in) & "im, ");

        end loop;

        write(L, string'("]"));
        writeline(output, L);


        wait for period * 400;

        std.env.stop;
    end process main;

    -- Capture the output of the 16 point (the input to the 8 point)
    eight: process(CLK)

        constant pt : integer := 8;

        variable saved_output : real_vector(0 to pt*4) := (others => 0.0);

        variable index : integer := 0;

        variable current_cycle : integer := 0;

        variable L : line;
    begin

        if (rising_edge(CLK)) then

            if (SIXTEEN_OUT_WE = '1') then

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

                            write(L, string'("sixteen_pt_output = "));
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




    -- Capture the output of the 8 point (the input to the 4 point)
    four: process(CLK)

        constant pt : integer := 4;

        variable saved_output : real_vector(0 to pt*4) := (others => 0.0);

        variable index : integer := 0;

        variable current_cycle : integer := 0;

        variable L : line;
    begin

        if (rising_edge(CLK)) then

            if (EIGHT_OUT_WE = '1') then

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

                            write(L, string'("eight_pt_output = "));
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

    -- Capture the output of the 4 point (input to the 2 point)
    two: process(CLK)

        constant pt : integer := 2;

        variable saved_output : real_vector(0 to pt*4) := (others => 0.0);

        variable index : integer := 0;

        variable current_cycle : integer := 0;

        variable L : line;
    begin

        if (rising_edge(CLK)) then

            if (FOUR_OUT_WE = '1') then

                -- Replicate the stage's read in sequence so we can send out the samples in the right order
                case(current_cycle) is

                    when 0 =>
                        -- Even real
                        saved_output(index) := four_current_out;
                        index := index + 2*pt;
                        current_cycle := 1;

                    when 1 => 

                        -- Odd real
                        saved_output(index) := four_current_out;
                        index := index - 2*pt + 1;
                        current_cycle := 2;

                    when 2 => 

                        -- Even imag
                        saved_output(index) := four_current_out;
                        index := index + 2*pt;
                        current_cycle := 3;

                    when 3 => 

                        -- odd imag;
                        saved_output(index) := four_current_out;

                        -- Cycle finished
                        if (index = 4*pt - 1) then

                            write(L, string'("four_pt_output = "));
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

    -- Capture the output
    final: process(CLK)

        -- Reverse addressing so we can extract the output in the right order
        variable real_index : unsigned(3 downto 0);

        variable even_real : real := 0.0;
        variable even_imag : real := 0.0;
        variable odd_real  : real := 0.0;
        variable odd_imag  : real := 0.0;
        

        variable saved_output : real_vector(0 to 31) := (others => 0.0);

        variable index : unsigned(3 downto 0) := to_unsigned(0, 4);

        variable cycle : integer := 0;

        variable L : line;
    begin

        if (rising_edge(CLK)) then

            if (TWO_OUT_WE = '1') then

                case (cycle) is
                    when 0 =>
                        even_real := two_current_out;
                        cycle := 1;

                    when 1 =>
                        odd_real := two_current_out;
                        cycle := 2;

                    when 2 =>
                        even_imag := two_current_out;
                        cycle := 3;

                    when 3 =>
                        odd_imag := two_current_out;
                        cycle := 4;

                    when others =>
                        cycle := 0;

                end case;

                if (cycle = 4) then

                    cycle := 0;

                    saved_output(to_integer(real_index)*2) := even_real;
                    saved_output(to_integer(real_index)*2+1) := even_imag;

                    index := index + 1;

                    real_index(0) := index(3);
                    real_index(1) := index(2);
                    real_index(2) := index(1);
                    real_index(3) := index(0);

                    saved_output(to_integer(real_index)*2)   := odd_real;
                    saved_output(to_integer(real_index)*2+1) := odd_imag;


                    if (index = 15) then

                        write(L, string'("final_output = "));
                        write(L, string'("["));

                        for sample in 0 to 15 loop

                            write(L, real'image(saved_output(sample*2)));
                            write(L, string'(" + "));

                            write(L, real'image(saved_output(sample*2+1)));
                            write(L, string'("im, "));

                        end loop;

                        write(L, string'("]"));

                        writeline(output,L);



                    else

                        index := index + 1;

                        real_index(0) := index(3);
                        real_index(1) := index(2);
                        real_index(2) := index(1);
                        real_index(3) := index(0);

                    end if;

                end if;

            end if;

        end if;

    end process;

end behav;
