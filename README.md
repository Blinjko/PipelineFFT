### Goal
The goal of this project was to create a pipelined Decimation in Frequency (DIF) FFT Core in VHDL in order to practice VHDL, digital logic and FPGA stuffs.


## Usage
To use the `FFTCORE` declare a component like seen below:
```
-- assuming library fft; and use fft.all; have been put before your entity
core: entity FFTCORE
	generic map (
		data_width  => <data_width>,
		addr_width  => <addr_width>,
		buffer_size => <buffer_size>
	)
	port map ( 
        CLK          => <CLK>,  
        RST          => <RST>,  
        SAMPLE_IN    => <SAMPLE_IN>,  
        WE           => <WE>,  
        OUT_WRITABLE => <OUT_WRITABLE>,  
        WRITABLE     => <WRITABLE>,  
        TRANSFORMED  => <TRANSFORMED>,  
        OUT_WE       => <OUT_WE>
        );
```
If you change the generic parameters from their default values, (16, 8, 256), then read the "Changing Memory Size" Section

## Changing Memory Size
The size of the memories that the FFT Core uses can be set by the generic parameters seen in "Usage". The default values are based on the Lattice ICE40 4k BRAM, running in a (256x16) configuration. Should you want to add more pipeline stages or use a different size RAM the generic parameters will have to be changed along with a few other things. Before we start we have to verify that the RAM size we want to use is big enough for the FFT we want to run. Also, for reference, the default FFT size is 64.

### Determining the Max FFT Size for My RAM & How many Blocks I Will Need
If you have an `n` point FFT then your RAM size will have to be at least `3n`. `n` for the pre-programmed twiddle values, and `2n` for the sample buffer.

Each stage uses it's own block ram piece, so if you are using an FPGA you have to ensure you have enough blocks available to be used. To determine this simply take the base 2 logarithm of the point size of your FFT.
EX: I want a 64 PT FFT, so I need at least `log_two(64) = 6` RAM blocks. 

Once we have verified our new memory configuration will work, we have to set the size of the fixed point numbers, and their precision in `complex_fixed_pkg.vhdl`

### Setting the Size of the Fixed Point Numbers
The size of the fixed point numbers in `complex_fixed_pkg.vhdl` have to match the size of the `data_width` of your RAM configuration, because they are the data that is being passed around.

To alter the size of the fixed point numbers, simply go into `complex_fixed_pkg.vhdl` and change the `high`, and `low` constant values. `high` is the highest bit number on the left hand side of the decimal (including zero), and `low` is the amount of bits to the right hand size of the decimal (not including zero). Don't forget the negative sign on the `low` value.

To verify your numbers match the `data_width` you used, the following equation should hold true.
`(high + 1) + (-low) = data_width`
If it does not, make it.

To adjust precision, i.e add more decimal accuracy, take bits from the left hand side, `high`, and put them on the right hand side, `low`. Or put more simply, subtract some bits from `high` and `low`. NOTE: Low is negative! So subtracting bits from it actually adds bits to it.

To hold larger values do the opposite, add bits to `high` and `low`. Note you have to add the same amount to ensure that the equation above holds  true.

It is also worth noting that we are using ,`sfixed`, a signed type, so you are losing one of  your data bits to the sign bit.

Now that we have verified your buffer is big enough and adjusted the size of the fixed point numbers used, you should be good to go with your declaration, assuming you are using the default FFT size (64). If you want to alter the size of the FFT keep reading onto the next section.

## Changing the Size of the FFT
The default size if 64, but this might not be enough, and you might want to add a stage. To do this we will need to do a few things. First, determine what size stage you want to use and ensure that you have a RAM configuration large enough to support it, see "Changing the Memory Size" above. The default configuration is already as large as it can be, so if you want more, you will need a bigger memory size.

Once you have sorted out your memory, the next thing we have to do is add the conditional generation statement in `stage.vhdl` for your new specified point size. This is necessary because the twiddles are pre-programmed into the memory, and the values used are different depending on the point size of the stage. 

### Adding a Stage Conditional-Generate 
To do this, go into `stage.vhdl`, find the other conditional generates for the other point sizes, copy one of them, and paste it. Look below for what you need to change.
```
-- Parts to change
-- The label
-- The '(n = pt_size)'
-- The twiddles that will be pre-prgrammed into the ram.
 CHANGE_ME: if (n = TYPE YOUR PT SIZE HERE) generate  
           
         constant pre_program : ram_type := (  
							-- CHANGE THESE VALUES to whatever you computed
							-- NOTE they are alternating real and imaginary
							-- parts.
							-- BELOW are the values for the 8PT
                           to_slv( to_sfixed(1.0, high, low) ),  -- real  
                           to_slv( to_sfixed(0.0, high, low) ),  -- imaginary  
    
                           to_slv( to_sfixed(0.7071067811865476, high, low) ),  
                           to_slv( to_sfixed(-0.7071067811865475, high, low) ),  
    
                           to_slv( to_sfixed(0.0, high, low) ),  
                           to_slv( to_sfixed(-1.0, high, low) ),  
    
                           to_slv( to_sfixed(-0.7071067811865475, high, low) ),  
                           to_slv( to_sfixed(-0.7071067811865476, high, low) ),  
    
						    -- LEAVE EVERTHING AFTER THIS ALONE --
						    -- EXCEPT THE LABEL AT THE VERY END --
                           others => (others => '0'));  
    
    
     begin  
    
         ram_buff: entity bram  
    
         generic map (  
             pre_program => pack_preprogram_vector(pre_program),  
             data_width  => data_width,  
             addr_width  => addr_width,  
             buffer_size => buffer_size  
         )  
    
         port map (  
             clk   => clk,  
             we    => we,  
             re    => re,  
             waddr => std_logic_vector(waddr),  
             wdata => sample_in,  
             raddr => ram_addr,  
             rdata => rdata);  
    
     end generate CHANGE_ME;
    
```
Obviously you need to follow the the patter used in the example, wrap your numbers in `to_slv( to_sfixed(number_here, high, low), ` and alternate them real, imaginary. The precision of the number you put in there doesn't matter as it will be rounded to fit.

