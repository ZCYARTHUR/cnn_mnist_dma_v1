if {[get_property NAME [current_project]] ne "cnn_mnist_dma"} {error "Open the new cnn_mnist_dma project"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {![string match *Complete* [get_property STATUS [get_runs impl_1]]]} {error "Implementation failed; inspect run log"}
open_run impl_1
set out [file join [get_property DIRECTORY [current_project]] deliverables]
file mkdir $out
report_timing_summary -file [file join $out timing.rpt]
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
set worst [get_timing_paths -max_paths 1 -setup]
if {![llength $worst] || [get_property SLACK $worst]<0} {error "Setup timing not met; no XSA exported"}
set worst_hold [get_timing_paths -max_paths 1 -hold]
if {[llength $worst_hold] && [get_property SLACK $worst_hold]<0} {error "Hold timing not met; no XSA exported"}
write_hw_platform -fixed -include_bit -force -file [file join $out cnn_mnist_dma.xsa]
puts "XSA exported to $out. Also review DRC and unconstrained-path warnings before board testing."
