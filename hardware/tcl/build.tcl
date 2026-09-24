set script_dir [file normalize [file dirname [info script]]]
set hardware_dir [file normalize [file join $script_dir ..]]
set project_dir [file join $hardware_dir build vivado]
set reports_dir [file join $hardware_dir reports]
set build_jobs 8
if {[info exists ::env(STAGE1G4_JOBS)]} { set build_jobs $::env(STAGE1G4_JOBS) }
file mkdir $project_dir
file mkdir $reports_dir

create_project stage1g4_hw_top_case_c_txc975_usb_gem2_mdio_clkoff_03m6_hw_tx_frame_buffer $project_dir -part xck26-sfvc784-2LV-c -force
set_property board_part xilinx.com:kr260_som:part0:2.0 [current_project]
set_property board_connections {som240_1_connector xilinx.com:kr260_carrier:som240_1_connector:2.0 som240_2_connector xilinx.com:kr260_carrier:som240_2_connector:2.0} [current_project]
set_property target_language Verilog [current_project]
set repo_dir $hardware_dir
add_files -norecurse [list [file join $hardware_dir rtl gmii_idle_terminator.v]]

# TEMAC案C baselineを生成し、TXC master delayだけを後段hookで975へ上書きする。
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name stage1g4_clk_wiz
set_property -dict [list CONFIG.PRIM_IN_FREQ {25.000} CONFIG.CLK_IN1_BOARD_INTERFACE {som240_1_connector_hpa_clk0p_clk} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} CONFIG.CLKOUT2_USED {true} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {333.333} CONFIG.USE_LOCKED {true} CONFIG.USE_RESET {false}] [get_ips stage1g4_clk_wiz]
create_ip -name tri_mode_ethernet_mac -vendor xilinx.com -library ip -version 9.0 -module_name temac_0
set_property -dict [list CONFIG.Physical_Interface {RGMII} CONFIG.MAC_Speed {1000_Mbps} CONFIG.Half_Duplex {false} CONFIG.Management_Interface {false} CONFIG.Enable_MDIO {false} CONFIG.Statistics_Counters {false} CONFIG.Frame_Filter {false} CONFIG.Enable_AVB {false} CONFIG.Enable_Priority_Flow_Control {false} CONFIG.Enable_1588 {false} CONFIG.EN_IODELAY {true} CONFIG.SupportLevel {1}] [get_ips temac_0]
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_03m5_p4fab_tx
set_property -dict [list \
  CONFIG.C_DATA_DEPTH {2048} \
  CONFIG.C_NUM_OF_PROBES {5} \
  CONFIG.C_PROBE0_WIDTH {32} \
  CONFIG.C_PROBE1_WIDTH {4} \
  CONFIG.C_PROBE2_WIDTH {3} \
  CONFIG.C_PROBE3_WIDTH {8} \
  CONFIG.C_PROBE4_WIDTH {6}] [get_ips ila_03m5_p4fab_tx]
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_03m_rx
set_property -dict [list \
  CONFIG.TDATA_NUM_BYTES {4} \
  CONFIG.HAS_TSTRB {0} \
  CONFIG.HAS_TKEEP {1} \
  CONFIG.HAS_TLAST {1} \
  CONFIG.TID_WIDTH {0} \
  CONFIG.TDEST_WIDTH {0} \
  CONFIG.TUSER_WIDTH {0} \
  CONFIG.IS_ACLK_ASYNC {1} \
  CONFIG.SYNCHRONIZATION_STAGES {2}] [get_ips axis_clock_converter_03m_rx]

# Read back every 03m-5 P4Fab/TX ILA setting before target generation or synthesis.
set ila_guard_file [open [file join $reports_dir ila_configuration_guard.txt] w]
foreach {property expected} {
  CONFIG.C_DATA_DEPTH 2048
  CONFIG.C_NUM_OF_PROBES 5
  CONFIG.C_PROBE0_WIDTH 32
  CONFIG.C_PROBE1_WIDTH 4
  CONFIG.C_PROBE2_WIDTH 3
  CONFIG.C_PROBE3_WIDTH 8
  CONFIG.C_PROBE4_WIDTH 6
} {
  set actual [get_property $property [get_ips ila_03m5_p4fab_tx]]
  puts $ila_guard_file "$property expected={$expected} resolved={$actual}"
  if {$actual ne $expected} {
    close $ila_guard_file
    error "ILA $property expected '$expected', got '$actual'"
  }
}
close $ila_guard_file
set axis_guard_file [open [file join $reports_dir axis_clock_converter_configuration.txt] w]
foreach {property expected} {
  CONFIG.TDATA_NUM_BYTES 4
  CONFIG.HAS_TSTRB 0
  CONFIG.HAS_TKEEP 1
  CONFIG.HAS_TLAST 1
  CONFIG.TID_WIDTH 0
  CONFIG.TDEST_WIDTH 0
  CONFIG.TUSER_WIDTH 0
  CONFIG.IS_ACLK_ASYNC 1
  CONFIG.SYNCHRONIZATION_STAGES 2
} {
  set actual [get_property $property [get_ips axis_clock_converter_03m_rx]]
  puts $axis_guard_file "$property expected={$expected} resolved={$actual}"
  if {$actual ne $expected} {
    close $axis_guard_file
    error "Clock Converter $property expected '$expected', got '$actual'"
  }
}
close $axis_guard_file
set packet_guard_file [open [file join $reports_dir packet_configuration_guard.txt] w]
foreach {property expected} {
  CONFIG.Physical_Interface RGMII
  CONFIG.MAC_Speed 1000_Mbps
  CONFIG.Management_Interface false
  CONFIG.Enable_MDIO false
  CONFIG.EN_IODELAY true
} {
  set actual [get_property $property [get_ips temac_0]]
  puts $packet_guard_file "$property expected={$expected} resolved={$actual}"
  if {$actual ne $expected} { close $packet_guard_file; error "TEMAC $property expected '$expected', got '$actual'" }
}
foreach {property expected} {
  CONFIG.PRIM_IN_FREQ 25.000
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 125.000
  CONFIG.CLKOUT2_USED true
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 333.333
  CONFIG.USE_LOCKED true
  CONFIG.USE_RESET false
} {
  set actual [get_property $property [get_ips stage1g4_clk_wiz]]
  puts $packet_guard_file "$property expected={$expected} resolved={$actual}"
  if {$actual ne $expected} { close $packet_guard_file; error "Packet clock wizard $property expected '$expected', got '$actual'" }
}
close $packet_guard_file
generate_target all [get_ips {stage1g4_clk_wiz temac_0 ila_03m5_p4fab_tx axis_clock_converter_03m_rx}]

# USB0/USB1を維持したPS GEM2 management-only BD。
create_bd_design stage1g4_ps_usb_gem2_mdio
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
set_property -dict [list \
  CONFIG.PSU__USB0__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__USB0__PERIPHERAL__IO {MIO 52 .. 63} \
  CONFIG.PSU__USB0__RESET__ENABLE 1 \
  CONFIG.PSU__USB0__RESET__IO {MIO 76} \
  CONFIG.PSU__USB0__REF_CLK_SEL {Ref Clk2} \
  CONFIG.PSU__USB0__REF_CLK_FREQ 26 \
  CONFIG.PSU__USB1__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__USB1__PERIPHERAL__IO {MIO 64 .. 75} \
  CONFIG.PSU__USB1__RESET__ENABLE 1 \
  CONFIG.PSU__USB1__RESET__IO {MIO 77} \
  CONFIG.PSU__USB1__REF_CLK_SEL {Ref Clk3} \
  CONFIG.PSU__USB1__REF_CLK_FREQ 26 \
  CONFIG.PSU__ENET2__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__ENET2__PERIPHERAL__IO EMIO \
  CONFIG.PSU__ENET2__GRP_MDIO__ENABLE 1 \
  CONFIG.PSU__ENET2__GRP_MDIO__IO EMIO] $ps

# Step 2cと同じくpresetのHPM0/HPM1を有効のままPL0 clockへ接続する。
connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins $ps/maxihpm0_fpd_aclk] [get_bd_pins $ps/maxihpm1_fpd_aclk]

set idle [create_bd_cell -type module -reference gmii_idle_terminator idle]
proc require_one_bd_pin {pattern} {
  set pins [get_bd_pins -quiet $pattern]
  if {[llength $pins] != 1} { error "Expected one BD pin for $pattern, got [llength $pins]: $pins" }
  return [lindex $pins 0]
}
set gmii_rx_clk [require_one_bd_pin $ps/emio_enet2_gmii_rx_clk]
set gmii_tx_clk [require_one_bd_pin $ps/emio_enet2_gmii_tx_clk]
connect_bd_net [get_bd_pins $idle/gmii_rx_clk] $gmii_rx_clk
connect_bd_net [get_bd_pins $idle/gmii_tx_clk] $gmii_tx_clk
foreach {ps_pin idle_pin} {
  emio_enet2_gmii_rxd gmii_rxd
  emio_enet2_gmii_rx_dv gmii_rx_dv
  emio_enet2_gmii_rx_er gmii_rx_er
  emio_enet2_gmii_crs gmii_crs
  emio_enet2_gmii_col gmii_col
  emio_enet2_gmii_txd gmii_txd
  emio_enet2_gmii_tx_en gmii_tx_en
  emio_enet2_gmii_tx_er gmii_tx_er
} {
  connect_bd_net [require_one_bd_pin $ps/$ps_pin] [get_bd_pins $idle/$idle_pin]
}

