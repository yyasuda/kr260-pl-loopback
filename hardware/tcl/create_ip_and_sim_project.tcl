set script_dir [file normalize [file dirname [info script]]]
set tree_dir [file normalize [file join $script_dir ..]]
set repo_dir $tree_dir
set build_dir [file join $tree_dir build simulation]
set report_dir [file join $tree_dir reports]
file mkdir $build_dir
file mkdir $report_dir

create_project stage1g4_03m6_tx_frame_buffer_sim [file join $build_dir vivado] \
  -part xck26-sfvc784-2LV-c -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip \
  -version 1.1 -module_name axis_clock_converter_03m_rx
set_property -dict [list \
  CONFIG.TDATA_NUM_BYTES {4} \
  CONFIG.HAS_TSTRB {0} \
  CONFIG.HAS_TKEEP {1} \
  CONFIG.HAS_TLAST {1} \
  CONFIG.TID_WIDTH {0} \
  CONFIG.TDEST_WIDTH {0} \
  CONFIG.TUSER_WIDTH {0} \
  CONFIG.IS_ACLK_ASYNC {1} \
  CONFIG.SYNCHRONIZATION_STAGES {2}] \
  [get_ips axis_clock_converter_03m_rx]

set guard [open [file join $report_dir axis_clock_converter_configuration.txt] w]
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
  puts $guard "$property expected={$expected} resolved={$actual}"
  if {$actual ne $expected} {
    close $guard
    error "$property expected '$expected', got '$actual'"
  }
}
close $guard
generate_target all [get_ips axis_clock_converter_03m_rx]

# Generated wrapper and installed core guards supplement the IP property
# readback above. They prove the exposed AXIS payload and the async FIFO
# implementation actually selected by Vivado 2026.1.
set generated_wrapper [file join $build_dir vivado stage1g4_03m6_tx_frame_buffer_sim.gen \
  sources_1 ip axis_clock_converter_03m_rx synth axis_clock_converter_03m_rx.v]
set wrapper_fh [open $generated_wrapper r]
set wrapper_text [read $wrapper_fh]
close $wrapper_fh
set generated_guard [open [file join $report_dir axis_clock_converter_generated_guard.txt] w]
foreach {label pattern} {
  ASYNC_PARAMETER {\.C_IS_ACLK_ASYNC\(1\)}
  TDATA_INPUT {input wire \[31 : 0\] s_axis_tdata}
  TKEEP_INPUT {input wire \[3 : 0\] s_axis_tkeep}
  TLAST_INPUT {input wire s_axis_tlast}
  TDATA_OUTPUT {output wire \[31 : 0\] m_axis_tdata}
  TKEEP_OUTPUT {output wire \[3 : 0\] m_axis_tkeep}
  TLAST_OUTPUT {output wire m_axis_tlast}
  SOURCE_READY {output wire s_axis_tready}
  SINK_VALID {output wire m_axis_tvalid}
} {
  set matched [regexp -- $pattern $wrapper_text]
  puts $generated_guard "$label matched=$matched pattern={$pattern}"
  if {!$matched} { close $generated_guard; error "Generated wrapper guard failed: $label" }
}
set core_hdl [file join $::env(XILINX_VIVADO) data ip xilinx \
  axis_clock_converter_v1_1 hdl axis_clock_converter_v1_1_vl_rfs.v]
set core_fh [open $core_hdl r]
set core_text [read $core_fh]
close $core_fh
set fifo_depth_guard [regexp -- {localparam integer P_FIFO_DEPTH[ ]*=[ ]*32} $core_text]
set xpm_async_guard [regexp -- {xpm_fifo_async[ ]*#} $core_text]
puts $generated_guard "INTERNAL_FIFO_DEPTH_32 matched=$fifo_depth_guard source=$core_hdl"
puts $generated_guard "XPM_FIFO_ASYNC matched=$xpm_async_guard source=$core_hdl"
if {!$fifo_depth_guard || !$xpm_async_guard} {
  close $generated_guard
  error "Installed Clock Converter async FIFO guard failed"
}
close $generated_guard

add_files -fileset sources_1 [list \
  [file join $repo_dir rtl p4fab_frame_buffer_noready_8.sv] \
  [file join $repo_dir rtl p4fab_pack_8to32.sv] \
  [file join $repo_dir rtl p4fab_unpack_32to8.sv] \
  [file join $tree_dir rtl p4fab_reset_sync.sv] \
  [file join $tree_dir rtl p4fab_temac_endpoint.sv]]
add_files -fileset sim_1 [file join $tree_dir sim tb_p4fab_temac_endpoint.sv]
set_property top tb_p4fab_temac_endpoint [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set ports_file [open [file join $report_dir axis_clock_converter_generated_files.txt] w]
foreach f [lsort [glob -nocomplain -directory [file dirname $generated_wrapper] *]] {
  puts $ports_file $f
}
close $ports_file

set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
run all
close_sim
set simulation_log [file join $build_dir vivado stage1g4_03m6_tx_frame_buffer_sim.sim \
  sim_1 behav xsim simulate.log]
file copy -force $simulation_log [file join $report_dir endpoint_simulation.txt]
close_project
