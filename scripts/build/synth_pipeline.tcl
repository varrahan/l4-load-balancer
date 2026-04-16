# =============================================================================
# synth_pipeline.tcl
# Vivado Synthesis Script — FPGA L4 Load Balancer
# =============================================================================
# Usage:
#   vivado -mode batch -source scripts/build/synth_pipeline.tcl
#
# Targets Xilinx UltraScale+ xcvu9p-flgb2104-2-i (VU9P on Alveo U200/U250).
# For Zynq 7000 (Zybo Z7-20): change PART to xc7z020clg400-1
#
# Reports written to synth/reports/
# =============================================================================

set project_root [file normalize [file join [file dirname [info script]] "../.."]]
set report_dir   "$project_root/synth/reports"
set part         "xcvu9p-flgb2104-2-i"

# Override part from environment if set
if {[info exists env(FPGA_PART)]} {
    set part $env(FPGA_PART)
}

puts "=============================================="
puts " L4 Load Balancer Synthesis"
puts " Part:         $part"
puts " Project root: $project_root"
puts "=============================================="

file mkdir $report_dir

# ---------------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------------
set rtl_sources [list \
    $project_root/rtl/common/sync_fifo.v \
    $project_root/rtl/common/meta_fifo.v \
    $project_root/rtl/parser/axi_stream_ingress.v \
    $project_root/rtl/parser/tuple_extractor.v \
    $project_root/rtl/hash_engine/toeplitz_core.v \
    $project_root/rtl/hash_engine/hash_pipeline_stages.v \
    $project_root/rtl/forwarding/fib_bram_controller.v \
    $project_root/rtl/forwarding/token_bucket_limiter.v \
    $project_root/rtl/rewrite/header_modifier.v \
    $project_root/rtl/rewrite/checksum_updater.v \
    $project_root/rtl/top/l4_load_balancer_top.v \
]

set constraints [list \
    $project_root/synth/constraints/timing.sdc \
    $project_root/synth/constraints/pinout.xdc \
]

# ---------------------------------------------------------------------------
# Create in-memory project
# ---------------------------------------------------------------------------
create_project -in_memory -part $part lb_synth

set_property default_lib work [current_project]
set_property target_language Verilog [current_project]

# Add RTL sources
foreach src $rtl_sources {
    if {[file exists $src]} {
        add_files -norecurse $src
        puts "  + [file tail $src]"
    } else {
        puts "WARNING: Source not found: $src"
    }
}

# Add constraints
foreach xdc $constraints {
    if {[file exists $xdc]} {
        add_files -fileset constrs_1 -norecurse $xdc
        puts "  + [file tail $xdc]"
    } else {
        puts "NOTE: Constraint file not found (optional): $xdc"
    }
}

set_property top l4_load_balancer_top [current_fileset]

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------
puts "\n[clock format [clock seconds] -format {%H:%M:%S}] Starting synthesis..."

synth_design \
    -top       l4_load_balancer_top \
    -part      $part \
    -directive PerformanceOptimized \
    -flatten_hierarchy rebuilt \
    -fsm_extraction auto \
    -resource_sharing off \
    -retiming on

puts "[clock format [clock seconds] -format {%H:%M:%S}] Synthesis complete."

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
puts "\nWriting reports to $report_dir ..."

report_timing_summary \
    -delay_type    max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths     20 \
    -input_pins \
    -file          $report_dir/timing_summary.rpt

report_utilization \
    -file          $report_dir/utilization.rpt

report_clock_interaction \
    -file          $report_dir/clock_interaction.rpt

report_cdc \
    -file          $report_dir/cdc.rpt

report_power \
    -file          $report_dir/power.rpt

report_drc \
    -file          $report_dir/drc.rpt

# ---------------------------------------------------------------------------
# Optional: run implementation if IMPLEMENT=1
# ---------------------------------------------------------------------------
if {[info exists env(IMPLEMENT)] && $env(IMPLEMENT) eq "1"} {
    puts "\n[clock format [clock seconds] -format {%H:%M:%S}] Running implementation..."

    opt_design
    place_design -directive ExtraTimingOpt
    phys_opt_design -directive AggressiveExplore
    route_design -directive AggressiveExplore
    phys_opt_design -directive AggressiveExplore

    report_timing_summary \
        -delay_type max \
        -max_paths  20 \
        -file       $report_dir/timing_post_route.rpt

    report_utilization \
        -file       $report_dir/utilization_post_route.rpt

    # Generate bitstream
    write_bitstream -force $project_root/synth/l4_load_balancer.bit
    write_debug_probes -force $project_root/synth/l4_load_balancer.ltx

    puts "[clock format [clock seconds] -format {%H:%M:%S}] Implementation complete."
    puts "Bitstream: $project_root/synth/l4_load_balancer.bit"
}

# ---------------------------------------------------------------------------
# Print Fmax summary from timing report
# ---------------------------------------------------------------------------
puts "\n========== TIMING SUMMARY =========="
set timing_lines [split [read [open $report_dir/timing_summary.rpt r]] "\n"]
foreach line $timing_lines {
    if {[string match "*WNS*" $line] || [string match "*TNS*" $line] ||
        [string match "*MHz*" $line] || [string match "*Fmax*" $line] ||
        [string match "*slack*" $line]} {
        puts $line
    }
}
puts "====================================="
puts "\nFull report: $report_dir/timing_summary.rpt"
puts "Done."