set expected_properties [dict create \
  CONFIG.PSU__USB0__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__USB0__PERIPHERAL__IO {MIO 52 .. 63} \
  CONFIG.PSU__USB0__RESET__ENABLE 1 \
  CONFIG.PSU__USB0__RESET__IO {MIO 76} \
  CONFIG.PSU__USB0__REF_CLK_SEL {Ref Clk2} \
  CONFIG.PSU__USB0__REF_CLK_FREQ 26 \
  CONFIG.PSU__USB1__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__USB1__PERIPHERAL__IO {MIO 64 .. 75} \
  CONFIG.PSU__USB1__RESET__ENABLE 1 \
  CONFIG.PSU__USB1__RESET__IO {MIO 77} \
  CONFIG.PSU__USB1__REF_CLK_SEL {Ref Clk3} \
  CONFIG.PSU__USB1__REF_CLK_FREQ 26 \
  CONFIG.PSU__ENET2__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__ENET2__PERIPHERAL__IO EMIO \
  CONFIG.PSU__ENET2__GRP_MDIO__ENABLE 1 \
  CONFIG.PSU__ENET2__GRP_MDIO__IO EMIO \
  CONFIG.PSU__UART1__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 36 .. 37} \
  CONFIG.PSU__UART1__BAUD_RATE 115200 \
  CONFIG.PSU__QSPI__PERIPHERAL__ENABLE 1 \
  CONFIG.PSU__QSPI__PERIPHERAL__IO {MIO 0 .. 5} \
  CONFIG.PSU__FPGA_PL0_ENABLE 1 \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ 100 \
  CONFIG.PSU__FPGA_PL1_ENABLE 1 \
  CONFIG.PSU__CRL_APB__PL1_REF_CTRL__FREQMHZ 100 \
  CONFIG.PSU__FPGA_PL2_ENABLE 0 \
  CONFIG.PSU__FPGA_PL3_ENABLE 0 \
  CONFIG.PSU__NUM_FABRIC_RESETS 1]
set pf [open [file join $reports_dir resolved_ps_config.txt] w]
set mismatches {}
dict for {p expected} $expected_properties {
  set actual [get_property $p $ps]
  set result [expr {$actual eq $expected ? "MATCH" : "MISMATCH"}]
  puts $pf "$result $p expected={$expected} resolved={$actual}"
  if {$actual ne $expected} { lappend mismatches "$p={$actual}" }
}
foreach p {
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ
  CONFIG.PSU__CRL_APB__PL1_REF_CTRL__ACT_FREQMHZ
  CONFIG.PSU__USE__M_AXI_GP0 CONFIG.PSU__USE__M_AXI_GP1
} { puts $pf "INFO $p resolved={[get_property $p $ps]}" }
close $pf
if {[llength $mismatches]} { error "Step 2c PS configuration mismatch: $mismatches" }

set mdio_if [get_bd_intf_pins -quiet $ps/MDIO_ENET2]
set gmii_if [get_bd_intf_pins -quiet $ps/GMII_ENET2]
if {[llength $mdio_if] != 1} { error "Expected one MDIO_ENET2 interface" }
if {[llength $gmii_if] != 1} { error "Expected one GMII_ENET2 interface" }

make_bd_intf_pins_external $mdio_if
set mdio_ext [get_bd_intf_ports -quiet MDIO_ENET2_0]
if {[llength $mdio_ext] != 1} { error "Expected generated MDIO_ENET2_0 interface" }
set_property name MDIO_PHY $mdio_ext

set gr [open [file join $reports_dir gmii_connections.txt] w]
puts $gr "GMII_ENET2_COUNT=[llength $gmii_if] MDIO_ENET2_COUNT=[llength $mdio_if]"
foreach p [lsort [get_bd_pins $ps/emio_enet2_gmii_*]] {
  puts $gr "$p DIR=[get_property DIR $p] NET=[get_bd_nets -of_objects $p] CONNECTED=[get_bd_pins -of_objects [get_bd_nets -of_objects $p]]"
}
puts $gr "EXTERNAL_GMII_PORTS=[get_bd_ports -quiet *gmii*]"
close $gr

set mgmt_cells [get_bd_cells -quiet mgmt_clk125]
if {[llength $mgmt_cells] != 0} { error "mgmt_clk125 must not exist: $mgmt_cells" }
set rx_clk_net [get_bd_nets -of_objects $gmii_rx_clk]
set tx_clk_net [get_bd_nets -of_objects $gmii_tx_clk]
set rx_clk_connections [get_bd_pins -of_objects $rx_clk_net]
set tx_clk_connections [get_bd_pins -of_objects $tx_clk_net]
if {[lsearch -exact $rx_clk_connections $idle/gmii_rx_clk] < 0} { error "GEM2 RX_CLK is not connected to idle constant-Low source" }
if {[lsearch -exact $tx_clk_connections $idle/gmii_tx_clk] < 0} { error "GEM2 TX_CLK is not connected to idle constant-Low source" }
set cr [open [file join $reports_dir management_clock_report.txt] w]
puts $cr "MGMT_CLK125_BD_CELL_COUNT=[llength $mgmt_cells]"
puts $cr "RX_CLK_PIN=$gmii_rx_clk NET=$rx_clk_net CONNECTED=$rx_clk_connections EXPECTED_SOURCE=$idle/gmii_rx_clk VALUE=0"
puts $cr "TX_CLK_PIN=$gmii_tx_clk NET=$tx_clk_net CONNECTED=$tx_clk_connections EXPECTED_SOURCE=$idle/gmii_tx_clk VALUE=0"
close $cr

save_bd_design
set vf [open [file join $reports_dir bd_validation.txt] w]
set vrc [catch {validate_bd_design} verr vopts]
if {$vrc} {
  puts $vf "RESULT=FAIL\nERROR=$verr\nERRORINFO=[dict get $vopts -errorinfo]"
  close $vf
  error $verr
}
puts $vf "RESULT=PASS"
close $vf
save_bd_design
if {[info exists ::env(STAGE1G4_STOP_AFTER_BD)] && $::env(STAGE1G4_STOP_AFTER_BD) eq "1"} {
  puts "STAGE1G4_STOP_AFTER_BD=1: BD validation passed; stopping before synthesis"
  close_project
  exit 0
}
set bd_file [get_files */stage1g4_ps_usb_gem2_mdio.bd]
generate_target all $bd_file
set wrapper_file [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_file

add_files -norecurse [list \
  [file join $repo_dir rtl p4fab_frame_buffer_noready_8.sv] \
  [file join $repo_dir rtl p4fab_pack_8to32.sv] \
  [file join $repo_dir rtl p4fab_unpack_32to8.sv] \
  [file join $hardware_dir rtl p4fab_reset_sync.sv] \
  [file join $hardware_dir rtl p4fab_temac_endpoint.sv] \
  [file join $hardware_dir rtl stage1g4_hw_top.sv] \
  [file join $hardware_dir rtl temac_rgmii_wrapper.sv]]
set_property top stage1g4_hw_top [current_fileset]
add_files -fileset constrs_1 -norecurse [file join $hardware_dir constraints stage1g4_pins.xdc]
update_compile_order -fileset sources_1

# synth_1のRTL elaborationはIP synthesis checkpointを含む通常flowで行う。
launch_runs synth_1 -jobs $build_jobs
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "Synthesis failed: [get_property STATUS [get_runs synth_1]]" }
open_run synth_1
report_utilization -file [file join $reports_dir utilization_synth.rpt]

