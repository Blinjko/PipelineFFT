-- Code for the pipeline stages of the FFT
-- There is only one entity with conditional generations that tune what is generated based on the values of the given generics
-- Currently it supports up to 64 a 64 point pipeline stage, I only went this high because I was using the Lattice ICE40 Hx1k
   -- BRAM sizes of 4k (16x256) as my constraint.

-- Should you want high number stages, this is what you need to do.
-- 1. Add an if-generate for the BRAM of that stage, each PT (2PT, 4PT, 8PT, ..etc) has a different memory generation because 
   -- The twiddles need to be pre-programmed into them.
-- 2. Add the twiddles to the pre-program vector, use the other, already existing ones for reference.
   -- Quick tip: the entries are alternating real and imaginary components, so make sure to split them
   -- Also, this is the main line you will use, to_slv( to_sfixed(YOUR_NUMBER, high, low)),  make sure to end with others => (others => '0');

-- Thats all that should be needed should you want to add another, higher number stage, just don't forget that your memory has to be able to support
-- the size.
-- For reference here is the calculation of the minimum number of spots you will need. pt_num*3
-- Assume n = pt_num then,
-- Then [0 to n) will be the twiddles, [n, 3n) will be the working buffer
-- Make sure your address width is large enough too!


-- The head of the FFT, i.e the first stage has to write the samples into the buffer differently, hence the head boolean parameter.
-- Only your first stage should be a head, the rest are not head stages, they are normal.

library ieee;
use ieee.std_logic_1164.all;
use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;
use ieee.numeric_std.all;

library complex;
use complex.complex_fixed_pkg.all;

library fft;
use fft.all;

entity STAGE is
    generic (
                n           : integer := 4;     -- What PT is this stage, 8PT, 4PT, 16PT? 
                head        : boolean := false; -- Is this the head stage i.e the one that will recieve the samples from the ADC, not anonther stage?
                data_width  : integer := 16;    -- Bit-width of a datapiece in BRAM
                addr_width  : integer := 8;     -- Address width for the BRAM
                buffer_size : integer := 256    -- Length of the BRAM buffer, i.e how many spots the BRAM has the the given data_width

            );

    port (CLK          : in  std_logic;
          RST          : in  std_logic;
          SAMPLE_IN    : in  std_logic_vector(15 downto 0);
          WE           : in  std_logic;
          OUT_WRITABLE : in  std_logic; -- is the output buffer full, i.e can I send this data out?
          SAMPLE_OUT   : out std_logic_vector(15 downto 0);
          OUT_WE       : out std_logic;
          WRITABLE     : out std_logic); -- is the input buffer full, i.e can the sender give me data or do they need to wait.
end STAGE;
          

architecture behav of STAGE is

    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin Constants --
    
    constant addr_offset : unsigned(addr_width-1 downto 0) := to_unsigned(n, addr_width); -- Offset to account for twiddles. Each twiddle takes 4 addresses

    type ram_type is array (0 to buffer_size - 1) of std_logic_vector(data_width - 1 downto 0);
    subtype preprogram_type is std_logic_vector(data_width*buffer_size -1 downto 0);

    -- End Constants  --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin Functions --

    function log_two (x : integer) return integer is

        variable temp   : integer := x;
        variable result : integer := 0;

    begin
        while (temp >= 2) loop
            temp := temp / 2;
            result := result + 1;
        end loop;

        return result;

    end function log_two;

    function pack_preprogram_vector (values : ram_type) return preprogram_type is

       variable data : preprogram_type := (others => '0'); 

       variable upper : integer := data_width - 1;
       variable lower : integer := 0;

    begin

        for addr in 0 to buffer_size - 1 loop
            
            data(upper downto lower) := values(addr);

            upper := upper + 16;
            lower := lower + 16;

        end loop;

        return data;

    end function pack_preprogram_vector;

    

    -- End Functions --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin control registers --

    signal computations_avail : unsigned(log_two(n) downto 0); -- Need to hold at least n computations, 
    signal writable_spots     : unsigned(log_two(n) downto 0); -- Keeps track of the amount of writable spots we have

    -- End control registers --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin control signals --

    signal RE       : std_logic;                     -- Read Enable signal for BRAM
    signal ram_addr : std_logic_vector(addr_width-1 downto 0);  -- The actual read address connected to the BRAM

    -- End control signals --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin address registers

    signal Waddr : unsigned(addr_width-1 downto 0); -- the next write address, directly connected to the BRAM
    signal Raddr : unsigned(addr_width-1 downto 0); -- the next read address for samples
    signal Taddr : unsigned(addr_width-1 downto 0); -- the next read address for twiddles

    -- End address registers
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin state control signals --

    type state_type is (COMP_WAIT,EVEN_RE,ODD_RE,EVEN_IM,ODD_IM,TWID_RE,TWID_IM,EVEN_OUT_RE,ODD_OUT_RE,EVEN_OUT_IM,ODD_OUT_IM);
    signal ps, ns : state_type; -- ps -> present state, ns -> next state

    -- End state control signals --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin Compute Input Registers and Butterfly / BRAM connections --

    -- Connection for the BRAM output data
    signal Rdata : std_logic_vector(data_width-1 downto 0);

    -- Registers for the even,odd, and twiddle inputs to the butterfly unit
    signal even,odd,twiddle : complex_fixed;

    -- Butterfly Unit output connections
    signal butt_out_even, butt_out_odd : complex_fixed;

    -- End Compute Input Registers and Butterfly connections --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------

