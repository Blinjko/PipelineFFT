
-- Block RAM instantiation (should be inferenceable if the sizes are gotten right)
-- Assumes that you have dual port memory

-- To change the size of the BRAM use the generic parameters as seen, should be self-explanatory

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_float_types.all;
use ieee.fixed_pkg.all;

library complex;
use complex.complex_fixed_pkg.all;

entity BRAM is
    generic (
                data_width  : integer := 16;
                addr_width  : integer := 8;
                buffer_size : integer := 256;
                pre_program : std_logic_vector(buffer_size*data_width-1 downto 0) := (others => '0')
            );

    port (CLK   : in  std_logic;
          WE    : in  std_logic;
          WADDR : in  std_logic_vector(addr_width-1 downto 0);
          WDATA : in  std_logic_vector(data_width-1 downto 0);
          RE    : in  std_logic;
          RADDR : in  std_logic_vector(addr_width-1 downto 0);
          RDATA : out std_logic_vector(data_width-1 downto 0));
end BRAM;

architecture behav of BRAM is

    type ram_type is array (0 to buffer_size-1) of std_logic_vector(data_width-1 downto 0);

    -- Function to unpack the given std_logic_vector
    function program_ram(data : std_logic_vector(buffer_size*data_width-1 downto 0)) return ram_type is

        variable temp_ram : ram_type;
        variable lower : integer := 0;
        variable upper : integer := data_width - 1;

    begin

        for addr in 0 to buffer_size-1 loop
            
            temp_ram(addr) := data(upper downto lower);

            upper := upper + data_width;
            lower := lower + data_width;

        end loop;

        return temp_ram;

    end function program_ram;


    signal ram : ram_type := program_ram(pre_program);

begin

    sync: process(CLK)
    begin
        
        if (rising_edge(CLK)) then

            -- RAM is expected to be dual port
            if (WE = '1') then

                ram(to_integer(unsigned(WADDR))) <= WDATA;

            end if;

            if (RE = '1') then

                RDATA <= ram(to_integer(unsigned(RADDR)));

            end if;

        end if;


    end process sync;

end behav;

