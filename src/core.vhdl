-- FFT Core File
-- Holds the assembly of the pipeline stages

-- To make the pipeline bigger, first expand the number of stages in stage.vhdl, i.e add the needed conditional generates for higher # stages
-- there are instructions in there.

-- Second, add those new stages below and connect them accordingly <--- (This is crucial, I spent to many hours of my life debugging only to realize that
-- I messed this shit up).

-- Note if you change the data_width make sure to adjust the high, and low constants in the complex_fixed_pkg, in complex_fixed_pkg.vhdl
-- These control the size of the sfixed numbers used. More info in complex_fixed_pkg.vhdl

-- Change the generic paramters to adjust the buffer size, make sure your buffer size is big enough for the PT # you will use, more on this in stage.vhdl.
-- Other than that, that is really it... oh!, The samples come out in bit-reversed order so the output buffering and reordering is left for you to make :)

library ieee;
use ieee.std_logic_1164.all;

library fft;
use fft.all;

entity FFTCORE is
    generic (
                data_width  : integer := 16;    -- Bit-width of a datapiece in BRAM
                addr_width  : integer := 8;     -- Address width for the BRAM
                buffer_size : integer := 256    -- Length of the BRAM buffer, i.e how many spots the BRAM has the the given data_width
            );
    port (CLK          : in  std_logic;
          RST          : in  std_logic;
          SAMPLE_IN    : in  std_logic_vector(data_width-1 downto 0);  -- Data coming in 
          WE           : in  std_logic;                                -- Write enable
          OUT_WRITABLE : in  std_logic;                                -- It the next stage able to be written to?
          WRITABLE     : out std_logic;                                -- Am I writalbe, i.e can I be written to, '1' = yes, '0' = no
          TRANSFORMED  : out std_logic_vector(data_width-1 downto 0);  -- Output data from the transform
          OUT_WE       : out std_logic);                               -- Out Write Enable
end FFTCORE;


architecture behav of FFTCORE is

    -- Signals to connect the 64PT to the 32PT
    signal SIXTYFOUR_OUT_WE       : std_logic;
    --  signal SIXTYFOUR_WRITABLE     : std_logic; -- Not needed since it is the head
    signal SIXTYFOUR_SAMPLE_OUT   : std_logic_vector(data_width-1 downto 0);

    -- Signals to connect the 32PT to the 16PT
    signal THIRTYTWO_OUT_WE       : std_logic;
    signal THIRTYTWO_WRITABLE     : std_logic;
    signal THIRTYTWO_SAMPLE_OUT   : std_logic_vector(data_width-1 downto 0);

    -- Signals to connect the 32PT to the 16PT
    signal SIXTEEN_OUT_WE       : std_logic;
    signal SIXTEEN_WRITABLE     : std_logic;
    signal SIXTEEN_SAMPLE_OUT   : std_logic_vector(data_width-1 downto 0);

    -- Signals to connect the 16PT to the 8PT
    signal EIGHT_OUT_WE     : std_logic;
    signal EIGHT_WRITABLE   : std_logic;
    signal EIGHT_SAMPLE_OUT : std_logic_vector(data_width-1 downto 0);

    -- Signals to connect the 4PT to the 8PT
    signal FOUR_OUT_WE     : std_logic;
    signal FOUR_WRITABLE   : std_logic;
    signal FOUR_SAMPLE_OUT : std_logic_vector(data_width-1 downto 0);

    -- Signals to connect the 2PT to the 4PT
    signal TWO_OUT_WE     : std_logic;
    signal TWO_WRITABLE   : std_logic;
    signal TWO_SAMPLE_OUT : std_logic_vector(data_width-1 downto 0);


begin

    sixtyfour_pt: entity STAGE

        generic map ( n           => 64,
                      head        => true,
                      data_width  => data_width,
                      addr_width  => addr_width,
                      buffer_size => buffer_size
                  )

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => SAMPLE_IN,
                  WE           => WE,
                  OUT_WRITABLE => THIRTYTWO_WRITABLE,
                  SAMPLE_OUT   => SIXTYFOUR_SAMPLE_OUT,
                  OUT_WE       => SIXTYFOUR_OUT_WE,
                  WRITABLE     => WRITABLE);

    thirtytwo_pt: entity STAGE

        generic map ( n           => 32,
                      head        => false,
                      data_width  => data_width,
                      addr_width  => addr_width,
                      buffer_size => buffer_size
                  )

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => SIXTYFOUR_SAMPLE_OUT,
                  WE           => SIXTYFOUR_OUT_WE,
                  OUT_WRITABLE => SIXTEEN_WRITABLE,
                  SAMPLE_OUT   => THIRTYTWO_SAMPLE_OUT,
                  OUT_WE       => THIRTYTWO_OUT_WE,
                  WRITABLE     => THIRTYTWO_WRITABLE);

    sixteen_pt: entity STAGE

        generic map ( n           => 16,
                      head        => false,
                      data_width  => data_width,
                      addr_width  => addr_width,
                      buffer_size => buffer_size
                  )

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => THIRTYTWO_SAMPLE_OUT,
                  WE           => THIRTYTWO_OUT_WE,
                  OUT_WRITABLE => EIGHT_WRITABLE,
                  SAMPLE_OUT   => SIXTEEN_SAMPLE_OUT,
                  OUT_WE       => SIXTEEN_OUT_WE,
                  WRITABLE     => SIXTEEN_WRITABLE);


    eight_pt: entity STAGE

        generic map ( n           => 8,
                      head        => false,
                      data_width  => data_width,
                      addr_width  => addr_width,
                      buffer_size => buffer_size
                  )

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => SIXTEEN_SAMPLE_OUT,
                  WE           => SIXTEEN_OUT_WE,
                  OUT_WRITABLE => FOUR_WRITABLE,
                  SAMPLE_OUT   => EIGHT_SAMPLE_OUT,
                  OUT_WE       => EIGHT_OUT_WE,
                  WRITABLE     => EIGHT_WRITABLE);

    four_pt: entity STAGE

        generic map ( n           => 4,
                      head        => false,
                      data_width  => data_width,
                      addr_width  => addr_width,
                      buffer_size => buffer_size
                  )

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => EIGHT_SAMPLE_OUT,
                  WE           => EIGHT_OUT_WE,
                  OUT_WRITABLE => TWO_WRITABLE,
                  SAMPLE_OUT   => FOUR_SAMPLE_OUT,
                  OUT_WE       => FOUR_OUT_WE,
                  WRITABLE     => FOUR_WRITABLE);

    two_pt: entity STAGE

        generic map ( n           => 2,
                      head        => false,
                      data_width  => data_width,
                      addr_width  => addr_width,
                      buffer_size => buffer_size
                  )

        port map (CLK          => CLK,
                  RST          => RST,
                  SAMPLE_IN    => FOUR_SAMPLE_OUT,
                  WE           => FOUR_OUT_WE,
                  OUT_WRITABLE => OUT_WRITABLE,
                  SAMPLE_OUT   => TRANSFORMED,
                  OUT_WE       => OUT_WE,
                  WRITABLE     => TWO_WRITABLE);
        
end behav;    
