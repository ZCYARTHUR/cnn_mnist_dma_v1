# Creates a NEW project from the user's known-good PS/DDR board snapshot.
# No generic development-board DDR preset is substituted.
set cnn_root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists cnn_lanes]} {set cnn_lanes 4}
if {$cnn_lanes ni {4 8 16}} {error "cnn_lanes must be 4,8,16"}
if {[llength [get_projects -quiet]]} {error "Close the original project before creating this new project"}
set snap [file join $cnn_root board_snapshot]
if {![file exists [file join $snap base_bd.tcl]]} {error "First run scripts/export_board.tcl in the known-good ps_hello project"}
set fd [open [file join $snap part.txt] r];set part [string trim [read $fd]];close $fd
if {$part ne "xczu15eg-ffvb1156-2-i"} {error "Unexpected board part $part; verify your actual board before adapting script"}
set dest [file join $cnn_root build vivado_lanes$cnn_lanes]
if {[file exists $dest]} {error "Project directory already exists: $dest. Open its .xpr to continue"}
create_project cnn_mnist_dma $dest -part $part
set_property target_language Verilog [current_project]
add_files [glob [file join $cnn_root rtl *.sv]]
foreach d [glob -nocomplain -directory $snap source_*] {add_files [glob [file join $d *]]}
foreach d [glob -nocomplain -directory $snap xdc_*] {add_files -fileset constrs_1 [glob [file join $d *.xdc]]}
update_compile_order -fileset sources_1
source [file join $snap base_bd.tcl]
set ps [get_bd_cells -quiet zynq_ultra_ps_e_0]
set rst [get_bd_cells -quiet rst_pl0_100M]
set old [get_bd_cells -quiet matmul_axi_0]
set sc [get_bd_cells -quiet smartconnect_0]
if {[llength $ps]!=1 || [llength $rst]!=1 || [llength $old]!=1 || [llength $sc]!=1} {
 error "Expected zynq_ultra_ps_e_0/rst_pl0_100M/matmul_axi_0/smartconnect_0. Inspect new BD and adjust these four names; original project is untouched."
}
# Remove only the old accelerator and its dedicated control SmartConnect.
delete_bd_objs $old $sc
set legacy_files {}
foreach f [get_files -quiet -all] {
    set normalized [string map {\\ /} [file normalize $f]]
    if {[string match "*board_snapshot/source_*/*" $normalized]} {
        lappend legacy_files $f
    }
}
if {[llength $legacy_files]} {
    remove_files $legacy_files
}
# HP0 FPD is the noncoherent DDR port; GP2 is its PS configuration key.
set_property -dict [list CONFIG.PSU__USE__S_AXI_GP2 {1} CONFIG.PSU__SAXIGP2__DATA_WIDTH {128}] $ps
create_bd_cell -type module -reference cnn_accel_top cnn_0
set_property CONFIG.LANES $cnn_lanes [get_bd_cells cnn_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_sg_include_stscntrl_strm {0} \
 CONFIG.c_include_mm2s {1} CONFIG.c_include_s2mm {1} CONFIG.c_addr_width {32} \
 CONFIG.c_m_axi_mm2s_data_width {64} CONFIG.c_m_axis_mm2s_tdata_width {32} \
 CONFIG.c_m_axi_s2mm_data_width {64} CONFIG.c_s_axis_s2mm_tdata_width {32} \
 CONFIG.c_include_mm2s_dre {0} CONFIG.c_include_s2mm_dre {0} \
 CONFIG.c_sg_length_width {23}] [get_bd_cells axi_dma_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 cnn_ctrl_smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [get_bd_cells cnn_ctrl_smc]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 cnn_mem_smc
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells cnn_mem_smc]
# AXI interface names inferred from explicit X_INTERFACE_INFO attributes.
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_LPD] [get_bd_intf_pins cnn_ctrl_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins cnn_ctrl_smc/M00_AXI] [get_bd_intf_pins cnn_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins cnn_ctrl_smc/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins cnn_mem_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins cnn_mem_smc/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins cnn_mem_smc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins cnn_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins cnn_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
foreach pin {cnn_0/aclk cnn_ctrl_smc/aclk cnn_mem_smc/aclk axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_mm2s_aclk axi_dma_0/m_axi_s2mm_aclk zynq_ultra_ps_e_0/saxihp0_fpd_aclk} {
 connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins $pin]
}
foreach pin {cnn_0/aresetn cnn_ctrl_smc/aresetn cnn_mem_smc/aresetn axi_dma_0/axi_resetn} {
 connect_bd_net [get_bd_pins rst_pl0_100M/peripheral_aresetn] [get_bd_pins $pin]
}
# DMA interrupt pins are intentionally unused in this polling design.
set cpu_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]
set cnn_seg [get_bd_addr_segs -of_objects [get_bd_intf_pins cnn_0/S_AXI]]
set dma_seg [get_bd_addr_segs -of_objects [get_bd_intf_pins axi_dma_0/S_AXI_LITE]]
if {[llength $cnn_seg]!=1 || [llength $dma_seg]!=1} {error "Control address segment inference failed; inspect module interfaces"}
assign_bd_address -offset 0x80000000 -range 64K -target_address_space $cpu_space $cnn_seg
assign_bd_address -offset 0xA0000000 -range 64K -target_address_space $cpu_space $dma_seg
assign_bd_address
validate_bd_design
save_bd_design
set bd [get_files -quiet *.bd]
generate_target all $bd
add_files [make_wrapper -files $bd -top]
set_property top [file rootname [file tail [lindex $bd 0]]]_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "NEW project created. Inspect Address Editor, HP0 DDR mapping and clock/reset; then run build_bitstream.tcl."
