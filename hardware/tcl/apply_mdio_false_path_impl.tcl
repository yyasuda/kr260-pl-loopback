# impl_1 STEPS.OPT_DESIGN.TCL.PRE hook.
# At this point init_design/link_design has expanded the PS DCP hierarchy and
# processed the TEMAC generated XDC.  First complete its missing rising-edge
# TX DDR delays, then apply the asynchronous MDIO-input exception.
set hook_dir [file normalize [file dirname [info script]]]
set hardware_dir [file normalize [file join $hook_dir ..]]
set hook_reports_dir [file join $hardware_dir reports]
file mkdir $hook_reports_dir

# TEMAC generated XDC/RTLは変更せず、link後の展開済みdesignでTXC master
# ODELAYE3だけを一意に選択して比較候補975 psへ上書きする。
set txc_delay_cells [get_cells -hier -quiet -filter {NAME == u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/delay_rgmii_tx_clk}]
if {[llength $txc_delay_cells] != 1} {
  error "TXC delay override expected exactly one master ODELAYE3, got [llength $txc_delay_cells]: $txc_delay_cells"
}
if {[get_property REF_NAME $txc_delay_cells] ne "ODELAYE3"} {
  error "TXC delay override target is not ODELAYE3: $txc_delay_cells"
}
set txc_delay_xdc [file join $hardware_dir constraints stage1g4_txc_delay_975.xdc]
if {![file exists $txc_delay_xdc]} {
  error "Missing TXC delay override XDC: $txc_delay_xdc"
}
if {![info exists ::stage1g4_txc_delay_975_applied]} {
  source $txc_delay_xdc
  set ::stage1g4_txc_delay_975_applied 1
}
set txc_delay_readback [get_property DELAY_VALUE $txc_delay_cells]
if {$txc_delay_readback != 975} {
  error "TXC master ODELAYE3 DELAY_VALUE expected 975 after override, got $txc_delay_readback"
}

# 03mではStage 1eのFF実装によりrx_axi_clk fanoutが大幅に増える。自動選択に
# 任せると03kのX1Y3からX1Y1へclock rootが移り、TEMAC RGMII RX input holdを
# 悪化させるため、03k routed known-goodと同じclock rootを明示的に維持する。
set rx_clock_bufgs [get_cells -hier -quiet -filter {NAME == u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/bufg_rgmii_rx_clk}]
if {[llength $rx_clock_bufgs] != 1 || [get_property REF_NAME $rx_clock_bufgs] ne "BUFGCE"} {
  error "RGMII RX clock BUFGCE expected exactly one, got $rx_clock_bufgs"
}
set rx_clock_o [get_pins -quiet -of_objects $rx_clock_bufgs -filter {REF_PIN_NAME == O}]
set rx_clock_nets [get_nets -quiet -of_objects $rx_clock_o]
if {[llength $rx_clock_nets] != 1} {
  error "RGMII RX BUFGCE output expected exactly one net, got $rx_clock_nets"
}
set_property USER_CLOCK_ROOT X1Y3 $rx_clock_nets
if {[get_property USER_CLOCK_ROOT $rx_clock_nets] ne "X1Y3"} {
  error "RGMII RX USER_CLOCK_ROOT readback mismatch: [get_property USER_CLOCK_ROOT $rx_clock_nets]"
}

set tx_ddr_xdc [file join $hardware_dir constraints stage1g4_temac_tx_ddr_completion.xdc]
if {![file exists $tx_ddr_xdc]} {
  error "Missing TX DDR completion XDC: $tx_ddr_xdc"
}
if {![info exists ::stage1g4_tx_ddr_completion_applied]} {
  source $tx_ddr_xdc
  set ::stage1g4_tx_ddr_completion_applied 1
}

set tx_ports [get_ports -quiet -filter {NAME =~ rgmii_txd* || NAME == rgmii_tx_ctl}]
if {[llength $tx_ports] != 5} {
  error "TX DDR completion expected five TXD/TX_CTL ports, got [llength $tx_ports]: $tx_ports"
}

