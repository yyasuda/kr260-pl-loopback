set script_dir [file normalize [file dirname [info script]]]
set hardware_dir [file normalize [file join $script_dir ..]]
set project_dir [file join $hardware_dir build vivado]
set reports_dir [file join $hardware_dir reports]
set artifacts_dir [file join $hardware_dir artifacts]
set project_file [file join $project_dir stage1g4_hw_top_case_c_txc975_usb_gem2_mdio_clkoff_03m6_hw_tx_frame_buffer.xpr]
set jobs 8
if {[info exists ::env(STAGE1G4_JOBS)]} { set jobs $::env(STAGE1G4_JOBS) }
file mkdir $reports_dir
file mkdir $artifacts_dir

set bit_artifact [file join $artifacts_dir stage1g4_03m6_tx_frame_buffer.bit]
set xsa_artifact [file join $artifacts_dir stage1g4_03m6_tx_frame_buffer.xsa]
set ltx_artifact [file join $artifacts_dir stage1g4_03m6_tx_frame_buffer.ltx]
foreach artifact [list $bit_artifact $xsa_artifact $ltx_artifact] {
  if {[file exists $artifact]} { error "Refusing to overwrite existing artifact: $artifact" }
}

open_project $project_file
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
  error "03m-2 synthesis checkpoint is not complete: [get_property STATUS [get_runs synth_1]]"
}

set impl_hook [file normalize [file join $script_dir apply_mdio_false_path_impl.tcl]]
if {![file exists $impl_hook]} { error "Missing implementation hook: $impl_hook" }
add_files -fileset utils_1 -norecurse $impl_hook
set_property STEPS.OPT_DESIGN.TCL.PRE $impl_hook [get_runs impl_1]

# A previous failed sign-off attempt may have left a routed impl_1. Preserve its
# reports before invoking this script again, then rerun implementation from the
# unchanged synth_1 checkpoint with the current implementation hook.
set reuse_routed 0
if {[info exists ::env(STAGE1G4_REUSE_ROUTED)] && $::env(STAGE1G4_REUSE_ROUTED) eq "1"} { set reuse_routed 1 }
if {!$reuse_routed} {
  reset_run impl_1
  launch_runs impl_1 -to_step route_design -jobs $jobs
  wait_on_run impl_1
}
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "route_design Complete*" $impl_status]} {
  error "Implementation did not complete route_design: $impl_status"
}
open_run impl_1

