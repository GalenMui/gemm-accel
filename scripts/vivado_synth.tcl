set default_part "xc7a200tfbg484-1"
set default_top  "gemm_accel"
set default_clk_period_ns 5.000

if {[llength $argv] >= 1} {
    set part_name [lindex $argv 0]
} else {
    set part_name $default_part
}

if {[llength $argv] >= 2} {
    set top_name [lindex $argv 1]
} else {
    set top_name $default_top
}

if {[llength $argv] >= 3} {
    set clk_period_ns [lindex $argv 2]
} else {
    set clk_period_ns $default_clk_period_ns
}

set root_dir [file normalize [file join [file dirname [info script]] ..]]
set out_dir  [file join $root_dir vivado_out]

file mkdir $out_dir

read_verilog -sv [list \
    [file join $root_dir rtl scratchpad.sv] \
    [file join $root_dir rtl tile_buffer.sv] \
    [file join $root_dir rtl mac_unit.sv] \
    [file join $root_dir rtl pe.sv] \
    [file join $root_dir rtl systolic_array.sv] \
    [file join $root_dir rtl controller.sv] \
    [file join $root_dir rtl gemm_top.sv] \
    [file join $root_dir rtl gemm_accel.sv] \
]

create_clock -name core_clk -period $clk_period_ns [get_ports clk]

synth_design -top $top_name -part $part_name

report_utilization -file [file join $out_dir post_synth_utilization.rpt]
report_utilization -hierarchical -file [file join $out_dir post_synth_utilization_hier.rpt]
report_timing_summary -file [file join $out_dir post_synth_timing.rpt]
report_power -file [file join $out_dir post_synth_power.rpt]

write_checkpoint -force [file join $out_dir post_synth.dcp]
