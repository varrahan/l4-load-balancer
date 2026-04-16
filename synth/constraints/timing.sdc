# =============================================================================
# timing.sdc — Synthesis Design Constraints (SDC format)
# Project    : L4 Smart Load Balancer
# Author     : Varrahan Uthayan
# Target     : Xilinx Vivado (XDC compatible superset of SDC)
#
# Clock plan:
#   - clk : Primary pipeline clock.  156.25 MHz ↔ 6.4 ns period.
#            This maps to a standard 10 Gbps Ethernet MAC clock on a 64-bit bus:
#              10 Gbps / 64 bits = 156.25 MHz line rate.
#
#   For 100 Gbps on a 256-bit bus: 100 Gbps / 256 bits ≈ 390 MHz.
#   Adjust PERIOD_NS accordingly and verify all paths meet timing.
#
# Target Fmax: >250 MHz  (leaves margin for 156.25 MHz operational point)
# =============================================================================

# ---------------------------------------------------------------------------
# Primary pipeline clock
# ---------------------------------------------------------------------------
set PERIOD_NS 6.4
# For 250 MHz target uncomment:
# set PERIOD_NS 4.0

create_clock -name clk -period $PERIOD_NS [get_ports clk]

# Uncertainty: account for jitter + skew across the FPGA fabric
set_clock_uncertainty -setup 0.2 [get_clocks clk]
set_clock_uncertainty -hold  0.1 [get_clocks clk]

# ---------------------------------------------------------------------------
# Input delays (relative to clk)
# Model the AXI4-Stream source timing (e.g., Ethernet MAC output).
# Assume source captures data at rising edge, setup time 0.5 ns.
# ---------------------------------------------------------------------------
set_input_delay -clock clk -max 0.5 [get_ports {s_axis_tdata[*]}]
set_input_delay -clock clk -max 0.5 [get_ports {s_axis_tkeep[*]}]
set_input_delay -clock clk -max 0.5 [get_ports s_axis_tvalid]
set_input_delay -clock clk -max 0.5 [get_ports s_axis_tlast]
set_input_delay -clock clk -min 0.0 [get_ports {s_axis_tdata[*]}]
set_input_delay -clock clk -min 0.0 [get_ports {s_axis_tkeep[*]}]
set_input_delay -clock clk -min 0.0 [get_ports s_axis_tvalid]
set_input_delay -clock clk -min 0.0 [get_ports s_axis_tlast]

# FIB write port (slow control plane path — relax constraints)
set_input_delay -clock clk -max 2.0 [get_ports fib_wr_*]

# ---------------------------------------------------------------------------
# Output delays (relative to clk)
# Downstream MAC input setup time.
# ---------------------------------------------------------------------------
set_output_delay -clock clk -max 0.5 [get_ports {m_axis_tdata[*]}]
set_output_delay -clock clk -max 0.5 [get_ports {m_axis_tkeep[*]}]
set_output_delay -clock clk -max 0.5 [get_ports m_axis_tvalid]
set_output_delay -clock clk -max 0.5 [get_ports m_axis_tlast]
set_output_delay -clock clk -min 0.0 [get_ports {m_axis_tdata[*]}]
set_output_delay -clock clk -min 0.0 [get_ports {m_axis_tkeep[*]}]
set_output_delay -clock clk -min 0.0 [get_ports m_axis_tvalid]
set_output_delay -clock clk -min 0.0 [get_ports m_axis_tlast]

# Status outputs — relax
set_output_delay -clock clk -max 2.0 [get_ports stat_*]

# ---------------------------------------------------------------------------
# Multicycle paths
# FIB BRAM controller: the BRAM read has a deterministic 1-cycle latency.
# This is inherently pipelined — no multicycle exception needed.
#
# Token bucket refill counter: the refill_cnt comparison is a wide add
# (~32-bit). If timing is tight, add a multicycle here:
# ---------------------------------------------------------------------------
# set_multicycle_path -setup 2 -from [get_cells u_token_bucket/refill_cnt*]
# set_multicycle_path -hold  1 -from [get_cells u_token_bucket/refill_cnt*]

# ---------------------------------------------------------------------------
# False paths
# Reset is synchronous with clk; async paths are not applicable.
# The FIB initialization (in initial block) is simulation only.
# ---------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# ---------------------------------------------------------------------------
# Max fanout constraint on critical enable signals
# The tuple_valid and hash_valid signals fan out to multiple pipeline registers.
# ---------------------------------------------------------------------------
set_max_fanout 20 [get_nets {*tuple_valid* *hash_valid* *hdr_valid*}]
