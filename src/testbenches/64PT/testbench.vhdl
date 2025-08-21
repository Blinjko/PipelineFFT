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

    constant period : time := 83.33 ns;

    -- Julia code used t make this
    -- x = range(0, 2pi, 64)
    -- y = sin.(x*2*pi*3) -- 3Hz sine wave, the numbers below are y
    signal input : real_vector(0 to 127) := (0.0, -- 64
                                             0.0,

                                             0.9525991212465059,
                                             0.0,
                                             
                                            -0.579615396820147,
                                             0.0,

                                            -0.5999282015091771, -- 70
                                             0.0,

                                             0.9446457803526515,
                                             0.0,

                                             0.025152068903555463,
                                             0.0,

                                            -0.9599497272839755,
                                             0.0,

                                             0.5589358540193884,
                                             0.0,

                                             0.6198614156334955, -- 80
                                             0.0,

                                            -0.9360947368931993,
                                             0.0,

                                            -0.05028822342266501,
                                             0.0,

                                             0.9666929475406838,
                                             0.0,

                                            -0.5379026576048608,
                                             0.0,

                                            -0.6394024269171876, -- 90
                                             0.0,

                                             0.9269514013412817,
                                             0.0,

                                             0.07539255924234149, -- 94 -- 16
                                             0.0,

                                            -0.972824515401427,
                                             0.0,

                                             0.5165291158405969,
                                             0.0,

                                             0.658538871241532, -- 100
                                             0.0,

                                            -0.9172215589290247,
                                             0.0,

                                            -0.10044919218012292,
                                             0.0,

                                             0.9783405512597778,
                                             0.0,

                                            -0.49482875233619705,
                                             0.0,

                                            -0.6772586404681058, -- 110
                                             0.0,

                                             0.9069113659870827,
                                             0.0,

                                             0.1254422682364605,
                                             0.0,

                                            -0.9832375649728139,
                                             0.0,

                                             0.4728152974900992,
                                             0.0,

                                             0.6955498900999273, -- 120
                                             0.0,

                                            -0.896027346049356,
                                             0.0,

                                            -0.15035597362590322,
                                             0.0,

                                             0.9875124580694247, -- 126 -- 32
                                             0.0,

                                            -0.4505026798019694,
                                             0.0,

                                            -0.7134010467757901, -- 130
                                             0.0,

                                             0.8845763857253824,
                                             0.0,

                                             0.17517454478295438,
                                             0.0,

                                            -0.991162525710797,
                                             0.0,

                                             0.42790501705978146,
                                             0.0,

                                             0.7308008155930168,
                                             0.0,

                                            -0.872565730342991,
                                             0.0,

                                            -0.19988227833609593,
                                             0.0,

                                             0.9941854584018384,
                                             0.0,

                                            -0.4050366074071131,
                                             0.0,

                                            -0.7477381872540758,
                                             0.0,

                                             0.8600029793640037,
                                             0.0,

                                             0.2244635410437092,
                                             0.0,

                                            -0.9965793434524561,
                                             0.0,

                                             0.3819119202963293,
                                             0.0,

                                             0.7642024450324363,
                                             0.0,

                                            -0.8468960815758326,
                                             0.0,

                                            -0.24890277968561592,
                                             0.0,

                                             0.9983426661877677,
                                             0.0,

                                            -0.35854558733337394,
                                             0.0,

                                            -0.7801831715533328,
                                             0.0,

                                             0.8332533300620845,
                                             0.0,

                                             0.27318453090409184,
                                             0.0,

                                            -0.9994743109064754,
                                             0.0,

                                             0.33495239301996305,
                                             0.0,

                                             0.7956702553851149,
                                             0.0,

                                            -0.8190833569553014,
                                             0.0,

                                            -0.29729343098788946,
                                             0.0,

                                             0.999973561586801,
                                             0.0,

                                            -0.3111472653990361,
                                             0.0,

                                            -0.8106538974370205,
                                             0.0);



    -- Connections
    signal SAMPLE_IN    : std_logic_vector(15 downto 0) := (others => '0');
    signal WE           : std_logic := '0';
    signal OUT_WRITABLE : std_logic := '1';

    signal WRITABLE    : std_logic;
    signal TRANSFORMED : std_logic_vector(15 downto 0);
    signal OUT_WE      : std_logic;


    -- Signals to connect the 64PT to the 32PT
    signal SIXTYFOUR_OUT_WE       : std_logic;
    signal SIXTYFOUR_WRITABLE     : std_logic;
    signal SIXTYFOUR_SAMPLE_OUT   : std_logic_vector(15 downto 0);

    -- Signals to connect the 32PT to the 16PT
    signal THIRTYTWO_OUT_WE       : std_logic;
    signal THIRTYTWO_WRITABLE     : std_logic;
    signal THIRTYTWO_SAMPLE_OUT   : std_logic_vector(15 downto 0);

    -- Signals to connect the 32PT to the 16PT
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

    signal current_out : real;
    signal current_in  : real := 0.0;
    signal sixtyfour_current_out : real;
    signal thirtytwo_current_out : real;

