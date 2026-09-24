# Stage 1g-4 case C TXC delay comparison candidate.
# The OPT_DESIGN.TCL.PRE hook guards the target count before sourcing this file
# and reads DELAY_VALUE back immediately afterwards.
set_property DELAY_VALUE 975 [get_cells -hier -filter {NAME == u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/delay_rgmii_tx_clk}]
