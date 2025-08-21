#!/bin/sh

# Script to build the FFT Core testbench
# Compile dependencies first
ghdl -a --std=08 --work=complex ../../complex_fixed/complex_fixed_pkg.vhdl
ghdl -a --std=08 --work=fft ../../butterfly.vhdl ../../bram.vhdl ../../stage.vhdl ../../core.vhdl
ghdl -a --std=08 testbench.vhdl
ghdl -e --std=08 testbench
ghdl -r testbench --wave=wave.ghw
