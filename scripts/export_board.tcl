# Run ONLY while the known-good ps_hello Vivado project is open.
# Writes snapshots to this new package; never saves/modifies the source project.
set cnn_root [file normalize [file join [file dirname [info script]] ..]]
set cnn_export [file join $cnn_root board_snapshot]
if {[file exists $cnn_export]} {error "board_snapshot already exists; keep it or choose another package directory"}
set cnn_bds [get_files -quiet *.bd]
if {[llength $cnn_bds]!=1} {error "Expected exactly one Block Design in ps_hello"}
file mkdir $cnn_export
open_bd_design [lindex $cnn_bds 0]
write_bd_tcl [file join $cnn_export base_bd.tcl]
set meta [open [file join $cnn_export part.txt] w]
puts $meta [get_property PART [current_project]]
close $meta
# Preserve sources required to resolve the old module reference on import.
set index 0
foreach f [get_files -quiet -of_objects [get_filesets sources_1]] {
 if {[get_property FILE_TYPE $f] ni {SystemVerilog Verilog {Verilog Header}}} {continue}
 if {[string match *_wrapper.v $f]} {continue}
 file mkdir [file join $cnn_export "source_$index"]
 file copy $f [file join $cnn_export "source_$index" [file tail $f]]
 incr index
}
# Preserve user constraints; generated IP constraints regenerate in new project.
foreach f [get_files -quiet -of_objects [get_filesets constrs_1]] {
 if {[string equal -nocase [file extension $f] .xdc]} {
  file mkdir [file join $cnn_export "xdc_$index"]
  file copy $f [file join $cnn_export "xdc_$index" [file tail $f]]
  incr index
 }
}
puts "Exported board settings to $cnn_export. Now close ps_hello; source scripts/create_vivado.tcl."
