#!/bin/sh

# Script to build the 8PT pipeline module testbench

ghdl -a --std=08 --work=complex ../../complex_fixed/complex_fixed_pkg.vhdl

ghdl -a --std=08 --work=fft ../../butterfly.vhdl ../../bram.vhdl ../../stage.vhdl
ghdl -a --std=08 testbench.vhdl

ghdl -e --std=08 testbench

ghdl -r testbench --wave=wave.ghw