# 03m-2 synthesis checkpoint.  Stop unconditionally after these guards; the
# inherited 03k implementation flow below is deliberately unreachable here.
proc m03_require_one_cell {pattern label} {
  set objects [get_cells -hier -quiet $pattern]
  if {[llength $objects] != 1} { error "$label expected one cell for $pattern, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc m03_require_one_pin {pattern label} {
  # NAME filtering is intentional: rebuilt pin names such as D[0] must be
  # matched literally rather than interpreted as Tcl/Vivado glob syntax.
  set objects [get_pins -hier -quiet -filter "NAME == \"$pattern\""]
  if {[llength $objects] != 1} { error "$label expected one pin for $pattern, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc m03_require_ref_pin {cell ref_pin_name label} {
  set objects [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME == \"$ref_pin_name\""]
  if {[llength $objects] != 1} { error "$label expected one $ref_pin_name pin on $cell, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc m03_require_same_net {report_handle label pins} {
  set common {}
  set logic_values {}
  foreach pin $pins {
    lappend logic_values [get_property -quiet LOGIC_VALUE $pin]
    set segments [get_nets -quiet -segments -of_objects $pin]
    puts $report_handle "$label PIN=$pin LOGIC=[get_property -quiet LOGIC_VALUE $pin] SEGMENTS=$segments"
    if {[llength $segments] == 0} { continue }
    if {[llength $common] == 0} {
      set common $segments
    } else {
      set intersection {}
      foreach segment $common {
        if {[lsearch -exact $segments $segment] >= 0} { lappend intersection $segment }
      }
      set common $intersection
    }
  }
  if {[llength $common] != 0} {
    puts $report_handle "$label RESULT=PASS COMMON_SEGMENT=[lindex $common 0]"
    return
  }
  set first_logic [lindex $logic_values 0]
  if {$first_logic eq "zero" || $first_logic eq "one"} {
    set all_same 1
    foreach value $logic_values { if {$value ne $first_logic} { set all_same 0 } }
    if {$all_same} {
      puts $report_handle "$label RESULT=PASS CONSTANT=$first_logic"
      return
    }
  }
  error "$label has no common net segment: $pins"
}

current_instance
set temac_cells [get_cells -hier -quiet -filter {REF_NAME == temac_0 && ORIG_REF_NAME == temac_0}]
if {[llength $temac_cells] != 1} { error "TEMAC expected exactly one instance, got [llength $temac_cells]: $temac_cells" }
set temac_cell [lindex $temac_cells 0]
set endpoint_cell [m03_require_one_cell u_p4fab_endpoint ENDPOINT]
set ila_cell [m03_require_one_cell u_ila_03m5_p4fab_tx P4FAB_TX_ILA]
set fixed_generators [get_cells -hier -quiet -filter {ORIG_REF_NAME == fixed_frame_tx || REF_NAME == fixed_frame_tx}]
if {[llength $fixed_generators] != 0} { error "fixed_frame_tx must not exist in 03m-2: $fixed_generators" }

set cf [open [file join $reports_dir endpoint_connectivity_synth.txt] w]
puts $cf "TEMAC_COUNT=[llength $temac_cells] TEMAC=$temac_cell"
puts $cf "ENDPOINT=$endpoint_cell REF_NAME=[get_property REF_NAME $endpoint_cell]"
puts $cf "FIXED_FRAME_TX_COUNT=[llength $fixed_generators]"
puts $cf "P4FAB_TX_ILA=$ila_cell ROLE=PASSIVE_P4FAB_TX_OBSERVER"

for {set bit 0} {$bit < 80} {incr bit} {
  foreach direction {rx tx} {
    set p [m03_require_ref_pin $temac_cell "${direction}_configuration_vector\[$bit\]" "${direction}_configuration_vector_$bit"]
    set expected [expr {$bit == 1 ? "one" : "zero"}]
    set actual [get_property -quiet LOGIC_VALUE $p]
    puts $cf "[string toupper $direction]_CONFIGURATION_VECTOR_$bit EXPECTED=$expected ACTUAL=$actual PIN=$p"
    if {$actual ne $expected} { close $cf; error "$direction configuration vector bit $bit expected $expected, got $actual" }
  }
}
puts $cf "RX_CONFIGURATION_VECTOR=80'h00000000000000000002"
puts $cf "TX_CONFIGURATION_VECTOR=80'h00000000000000000002"

# TEMAC client mapping at the endpoint boundary.
foreach {label temac_ref endpoint_pin} {
  RX_TVALID rx_axis_mac_tvalid u_p4fab_endpoint/rx_axis_mac_tvalid
  RX_TLAST  rx_axis_mac_tlast  u_p4fab_endpoint/rx_axis_mac_tlast
  RX_TUSER  rx_axis_mac_tuser  u_p4fab_endpoint/rx_axis_mac_tuser
  RX_RESET  rx_reset           u_p4fab_endpoint/rx_reset
  TX_TVALID tx_axis_mac_tvalid u_p4fab_endpoint/tx_axis_mac_tvalid
  TX_TREADY tx_axis_mac_tready u_p4fab_endpoint/tx_axis_mac_tready
  TX_TLAST  tx_axis_mac_tlast  u_p4fab_endpoint/tx_axis_mac_tlast
  TX_TUSER  tx_axis_mac_tuser  u_p4fab_endpoint/tx_axis_mac_tuser
  TX_RESET  tx_reset           u_p4fab_endpoint/tx_reset
} {
  m03_require_same_net $cf $label [list [m03_require_ref_pin $temac_cell $temac_ref $label] [m03_require_one_pin $endpoint_pin $label]]
}
for {set bit 0} {$bit < 8} {incr bit} {
  m03_require_same_net $cf RX_TDATA_$bit [list \
    [m03_require_ref_pin $temac_cell "rx_axis_mac_tdata\[$bit\]" RX_TDATA_$bit] \
    [m03_require_one_pin "u_p4fab_endpoint/rx_axis_mac_tdata\[$bit\]" RX_TDATA_$bit]]
  m03_require_same_net $cf TX_TDATA_$bit [list \
    [m03_require_ref_pin $temac_cell "tx_axis_mac_tdata\[$bit\]" TX_TDATA_$bit] \
    [m03_require_one_pin "u_p4fab_endpoint/tx_axis_mac_tdata\[$bit\]" TX_TDATA_$bit]]
}

# Direct P4Fab RX-to-TX AXI4-Stream loopback at the wrapper boundary.
foreach {label width} {TDATA 32 TKEEP 4 TVALID 1 TREADY 1 TLAST 1} {
  for {set bit 0} {$bit < $width} {incr bit} {
    set suffix [expr {$width == 1 ? "" : "\[$bit\]"}]
    m03_require_same_net $cf LOOPBACK_${label}${suffix} [list \
      [m03_require_one_pin "u_p4fab_endpoint/p4fab_rx_[string tolower $label]${suffix}" LOOPBACK_RX_${label}] \
      [m03_require_one_pin "u_p4fab_endpoint/p4fab_tx_[string tolower $label]${suffix}" LOOPBACK_TX_${label}]]
  }
}

# Clock identity is checked by electrical net segments, not just frequency.
set temac_tx_clk [m03_require_ref_pin $temac_cell tx_mac_aclk TX_MAC_ACLK]
set temac_rx_clk [m03_require_ref_pin $temac_cell rx_mac_aclk RX_MAC_ACLK]
set endpoint_p4_clk [m03_require_one_pin u_p4fab_endpoint/p4fab_clk P4FAB_CLK]
set endpoint_rx_clk [m03_require_one_pin u_p4fab_endpoint/rx_mac_aclk ENDPOINT_RX_CLK]
m03_require_same_net $cf P4FAB_GTX_TX_CLOCK_IDENTITY [list $endpoint_p4_clk $temac_tx_clk]
m03_require_same_net $cf RX_MAC_CLOCK_CONNECTION [list $endpoint_rx_clk $temac_rx_clk]

# Generated Clock Converter and reset synchronizers must survive synthesis.
set converter_cells [get_cells -hier -quiet -filter {ORIG_REF_NAME == axis_clock_converter_03m_rx || REF_NAME == axis_clock_converter_03m_rx}]
if {[llength $converter_cells] != 1} { close $cf; error "Clock Converter expected exactly one instance, got [llength $converter_cells]: $converter_cells" }
set converter_cell [lindex $converter_cells 0]
set converter_s_clk [m03_require_ref_pin $converter_cell s_axis_aclk CONVERTER_S_AXIS_ACLK]
set converter_m_clk [m03_require_ref_pin $converter_cell m_axis_aclk CONVERTER_M_AXIS_ACLK]
m03_require_same_net $cf CLOCK_CONVERTER_SOURCE_CLOCK [list $converter_s_clk $temac_rx_clk]
m03_require_same_net $cf CLOCK_CONVERTER_SINK_CLOCK [list $converter_m_clk $endpoint_p4_clk $temac_tx_clk]
puts $cf "CLOCK_CONVERTER=$converter_cell SOURCE_CLOCK=$converter_s_clk SINK_CLOCK=$converter_m_clk"

# 03m-6 functional delta: exactly one RX and one TX instance of the unchanged
# Stage 1e frame buffer.  Guard every TX boundary so an old direct
# unpacker-to-TEMAC path cannot pass this checkpoint.
set frame_buffers [get_cells -hier -quiet -filter {ORIG_REF_NAME == p4fab_frame_buffer_noready_8 || REF_NAME == p4fab_frame_buffer_noready_8}]
if {[llength $frame_buffers] != 2} { close $cf; error "Expected exactly two frame buffers (RX/TX), got $frame_buffers" }
set rx_frame_buffer [lindex $frame_buffers [lsearch -exact $frame_buffers u_p4fab_endpoint/u_rx_frame_buffer]]
set tx_frame_buffer [lindex $frame_buffers [lsearch -exact $frame_buffers u_p4fab_endpoint/u_tx_frame_buffer]]
if {$rx_frame_buffer ne "u_p4fab_endpoint/u_rx_frame_buffer" || $tx_frame_buffer ne "u_p4fab_endpoint/u_tx_frame_buffer"} {
  close $cf; error "RX/TX frame buffer identities changed: $frame_buffers"
}
set unpackers [get_cells -hier -quiet -filter {ORIG_REF_NAME == p4fab_unpack_32to8 || REF_NAME == p4fab_unpack_32to8}]
if {[llength $unpackers] != 1} { close $cf; error "Expected exactly one TX unpacker, got $unpackers" }
set tx_unpacker [lindex $unpackers 0]
puts $cf "FRAME_BUFFER_COUNT=[llength $frame_buffers] RX_FRAME_BUFFER=$rx_frame_buffer TX_FRAME_BUFFER=$tx_frame_buffer"
puts $cf "TX_UNPACKER_COUNT=1 TX_UNPACKER=$tx_unpacker"
foreach {label producer_ref consumer_ref width} {
  TX_UNPACK_TO_BUFFER_DATA m_data s_data 8
  TX_BUFFER_TO_TEMAC_DATA m_data tx_axis_mac_tdata 8
} {
  for {set bit 0} {$bit < $width} {incr bit} {
    set producer [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? $tx_unpacker : $tx_frame_buffer}]
    set consumer [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? $tx_frame_buffer : $endpoint_cell}]
    set producer_pin [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? \
      [m03_require_one_pin "${producer}/D\[$bit\]" ${label}_$bit] : \
      [m03_require_one_pin "${producer}/tx_axis_mac_tdata\[$bit\]" ${label}_$bit]}]
    set consumer_pin [expr {$label eq "TX_UNPACK_TO_BUFFER_DATA" ? \
      [m03_require_one_pin "${consumer}/D\[$bit\]" ${label}_$bit] : \
      [m03_require_one_pin "${consumer}/tx_axis_mac_tdata\[$bit\]" ${label}_$bit]}]
    m03_require_same_net $cf ${label}_$bit [list $producer_pin $consumer_pin]
  }
}
foreach {label producer producer_ref consumer consumer_ref} [list \
  TX_UNPACK_TO_BUFFER_VALID $tx_unpacker tx_unpack_valid $tx_frame_buffer tx_unpack_valid \
  TX_UNPACK_TO_BUFFER_LAST  $tx_unpacker tx_unpack_last  $tx_frame_buffer tx_unpack_last \
  TX_BUFFER_TO_TEMAC_LAST   $tx_frame_buffer tx_axis_mac_tlast $endpoint_cell tx_axis_mac_tlast \
  TX_TEMAC_READY_TO_BUFFER  $endpoint_cell tx_axis_mac_tready $tx_frame_buffer tx_axis_mac_tready] {
  m03_require_same_net $cf $label [list \
    [m03_require_one_pin "${producer}/${producer_ref}" $label] \
    [m03_require_one_pin "${consumer}/${consumer_ref}" $label]]
}
# The explicit tx_path_aresetn gate lets synthesis absorb the buffer's m_valid
# cone into u_tx_reset_sync.  The static RTL guard above proves the assignment;
# here require that the surviving endpoint valid output still exists.
puts $cf "TX_BUFFER_TO_TEMAC_VALID_RESET_GATED_PIN=[m03_require_one_pin ${endpoint_cell}/tx_axis_mac_tvalid TX_BUFFER_TO_TEMAC_VALID]"
m03_require_same_net $cf TX_FRAME_BUFFER_CLOCK [list \
  [m03_require_one_pin "${tx_frame_buffer}/p4fab_clk" TX_FRAME_BUFFER_CLOCK] $endpoint_p4_clk $temac_tx_clk]
