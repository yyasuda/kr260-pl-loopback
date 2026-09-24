# TEMAC v9.0 generated XDC installs the falling-reference output delays
# without -add_delay, replacing the preceding rising-reference delays.
# Restore only the missing rising-reference max/min delays.  This file is
# sourced by STEPS.OPT_DESIGN.TCL.PRE after all generated IP constraints.
set_output_delay 0.55 -max -clock [get_clocks u_temac_wrapper/u_temac/inst_rgmii_tx_clk] -add_delay [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -0.7 -min -clock [get_clocks u_temac_wrapper/u_temac/inst_rgmii_tx_clk] -add_delay [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
