#
# user core constraints
#
# clk_74a (bridge, framework) is asynchronous to the core: everything that crosses goes through a
# synchroniser or a toggle (core_top.v, apf_dataslot.vhd, sound_i2s.sv).
# The PLL outputs are the 42 MHz core clock and the 10.5 MHz video clock with its 90 degree copy;
# they come from one PLL and are timed against each other.
#

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk }
