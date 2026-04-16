# =============================================================================
# run_sim.tcl
# Vivado xsim / ModelSim Simulation Script
# =============================================================================
# Usage:
#   vivado -mode batch -source scripts/build/run_sim.tcl
#
#   # Run specific target:
#   SIM_TARGET=unit_tuple    vivado -mode batch -source scripts/build/run_sim.tcl
#   SIM_TARGET=unit_toeplitz vivado -mode batch -source scripts/build/run_sim.tcl
#   SIM_TARGET=integration   vivado -mode batch -source scripts/build/run_sim.tcl
#
# For ModelSim:
#   SIM=modelsim vsim -do scripts/build/run_sim.tcl
# =============================================================================

# Detect simulator
set sim_tool "xsim"
if {[info exists env(SIM)]} {
    set sim_tool $env(SIM)
}

# Detect target
set sim_target "all"
if {[info exists env(SIM_TARGET)]} {
    set sim_target $env(SIM_TARGET)
}

# Project root (two levels up from scripts/build/)
set project_root [file normalize [file join [file dirname [info script]] "../.."]]
puts "Project root: $project_root"
puts "Sim tool:     $sim_tool"
puts "Sim target:   $sim_target"

# ---------------------------------------------------------------------------
# Source file lists
# ---------------------------------------------------------------------------
set rtl_common [list \
    $project_root/rtl/common/sync_fifo.v \
    $project_root/rtl/common/meta_fifo.v \
]

set rtl_parser [list \
    $project_root/rtl/parser/axi_stream_ingress.v \
    $project_root/rtl/parser/tuple_extractor.v \
]

set rtl_hash [list \
    $project_root/rtl/hash_engine/toeplitz_core.v \
    $project_root/rtl/hash_engine/hash_pipeline_stages.v \
]

set rtl_forwarding [list \
    $project_root/rtl/forwarding/fib_bram_controller.v \
    $project_root/rtl/forwarding/token_bucket_limiter.v \
]

set rtl_rewrite [list \
    $project_root/rtl/rewrite/header_modifier.v \
    $project_root/rtl/rewrite/checksum_updater.v \
]

set rtl_top [list \
    $project_root/rtl/top/l4_load_balancer_top.v \
]

set rtl_all [concat $rtl_common $rtl_parser $rtl_hash $rtl_forwarding $rtl_rewrite $rtl_top]

# ---------------------------------------------------------------------------
# Simulation helper procs
# ---------------------------------------------------------------------------
proc run_xsim {sources top_module work_dir} {
    global project_root
    file mkdir $work_dir

    set opts "-timescale 1ns/1ps --nolog"

    # Compile
    foreach src $sources {
        puts "Compiling: [file tail $src]"
        exec xvlog $opts -work work $src
    }

    # Elaborate
    exec xelab --debug typical $top_module -s ${top_module}_sim \
        --timescale 1ns/1ps --nolog

    # Simulate
    exec xsim ${top_module}_sim --runall --nolog
}

proc run_modelsim {sources top_module work_dir} {
    file mkdir $work_dir
    exec vlib $work_dir/work
    exec vmap work $work_dir/work

    foreach src $sources {
        puts "Compiling: [file tail $src]"
        exec vlog -work work $src
    }
    exec vsim -c $top_module -do "run -all; quit"
}

# ---------------------------------------------------------------------------
# Run targets
# ---------------------------------------------------------------------------
set work_dir "$project_root/sim_work"

if {$sim_target eq "unit_tuple" || $sim_target eq "all"} {
    puts "\n=========================================="
    puts " Running: tb_tuple_extractor"
    puts "=========================================="
    set sources [concat $rtl_common $rtl_parser \
        [list $project_root/tb/unit/tb_tuple_extractor.v]]

    if {$sim_tool eq "xsim"} {
        run_xsim $sources tb_tuple_extractor $work_dir/tuple
    } else {
        run_modelsim $sources tb_tuple_extractor $work_dir/tuple
    }
}

if {$sim_target eq "unit_toeplitz" || $sim_target eq "all"} {
    puts "\n=========================================="
    puts " Running: tb_toeplitz_core"
    puts "=========================================="
    set sources [concat $rtl_hash \
        [list $project_root/tb/unit/tb_toeplitz_core.v]]

    if {$sim_tool eq "xsim"} {
        run_xsim $sources tb_toeplitz_core $work_dir/toeplitz
    } else {
        run_modelsim $sources tb_toeplitz_core $work_dir/toeplitz
    }
}

if {$sim_target eq "integration" || $sim_target eq "all"} {
    puts "\n=========================================="
    puts " Running: tb_l4_pipeline_full"
    puts "=========================================="
    set sources [concat $rtl_all \
        [list $project_root/tb/integration/tb_l4_pipeline_full.v]]

    if {$sim_tool eq "xsim"} {
        run_xsim $sources tb_l4_pipeline_full $work_dir/integration
    } else {
        run_modelsim $sources tb_l4_pipeline_full $work_dir/integration
    }
}

puts "\n=========================================="
puts " Simulation complete"
puts "=========================================="