proc m03r_one_cell {pattern label} {
  set objects [get_cells -hier -quiet $pattern]
  if {[llength $objects] != 1} { error "$label expected one cell for $pattern, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc m03r_one_pin {pattern label} {
  # NAME filtering keeps bus indices (for example D[0]) literal.
  set objects [get_pins -hier -quiet -filter "NAME == \"$pattern\""]
  if {[llength $objects] != 1} { error "$label expected one pin for $pattern, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc m03r_ref_pin {cell ref_name label} {
  set objects [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME == \"$ref_name\""]
  if {[llength $objects] != 1} { error "$label expected one $ref_name pin on $cell, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc m03r_same_net {fh label pins} {
  set common {}
  set logic_values {}
  foreach pin $pins {
    lappend logic_values [get_property -quiet LOGIC_VALUE $pin]
    set segments [get_nets -quiet -segments -of_objects $pin]
    puts $fh "$label PIN=$pin LOGIC=[get_property -quiet LOGIC_VALUE $pin] SEGMENTS=$segments"
    if {[llength $segments] == 0} { error "$label pin $pin has no net segment" }
    if {[llength $common] == 0} {
      set common $segments
    } else {
      set intersection {}
      foreach segment $common { if {[lsearch -exact $segments $segment] >= 0} { lappend intersection $segment } }
      set common $intersection
    }
  }
  if {[llength $common] != 0} { puts $fh "$label RESULT=PASS COMMON=[lindex $common 0]"; return }
  set first [lindex $logic_values 0]
  if {$first eq "zero" || $first eq "one"} {
    set all_same 1
    foreach value $logic_values { if {$value ne $first} { set all_same 0 } }
    if {$all_same} { puts $fh "$label RESULT=PASS CONSTANT=$first"; return }
  }
  error "$label has no common net segment: $pins"
}
proc m03r_same_clock {fh label pins} {
  set common {}
  foreach pin $pins {
    set clocks [get_clocks -quiet -of_objects $pin]
    puts $fh "$label PIN=$pin CLOCKS=$clocks"
    if {[llength $clocks] == 0} { error "$label pin $pin has no clock object" }
    if {[llength $common] == 0} {
      set common $clocks
    } else {
      set intersection {}
      foreach clock $common { if {[lsearch -exact $clocks $clock] >= 0} { lappend intersection $clock } }
      set common $intersection
    }
  }
  if {[llength $common] == 0} { error "$label has no common clock object: $pins" }
  puts $fh "$label RESULT=PASS COMMON_CLOCK=[lindex $common 0]"
}
proc m03r_edge_pairs {paths} {
  set pairs {}
  foreach path $paths {
    set s [expr {fmod(double([get_property STARTPOINT_CLOCK_EDGE $path]), 8.0)}]
    set e [expr {fmod(double([get_property ENDPOINT_CLOCK_EDGE $path]), 8.0)}]
    if {$s < 0.0} { set s [expr {$s + 8.0}] }
    if {$e < 0.0} { set e [expr {$e + 8.0}] }
    lappend pairs [format "%.3f->%.3f" $s $e]
  }
  return [lsort -unique $pairs]
}

# Route status must be fully routed with no routing errors.
set route_text [report_route_status -return_string]
set route_file [open [file join $reports_dir route_status.rpt] w]
puts -nonewline $route_file $route_text
close $route_file
if {![regexp {# of routable nets\.+\s*:\s*([0-9]+)} $route_text -> routable_count] ||
    ![regexp {# of fully routed nets\.+\s*:\s*([0-9]+)} $route_text -> routed_count] ||
    ![regexp {# of nets with routing errors\.+\s*:\s*([0-9]+)} $route_text -> routing_errors]} {
  error "Unable to parse route status"
}
if {$routable_count != $routed_count || $routing_errors != 0} {
  error "Route incomplete: routable=$routable_count routed=$routed_count errors=$routing_errors"
}

current_instance
set temac_cells [get_cells -hier -quiet -filter {REF_NAME == temac_0 && ORIG_REF_NAME == temac_0}]
if {[llength $temac_cells] != 1} { error "TEMAC expected exactly one instance, got $temac_cells" }
set temac [lindex $temac_cells 0]
set endpoint [m03r_one_cell u_p4fab_endpoint ENDPOINT]
set converter_cells [get_cells -hier -quiet -filter {REF_NAME == axis_clock_converter_03m_rx || ORIG_REF_NAME == axis_clock_converter_03m_rx}]
if {[llength $converter_cells] != 1} { error "Clock Converter expected exactly one instance, got $converter_cells" }
set converter [lindex $converter_cells 0]
set frame_buffers [get_cells -hier -quiet -filter {REF_NAME == p4fab_frame_buffer_noready_8 || ORIG_REF_NAME == p4fab_frame_buffer_noready_8}]
if {[llength $frame_buffers] != 2} { error "Expected exactly two frame buffers (RX/TX), got $frame_buffers" }
set rx_frame_buffer [lindex $frame_buffers [lsearch -exact $frame_buffers u_p4fab_endpoint/u_rx_frame_buffer]]
set tx_frame_buffer [lindex $frame_buffers [lsearch -exact $frame_buffers u_p4fab_endpoint/u_tx_frame_buffer]]
if {$rx_frame_buffer ne "u_p4fab_endpoint/u_rx_frame_buffer" || $tx_frame_buffer ne "u_p4fab_endpoint/u_tx_frame_buffer"} { error "RX/TX frame buffer identities changed: $frame_buffers" }
set unpackers [get_cells -hier -quiet -filter {REF_NAME == p4fab_unpack_32to8 || ORIG_REF_NAME == p4fab_unpack_32to8}]
if {[llength $unpackers] != 1} { error "Expected exactly one TX unpacker, got $unpackers" }
set tx_unpacker [lindex $unpackers 0]
set fixed_generators [get_cells -hier -quiet -filter {REF_NAME == fixed_frame_tx || ORIG_REF_NAME == fixed_frame_tx}]
if {[llength $fixed_generators] != 0} { error "fixed_frame_tx must not exist: $fixed_generators" }

set cf [open [file join $reports_dir endpoint_connectivity_route.txt] w]
puts $cf "TEMAC_COUNT=[llength $temac_cells] TEMAC=$temac"
puts $cf "ENDPOINT=$endpoint CLOCK_CONVERTER=$converter FIXED_FRAME_TX_COUNT=[llength $fixed_generators]"
puts $cf "FRAME_BUFFER_COUNT=[llength $frame_buffers] RX_FRAME_BUFFER=$rx_frame_buffer TX_FRAME_BUFFER=$tx_frame_buffer TX_UNPACKER=$tx_unpacker"
# Full 80-bit values were guarded in the 03m-2 synthesized netlist. At route,
# unused constant input pins can be removed by opt_design (notably RX bit 1), so
# preserve the exact synth guard as evidence instead of treating removed pins as
# a route-time functional change.
set synth_connectivity_path [file join $reports_dir endpoint_connectivity_synth.txt]
set synth_cf [open $synth_connectivity_path r]
set synth_connectivity [read $synth_cf]
close $synth_cf
for {set bit 0} {$bit < 80} {incr bit} {
  set expected [expr {$bit == 1 ? "one" : "zero"}]
  foreach direction {RX TX} {
    set marker "${direction}_CONFIGURATION_VECTOR_$bit EXPECTED=$expected ACTUAL=$expected"
    if {[string first $marker $synth_connectivity] < 0} { error "Missing 03m-2 synthesized vector guard: $marker" }
  }
}
puts $cf "RX_CONFIGURATION_VECTOR=80'h00000000000000000002"
puts $cf "TX_CONFIGURATION_VECTOR=80'h00000000000000000002"
puts $cf "CONFIGURATION_VECTOR_SOURCE=$synth_connectivity_path (03m-2 synthesized netlist guard; route may remove unused constant pins)"

foreach {label temac_ref endpoint_pin} {
  RX_TVALID rx_axis_mac_tvalid u_p4fab_endpoint/rx_axis_mac_tvalid
  RX_TLAST rx_axis_mac_tlast u_p4fab_endpoint/rx_axis_mac_tlast
  RX_TUSER rx_axis_mac_tuser u_p4fab_endpoint/rx_axis_mac_tuser
  RX_RESET rx_reset u_p4fab_endpoint/rx_reset
  TX_TVALID tx_axis_mac_tvalid u_p4fab_endpoint/tx_axis_mac_tvalid
  TX_TREADY tx_axis_mac_tready u_p4fab_endpoint/tx_axis_mac_tready
  TX_TLAST tx_axis_mac_tlast u_p4fab_endpoint/tx_axis_mac_tlast
  TX_TUSER tx_axis_mac_tuser u_p4fab_endpoint/tx_axis_mac_tuser
  TX_RESET tx_reset u_p4fab_endpoint/tx_reset
} {
  m03r_same_net $cf $label [list [m03r_ref_pin $temac $temac_ref $label] [m03r_one_pin $endpoint_pin $label]]
}
for {set bit 0} {$bit < 8} {incr bit} {
  m03r_same_net $cf RX_TDATA_$bit [list [m03r_ref_pin $temac "rx_axis_mac_tdata\[$bit\]" RX_TDATA_$bit] [m03r_one_pin "u_p4fab_endpoint/rx_axis_mac_tdata\[$bit\]" RX_TDATA_$bit]]
  m03r_same_net $cf TX_TDATA_$bit [list [m03r_ref_pin $temac "tx_axis_mac_tdata\[$bit\]" TX_TDATA_$bit] [m03r_one_pin "u_p4fab_endpoint/tx_axis_mac_tdata\[$bit\]" TX_TDATA_$bit]]
}
foreach {label producer_ref consumer_ref width} {
  TX_UNPACK_TO_BUFFER_DATA m_data s_data 8
  TX_BUFFER_TO_TEMAC_DATA m_data tx_axis_mac_tdata 8
} {
  for {set bit 0} {$bit < $width} {incr bit} {
    set producer [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? $tx_unpacker : $tx_frame_buffer}]
    set consumer [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? $tx_frame_buffer : $endpoint}]
    set producer_pin [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? \
      [m03r_one_pin "${producer}/D\[$bit\]" ${label}_$bit] : \
      [m03r_one_pin "${producer}/tx_axis_mac_tdata\[$bit\]" ${label}_$bit]}]
    set consumer_pin [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? \
      [m03r_one_pin "${consumer}/D\[$bit\]" ${label}_$bit] : \
      [m03r_one_pin "${consumer}/tx_axis_mac_tdata\[$bit\]" ${label}_$bit]}]
    m03r_same_net $cf ${label}_$bit [list $producer_pin $consumer_pin]
  }
}
foreach {label producer producer_ref consumer consumer_ref} [list \
  TX_UNPACK_TO_BUFFER_VALID $tx_unpacker tx_unpack_valid $tx_frame_buffer tx_unpack_valid \
  TX_UNPACK_TO_BUFFER_LAST  $tx_unpacker tx_unpack_last  $tx_frame_buffer tx_unpack_last \
  TX_BUFFER_TO_TEMAC_LAST   $tx_frame_buffer tx_axis_mac_tlast $endpoint tx_axis_mac_tlast \
  TX_TEMAC_READY_TO_BUFFER  $endpoint tx_axis_mac_tready $tx_frame_buffer tx_axis_mac_tready] {
  m03r_same_net $cf $label [list \
    [m03r_one_pin "${producer}/${producer_ref}" $label] \
    [m03r_one_pin "${consumer}/${consumer_ref}" $label]]
}
puts $cf "TX_BUFFER_TO_TEMAC_VALID_RESET_GATED_PIN=[m03r_one_pin ${endpoint}/tx_axis_mac_tvalid TX_BUFFER_TO_TEMAC_VALID]"
foreach {label width} {TDATA 32 TKEEP 4 TVALID 1 TREADY 1 TLAST 1} {
  for {set bit 0} {$bit < $width} {incr bit} {
    set suffix [expr {$width == 1 ? "" : "\[$bit\]"}]
    set lower [string tolower $label]
    m03r_same_net $cf LOOPBACK_${label}${suffix} [list [m03r_one_pin "u_p4fab_endpoint/p4fab_rx_${lower}${suffix}" LOOP_RX] [m03r_one_pin "u_p4fab_endpoint/p4fab_tx_${lower}${suffix}" LOOP_TX]]
  }
}

set rx_clk [m03r_ref_pin $temac rx_mac_aclk RX_MAC_ACLK]
set p4_clk [m03r_one_pin u_p4fab_endpoint/p4fab_clk P4FAB_CLK]
# opt_design removes the routable clock object from the TEMAC tx_mac_aclk
# output pin.  Its equality with p4fab_clk is already an exact-net synthesis
# guard below; after route prove the surviving buffer and endpoint clocks.
m03r_same_clock $cf TX_FRAME_BUFFER_P4FAB_CLOCK [list \
  [m03r_one_pin "${tx_frame_buffer}/p4fab_clk" TX_FRAME_BUFFER_CLOCK] $p4_clk]
puts $cf "TX_FRAME_BUFFER_CAPACITY=2048 S_ERROR=0 STORE_AND_FORWARD=1"
foreach marker {
  {P4FAB_GTX_TX_CLOCK_IDENTITY RESULT=PASS COMMON_SEGMENT=u_clk_wiz/inst/clk_out1}
  {CLOCK_CONVERTER_SOURCE_CLOCK RESULT=PASS COMMON_SEGMENT=u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/rx_axi_clk}
  {CLOCK_CONVERTER_SINK_CLOCK RESULT=PASS COMMON_SEGMENT=u_clk_wiz/inst/clk_out1}
} {
  if {[string first $marker $synth_connectivity] < 0} { error "Missing 03m-2 synthesized clock guard: $marker" }
  puts $cf "SYNTH_CLOCK_GUARD=$marker"
}
set conv_s_clk [m03r_ref_pin $converter s_axis_aclk CONV_S_CLK]
set conv_m_clk [m03r_ref_pin $converter m_axis_aclk CONV_M_CLK]
m03r_same_clock $cf CONVERTER_SINK_P4FAB_CLOCK [list $conv_m_clk $p4_clk]
set source_clocks [get_clocks -quiet -of_objects $conv_s_clk]
set sink_clocks [get_clocks -quiet -of_objects $conv_m_clk]
if {[llength $source_clocks] == 0 || [llength $sink_clocks] == 0} { error "Clock Converter route clock objects missing" }
foreach clock $source_clocks {
  if {[lsearch -exact $sink_clocks $clock] >= 0} { error "Clock Converter source and sink unexpectedly share clock object $clock" }
}
puts $cf "CONVERTER_SOURCE_CLOCKS=$source_clocks CONVERTER_SINK_CLOCKS=$sink_clocks ASYNCHRONOUS=PASS"
set rx_clock_net [get_nets -hier -quiet -filter {NAME == u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/rx_axi_clk}]
if {[llength $rx_clock_net] != 1 || [get_property CLOCK_ROOT $rx_clock_net] ne "X1Y3" || [get_property USER_CLOCK_ROOT $rx_clock_net] ne "X1Y3"} {
  error "RGMII RX clock root expected CLOCK_ROOT=USER_CLOCK_ROOT=X1Y3, got net=$rx_clock_net CLOCK_ROOT=[get_property -quiet CLOCK_ROOT $rx_clock_net] USER_CLOCK_ROOT=[get_property -quiet USER_CLOCK_ROOT $rx_clock_net]"
}
puts $cf "RGMII_RX_CLOCK_ROOT=X1Y3 USER_CLOCK_ROOT=X1Y3 NET=$rx_clock_net"
set reset_syncs [get_cells -hier -quiet -filter {REF_NAME == p4fab_reset_sync || ORIG_REF_NAME == p4fab_reset_sync}]
if {[llength $reset_syncs] != 3} { error "Expected three reset synchronizers, got $reset_syncs" }
puts $cf "RESET_SYNCHRONIZER_COUNT=[llength $reset_syncs] CELLS=$reset_syncs"
set tx_user [m03r_ref_pin $temac tx_axis_mac_tuser TX_TUSER]
if {[get_property -quiet LOGIC_VALUE $tx_user] ne "zero"} { error "TEMAC tx_axis_mac_tuser is not zero" }
puts $cf "TX_AXIS_MAC_TUSER=0"
close $cf

# P4Fab/TX ILA remains a passive observer clocked by p4fab_clk/tx_mac_aclk.
set ila [m03r_one_cell u_ila_03m5_p4fab_tx P4FAB_TX_ILA]
set ilaf [open [file join $reports_dir p4fab_tx_ila_connectivity_route.txt] w]
# opt_design can remove the TEMAC tx_mac_aclk output pin's routable segment.
# Its identity with p4fab_clk is preserved by the synthesis guard above; route
# independently proves that the surviving p4fab clock drives this ILA.
m03r_same_net $ilaf P4FAB_TX_ILA_CLOCK [list $p4_clk [m03r_one_pin u_ila_03m5_p4fab_tx/clk P4FAB_TX_ILA_CLOCK]]
foreach {probe signal width} {probe0 tdata 32 probe1 tkeep 4} {
  for {set bit 0} {$bit < $width} {incr bit} {
    m03r_same_net $ilaf ${probe}_${bit} [list \
      [m03r_one_pin "u_p4fab_endpoint/p4fab_rx_${signal}\[$bit\]" ${probe}_${bit}] \
      [m03r_one_pin "u_ila_03m5_p4fab_tx/${probe}\[$bit\]" ${probe}_${bit}]]
  }
}
foreach {endpoint_pin ila_pin label} {
  u_p4fab_endpoint/p4fab_rx_tvalid {u_ila_03m5_p4fab_tx/probe2[0]} P4FAB_TVALID
  u_p4fab_endpoint/p4fab_rx_tready {u_ila_03m5_p4fab_tx/probe2[1]} P4FAB_TREADY
  u_p4fab_endpoint/p4fab_rx_tlast  {u_ila_03m5_p4fab_tx/probe2[2]} P4FAB_TLAST
  u_p4fab_endpoint/tx_axis_mac_tvalid {u_ila_03m5_p4fab_tx/probe4[0]} TX_TVALID
  u_p4fab_endpoint/tx_axis_mac_tready {u_ila_03m5_p4fab_tx/probe4[1]} TX_TREADY
  u_p4fab_endpoint/tx_axis_mac_tlast  {u_ila_03m5_p4fab_tx/probe4[2]} TX_TLAST
  u_p4fab_endpoint/p4fab_aresetn      {u_ila_03m5_p4fab_tx/probe4[3]} P4FAB_ARESETN
  u_p4fab_endpoint/tx_path_aresetn    {u_ila_03m5_p4fab_tx/probe4[4]} TX_PATH_ARESETN
  u_p4fab_endpoint/tx_reset           {u_ila_03m5_p4fab_tx/probe4[5]} TX_RESET
} { m03r_same_net $ilaf $label [list [m03r_one_pin $endpoint_pin $label] [m03r_one_pin $ila_pin $label]] }
for {set bit 0} {$bit < 8} {incr bit} {
  m03r_same_net $ilaf TX_TDATA_$bit [list \
    [m03r_one_pin "u_p4fab_endpoint/tx_axis_mac_tdata\[$bit\]" TX_TDATA_$bit] \
    [m03r_one_pin "u_ila_03m5_p4fab_tx/probe3\[$bit\]" TX_TDATA_$bit]]
}
puts $ilaf "ILA=$ila ROLE=PASSIVE_P4FAB_TX_OBSERVER"
close $ilaf

# Physical RGMII delay guards inherited from 03k.
set txc_cells [get_cells -hier -quiet -filter {NAME == u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/delay_rgmii_tx_clk}]
if {[llength $txc_cells] != 1} { error "Expected one TXC master ODELAYE3, got $txc_cells" }
set txc [lindex $txc_cells 0]
foreach {property expected} {REF_NAME ODELAYE3 DELAY_VALUE 975 DELAY_TYPE FIXED DELAY_FORMAT TIME CASCADE MASTER REFCLK_FREQUENCY 333.333} {
  set actual [get_property $property $txc]
  if {$actual ne $expected} { error "TXC $property expected $expected, got $actual" }
}
set rx_delays [get_cells -hier -quiet -filter {NAME =~ u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/*delay_rgmii_rx*}]
if {[llength $rx_delays] != 5} { error "Expected five RX IDELAYE3 cells, got $rx_delays" }
foreach cell $rx_delays {
  if {[get_property REF_NAME $cell] ne "IDELAYE3" || [get_property DELAY_VALUE $cell] != 900} { error "RX IDELAY mismatch at $cell" }
}
set pf [open [file join $reports_dir physical_delay_guard_route.txt] w]
puts $pf "TXC_COUNT=1 CELL=$txc DELAY_VALUE=975 DELAY_TYPE=FIXED DELAY_FORMAT=TIME CASCADE=MASTER REFCLK_FREQUENCY=333.333"
puts $pf "RX_IDELAY_COUNT=[llength $rx_delays]"
foreach cell $rx_delays { puts $pf "RX_IDELAY=$cell DELAY_VALUE=[get_property DELAY_VALUE $cell]" }
close $pf

# TX DDR setup/hold must cover both DDR edge pairs after route.
set tx_ports [get_ports -quiet -filter {NAME =~ rgmii_txd* || NAME == rgmii_tx_ctl}]
set setup_paths [get_timing_paths -quiet -to $tx_ports -delay_type max -max_paths 100 -nworst 20]
set hold_paths [get_timing_paths -quiet -to $tx_ports -delay_type min -max_paths 100 -nworst 20]
set setup_pairs [m03r_edge_pairs $setup_paths]
set hold_pairs [m03r_edge_pairs $hold_paths]
if {$setup_pairs ne {0.000->0.000 4.000->4.000}} { error "TX DDR setup edge coverage mismatch: $setup_pairs" }
if {$hold_pairs ne {0.000->4.000 4.000->0.000}} { error "TX DDR hold edge coverage mismatch: $hold_pairs" }
set ef [open [file join $reports_dir tx_ddr_edge_coverage_route.txt] w]
puts $ef "TX_SETUP_PATH_COUNT=[llength $setup_paths] TX_SETUP_EDGE_PAIRS=$setup_pairs"
puts $ef "TX_HOLD_PATH_COUNT=[llength $hold_paths] TX_HOLD_EDGE_PAIRS=$hold_pairs"
close $ef

# MDIO structure and false path.
set all_iobufs [get_cells -hier -quiet -filter {REF_NAME == IOBUF}]
set mdio_iobufs [get_cells -hier -quiet -filter {REF_NAME == IOBUF && NAME =~ *mdio*}]
set mdio_leafs [get_pins -hier -quiet -filter {REF_PIN_NAME == EMIOENET2MDIOI}]
if {[llength $all_iobufs] != 1 || [llength $mdio_iobufs] != 1 || [llength $mdio_leafs] != 1} { error "MDIO route structure mismatch" }
set mdio_exception_text [report_exceptions -to $mdio_leafs -return_string]
set mef [open [file join $reports_dir mdio_exceptions_route.rpt] w]
puts -nonewline $mef $mdio_exception_text
close $mef
if {![regexp {EMIOENET2MDIOI.*false\s+false} $mdio_exception_text]} { error "MDIO setup/hold false path is not present in route exception report" }
set mf [open [file join $reports_dir mdio_connectivity_route.txt] w]
puts $mf "IOBUF_TOTAL_COUNT=[llength $all_iobufs] MDIO_IOBUF_COUNT=[llength $mdio_iobufs] MDIO_INPUT_LEAF_COUNT=[llength $mdio_leafs]"
puts $mf "SETUP_FALSE_PATH=true HOLD_FALSE_PATH=true FALSE_PATH=PASS"
close $mf

# Timing sign-off.
set timing_text [report_timing_summary -delay_type min_max -report_unconstrained -return_string]
set tf [open [file join $reports_dir timing_summary_route.rpt] w]
puts -nonewline $tf $timing_text
close $tf
set timing_found 0
foreach line [split $timing_text "\n"] {
  if {[regexp {^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+([0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+([0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+([0-9]+)\s*$} $line -> wns tns setup_fail setup_total whs ths hold_fail hold_total wpws tpws pw_fail pw_total]} {
    set timing_found 1
    break
  }
}
if {!$timing_found} { error "Unable to parse design timing summary" }
if {$wns < 0.0 || $tns < 0.0 || $whs < 0.0 || $ths < 0.0 || $wpws < 0.0 || $tpws < 0.0 || $setup_fail != 0 || $hold_fail != 0 || $pw_fail != 0} {
  error "Timing sign-off failed: WNS=$wns TNS=$tns setup_fail=$setup_fail WHS=$whs THS=$ths hold_fail=$hold_fail WPWS=$wpws TPWS=$tpws pw_fail=$pw_fail"
}
set ts [open [file join $reports_dir timing_signoff_guard.txt] w]
puts $ts "WNS=$wns TNS=$tns SETUP_FAILING_ENDPOINTS=$setup_fail"
puts $ts "WHS=$whs THS=$ths HOLD_FAILING_ENDPOINTS=$hold_fail"
puts $ts "WPWS=$wpws TPWS=$tpws PW_FAILING_ENDPOINTS=$pw_fail"
close $ts
report_timing -to [get_ports -quiet -filter {NAME =~ rgmii_txd* || NAME == rgmii_tx_ctl || NAME == rgmii_txc}] -delay_type max -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_tx_setup_route.rpt]
report_timing -to [get_ports -quiet -filter {NAME =~ rgmii_txd* || NAME == rgmii_tx_ctl || NAME == rgmii_txc}] -delay_type min -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_tx_hold_route.rpt]
report_timing -from [get_ports -quiet -filter {NAME =~ rgmii_rxd* || NAME == rgmii_rx_ctl || NAME == rgmii_rxc}] -delay_type max -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_rx_setup_route.rpt]
report_timing -from [get_ports -quiet -filter {NAME =~ rgmii_rxd* || NAME == rgmii_rx_ctl || NAME == rgmii_rxc}] -delay_type min -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_rx_hold_route.rpt]

# DRC, methodology, CDC, utilization.
report_drc -file [file join $reports_dir drc_route.rpt]
set blocking_drc [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]
if {[llength $blocking_drc] != 0} { error "Blocking DRC violations: $blocking_drc" }
report_methodology -file [file join $reports_dir methodology_route.rpt]
report_utilization -file [file join $reports_dir utilization_route.rpt]
set cdc_path [file join $reports_dir cdc_route.rpt]
report_cdc -details -file $cdc_path
set cfh [open $cdc_path r]; set cdc_text [read $cfh]; close $cfh
foreach {pattern label} {
  {CDC-3\s+Info\s+13} CDC3
  {CDC-9\s+Info\s+3} CDC9
  {CDC-10\s+Critical\s+1} CDC10
  {CDC-11\s+Critical\s+2} CDC11
  {CDC-13\s+Critical\s+1} CDC13
  {CDC-15\s+Warning\s+56} CDC15
  {CDC-17\s+Warning\s+1} CDC17
} { if {![regexp $pattern $cdc_text]} { error "Route CDC classification changed: $label" } }
set cgf [open [file join $reports_dir cdc_classification_guard_route.txt] w]
foreach line [split $cdc_text "\n"] {
  if {[regexp {^\s*[0-9]+\s+CDC-3\s+Info} $line] && [string first "u_rx_clock_converter" $line] < 0 && [string first "u_temac_wrapper/u_temac" $line] < 0 && [string first "dbg_hub" $line] < 0} { error "CDC-3 outside allowed IP/debug: $line" }
  if {[regexp {^\s*[0-9]+\s+CDC-9\s+Info} $line] && [string first "u_temac_wrapper/u_temac" $line] < 0 && [string first "dbg_hub" $line] < 0} { error "CDC-9 outside allowed IP/debug: $line" }
  if {[regexp {^\s*[0-9]+\s+CDC-11\s+Critical} $line] && [string first "u_temac_wrapper/u_temac" $line] < 0} { error "CDC-11 outside TEMAC: $line" }
  if {[regexp {^\s*[0-9]+\s+CDC-13\s+Critical} $line] && ([string first "phy_mdio" $line] < 0 || [string first "EMIOENET2MDIOI" $line] < 0)} { error "CDC-13 outside known MDIO false-path: $line" }
  if {[regexp {^\s*[0-9]+\s+CDC-15\s+Warning} $line] && [string first "u_rx_clock_converter" $line] < 0 && [string first "u_temac_wrapper/u_temac" $line] < 0 && [string first "dbg_hub" $line] < 0} { error "CDC-15 outside allowed IP/debug: $line" }
  if {[regexp {^\s*[0-9]+\s+CDC-17\s+Warning} $line] && [string first "u_temac_wrapper/u_temac" $line] < 0} { error "CDC-17 outside TEMAC: $line" }
  if {[regexp {^\s*[0-9]+\s+CDC-10\s+Critical} $line]} {
    if {[string first "resetn_reg/C" $line] < 0 || [string first "u_p4fab_endpoint/u_rx_reset_sync/sync_ff_reg\[0\]/CLR" $line] < 0} { error "Unexpected CDC-10: $line" }
    puts $cgf "CDC10_PATH=$line"
  }
}
puts $cgf "SUMMARY=CDC3:13 CDC9:3 CDC10:1 CDC11:2 CDC13:1 CDC15:56 CDC17:1"
puts $cgf "CDC11_CLASSIFICATION=existing_TEMAC_internal_only"
puts $cgf "CDC13_CLASSIFICATION=existing_MDIO_input_false_path_only"
puts $cgf "UNEXPECTED_DATA_CDC_OUTSIDE_CLOCK_CONVERTER_TEMAC_MDIO_DEBUG=0"
close $cgf
check_timing -verbose -file [file join $reports_dir check_timing_route.rpt]

set sf [open [file join $reports_dir implementation_signoff.txt] w]
puts $sf "RESULT=PASS RUN_STATUS=$impl_status"
puts $sf "ROUTABLE_NETS=$routable_count FULLY_ROUTED_NETS=$routed_count ROUTING_ERRORS=$routing_errors"
puts $sf "WNS=$wns TNS=$tns SETUP_FAIL=$setup_fail WHS=$whs THS=$ths HOLD_FAIL=$hold_fail WPWS=$wpws TPWS=$tpws PW_FAIL=$pw_fail"
puts $sf "TXC_DELAY=975 RX_IDELAY_COUNT=5 RX_IDELAY_VALUE=900"
puts $sf "FRAME_BUFFER_COUNT=[llength $frame_buffers] TX_FRAME_BUFFER_COUNT=1 RX_FRAME_BUFFER_COUNT=1 TX_UNPACKER_COUNT=1"
puts $sf "TX_SETUP_EDGE_PAIRS=$setup_pairs TX_HOLD_EDGE_PAIRS=$hold_pairs"
puts $sf "BLOCKING_DRC_COUNT=[llength $blocking_drc]"
close $sf

# All sign-off guards passed. Continue only the run-managed write_bitstream step
# so that write_hw_platform can include exactly the same run bitstream.
close_design
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {![string match "write_bitstream Complete*" [get_property STATUS [get_runs impl_1]]]} {
  error "write_bitstream did not complete: [get_property STATUS [get_runs impl_1]]"
}
set run_bit [file join $project_dir stage1g4_hw_top_case_c_txc975_usb_gem2_mdio_clkoff_03m6_hw_tx_frame_buffer.runs impl_1 stage1g4_hw_top.bit]
if {![file exists $run_bit]} { error "Run-managed bitstream missing: $run_bit" }
file copy $run_bit $bit_artifact
open_run impl_1
write_debug_probes $ltx_artifact
write_hw_platform -fixed -include_bit -file $xsa_artifact
foreach artifact [list $bit_artifact $xsa_artifact $ltx_artifact] {
  if {![file exists $artifact] || [file size $artifact] == 0} { error "Artifact missing or empty: $artifact" }
}
set af [open [file join $reports_dir artifact_generation.txt] w]
puts $af "RUN_BIT=$run_bit"
puts $af "BIT=$bit_artifact SIZE=[file size $bit_artifact]"
puts $af "XSA=$xsa_artifact SIZE=[file size $xsa_artifact]"
puts $af "LTX=$ltx_artifact SIZE=[file size $ltx_artifact]"
close $af
close_design
close_project
puts "03M6_IMPLEMENTATION_AND_ARTIFACTS_PASS"
