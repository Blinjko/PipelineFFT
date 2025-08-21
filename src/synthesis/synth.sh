#!/bin/sh

# Script to prep the files for yosys

# Analyze the complex_fixed
ghdl -a --std=08 --work=complex ../complex_fixed/complex_fixed_pkg.vhdl

# Analyze the rest of the pipeline
ghdl -a --std=08 --work=fft ../butterfly.vhdl ../bram.vhdl ../stage.vhdl ../core.vhdl

# Analyze your module here
# ghdl -a --std=08 filename.vhdl