begin
    -- Butterfly Declaration
    butt: entity butterfly port map (
                                     EVEN    => even,
                                     ODD     => odd,
                                     TWIDDLE => twiddle,
                                     OUT_A   => butt_out_even,
                                     OUT_B   => butt_out_odd);


    -- Begin conditional Generates for the pre-programmed memories --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin 64PT BRAM --

    sixtyfour_pt_mem: if (n = 64) generate
        -- the twiddles needed for the 64_pt
        constant pre_program : ram_type := ( 
                                            to_slv ( to_sfixed (1.0, high, low) ), -- Real 
                                            to_slv ( to_sfixed (-0.0, high, low) ),-- Imag

                                            to_slv ( to_sfixed(0.9951847266721969, high, low) ),
                                            to_slv ( to_sfixed(-0.0980171403295606, high, low) ),

                                            to_slv ( to_sfixed(0.9807852804032304, high, low) ),
                                            to_slv ( to_sfixed(-0.19509032201612825, high, low) ),

                                            to_slv ( to_sfixed(0.9569403357322088, high, low) ),
                                            to_slv ( to_sfixed(-0.29028467725446233, high, low) ),

                                            to_slv ( to_sfixed(0.9238795325112867, high, low) ),
                                            to_slv ( to_sfixed(-0.3826834323650898, high, low) ),

                                            to_slv ( to_sfixed(0.881921264348355, high, low) ),
                                            to_slv ( to_sfixed(-0.47139673682599764, high, low) ),

                                            to_slv ( to_sfixed(0.8314696123025452, high, low) ),
                                            to_slv ( to_sfixed(-0.5555702330196022, high, low) ),

                                            to_slv ( to_sfixed(0.773010453362737, high, low) ),
                                            to_slv ( to_sfixed(-0.6343932841636455, high, low) ),

                                            to_slv ( to_sfixed(0.7071067811865476, high, low) ),
                                            to_slv ( to_sfixed(-0.7071067811865475, high, low) ),

                                            to_slv ( to_sfixed(0.6343932841636455, high, low) ),
                                            to_slv ( to_sfixed(-0.7730104533627369, high, low) ),

                                            to_slv ( to_sfixed(0.5555702330196023, high, low) ),
                                            to_slv ( to_sfixed(-0.8314696123025452, high, low) ),

                                            to_slv ( to_sfixed(0.4713967368259978, high, low) ),
                                            to_slv ( to_sfixed(-0.8819212643483549, high, low) ),

                                            to_slv ( to_sfixed(0.38268343236508984, high, low) ),
                                            to_slv ( to_sfixed(-0.9238795325112867, high, low) ),

                                            to_slv ( to_sfixed(0.29028467725446233, high, low) ),
                                            to_slv ( to_sfixed(-0.9569403357322089, high, low) ),

                                            to_slv ( to_sfixed(0.19509032201612833, high, low) ),
                                            to_slv ( to_sfixed(-0.9807852804032304, high, low) ),

                                            to_slv ( to_sfixed(0.09801714032956077, high, low) ),
                                            to_slv ( to_sfixed(-0.9951847266721968, high, low) ),

                                            to_slv ( to_sfixed(0.0, high, low) ),
                                            to_slv ( to_sfixed(-1.0, high, low) ),

                                            to_slv ( to_sfixed(-0.09801714032956065, high, low) ),
                                            to_slv ( to_sfixed(-0.9951847266721969, high, low) ),

                                            to_slv ( to_sfixed(-0.1950903220161282, high, low) ),
                                            to_slv ( to_sfixed(-0.9807852804032304, high, low) ),

                                            to_slv ( to_sfixed(-0.29028467725446216, high, low) ),
                                            to_slv ( to_sfixed(-0.9569403357322089, high, low) ),

                                            to_slv ( to_sfixed(-0.3826834323650897, high, low) ),
                                            to_slv ( to_sfixed(-0.9238795325112867, high, low) ),

                                            to_slv ( to_sfixed(-0.4713967368259977, high, low) ),
                                            to_slv ( to_sfixed(-0.881921264348355, high, low) ),

                                            to_slv ( to_sfixed(-0.555570233019602, high, low) ),
                                            to_slv ( to_sfixed(-0.8314696123025453, high, low) ),

                                            to_slv ( to_sfixed(-0.6343932841636454, high, low) ),
                                            to_slv ( to_sfixed(-0.7730104533627371, high, low) ),

                                            to_slv ( to_sfixed(-0.7071067811865475, high, low) ),
                                            to_slv ( to_sfixed(-0.7071067811865476, high, low) ),

                                            to_slv ( to_sfixed(-0.773010453362737, high, low) ),
                                            to_slv ( to_sfixed(-0.6343932841636455, high, low) ),

                                            to_slv ( to_sfixed(-0.8314696123025453, high, low) ),
                                            to_slv ( to_sfixed(-0.5555702330196022, high, low) ),

                                            to_slv ( to_sfixed(-0.8819212643483549, high, low) ),
                                            to_slv ( to_sfixed(-0.47139673682599786, high, low) ),

                                            to_slv ( to_sfixed(-0.9238795325112867, high, low) ),
                                            to_slv ( to_sfixed(-0.3826834323650899, high, low) ),

                                            to_slv ( to_sfixed(-0.9569403357322088, high, low) ),
                                            to_slv ( to_sfixed(-0.2902846772544624, high, low) ),

                                            to_slv ( to_sfixed(-0.9807852804032304, high, low) ),
                                            to_slv ( to_sfixed(-0.1950903220161286, high, low) ),

                                            to_slv ( to_sfixed(-0.9951847266721968, high, low) ),
                                            to_slv ( to_sfixed(-0.09801714032956083, high, low) ),

                                            others => (others => '0'));