# Verify edge coverage from timing-path object properties, not report text.
# Modulo the 8 ns RGMII period, setup must contain both same-edge phase pairs
# and hold must contain both cross-edge phase pairs.
proc stage1g4_edge_pairs {paths} {
  set pairs {}
  foreach path $paths {
    set start_phase [expr {fmod(double([get_property STARTPOINT_CLOCK_EDGE $path]), 8.0)}]
    set end_phase [expr {fmod(double([get_property ENDPOINT_CLOCK_EDGE $path]), 8.0)}]
    if {$start_phase < 0.0} { set start_phase [expr {$start_phase + 8.0}] }
    if {$end_phase < 0.0} { set end_phase [expr {$end_phase + 8.0}] }
    lappend pairs [format "%.3f->%.3f" $start_phase $end_phase]
  }
  return [lsort -unique $pairs]
}

set tx_setup_paths [get_timing_paths -quiet -to $tx_ports -delay_type max -max_paths 100 -nworst 20]
set tx_hold_paths [get_timing_paths -quiet -to $tx_ports -delay_type min -max_paths 100 -nworst 20]
set tx_setup_pairs [stage1g4_edge_pairs $tx_setup_paths]
set tx_hold_pairs [stage1g4_edge_pairs $tx_hold_paths]
foreach required_pair {0.000->0.000 4.000->4.000} {
  if {[lsearch -exact $tx_setup_pairs $required_pair] < 0} {
    error "TX DDR setup edge coverage lacks $required_pair; found $tx_setup_pairs"
  }
}
foreach required_pair {0.000->4.000 4.000->0.000} {
  if {[lsearch -exact $tx_hold_pairs $required_pair] < 0} {
    error "TX DDR hold edge coverage lacks $required_pair; found $tx_hold_pairs"
  }
}

set mdio_input_leaf [get_pins -hier -quiet -filter {REF_PIN_NAME == EMIOENET2MDIOI}]
set endpoint_count [llength $mdio_input_leaf]
if {$endpoint_count != 1} {
  error "MDIO implementation hook expected exactly one PS GEM2 MDIO input leaf, got $endpoint_count: $mdio_input_leaf"
}

set_false_path -to $mdio_input_leaf

set f [open [file join $hook_reports_dir mdio_false_path_impl_hook.txt] w]
puts $f "HOOK=STEPS.OPT_DESIGN.TCL.PRE"
puts $f "TXC_DELAY_XDC=$txc_delay_xdc"
puts $f "TXC_MASTER_COUNT=[llength $txc_delay_cells]"
puts $f "TXC_MASTER=$txc_delay_cells"
puts $f "TXC_DELAY_VALUE=$txc_delay_readback"
puts $f "RGMII_RX_CLOCK_BUFG=$rx_clock_bufgs"
puts $f "RGMII_RX_CLOCK_NET=$rx_clock_nets"
puts $f "RGMII_RX_USER_CLOCK_ROOT=[get_property USER_CLOCK_ROOT $rx_clock_nets]"
puts $f "TX_DDR_XDC=$tx_ddr_xdc"
puts $f "TX_PORT_COUNT=[llength $tx_ports]"
puts $f "TX_PORTS=$tx_ports"
puts $f "TX_SETUP_PATH_COUNT=[llength $tx_setup_paths]"
puts $f "TX_SETUP_EDGE_PAIRS=$tx_setup_pairs"
puts $f "TX_HOLD_PATH_COUNT=[llength $tx_hold_paths]"
puts $f "TX_HOLD_EDGE_PAIRS=$tx_hold_pairs"
puts $f "ENDPOINT_COUNT=$endpoint_count"
puts $f "ENDPOINT=$mdio_input_leaf"
puts $f "REF_PIN_NAME=[get_property REF_PIN_NAME $mdio_input_leaf]"
puts $f "DESIGN=[current_design]"
close $f
report_timing -to $tx_ports -delay_type max -max_paths 100 -nworst 20 -file [file join $hook_reports_dir timing_rgmii_tx_setup_impl_hook.rpt]
report_timing -to $tx_ports -delay_type min -max_paths 100 -nworst 20 -file [file join $hook_reports_dir timing_rgmii_tx_hold_impl_hook.rpt]
report_methodology -checks {TIMING-18} -file [file join $hook_reports_dir methodology_timing18_impl_hook.rpt]
report_exceptions -file [file join $hook_reports_dir exceptions_impl_hook.rpt]
report_exceptions -to $mdio_input_leaf -file [file join $hook_reports_dir mdio_exceptions_impl_hook.rpt]