begin

    fpga: entity FPGA_CLOCK port map (CLK => CLK);

    sixtyfour_pt: entity STAGE

        generic map ( n    => 64,
                      head => true)

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => SAMPLE_IN,
                  WE           => WE,
                  OUT_WRITABLE => THIRTYTWO_WRITABLE,
                  SAMPLE_OUT   => SIXTYFOUR_SAMPLE_OUT,
                  OUT_WE       => SIXTYFOUR_OUT_WE,
                  WRITABLE     => WRITABLE);

    thirtytwo_pt: entity STAGE

        generic map ( n    => 32,
                      head => false)

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => SIXTYFOUR_SAMPLE_OUT,
                  WE           => SIXTYFOUR_OUT_WE,
                  OUT_WRITABLE => SIXTEEN_WRITABLE,
                  SAMPLE_OUT   => THIRTYTWO_SAMPLE_OUT,
                  OUT_WE       => THIRTYTWO_OUT_WE,
                  WRITABLE     => THIRTYTWO_WRITABLE);

    sixteen_pt: entity STAGE

        generic map ( n    => 16,
                      head => false)

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => THIRTYTWO_SAMPLE_OUT,
                  WE           => THIRTYTWO_OUT_WE,
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
                  SAMPLE_OUT   => TRANSFORMED,
                  OUT_WE       => OUT_WE,
                  WRITABLE     => TWO_WRITABLE);


    current_out           <= to_real(to_sfixed(TRANSFORMED, high, low));
    sixtyfour_current_out <= to_real(to_sfixed(SIXTYFOUR_SAMPLE_OUT, high, low));
    thirtytwo_current_out <= to_real(to_sfixed(THIRTYTWO_SAMPLE_OUT, high, low));

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

        for sample in 0 to 63 loop

            current_in <= to_real(to_sfixed(input(sample*2), high, low));

            SAMPLE_IN <= to_slv(to_sfixed(input(sample*2), high, low)); -- high and low are from complex_fixed

            while (WRITABLE = '0') loop

                wait for period;

            end loop;

            WE <= '1';

            wait for period;

            WE <= '0';

            write(L, real'image(current_in) & " + ");

            current_in <= to_real(to_sfixed(input(sample*2+1), high, low));

            SAMPLE_IN <= to_slv(to_sfixed(input(sample*2+1), high, low));

            while (WRITABLE = '0') loop

                wait for period;

            end loop;

            WE <= '1';

            wait for period;

            WE <= '0';

            write(L, real'image(current_in) & "im, ");

        end loop;

        write(L, string'("]"));
        writeline(output, L);


        wait for period * 1000;

        std.env.stop;

    end process main;

    -- Capture the output of the 64 point 
    sixfour: process(CLK)

        constant pt : integer := 64;

        variable saved_output : real_vector(0 to 2*pt-1) := (others => 0.0);

        variable index : integer := 0;

        variable current_cycle : integer := 0;

        variable L : line;

        variable even_re : real := 0.0;
        variable even_im : real := 0.0;
        variable odd_re  : real := 0.0;
        variable odd_im  : real := 0.0;
    begin

        if (rising_edge(CLK)) then

            if (SIXTYFOUR_OUT_WE = '1') then

                -- Replicate the stage's read in sequence so we can send out the samples in the right order
                case(current_cycle) is

                    when 0 =>
                        -- Even real
                        even_re := sixtyfour_current_out;
                        current_cycle := 1;

                    when 1 => 

                        -- Odd real
                        odd_re := sixtyfour_current_out;
                        current_cycle := 2;

                    when 2 => 

                        -- Even imag
                        even_im := sixtyfour_current_out;
                        current_cycle := 3;

                    when 3 => 

                        -- odd imag;
                        odd_im := sixtyfour_current_out;

                        -- write to vector
                        saved_output(index) := even_re;
                        index := index + pt;

                        saved_output(index) := odd_re;
                        index := index - pt + 1;

                        saved_output(index) := even_im;
                        index := index + pt;

                        saved_output(index) := odd_im;
                        index := index - pt + 1;


                        -- Cycle finished
                        if (index = pt) then

                            write(L, string'("sixtyfour_pt_output = "));
                            write(L, string'("["));

                            for sample in 0 to pt-1 loop

                                write(L, real'image(saved_output(sample*2)));
                                write(L, string'(" + "));

                                write(L, real'image(saved_output(sample*2+1)));
                                write(L, string'("im, "));

                            end loop;

                            write(L, string'("]"));

                            writeline(output,L);

                            index := 0;
                            
                        end if;

                        current_cycle := 0;

                    when others =>

                        current_cycle := 0;

                end case;

            end if;

        end if;

    end process;

    -- Capture the output of the 32 point 
    threetwo: process(CLK)

        constant pt : integer := 32;

        variable saved_output : real_vector(0 to 2*pt-1) := (others => 0.0);

        variable index : integer := 0;

        variable current_cycle : integer := 0;

        variable L : line;

        variable even_re : real := 0.0;
        variable even_im : real := 0.0;
        variable odd_re  : real := 0.0;
        variable odd_im  : real := 0.0;
    begin

        if (rising_edge(CLK)) then

            if (THIRTYTWO_OUT_WE = '1') then

                -- Replicate the stage's read in sequence so we can send out the samples in the right order
                case(current_cycle) is

                    when 0 =>
                        -- Even real
                        even_re := thirtytwo_current_out;
                        current_cycle := 1;

                    when 1 => 

                        -- Odd real
                        odd_re := thirtytwo_current_out;
                        current_cycle := 2;

                    when 2 => 

                        -- Even imag
                        even_im := thirtytwo_current_out;
                        current_cycle := 3;

                    when 3 => 

                        -- odd imag;
                        odd_im := thirtytwo_current_out;

                        -- write to vector
                        saved_output(index) := even_re;
                        index := index + pt;

                        saved_output(index) := odd_re;
                        index := index - pt + 1;

                        saved_output(index) := even_im;
                        index := index + pt;

                        saved_output(index) := odd_im;
                        index := index - pt + 1;


                        -- Cycle finished
                        if (index = pt) then

                            write(L, string'("thirtytwo_pt_output = "));
                            write(L, string'("["));

                            for sample in 0 to pt-1 loop

                                write(L, real'image(saved_output(sample*2)));
                                write(L, string'(" + "));

                                write(L, real'image(saved_output(sample*2+1)));
                                write(L, string'("im, "));

                            end loop;

                            write(L, string'("]"));

                            writeline(output,L);

                            index := 0;
                            
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
        variable real_index : unsigned(5 downto 0);

        variable even_real : real := 0.0;
        variable even_imag : real := 0.0;
        variable odd_real  : real := 0.0;
        variable odd_imag  : real := 0.0;
        

        variable saved_output : real_vector(0 to 127) := (others => 0.0);

        variable index : unsigned(5 downto 0) := to_unsigned(0, 6);

        variable cycle : integer := 0;

        variable L : line;
    begin

        if (rising_edge(CLK)) then

            if (OUT_WE = '1') then

                case (cycle) is
                    when 0 =>
                        even_real := current_out;
                        cycle := 1;

                    when 1 =>
                        odd_real := current_out;
                        cycle := 2;

                    when 2 =>
                        even_imag := current_out;
                        cycle := 3;

                    when 3 =>
                        odd_imag := current_out;
                        cycle := 4;

                    when others =>
                        cycle := 0;

                end case;

                if (cycle = 4) then

                    cycle := 0;

                    saved_output(to_integer(real_index)*2) := even_real;
                    saved_output(to_integer(real_index)*2+1) := even_imag;

                    index := index + 1;

                    real_index(0) := index(5);
                    real_index(1) := index(4);
                    real_index(2) := index(3);
                    real_index(3) := index(2);
                    real_index(4) := index(1);
                    real_index(5) := index(0);

                    saved_output(to_integer(real_index)*2)   := odd_real;
                    saved_output(to_integer(real_index)*2+1) := odd_imag;


                    if (index = 63) then

                        write(L, string'("final_output = "));
                        write(L, string'("["));

                        for sample in 0 to 63 loop

                            write(L, real'image(saved_output(sample*2)));
                            write(L, string'(" + "));

                            write(L, real'image(saved_output(sample*2+1)));
                            write(L, string'("im, "));

                        end loop;

                        write(L, string'("]"));

                        writeline(output,L);



                    else

                        index := index + 1;

                        real_index(0) := index(5);
                        real_index(1) := index(4);
                        real_index(2) := index(3);
                        real_index(3) := index(2);
                        real_index(4) := index(1);
                        real_index(5) := index(0);

                    end if;

                end if;

            end if;

        end if;

    end process;

end behav;