begin

        ram_buff: entity bram

        generic map (
            pre_program => pack_preprogram_vector(pre_program),
            data_width  => data_width,
            addr_width  => addr_width,
            buffer_size => buffer_size
        )

        port map (
            clk   => clk,
            we    => we,
            re    => re,
            waddr => std_logic_vector(waddr),
            wdata => sample_in,
            raddr => ram_addr,
            rdata => rdata);

    end generate sixtyfour_pt_mem;

    -- End 64PT BRAM --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin 32PT BRAM --

    thirtytwo_pt_mem: if (n = 32) generate
        -- the twiddles needed for the 32_pt
        constant pre_program : ram_type := ( 
                                            to_slv ( to_sfixed (1.0, high, low) ), 
                                            to_slv ( to_sfixed (-0.0, high, low) ), 

                                            to_slv ( to_sfixed (0.9807852804032304, high, low) ), 
                                            to_slv ( to_sfixed (-0.19509032201612825, high, low) ), 

                                            to_slv ( to_sfixed (0.9238795325112867, high, low) ), 
                                            to_slv ( to_sfixed (-0.3826834323650898, high, low) ), 

                                            to_slv ( to_sfixed (0.8314696123025452, high, low) ), 
                                            to_slv ( to_sfixed (-0.5555702330196022, high, low) ), 

                                            to_slv ( to_sfixed (0.7071067811865476, high, low) ), 
                                            to_slv ( to_sfixed (-0.7071067811865475, high, low) ), 

                                            to_slv ( to_sfixed (0.5555702330196023, high, low) ), 
                                            to_slv ( to_sfixed (-0.8314696123025452, high, low) ), 

                                            to_slv ( to_sfixed (0.38268343236508984, high, low) ), 
                                            to_slv ( to_sfixed (-0.9238795325112867, high, low) ), 

                                            to_slv ( to_sfixed (0.19509032201612833, high, low) ), 
                                            to_slv ( to_sfixed (-0.9807852804032304, high, low) ), 

                                            to_slv ( to_sfixed (0.0, high, low) ), 
                                            to_slv ( to_sfixed (-1.0, high, low) ), 

                                            to_slv ( to_sfixed (-0.1950903220161282, high, low) ), 
                                            to_slv ( to_sfixed (-0.9807852804032304, high, low) ), 

                                            to_slv ( to_sfixed (-0.3826834323650897, high, low) ), 
                                            to_slv ( to_sfixed (-0.9238795325112867, high, low) ), 

                                            to_slv ( to_sfixed (-0.555570233019602, high, low) ), 
                                            to_slv ( to_sfixed (-0.8314696123025453, high, low) ), 

                                            to_slv ( to_sfixed (-0.7071067811865475, high, low) ), 
                                            to_slv ( to_sfixed (-0.7071067811865476, high, low) ), 

                                            to_slv ( to_sfixed (-0.8314696123025453, high, low) ), 
                                            to_slv ( to_sfixed (-0.5555702330196022, high, low) ), 

                                            to_slv ( to_sfixed (-0.9238795325112867, high, low) ), 
                                            to_slv ( to_sfixed (-0.3826834323650899, high, low) ), 

                                            to_slv ( to_sfixed (-0.9807852804032304, high, low) ), 
                                            to_slv ( to_sfixed (-0.1950903220161286, high, low) ), 

                                            others => (others => '0'));
    begin

        ram_buff: entity bram

        generic map (
            pre_program => pack_preprogram_vector(pre_program),
            data_width  => data_width,
            addr_width  => addr_width,
            buffer_size => buffer_size
        )

        port map (
            clk   => clk,
            we    => we,
            re    => re,
            waddr => std_logic_vector(waddr),
            wdata => sample_in,
            raddr => ram_addr,
            rdata => rdata);

    end generate thirtytwo_pt_mem;

    -- End 32PT BRAM --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin 16PT BRAM --

    sixteen_pt_mem: if (n = 16) generate
        -- the twiddles needed for the 16_pt
        constant pre_program : ram_type := ( 
                                            to_slv ( to_sfixed (1.0, high, low) ), -- Real 
                                            to_slv ( to_sfixed (-0.0, high, low) ),-- Imag

                                            to_slv ( to_sfixed (0.9238795325112867, high, low) ),
                                            to_slv ( to_sfixed (-0.3826834323650898, high, low) ),

                                            to_slv ( to_sfixed (0.7071067811865476, high, low) ),
                                            to_slv ( to_sfixed (-0.7071067811865475, high, low) ),

                                            to_slv ( to_sfixed (0.38268343236508984, high, low) ),
                                            to_slv ( to_sfixed (-0.9238795325112867, high, low) ),

                                            to_slv ( to_sfixed (0.0, high, low) ),
                                            to_slv ( to_sfixed (-1.0, high, low) ),

                                            to_slv ( to_sfixed (-0.3826834323650897, high, low) ),
                                            to_slv ( to_sfixed (-0.9238795325112867, high, low) ),

                                            to_slv ( to_sfixed (-0.7071067811865475, high, low) ),
                                            to_slv ( to_sfixed (-0.7071067811865476, high, low) ),

                                            to_slv ( to_sfixed (-0.9238795325112867, high, low) ),
                                            to_slv ( to_sfixed (-0.3826834323650899, high, low) ),

                                            others => (others => '0'));
    begin

        ram_buff: entity bram

        generic map (
            pre_program => pack_preprogram_vector(pre_program),
            data_width  => data_width,
            addr_width  => addr_width,
            buffer_size => buffer_size
        )

        port map (
            clk   => clk,
            we    => we,
            re    => re,
            waddr => std_logic_vector(waddr),
            wdata => sample_in,
            raddr => ram_addr,
            rdata => rdata);

    end generate sixteen_pt_mem;

    -- End 16PT BRAM --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin 8PT BRAM --

    eight_pt_mem: if (n = 8) generate
        -- the twiddles needed for the eight_pt
        constant pre_program : ram_type := ( 

                             to_slv( to_sfixed(1.0, high, low) ),  -- real
                             to_slv( to_sfixed(0.0, high, low) ),  -- imaginary

                             to_slv( to_sfixed(0.7071067811865476, high, low) ),
                             to_slv( to_sfixed(-0.7071067811865475, high, low) ),

                             to_slv( to_sfixed(0.0, high, low) ),
                             to_slv( to_sfixed(-1.0, high, low) ),
  
                             to_slv( to_sfixed(-0.7071067811865475, high, low) ),
                             to_slv( to_sfixed(-0.7071067811865476, high, low) ), 

                             others => (others => '0'));


    begin

        ram_buff: entity bram

        generic map (
            pre_program => pack_preprogram_vector(pre_program),
            data_width  => data_width,
            addr_width  => addr_width,
            buffer_size => buffer_size
        )

        port map (
            clk   => clk,
            we    => we,
            re    => re,
            waddr => std_logic_vector(waddr),
            wdata => sample_in,
            raddr => ram_addr,
            rdata => rdata);

    end generate eight_pt_mem;

    -- End 8PT BRAM --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin 4PT BRAM --

    four_pt_mem: if (n = 4) generate
        -- The twiddles needed for the four_pt
        constant pre_program : ram_type := (

                              to_slv( to_sfixed(1.0, high, low) ), -- Real
                              to_slv( to_sfixed(0.0, high, low) ), -- Imag

                              to_slv( to_sfixed(0.0, high, low) ),
                              to_slv( to_sfixed(-1.0,high, low) ),
                            
                              others => (others => '0'));



    begin

        ram_buff: entity BRAM

        generic map (
            pre_program => pack_preprogram_vector(pre_program),
            data_width  => data_width,
            addr_width  => addr_width,
            buffer_size => buffer_size
        )

        port map (
            CLK   => CLK,
            WE    => WE,
            RE    => RE,
            WADDR => std_logic_vector(Waddr),
            WDATA => SAMPLE_IN,
            RADDR => ram_addr,
            RDATA => Rdata);

    end generate four_pt_mem;

    -- End 4PT BRAM --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin 2PT BRAM --

    two_pt_mem: if (n = 2) generate
        -- The twiddles needed for the four_pt
        constant pre_program : ram_type := (

                              to_slv( to_sfixed(1.0, high, low) ), -- Real
                              to_slv( to_sfixed(0.0, high, low) ), -- Imag

                              others => (others => '0'));


    begin

        ram_buff: entity BRAM

        generic map (
            pre_program => pack_preprogram_vector(pre_program),
            data_width  => data_width,
            addr_width  => addr_width,
            buffer_size => buffer_size
        )

        port map (
            CLK   => CLK,
            WE    => WE,
            RE    => RE,
            WADDR => std_logic_vector(Waddr),
            WDATA => SAMPLE_IN,
            RADDR => ram_addr,
            RDATA => Rdata);

    end generate two_pt_mem;


    -- End 2PT BRAM --
    -- End If-Generates for BRAM --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin Signal Assignments --

    WRITABLE <= '1' when writable_spots > 0 else '0'; -- All alone :(

    -- End Signal Assingments --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin [Head Stage] Logic

    head_stage_logic: if (head = true) generate
    begin

    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- [Head Stage] Begin write address (Waddr) sequence logic --

    write_addr_proc: process(CLK)
    begin

        if (rising_edge(CLK)) then

            if (RST = '1') then

                Waddr <= addr_offset;

            else

                if (WE = '1') then

                -- Head stage writes data sequentially in memory

                -- If were at the end wrap around to the start
                    if (Waddr = addr_offset + 4*n-1) then

                        Waddr <= addr_offset;


                -- Otherwise just go to the next address
                    else

                        Waddr <= Waddr + 1;

                    end if;

                end if;
            end if;

        end if;

    end process write_addr_proc;

    -- [Head Stage] End write address (Waddr) sequence logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- [Head Stage] Begin computations available register Logic --

    computations_avail_proc: process(CLK)
    begin

        if (rising_edge(CLK)) then

            if (RST = '1') then

                computations_avail <= to_unsigned(0, log_two(n)+1);

            else
                -- If were writing
                if (WE = '1') then 

                    -- If were on an odd address (i.e we are writing the last part of a sample)
                    -- and there is not a computation finishing
                    -- and Waddr is past the first half of the buffer
                    if (Waddr(0) = '1' and                                           -- Tells us we are writing the imaginary part
                        Waddr > (n + addr_offset) and                                -- Tells us if we are past the first half 
                        ps /= TWID_IM) then                                          -- Make sure there is no simultaneous computation

                        computations_avail <= computations_avail + 1;


                    -- If were on an odd address (i.e we are writing the last part of a sample)
                    -- and there is a computation finishing
                    -- and Waddr is past the first half of the buffer
                    elsif (Waddr(0) = '1' and                                           -- Tells us we are writing the imaginary part
                           Waddr > (n + addr_offset) and                                -- Tells us if we are past the first half 
                           ps = TWID_IM) then                                           -- Make sure there is a simultaneous computation

                        computations_avail <= computations_avail;

                    -- A finished compute happens while were writing, but were still not ready to add a computation yet.
                    elsif (ps = TWID_IM) then

                        computations_avail <= computations_avail - 1;

                    end if;

                -- Were not writing
                else
                    
                    if (ps = TWID_IM) then
                        computations_avail <= computations_avail - 1;
                    end if;

                end if;

            end if;

        end if;

    end process computations_avail_proc;

    -- [Head Stage] End computations available register Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- [Head Stage] Begin writable spots register Logic  --

    writable_spots_proc: process(CLK)
    begin

        if (rising_edge(CLK)) then

            if (RST = '1') then

                writable_spots <= to_unsigned(n, log_two(n)+1);
            --writable_spots <= to_unsigned(8, 4);

            else

                -- If we are finisning writing a sample to the buffer and there is no simultaneous read finising
                if (WE = '1' and Waddr(0) = '1' and (ps /= EVEN_IM and ps /= ODD_RE)) then

                    writable_spots <= writable_spots - 1;

                -- Condition where we are finishing writing a sample and a simultaneous read is finishing
                elsif (WE = '1' and Waddr(0) = '1' and (ps = EVEN_IM or ps = ODD_RE)) then

                    -- Executes on last computation cycle EVEN_IM, where the last value 
                    -- in the first half is read, exposing all the free spots in the second half.
                    if (Raddr = (addr_offset + (n-1)) and ps = ODD_RE) then

                        writable_spots <= writable_spots + (n/2)- 1; -- Minus one due to the simultaneous read and write

                    -- Executes on the last computation cycle ODD_IM, where the last value in the buffer is read.
                    elsif (Raddr = (addr_offset + 2*n - 1) and ps = EVEN_IM) then

                        writable_spots <= writable_spots; -- No net change since simultaneous read and write.

                    elsif (Raddr < (addr_offset + n - 1) and ps = ODD_RE) then

                        writable_spots <= writable_spots; -- No net change since simultaneous read and write.

                    -- None of the above conditions executed (is possible if were on EVEN_IM but it's only condition above is not satisfied)
                    else

                        writable_spots <= writable_spots - 1;

                    end if;

                -- Writing and reading, but no collision since we are not finishing a sample write
                elsif (WE = '1' and Waddr(0) = '0' and (ps = EVEN_IM or ps = ODD_RE)) then

                    -- Executes on last computation cycle EVEN_IM, where the last value 
                    -- in the first half is read, exposing all the free spots in the second half.
                    if (Raddr = (addr_offset + (n-1)) and ps = ODD_RE) then

                        writable_spots <= writable_spots + (n/2);

                    -- Executes on the last computation cycle ODD_IM, where the last value in the buffer is read.
                    elsif (Raddr = (addr_offset + 2*n - 1) and ps = EVEN_IM) then

                        writable_spots <= writable_spots + 1;

                    elsif (Raddr < (addr_offset + n - 1) and ps = ODD_RE) then

                        writable_spots <= writable_spots + 1;

                    end if;

                -- Not writing so no simultaneous read write possible
                elsif (WE = '0' and (ps = EVEN_IM or ps = ODD_RE)) then

                    -- Executes on last computation cycle EVEN_IM, where the last value 
                    -- in the first half is read, exposing all the free spots in the second half.
                    if (Raddr = (addr_offset + (n-1)) and ps = ODD_RE) then

                        writable_spots <= writable_spots + (n/2);

                    -- Executes on the last computation cycle ODD_IM, where the last value in the buffer is read.
                    elsif (Raddr = (addr_offset + 2*n - 1) and ps = EVEN_IM) then

                        writable_spots <= writable_spots + 1;

                    elsif (Raddr < (addr_offset + n - 1) and ps = ODD_RE) then

                        writable_spots <= writable_spots + 1;

                    end if;


                end if;

            end if;

    end if;

end process writable_spots_proc;

    -- [Head Stage] End writable spots register Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------

    end generate head_stage_logic;

    -- End [Head Stage] Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin [Normal Stage] Logic --

    normal_stage_logic: if (head = false) generate
    begin

    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- [Normal Stage] Begin write address (Waddr) sequence logic --

    write_addr_proc: process(CLK)
    begin

        if (rising_edge(CLK)) then

            if (RST = '1') then

                Waddr <= addr_offset;

            else

                if (WE = '1') then

                    -- Are we writing an even? Always true if the address is < 2*n + offset, b/c all the odd reside at addrs >= 2*n + offset
                    if (Waddr < (2*n + addr_offset)) then

                        -- Update the address so that next time were writing an odd
                        Waddr <= Waddr + 2*n;

                    -- Must be writing an odd
                    else

                        -- Check if were at the end and need to wrap around
                        if (Waddr = (addr_offset + 4*n - 1)) then

                            Waddr <= addr_offset;

                        else
                            -- Otherwise go back to the next address on the even side
                            Waddr <= Waddr - 2*n + 1;

                        end if;

                    end if;

                end if;
            end if;

        end if;

    end process write_addr_proc;

    -- [Normal Stage] End write address (Waddr) sequence logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- [Normal Stage] Begin writeable spots register Logic --

    writeable_spots_proc: process(CLK)
    begin

        if (rising_edge(CLK)) then

            if (RST = '1') then

                writable_spots <= to_unsigned(n, log_two(n)+1);

            else

                -- Conditions that can occur  --
                -- There are 4 differet cases here
                -- 1. We are finishing writing a sample only - no simultaneous read finising
                -- 2. We are finishing writing a writing and there is a simultaneous read finishing
                -- 3. We are writing, but not finished writing a sample and there is a computation finishing
                -- 4. We are not writing and there is a computation finishing

                -- If we are finising a write, accounts for condition 1
                if (WE = '1' and Waddr(0) = '1' and Waddr > (addr_offset + 2*n) and ps /= EVEN_IM) then 

                    writable_spots <= writable_spots - 1;

                -- Simultaneous write finish and read finish, condition 2
                elsif (WE = '1' and Waddr(0) = '1' and Waddr > (addr_offset + 2*n) and ps = EVEN_IM) then 

                    -- If we are at the end of the buffer
                    if (Raddr = (addr_offset + 4*n - 1)) then

                        writable_spots <= writable_spots + (n/2);

                    elsif (Raddr > (addr_offset + 2*n)) then

                        writable_spots <= writable_spots; -- Stays the same because we add 1 then subtract 1

                    end if;

                -- We are not finished writing but finished a read -- condition 3
                -- We are not writing but a read finished -- condition 4
                elsif ((WE = '1' or WE = '0') and ps = EVEN_IM) then 

                    -- If we are at the end of the buffer
                    if (Raddr = (addr_offset + 4*n - 1)) then

                        writable_spots <= writable_spots + (n/2) + 1;

                    elsif (Raddr > (addr_offset + 2*n)) then

                        writable_spots <= writable_spots + 1;

                    end if;

                end if;

            end if;

        end if;

    end process writeable_spots_proc;

    -- [Normal Stage] End writeable_spots register Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- [Normal Stage] Begin computations available register Logic  --

    computations_avail_proc: process(CLK)
    begin

        if (rising_edge(CLK)) then

            if (RST = '1') then

                computations_avail <= to_unsigned(0, log_two(n)+1);

            else

                -- If Data is being written into the buffer
                if (WE = '1') then

                    -- The buffer will be filled on this write
                    if (Waddr = (addr_offset + 4*n - 1)) then

                        -- Simultaneously, a computation gets finished
                        if (ps = TWID_IM) then

                            computations_avail <= computations_avail + (n/2);

                        -- No Simultaneous finished computation
                        else

                            computations_avail <= computations_avail + (n/2) + 1;

                        end if;


                    -- Have we written half the samples and are about to finish writing another?
                    -- Waddr(0) = '1' Tells us that we are on the imaginary component (which is always the last part to be written)
                    -- Waddr > 3*n    Tells us that we are writing and ODD, and that the buffer is at least half full.
                        -- (i.e every new set of samples we write means we can do a computation)
                    -- ps /= TWID_IM  Tells us that a simultaneous computation is not finishing, i.e
                    -- it is safe to increment the buffer by 1, because if a computation was finishing this cycle,
                    -- then it would be a + 1 and -1, i.e no net change so do nothing, hence why you don't see that
                    -- branch here :)
                    elsif (Waddr(0) = '1' and Waddr > (addr_offset + 3*n) and ps /= TWID_IM) then

                        computations_avail <= computations_avail + 1;

                    -- A simultaneous computation finishes as we are ready to increment so stay the same
                    elsif (Waddr(0) = '1' and Waddr > (addr_offset + 3*n) and ps = TWID_IM) then

                        computations_avail <= computations_avail;

                    -- Condition where a computation finishes while there is writing happening, but were also not ready to add a computation yet
                    -- So it doesn't overlap with the writers increment.
                    elsif (ps = TWID_IM) then

                        computations_avail <= computations_avail - 1;

                    end if;


                -- Data is not being written into the buffer
                -- And we are finishing a computation
                elsif (ps = TWID_IM) then

                    -- Simultaneous Write and Compute not possible then
                    -- So decrement the number of computations available since we just finishd one
                    computations_avail <= computations_avail - 1;

                end if;

            end if;

        end if;

    end process computations_avail_proc;

    -- [Normal Stage] End computations available register Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------

    end generate normal_stage_logic;
    
    -- End [Normal Stage] Logic  --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin Raddr sequence control Logic --

    Raddr_proc: process(CLK)
    begin
        if (rising_edge(CLK)) then

            if (RST = '1') then

                Raddr <= addr_offset;

            else

                if (ps = COMP_WAIT and computations_avail > 0) then

                    -- We need to read an odd next so jump to the odd half
                    Raddr <= Raddr + n;

                elsif (ps = EVEN_RE) then

                    Raddr <= Raddr - n + 1;

                elsif (ps = ODD_RE) then

                    Raddr <= Raddr + n;

                elsif (ps = ODD_IM) then

                    -- If we are about to complete the first compute cycle
                    -- Then we have to reset and jump to the odd half of the samples in the buffer
                    -- to run the computations on those
                    -- NOTE: the nead unit does not have more than 1 compute cycle
                    if (Raddr = (addr_offset + 2*n - 1) and head = false) then

                        -- Only adding 1 here since we are already at the end of the even samples in the buffer,
                        -- and the odd samples are put in the other half directly after the even samples, so
                        -- all we need to do is simply go to the next address
                        Raddr <= Raddr + 1; -- Jump to next half

                    -- If we are reading the last sample out (i.e we just finished the second computation cycle)
                    elsif ((Raddr = (addr_offset + 4*n - 1) and head = false) or
                           (Raddr = (addr_offset + 2*n - 1) and head = true)) then -- Head stages only have one compute cycle so we wrap around earlier

                        -- Reset the address to its start
                        Raddr <= addr_offset;

                    -- The not special condition, i.e we are not at the end of the first computation or second computation cycle
                    else

                        -- So just go to the next even samples real part.
                        Raddr <= Raddr - n + 1;

                    end if;

                end if;

            end if;

        end if;

     end process Raddr_proc;

     -- End Raddr sequence control Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
     -- Begin Taddr increment Logic --

     Taddr_proc: process(CLK)
     begin

         if (rising_edge(CLK)) then

             if (RST = '1') then

                 Taddr <= (others => '0');

             else

                 -- If we are reading a twiddle
                 if (ps = TWID_RE or ps = ODD_IM) then

                     -- If were at the last twiddle
                     if (Taddr = (addr_offset - 1)) then

                         -- Reset addr to the start of the twiddles (which is the start of the buffer)

                         Taddr <= (others => '0');

                    -- Were somewhere in the middle
                     else

                         -- So just increment normally
                         Taddr <= Taddr + 1;

                         -- Unlike the samples, the twiddles are just written sequentially in the order they are needed

                     end if;

                 end if;

            end if;

        end if;

    end process Taddr_proc;


    -- End Taddr increment Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin Read / Compute Logic

    read_proc: process(CLK)
    begin

        if (rising_edge(CLK)) then

            if (RST = '1') then

                even.re <= to_sfixed(0.0, high, low);
                even.im <= to_sfixed(0.0, high, low);

                odd.re <= to_sfixed(0.0, high, low);
                odd.im <= to_sfixed(0.0, high, low);

                twiddle.re <= to_sfixed(0.0, high, low);
                twiddle.im <= to_sfixed(0.0, high, low);

                ps <= COMP_WAIT;

            else

                -- If were reading an even sample
                if (ps = EVEN_RE) then

                        even.re <= to_sfixed(Rdata, high, low);

                elsif (PS = EVEN_IM) then

                        even.im <= to_sfixed(Rdata, high, low);

                -- If were reading an odd sample
                elsif (ps = ODD_RE) then

                        odd.re <= to_sfixed(Rdata, high, low);

                elsif (ps = ODD_IM) then

                        odd.im <= to_sfixed(Rdata, high, low);

                -- If were reading a twiddle
                elsif (ps = TWID_RE) then

                        twiddle.re <= to_sfixed(Rdata, high, low);

                elsif (ps = TWID_IM) then

                        twiddle.im <= to_sfixed(Rdata, high, low);
                end if;

                ps <= ns; -- Don't forget to change the state :)

            end if;

        end if;

    end process read_proc;

     -- End Read / Compute Logic --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
    -- Begin Combinatorial Process and Read / Compute FSM --

    comb: process(ps,computations_avail,OUT_WRITABLE)
    begin
        OUT_WE     <= '0';
        RE         <= '0';
        SAMPLE_OUT <= (others => '0');
        ram_addr   <= std_logic_vector(Raddr);

        case (ps) is

            -- Wait until there is a computation available
            when COMP_WAIT =>

                -- If there is a computation available
                if (computations_avail > 0) then

                    -- Begin compute cycle
                    ns       <= EVEN_RE;
                    ram_addr <= std_logic_vector(Raddr);
                    RE       <= '1';

                else
                    -- Otherwise stay here :(
                    ns <= COMP_WAIT;
                end if;

            -- Read states, just get cycled through
            when EVEN_RE =>

                RE       <= '1';
                ram_addr <= std_logic_vector(Raddr);
                ns       <= ODD_RE;
                
            when ODD_RE =>

                RE       <= '1';
                ram_addr <= std_logic_vector(Raddr);
                ns       <= EVEN_IM;

            when EVEN_IM =>

                RE       <= '1';
                ram_addr <= std_logic_vector(Raddr);
                ns       <= ODD_IM;

            when ODD_IM =>

                RE       <= '1';
                ram_addr <= std_logic_vector(Taddr);
                ns       <= TWID_RE;

            when TWID_RE =>

                RE       <= '1';
                ram_addr <= std_logic_vector(Taddr);
                ns       <= TWID_IM;

            when TWID_IM =>

                ns       <= EVEN_OUT_RE;
                RE       <= '1';
                ram_addr <= std_logic_vector(Taddr);

            -- Writing states, can halt if output is not ready to recieve data
            when EVEN_OUT_RE =>

                if (OUT_WRITABLE = '1') then

                    OUT_WE     <= '1';
                    SAMPLE_OUT <= to_slv(butt_out_even.re);
                    ns         <= ODD_OUT_RE;

                else
                    ns <= EVEN_OUT_RE;
                end if;

            when ODD_OUT_RE =>

                if (OUT_WRITABLE = '1') then

                    OUT_WE     <= '1';
                    SAMPLE_OUT <= to_slv(butt_out_odd.re);
                    ns          <= EVEN_OUT_IM;

                else
                    ns <= ODD_OUT_RE;
                end if;

            when EVEN_OUT_IM =>

                if (OUT_WRITABLE = '1') then

                    OUT_WE     <= '1';
                    SAMPLE_OUT <= to_slv(butt_out_even.im);
                    ns         <= ODD_OUT_IM;

                else
                    ns <= EVEN_OUT_IM;
                end if;

            when ODD_OUT_IM =>

                if (OUT_WRITABLE = '1') then

                    OUT_WE     <= '1';
                    SAMPLE_OUT <= to_slv(butt_out_odd.im);
                    ns         <= COMP_WAIT;

                else
                    ns <= ODD_OUT_IM;
                end if;
                    
            when others =>
                ns <= COMP_WAIT;

        end case;
    end process comb;

    -- End Combinatorial Process and Read / Compute FSM --
    ----------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
end behav;