Once you have finished adding the conditional generate(s) for your new stages, you now have to add them to the `FFTCORE` architecture and wire them up.

### Wiring Up New Stages
The wiring of the pipeline is rather simple and straightforward. Read the following code to understand how it is wired.

The head stage, i.e the first stage of the FFT
```
-- Head stage of the default configuration
sixtyfour_pt: entity STAGE  
    
         generic map ( n           => 64,  <-- this will need changing 
                       head        => true,  <-- should only be true for the head
                       data_width  => data_width,  
                       addr_width  => addr_width,  
                       buffer_size => buffer_size  
                   )  
    
         port map (CLK          => CLK,  
                   RST          => RST,  
                   SAMPLE_IN    => SAMPLE_IN, <-- the head always gets wired to this, it connects it to the FFTCORE's interface
                   
                   WE           => WE,  <-- same as said above
                   
                   OUT_WRITABLE => THIRTYTWO_WRITABLE,  <-- always connects to the next stages writable siganl, in this case it is 32 because this stage is 64.
                   
                   SAMPLE_OUT   => SIXTYFOUR_SAMPLE_OUT,
                   OUT_WE       => SIXTYFOUR_OUT_WE,  
                   WRITABLE     => WRITABLE); <-- same as SAMPLE_IN and WE
```

An intermediate (non head) stage
```
thirtytwo_pt: entity STAGE  
    
         generic map ( n           => 32,  
                       head        => false,  
                       data_width  => data_width,  
                       addr_width  => addr_width,  
                       buffer_size => buffer_size  
                   )  
    
         port map (CLK          => CLK,  
                   RST          => RST,  
                   SAMPLE_IN    => SIXTYFOUR_SAMPLE_OUT, <-- this stages input is the previous stages output
                   
                   WE           => SIXTYFOUR_OUT_WE,  <-- input WE signal is wired to the previous stages OUT_WE signal
                   
                   OUT_WRITABLE => SIXTEEN_WRITABLE,  <-- Wired to the next stages WRITABLE signal
                   
                   SAMPLE_OUT   => THIRTYTWO_SAMPLE_OUT,  
                   OUT_WE       => THIRTYTWO_OUT_WE,  
                   WRITABLE     => THIRTYTWO_WRITABLE);
```

So, to add a new head stage, 
1. First create your port mapping like the ones already existing in `core.vhdl` , it is probably easiest to copy the old head stage port map and just change the parts needed.
2. Add 3 signal declarations, one for the `OUT_WE`, `WRITABLE`, and `SAMPLE_OUT` connections. We wont be using the `WRITABLE` one for the head stage so you can comment it out. What you name them is up to you, you can follow the convention used in the file or whatever.
3. Wire the head stage up, using the above head stage and comments as reference.
4. Wire the old head stage into an intermediate stage (don't forget to set head = true  to, head = false), using the example above.
5. Your done :)

If you're adding more than one stage, i.e you are adding intermediate stages, then add the three signals stated before for each new stage, and wire it up according to the references above. Correct wiring is crucial to functionality.

Now that you have
- Adjusted your memory size
- Adjusted your fixed point number size & precision
- Added new conditional generates for you new stages in `stage.vhdl` (for the twiddles)
- And wired up your new stages in `FFTCORE`, found in `core.vhdl` you should be good to go.

### Structure
There are a few VHDL files:
- `core.vhdl` - holds the final, assembled, FFT Core
- `stage.vhdl` - this is where most of the code is, holds definition for the pipeline stages and the logic of how to compute the FFT
- `bram.vhdl` - holds the entity declaration of a block ram entity, meant to be inferenceable by a synthesis tool so that it can be put into FPGA's
- `complex_fixed_pkg.vhdl` - holds the type declaration of `complex_fixed` and the  overloaded operator functions so that it can be used like a normal numeric type.
- `butterfly.vhdl` - holds the butterfly entity, the part that does the critical operation needed for the FFT

### Build Order
Build scripts are included where applicable, but should you need to make your own, here is the order. NOTE: Build everything using the 2008 VHDL standard
1. Compile `complex_fixed_pkg.vhdl` into the `complex` library.
2. Compile `butterfly.vhdl`, `bram.vhdl`, `stage.vhdl`, `core.vhdl` into the `fft` library.
3. Compile whatever other files  you have for your project.
So an example build sequence with GHDL
```
cd src/
ghdl -a --std=08 --work=complex complex_fixed/complex_fixed_pkg.vhdl
ghdl -a --std=08 --work=fft butterfly.vhdl bram.vhdl stage.vhdl core.vhdl
ghdl -a --std=08 your_design.vhdl
ghdl -e --std=08 top_module
```

### Synthesis
A script for synthesis is included in the `synthesis` folder. To run a synthesis on the `FFTCORE` entity using yosys:
1. Run the `syth.sh` script, this compiles the files like we did above
2. run `yosys -s synth.ys`

Edit as you need, I just tested to see if the code would synthesize correctly, but I didn't actually program it into an FPGA because my FPGA isn't big enough :(