puts $cf "TX_FRAME_BUFFER_CAPACITY=2048 S_ERROR=0 STORE_AND_FORWARD=1"

set reset_sync_cells [get_cells -hier -quiet -filter {ORIG_REF_NAME == p4fab_reset_sync || REF_NAME == p4fab_reset_sync}]
if {[llength $reset_sync_cells] != 3} { close $cf; error "Expected three reset synchronizers, got [llength $reset_sync_cells]: $reset_sync_cells" }
puts $cf "RESET_SYNCHRONIZER_COUNT=[llength $reset_sync_cells] CELLS=$reset_sync_cells"
foreach reset_name {p4fab_aresetn rx_path_aresetn tx_path_aresetn} {
  set reset_pin [m03_require_one_pin u_p4fab_endpoint/$reset_name $reset_name]
  puts $cf "RESET_BOUNDARY=$reset_name PIN=$reset_pin NETS=[get_nets -segments -of_objects $reset_pin]"
}
set converter_s_reset [m03_require_ref_pin $converter_cell s_axis_aresetn CONVERTER_S_RESET]
set converter_m_reset [m03_require_ref_pin $converter_cell m_axis_aresetn CONVERTER_M_RESET]
m03_require_same_net $cf CLOCK_CONVERTER_SOURCE_RESET [list $converter_s_reset [m03_require_one_pin u_p4fab_endpoint/rx_path_aresetn RX_PATH_RESET]]
m03_require_same_net $cf CLOCK_CONVERTER_SINK_RESET [list $converter_m_reset [m03_require_one_pin u_p4fab_endpoint/p4fab_aresetn P4FAB_RESET]]
set tx_reset_segments [get_nets -hier -quiet -segments -regexp {^u_p4fab_endpoint/u_tx_reset_sync/sync_ff\[2\]$}]
set rx_reset_segments [get_nets -hier -quiet -segments -regexp {^u_p4fab_endpoint/u_rx_reset_sync/sync_ff\[2\]$}]
set p4fab_reset_segments [get_nets -hier -quiet -segments -regexp {^u_p4fab_endpoint/u_p4fab_reset_sync/sync_ff\[2\]$}]
foreach {label segments} [list TX_RESET $tx_reset_segments RX_RESET $rx_reset_segments P4FAB_RESET $p4fab_reset_segments] {
  if {[llength $segments] == 0} { close $cf; error "$label final synchronizer net not found" }
}
foreach {label segments consumer_pin} [list \
  RX_CLOCK_CONVERTER_RESET $rx_reset_segments $converter_s_reset \
  P4FAB_CLOCK_CONVERTER_RESET $p4fab_reset_segments $converter_m_reset] {
  set consumer_segments [get_nets -quiet -segments -of_objects $consumer_pin]
  set intersection {}
  foreach segment $segments {
    if {[lsearch -exact $consumer_segments $segment] >= 0} { lappend intersection $segment }
  }
  puts $cf "$label RESET_SEGMENTS=$segments CONSUMER=$consumer_pin COMMON=$intersection"
  if {[llength $intersection] == 0} { close $cf; error "$label has no common reset net" }
}
foreach {label reset_segments} [list \
  RX_PATH_RESET_FANOUT $rx_reset_segments \
  TX_PATH_RESET_FANOUT $tx_reset_segments \
  P4FAB_RESET_FANOUT $p4fab_reset_segments] {
  set reset_fanout_pins [get_pins -quiet -of_objects $reset_segments]
  puts $cf "$label RESET_SEGMENTS=$reset_segments FANOUT_PIN_COUNT=[llength $reset_fanout_pins] FANOUT_PINS=$reset_fanout_pins"
  if {[llength $reset_fanout_pins] == 0} {
    close $cf
    error "$label has no synthesized fanout"
  }
}

set tx_user_pin [m03_require_ref_pin $temac_cell tx_axis_mac_tuser TX_TUSER_ZERO]
if {[get_property -quiet LOGIC_VALUE $tx_user_pin] ne "zero"} { close $cf; error "TEMAC tx_axis_mac_tuser is not constant zero" }
puts $cf "TX_AXIS_MAC_TUSER=0 PIN=$tx_user_pin"
close $cf

# Preserve and verify the debug-only P4Fab/TX observation mapping.
set ilaf [open [file join $reports_dir p4fab_tx_ila_connectivity_synth.txt] w]
m03_require_same_net $ilaf P4FAB_TX_ILA_CLOCK [list $endpoint_p4_clk $temac_tx_clk [m03_require_one_pin u_ila_03m5_p4fab_tx/clk P4FAB_TX_ILA_CLOCK]]
foreach {probe signal width} {probe0 tdata 32 probe1 tkeep 4} {
  for {set bit 0} {$bit < $width} {incr bit} {
    m03_require_same_net $ilaf ${probe}_${bit} [list [m03_require_one_pin "u_p4fab_endpoint/p4fab_rx_${signal}\[$bit\]" ${probe}_${bit}] [m03_require_one_pin "u_ila_03m5_p4fab_tx/${probe}\[$bit\]" ${probe}_${bit}]]
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
} { m03_require_same_net $ilaf $label [list [m03_require_one_pin $endpoint_pin $label] [m03_require_one_pin $ila_pin $label]] }
for {set bit 0} {$bit < 8} {incr bit} {
  m03_require_same_net $ilaf TX_TDATA_$bit [list [m03_require_one_pin "u_p4fab_endpoint/tx_axis_mac_tdata\[$bit\]" TX_TDATA_$bit] [m03_require_one_pin "u_ila_03m5_p4fab_tx/probe3\[$bit\]" TX_TDATA_$bit]]
}
close $ilaf

report_clocks -file [file join $reports_dir clocks_synth.rpt]
report_clock_interaction -delay_type min_max -file [file join $reports_dir clock_interaction_synth.rpt]
set cdc_rc [catch {report_cdc -details -file [file join $reports_dir cdc_synth.rpt]} cdc_error]
set cdc_status [open [file join $reports_dir cdc_command_status.txt] w]
puts $cdc_status "RETURN_CODE=$cdc_rc"
puts $cdc_status "MESSAGE=$cdc_error"
close $cdc_status
if {$cdc_rc} { error "report_cdc failed: $cdc_error" }
set cdc_report_path [file join $reports_dir cdc_synth.rpt]
set cdc_input [open $cdc_report_path r]
set cdc_text [read $cdc_input]
close $cdc_input
foreach {pattern label} {
  {CDC-3\s+Info\s+4} CDC3_COUNT
  {CDC-9\s+Info\s+3} CDC9_COUNT
  {CDC-10\s+Critical\s+1} CDC10_COUNT
  {CDC-15\s+Warning\s+52} CDC15_COUNT
  {CDC-17\s+Warning\s+1} CDC17_COUNT
} {
  if {![regexp $pattern $cdc_text]} { error "CDC classification changed: $label pattern '$pattern' not found" }
}
set cdc_classification [open [file join $reports_dir cdc_classification_guard.txt] w]
puts $cdc_classification "CDC-3=4 INFO allowed IP/reset synchronizers"
puts $cdc_classification "CDC-9=3 INFO allowed asynchronous reset synchronizers"
puts $cdc_classification "CDC-10=1 CRITICAL classified intentional asynchronous-assert reset combine"
puts $cdc_classification "CDC-15=52 WARNING allowed only inside axis_clock_converter_03m_rx or temac_0"
puts $cdc_classification "CDC-17=1 WARNING allowed only inside temac_0"
foreach line [split $cdc_text "\n"] {
  if {[regexp {^\s*[0-9]+\s+CDC-15\s+Warning} $line] && \
      [string first "u_rx_clock_converter" $line] < 0 && \
      [string first "u_temac_wrapper/u_temac" $line] < 0} {
    close $cdc_classification
    error "CDC-15 outside Clock Converter: $line"
  }
  if {[regexp {^\s*[0-9]+\s+CDC-17\s+Warning} $line] && [string first "u_temac_wrapper/u_temac" $line] < 0} {
    close $cdc_classification
    error "CDC-17 outside TEMAC: $line"
  }
  if {[regexp {^\s*[0-9]+\s+CDC-10\s+Critical} $line]} {
    if {[string first "resetn_reg/C" $line] < 0 || [string first "u_p4fab_endpoint/u_rx_reset_sync/sync_ff_reg\[0\]/CLR" $line] < 0} {
      close $cdc_classification
      error "Unexpected CDC-10 path: $line"
    }
    puts $cdc_classification "CDC10_PATH=$line"
  }
}
puts $cdc_classification "UNEXPECTED_DATA_CDC_OUTSIDE_CLOCK_CONVERTER=0"
close $cdc_classification
report_exceptions -file [file join $reports_dir exceptions_synth.rpt]
check_timing -verbose -file [file join $reports_dir check_timing_synth.rpt]

# Keep the management-only GEM2/MDIO structural checks from the 03k baseline.
set synth_mgmt_cells [get_cells -hier -quiet -filter {NAME =~ *mgmt_clk125*}]
if {[llength $synth_mgmt_cells] != 0} { error "Synthesized design contains mgmt_clk125 cells: $synth_mgmt_cells" }
set all_iobufs [get_cells -hier -quiet -filter {REF_NAME == IOBUF}]
set mdio_iobufs [get_cells -hier -quiet -filter {REF_NAME == IOBUF && NAME =~ *mdio*}]
if {[llength $all_iobufs] != 1 || [llength $mdio_iobufs] != 1} { error "Expected exactly one total/MDIO IOBUF" }
set mdio_leafs [get_pins -hier -quiet -filter {REF_PIN_NAME == EMIOENET2MDIOI}]
if {[llength $mdio_leafs] != 1} { error "MDIO input leaf endpoint is not unique" }
set_false_path -to $mdio_leafs
report_exceptions -to $mdio_leafs -file [file join $reports_dir mdio_exceptions_synth.rpt]

set sf [open [file join $reports_dir synthesis_checkpoint.txt] w]
puts $sf "RESULT=PASS"
puts $sf "RUN_STATUS=[get_property STATUS [get_runs synth_1]]"
puts $sf "TEMAC_COUNT=[llength $temac_cells]"
puts $sf "CLOCK_CONVERTER_COUNT=[llength $converter_cells]"
puts $sf "FRAME_BUFFER_COUNT=[llength $frame_buffers] TX_FRAME_BUFFER_COUNT=1 RX_FRAME_BUFFER_COUNT=1"
puts $sf "TX_UNPACKER_COUNT=1"
puts $sf "RESET_SYNCHRONIZER_COUNT=[llength $reset_sync_cells]"
puts $sf "FIXED_FRAME_TX_COUNT=[llength $fixed_generators]"
puts $sf "IMPLEMENTATION_RUN_STATUS=[get_property STATUS [get_runs impl_1]]"
close $sf
close_design
close_project
puts "03M6_SYNTHESIS_CHECKPOINT_PASS: stopping before implementation"
exit 0

# 03k synthesized connectivity guard.  The ILA loads preserve each observed
# datapath net; exact pin-to-net equality prevents a stale idle constant from
# passing this checkpoint.
proc require_one_cell {pattern label} {
  set objects [get_cells -hier -quiet $pattern]
  if {[llength $objects] != 1} { error "$label expected one cell for $pattern, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc require_one_pin {pattern label} {
  set objects [get_pins -quiet $pattern]
  if {[llength $objects] != 1} { error "$label expected one pin for $pattern, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc require_ref_pin {cell ref_pin_name label} {
  set objects [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME == \"$ref_pin_name\""]
  if {[llength $objects] != 1} { error "$label expected one $ref_pin_name pin on $cell, got [llength $objects]: $objects" }
  return [lindex $objects 0]
}
proc require_same_net {report_handle label pin_patterns} {
  set pins {}
  set logic_values {}
  foreach pattern $pin_patterns {
    set pin [require_one_pin $pattern $label]
    lappend pins $pin
    lappend logic_values [get_property -quiet LOGIC_VALUE $pin]
  }
  # Synthesis may replace a constant output (notably fixed tuser=0) with
  # separate hierarchy-local GND nets, or leave the source pin without a net.
  # In that case electrical equivalence is represented by LOGIC_VALUE rather
  # than a shared segment.  Only a unanimous known zero/one is accepted.
  set first_logic [lindex $logic_values 0]
  if {$first_logic eq "zero" || $first_logic eq "one"} {
    set all_same 1
    foreach logic_value $logic_values {
      if {$logic_value ne $first_logic} { set all_same 0 }
    }
    if {$all_same} {
      puts $report_handle "$label CONSTANT=$first_logic PINS=$pins"
      return
    }
  }
  set common_segments {}
  foreach pin $pins {
    set local_nets [get_nets -quiet -of_objects $pin]
    if {[llength $local_nets] != 1} { error "$label pin $pin expected one local net, got $local_nets" }
    # A preserved hierarchy reports one local net name per boundary.  The
    # complete -segments sets must overlap for electrically connected pins.
    set segments [get_nets -quiet -segments -of_objects $pin]
    if {[llength $segments] == 0} { error "$label pin $pin has no hierarchical net segments" }
    puts $report_handle "$label PIN=$pin LOCAL_NET=$local_nets SEGMENT_COUNT=[llength $segments]"
    if {[llength $common_segments] == 0} {
      set common_segments $segments
    } else {
      set intersection {}
      foreach segment $common_segments {
        if {[lsearch -exact $segments $segment] >= 0} { lappend intersection $segment }
      }
      set common_segments $intersection
      if {[llength $common_segments] == 0} { error "$label net mismatch at $pin: no common hierarchical segment" }
    }
  }
  puts $report_handle "$label COMMON_SEGMENT=[lindex $common_segments 0]"
}

set generator_cell [require_one_cell u_fixed_frame_tx generator]
set ila_cell [require_one_cell u_ila_03k_rx ila]
# Reset to top scope, then identify the TEMAC by IP identity rather than a
# hierarchical path passed to get_cells -hier (which has different pattern
# semantics for names containing '/').
current_instance
set temac_cells [get_cells -hier -quiet -filter {REF_NAME == temac_0 && ORIG_REF_NAME == temac_0}]
if {[llength $temac_cells] != 1} { error "TEMAC expected exactly one temac_0 cell, got [llength $temac_cells]: $temac_cells" }
set temac_cell [lindex $temac_cells 0]
set connectivity_file [open [file join $reports_dir rx_tx_connectivity_synth.txt] w]
puts $connectivity_file "GENERATOR_CELL=$generator_cell REF_NAME=[get_property REF_NAME $generator_cell] ORIG_REF_NAME=[get_property ORIG_REF_NAME $generator_cell]"
puts $connectivity_file "ILA_CELL=$ila_cell REF_NAME=[get_property REF_NAME $ila_cell]"
puts $connectivity_file "TEMAC_CELL=$temac_cell REF_NAME=[get_property REF_NAME $temac_cell]"
set wait_attribute [get_property -quiet STAGE1G4_WAIT_CYCLES $generator_cell]
puts $connectivity_file "GENERATOR_WAIT_CYCLES=$wait_attribute"
if {$wait_attribute ne "1250000000"} { close $connectivity_file; error "Generator WAIT_CYCLES attribute mismatch: $wait_attribute" }

# Management is disabled, so these vectors are the authoritative TEMAC RX/TX
# MAC configuration. Guard every bit: bit 1 enables each direction, bit 0
# leaves soft reset deasserted, and every other option remains Low.
for {set bit 0} {$bit < 80} {incr bit} {
  set config_pin [require_ref_pin $temac_cell "rx_configuration_vector\[$bit\]" RX_CONFIGURATION_VECTOR_$bit]
  set expected_logic [expr {$bit == 1 ? "one" : "zero"}]
  set actual_logic [get_property -quiet LOGIC_VALUE $config_pin]
  puts $connectivity_file "RX_CONFIGURATION_VECTOR_$bit PIN=$config_pin EXPECTED=$expected_logic ACTUAL=$actual_logic"
  if {$actual_logic ne $expected_logic} {
    close $connectivity_file
    error "TEMAC rx_configuration_vector\[$bit\] expected $expected_logic, got $actual_logic"
  }
}
puts $connectivity_file "RX_CONFIGURATION_VECTOR=80'h00000000000000000002"

for {set bit 0} {$bit < 80} {incr bit} {
  set config_pin [require_ref_pin $temac_cell "tx_configuration_vector\[$bit\]" TX_CONFIGURATION_VECTOR_$bit]
  set expected_logic [expr {$bit == 1 ? "one" : "zero"}]
  set actual_logic [get_property -quiet LOGIC_VALUE $config_pin]
  puts $connectivity_file "TX_CONFIGURATION_VECTOR_$bit PIN=$config_pin EXPECTED=$expected_logic ACTUAL=$actual_logic"
  if {$actual_logic ne $expected_logic} {
    close $connectivity_file
    error "TEMAC tx_configuration_vector\[$bit\] expected $expected_logic, got $actual_logic"
  }
}
puts $connectivity_file "TX_CONFIGURATION_VECTOR=80'h00000000000000000002"

set temac_tx_clock [require_ref_pin $temac_cell tx_mac_aclk TX_CLOCK]
set temac_tx_reset [require_ref_pin $temac_cell tx_reset TX_RESET]
require_same_net $connectivity_file TX_CLOCK [list u_fixed_frame_tx/clk $temac_tx_clock]
require_same_net $connectivity_file TX_RESET [list u_fixed_frame_tx/rst $temac_tx_reset]
for {set bit 0} {$bit < 8} {incr bit} {
  set temac_tdata [require_ref_pin $temac_cell "tx_axis_mac_tdata\[$bit\]" TX_TDATA_$bit]
  require_same_net $connectivity_file TX_TDATA_$bit [list "u_fixed_frame_tx/tdata\[$bit\]" $temac_tdata]
}
foreach {label generator_pin ref_pin_name} {
  TX_TVALID u_fixed_frame_tx/tvalid tx_axis_mac_tvalid
  TX_TREADY u_fixed_frame_tx/tready tx_axis_mac_tready
  TX_TLAST  u_fixed_frame_tx/tlast  tx_axis_mac_tlast
  TX_TUSER  u_fixed_frame_tx/tuser  tx_axis_mac_tuser
} {
  set temac_pin [require_ref_pin $temac_cell $ref_pin_name $label]
  require_same_net $connectivity_file $label [list $generator_pin $temac_pin]
}

# Guard the RX-domain ILA clock and every packed probe bit against the TEMAC
# RX client pins. This also prevents the otherwise unconsumed RX AXIS from
# being optimized away or silently replaced by a stale constant.
set temac_rx_clock [require_ref_pin $temac_cell rx_mac_aclk RX_CLOCK]
require_same_net $connectivity_file RX_ILA_CLOCK [list $temac_rx_clock u_ila_03k_rx/clk]
for {set bit 0} {$bit < 8} {incr bit} {
  set temac_rx_tdata [require_ref_pin $temac_cell "rx_axis_mac_tdata\[$bit\]" RX_TDATA_$bit]
  require_same_net $connectivity_file RX_ILA_PROBE0_TDATA_$bit [list $temac_rx_tdata "u_ila_03k_rx/probe0\[$bit\]"]
}
foreach {label ref_pin_name ila_pin} {
  RX_ILA_PROBE1_TVALID rx_axis_mac_tvalid {u_ila_03k_rx/probe1[0]}
  RX_ILA_PROBE1_TLAST  rx_axis_mac_tlast  {u_ila_03k_rx/probe1[1]}
  RX_ILA_PROBE1_TUSER  rx_axis_mac_tuser  {u_ila_03k_rx/probe1[2]}
  RX_ILA_PROBE1_RESET  rx_reset           {u_ila_03k_rx/probe1[3]}
} {
  set temac_rx_pin [require_ref_pin $temac_cell $ref_pin_name $label]
  require_same_net $connectivity_file $label [list $temac_rx_pin $ila_pin]
}
set unexpected_probe2 [get_pins -quiet -of_objects $ila_cell -filter {REF_PIN_NAME =~ probe2*}]
puts $connectivity_file "ILA_PROBE2_PIN_COUNT=[llength $unexpected_probe2]"
if {[llength $unexpected_probe2] != 0} { close $connectivity_file; error "2-probe ILA unexpectedly contains probe2 pins: $unexpected_probe2" }
close $connectivity_file

proc require_grounded_ps_pins {pattern expected_count report_handle} {
  set pins [get_pins -hier -quiet -filter "REF_PIN_NAME == $pattern"]
  if {[llength $pins] != $expected_count} {
    error "Expected $expected_count PS pins matching $pattern, got [llength $pins]: $pins"
  }
  foreach pin $pins {
    set nets [get_nets -quiet -of_objects $pin]
    if {[llength $nets] != 1 || [get_property TYPE $nets] ne "GROUND"} {
      error "PS pin $pin expected constant Low, net=$nets TYPE=[get_property TYPE $nets]"
    }
    puts $report_handle "PIN=$pin NET=$nets TYPE=[get_property TYPE $nets]"
  }
}

set synth_mgmt_cells [get_cells -hier -quiet -filter {NAME =~ *mgmt_clk125*}]
if {[llength $synth_mgmt_cells] != 0} { error "Synthesized design contains mgmt_clk125 cells: $synth_mgmt_cells" }
set cf [open [file join $reports_dir gmii_idle_constants_synth.txt] w]
puts $cf "MGMT_CLK125_CELL_COUNT=[llength $synth_mgmt_cells]"
require_grounded_ps_pins EMIOENET2GMIIRXCLK 1 $cf
require_grounded_ps_pins EMIOENET2GMIITXCLK 1 $cf
foreach i {0 1 2 3 4 5 6 7} { require_grounded_ps_pins [format {EMIOENET2GMIIRXD[%d]} $i] 1 $cf }
require_grounded_ps_pins EMIOENET2GMIIRXDV 1 $cf
require_grounded_ps_pins EMIOENET2GMIIRXER 1 $cf
require_grounded_ps_pins EMIOENET2GMIICRS 1 $cf
require_grounded_ps_pins EMIOENET2GMIICOL 1 $cf
close $cf

set rf [open [file join $reports_dir mdio_connectivity_synth.txt] w]
set all_iobufs [get_cells -hier -quiet -filter {REF_NAME == IOBUF}]
set iobufs [get_cells -hier -quiet -filter {REF_NAME == IOBUF && NAME =~ *mdio*}]
puts $rf "IOBUF_TOTAL_COUNT=[llength $all_iobufs] MDIO_IOBUF_COUNT=[llength $iobufs]"
foreach c $all_iobufs {
  puts $rf "IOBUF=$c"
  foreach pin {I O T IO} {
    set p [get_pins -quiet $c/$pin]
    puts $rf "  $pin pin=$p net=[get_nets -quiet -of_objects $p]"
  }
}
set mdc_ports [get_ports -quiet phy_mdc]
set mdio_ports [get_ports -quiet phy_mdio]
puts $rf "MDC_PORT_COUNT=[llength $mdc_ports] port=$mdc_ports net=[get_nets -quiet -of_objects $mdc_ports]"
puts $rf "MDIO_PORT_COUNT=[llength $mdio_ports] port=$mdio_ports net=[get_nets -quiet -of_objects $mdio_ports]"

set mdio_leafs [get_pins -hier -quiet -filter {REF_PIN_NAME == EMIOENET2MDIOI}]
puts $rf "MDIO_INPUT_LEAF_COUNT=[llength $mdio_leafs]"
foreach p $mdio_leafs { puts $rf "MDIO_INPUT_LEAF=$p net=[get_nets -quiet -of_objects $p]" }

set mdc_leafs [get_pins -hier -quiet -filter {NAME =~ */PS8_i/EMIOENET2MDIOMDC}]
puts $rf "MDC_OUTPUT_LEAF_COUNT=[llength $mdc_leafs]"
foreach p $mdc_leafs { puts $rf "MDC_OUTPUT_LEAF=$p net=[get_nets -quiet -of_objects $p]" }
close $rf

if {[llength $all_iobufs] != 1 || [llength $iobufs] != 1} { error "Expected exactly one total/MDIO IOBUF" }
if {[llength $mdio_ports] != 1 || [llength $mdc_ports] != 1} { error "MDIO/MDC top port mismatch" }
if {[llength $mdio_leafs] != 1} { error "MDIO input leaf endpoint is not unique" }
set_false_path -to $mdio_leafs
report_exceptions -to $mdio_leafs -file [file join $reports_dir mdio_exceptions_synth.rpt]
close_design

if {[info exists ::env(STAGE1G4_STOP_AFTER_SYNTH)] && $::env(STAGE1G4_STOP_AFTER_SYNTH) eq "1"} {
  puts "STAGE1G4_STOP_AFTER_SYNTH=1: synthesis and 03k connectivity guards passed; stopping before implementation"
  close_project
  exit 0
}

# Complete the TEMAC TX DDR constraints and apply the MDIO exception inside
# impl_1 after link/init_design, before opt_design.  The hook guards TX edge
# coverage and the expanded PS endpoint count.  Run through route_design, but
# do not write a bitstream or hardware platform.
set mdio_impl_hook [file normalize [file join $script_dir apply_mdio_false_path_impl.tcl]]
add_files -fileset utils_1 -norecurse $mdio_impl_hook
set_property STEPS.OPT_DESIGN.TCL.PRE $mdio_impl_hook [get_runs impl_1]
launch_runs impl_1 -to_step route_design -jobs $build_jobs
wait_on_run impl_1
if {![string match "route_design Complete*" [get_property STATUS [get_runs impl_1]]]} {
  error "Implementation did not complete route_design: [get_property STATUS [get_runs impl_1]]"
}

set impl_run_status [get_property STATUS [get_runs impl_1]]
set impl_hook_path [get_property STEPS.OPT_DESIGN.TCL.PRE [get_runs impl_1]]
open_run impl_1

# Re-check the RX ILA in the routed netlist, including its clock and every
# client AXIS probe. This is intentionally independent of the synth guard.
set route_temac_cells [get_cells -hier -quiet -filter {REF_NAME == temac_0 && ORIG_REF_NAME == temac_0}]
if {[llength $route_temac_cells] != 1} { error "Routed TEMAC expected exactly one cell, got [llength $route_temac_cells]: $route_temac_cells" }
set route_temac_cell [lindex $route_temac_cells 0]
set route_ila_cell [require_one_cell u_ila_03k_rx routed_ila]
set route_ila_guard [open [file join $reports_dir rx_ila_connectivity_route.txt] w]
set route_rx_clock [require_ref_pin $route_temac_cell rx_mac_aclk ROUTE_RX_CLOCK]
require_same_net $route_ila_guard ROUTE_RX_ILA_CLOCK [list $route_rx_clock u_ila_03k_rx/clk]
for {set bit 0} {$bit < 8} {incr bit} {
  set route_rx_tdata [require_ref_pin $route_temac_cell "rx_axis_mac_tdata\[$bit\]" ROUTE_RX_TDATA_$bit]
  require_same_net $route_ila_guard ROUTE_RX_ILA_PROBE0_TDATA_$bit [list $route_rx_tdata "u_ila_03k_rx/probe0\[$bit\]"]
}
foreach {label ref_pin_name ila_pin} {
  ROUTE_RX_ILA_PROBE1_TVALID rx_axis_mac_tvalid {u_ila_03k_rx/probe1[0]}
  ROUTE_RX_ILA_PROBE1_TLAST  rx_axis_mac_tlast  {u_ila_03k_rx/probe1[1]}
  ROUTE_RX_ILA_PROBE1_TUSER  rx_axis_mac_tuser  {u_ila_03k_rx/probe1[2]}
  ROUTE_RX_ILA_PROBE1_RESET  rx_reset           {u_ila_03k_rx/probe1[3]}
} {
  set route_rx_pin [require_ref_pin $route_temac_cell $ref_pin_name $label]
  require_same_net $route_ila_guard $label [list $route_rx_pin $ila_pin]
}
set route_ila_clocks [get_clocks -quiet -of_objects [get_pins u_ila_03k_rx/clk]]
puts $route_ila_guard "ILA_CELL=$route_ila_cell"
puts $route_ila_guard "ILA_CLOCKS=$route_ila_clocks"
foreach c $route_ila_clocks {
  puts $route_ila_guard "ILA_CLOCK=$c PERIOD=[get_property PERIOD $c] WAVEFORM=[get_property WAVEFORM $c]"
}
if {[llength $route_ila_clocks] != 1} { close $route_ila_guard; error "RX ILA expected exactly one routed clock, got $route_ila_clocks" }
close $route_ila_guard

set route_mgmt_cells [get_cells -hier -quiet -filter {NAME =~ *mgmt_clk125*}]
set route_mgmt_clocks [get_clocks -quiet -filter {NAME =~ *mgmt_clk125*}]
if {[llength $route_mgmt_cells] != 0} { error "Routed design contains mgmt_clk125 cells: $route_mgmt_cells" }
if {[llength $route_mgmt_clocks] != 0} { error "Routed design contains mgmt_clk125 clocks: $route_mgmt_clocks" }
set cf [open [file join $reports_dir gmii_idle_constants_route.txt] w]
puts $cf "MGMT_CLK125_CELL_COUNT=[llength $route_mgmt_cells]"
puts $cf "MGMT_CLK125_GENERATED_CLOCK_COUNT=[llength $route_mgmt_clocks]"
require_grounded_ps_pins EMIOENET2GMIIRXCLK 1 $cf
require_grounded_ps_pins EMIOENET2GMIITXCLK 1 $cf
foreach i {0 1 2 3 4 5 6 7} { require_grounded_ps_pins [format {EMIOENET2GMIIRXD[%d]} $i] 1 $cf }
require_grounded_ps_pins EMIOENET2GMIIRXDV 1 $cf
require_grounded_ps_pins EMIOENET2GMIIRXER 1 $cf
require_grounded_ps_pins EMIOENET2GMIICRS 1 $cf
require_grounded_ps_pins EMIOENET2GMIICOL 1 $cf
close $cf

set route_txc_delay_cells [get_cells -hier -quiet -filter {NAME == u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/delay_rgmii_tx_clk}]
if {[llength $route_txc_delay_cells] != 1} {
  error "Routed design expected exactly one TXC master ODELAYE3, got [llength $route_txc_delay_cells]: $route_txc_delay_cells"
}
set route_txc_delay_value [get_property DELAY_VALUE $route_txc_delay_cells]
if {$route_txc_delay_value != 975} {
  error "Routed TXC master ODELAYE3 DELAY_VALUE expected 975, got $route_txc_delay_value"
}
set f [open [file join $reports_dir txc_delay_readback_route.txt] w]
puts $f "TXC_MASTER_COUNT=[llength $route_txc_delay_cells]"
puts $f "TXC_MASTER=$route_txc_delay_cells"
puts $f "REF_NAME=[get_property REF_NAME $route_txc_delay_cells]"
puts $f "DELAY_VALUE=$route_txc_delay_value"
puts $f "DELAY_TYPE=[get_property DELAY_TYPE $route_txc_delay_cells]"
puts $f "DELAY_FORMAT=[get_property DELAY_FORMAT $route_txc_delay_cells]"
puts $f "CASCADE=[get_property CASCADE $route_txc_delay_cells]"
puts $f "REFCLK_FREQUENCY=[get_property REFCLK_FREQUENCY $route_txc_delay_cells]"
close $f

set route_mdio_leafs [get_pins -hier -quiet -filter {REF_PIN_NAME == EMIOENET2MDIOI}]
if {[llength $route_mdio_leafs] != 1} {
  error "Routed design expected exactly one PS GEM2 MDIO input leaf, got [llength $route_mdio_leafs]"
}
set route_iobufs [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ *mdio*}]
set route_all_iobufs [get_cells -hier -quiet -filter {REF_NAME == IOBUF}]
if {[llength $route_all_iobufs] != 1 || [llength $route_iobufs] != 1} {
  error "Routed design expected exactly one MDIO IOBUF, got [llength $route_iobufs]"
}
set route_mdc_ports [get_ports -quiet phy_mdc]
set route_mdio_ports [get_ports -quiet phy_mdio]
if {[llength $route_mdc_ports] != 1 || [llength $route_mdio_ports] != 1} {
  error "Routed design MDIO/MDC top port mismatch"
}

set f [open [file join $reports_dir mdio_connectivity_route.txt] w]
puts $f "RUN_STATUS=$impl_run_status"
puts $f "IOBUF_TOTAL_COUNT=[llength $route_all_iobufs] MDIO_IOBUF_COUNT=[llength $route_iobufs]"
puts $f "MDIO_IOBUF=$route_iobufs"
puts $f "MDIO_INPUT_LEAF_COUNT=[llength $route_mdio_leafs]"
puts $f "MDIO_INPUT_LEAF=$route_mdio_leafs"
puts $f "HOOK=$impl_hook_path"
foreach p [list $route_mdc_ports $route_mdio_ports] {
  puts $f "PORT=$p PACKAGE_PIN=[get_property PACKAGE_PIN $p] IOSTANDARD=[get_property IOSTANDARD $p] SLEW=[get_property SLEW $p]"
}
close $f

foreach {port expected_pin} [list $route_mdc_ports G3 $route_mdio_ports F3] {
  if {[get_property PACKAGE_PIN $port] ne $expected_pin} { error "$port expected PACKAGE_PIN $expected_pin" }
  if {[get_property IOSTANDARD $port] ne "LVCMOS18"} { error "$port expected LVCMOS18" }
  if {[get_property SLEW $port] ne "SLOW"} { error "$port expected SLEW SLOW" }
}

report_exceptions -to $route_mdio_leafs -file [file join $reports_dir mdio_exceptions_route.rpt]
report_exceptions -file [file join $reports_dir exceptions_route.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $reports_dir timing_summary_route.rpt]
check_timing -verbose -file [file join $reports_dir check_timing_route.rpt]
report_methodology -file [file join $reports_dir methodology_route.rpt]
report_route_status -file [file join $reports_dir route_status.rpt]
report_timing -delay_type max -max_paths 20 -nworst 5 -sort_by group -file [file join $reports_dir timing_worst_setup_route.rpt]
report_timing -delay_type min -max_paths 20 -nworst 5 -sort_by group -file [file join $reports_dir timing_worst_hold_route.rpt]

set rgmii_tx_ports [get_ports -quiet -filter {NAME =~ rgmii_txd* || NAME == rgmii_tx_ctl || NAME == rgmii_txc}]
set rgmii_rx_ports [get_ports -quiet -filter {NAME =~ rgmii_rxd* || NAME == rgmii_rx_ctl || NAME == rgmii_rxc}]
if {[llength $rgmii_tx_ports] != 6 || [llength $rgmii_rx_ports] != 6} {
  error "RGMII routed port count mismatch: TX=[llength $rgmii_tx_ports] RX=[llength $rgmii_rx_ports]"
}
set external_gmii_ports [get_ports -quiet -filter {NAME =~ *gmii* && NAME !~ rgmii*}]
if {[llength $external_gmii_ports] != 0} { error "Unexpected external GMII ports: $external_gmii_ports" }

set rx_delay_cells [get_cells -hier -quiet -filter {NAME =~ u_temac_wrapper/u_temac/inst/tri_mode_ethernet_mac_i/rgmii_interface/*delay_rgmii_rx*}]
if {[llength $rx_delay_cells] != 5} { error "Expected five RGMII RX IDELAYE3 cells, got [llength $rx_delay_cells]: $rx_delay_cells" }
foreach c $rx_delay_cells {
  if {[get_property REF_NAME $c] ne "IDELAYE3" || [get_property DELAY_VALUE $c] != 900} {
    error "RX delay mismatch at $c: REF_NAME=[get_property REF_NAME $c] DELAY_VALUE=[get_property DELAY_VALUE $c]"
  }
}
set packet_guard [open [file join $reports_dir packet_structure_guard_route.txt] w]
puts $packet_guard "TEMAC_HIERARCHY_EVIDENCE_COUNT=[llength $route_txc_delay_cells] EVIDENCE=$route_txc_delay_cells"
puts $packet_guard "RX_IDELAY_COUNT=[llength $rx_delay_cells]"
foreach c $rx_delay_cells { puts $packet_guard "RX_IDELAY=$c REF_NAME=[get_property REF_NAME $c] DELAY_VALUE=[get_property DELAY_VALUE $c]" }
puts $packet_guard "TXC_MASTER_COUNT=[llength $route_txc_delay_cells] DELAY_VALUE=$route_txc_delay_value"
puts $packet_guard "EXTERNAL_GMII_PORTS=$external_gmii_ports"
foreach {name expected_pin} {
  rgmii_rxd[0] A1 rgmii_rxd[1] B3 rgmii_rxd[2] A3 rgmii_rxd[3] B4
  rgmii_rx_ctl A4 rgmii_rxc D4 rgmii_txd[0] E1 rgmii_txd[1] D1
  rgmii_txd[2] F2 rgmii_txd[3] E2 rgmii_tx_ctl F1 rgmii_txc A2 phy_reset_n B1
} {
  set port [get_ports -quiet $name]
  if {[llength $port] != 1 || [get_property PACKAGE_PIN $port] ne $expected_pin} { error "$name pin guard failed" }
  if {[get_property IOSTANDARD $port] ne "LVCMOS18"} { error "$name expected LVCMOS18" }
  puts $packet_guard "PORT=$name PACKAGE_PIN=[get_property PACKAGE_PIN $port] IOSTANDARD=[get_property IOSTANDARD $port]"
}
close $packet_guard
set tx_data_ports [get_ports -quiet -filter {NAME =~ rgmii_txd* || NAME == rgmii_tx_ctl}]
proc stage1g4_route_edge_pairs {paths} {
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
set route_tx_setup_paths [get_timing_paths -quiet -to $tx_data_ports -delay_type max -max_paths 100 -nworst 20]
set route_tx_hold_paths [get_timing_paths -quiet -to $tx_data_ports -delay_type min -max_paths 100 -nworst 20]
set route_tx_setup_pairs [stage1g4_route_edge_pairs $route_tx_setup_paths]
set route_tx_hold_pairs [stage1g4_route_edge_pairs $route_tx_hold_paths]
if {$route_tx_setup_pairs ne {0.000->0.000 4.000->4.000}} {
  error "Routed TX DDR setup edge coverage mismatch: $route_tx_setup_pairs"
}
if {$route_tx_hold_pairs ne {0.000->4.000 4.000->0.000}} {
  error "Routed TX DDR hold edge coverage mismatch: $route_tx_hold_pairs"
}
set f [open [file join $reports_dir tx_ddr_edge_coverage_route.txt] w]
puts $f "TX_PORT_COUNT=[llength $tx_data_ports]"
puts $f "TX_PORTS=$tx_data_ports"
puts $f "TX_SETUP_PATH_COUNT=[llength $route_tx_setup_paths]"
puts $f "TX_SETUP_EDGE_PAIRS=$route_tx_setup_pairs"
puts $f "TX_HOLD_PATH_COUNT=[llength $route_tx_hold_paths]"
puts $f "TX_HOLD_EDGE_PAIRS=$route_tx_hold_pairs"
close $f
report_timing -to $rgmii_tx_ports -delay_type max -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_tx_setup_route.rpt]
report_timing -to $rgmii_tx_ports -delay_type min -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_tx_hold_route.rpt]
report_timing -from $rgmii_rx_ports -delay_type max -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_rx_setup_route.rpt]
report_timing -from $rgmii_rx_ports -delay_type min -max_paths 100 -nworst 20 -file [file join $reports_dir timing_rgmii_rx_hold_route.rpt]
report_drc -file [file join $reports_dir drc_route.rpt]
close_design
close_project
