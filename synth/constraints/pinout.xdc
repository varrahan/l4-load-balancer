# =============================================================================
# pinout.xdc — Physical FPGA Pin Assignments
# Project    : L4 Smart Load Balancer
# Author     : Varrahan Uthayan
# Target     : Xilinx Alveo U50 / ZCU102 FPGA SmartNIC platform
#
# Pin assignments target a Xilinx Alveo U50 Data Center Accelerator Card
# with the on-board 100GbE QSFP28 port connected through the CMAC hard IP.
# The actual pinout depends on the board support package (BSP) and shell.
#
# NOTE: In a real SmartNIC deployment, AXI4-Stream signals connect to the
#       hard CMAC or LBUS interface — not to raw I/O pins.  These XDC
#       constraints are provided for:
#         1. Reference / documentation completeness
#         2. Custom FPGA board evaluation platforms
#
# Clock configuration:
#   The 156.25 MHz reference clock is typically sourced from:
#   - Alveo U50: QSFP reference clock input (Si5324 synthesizer)
#   - ZCU102:    J83 SMA clock input or U4 oscillator
# =============================================================================

# ---------------------------------------------------------------------------
# Clock — 156.25 MHz differential reference from on-board oscillator
# Alveo U50: Bank 65 differential clock input
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN   AK17           [get_ports clk_p]
set_property PACKAGE_PIN   AK16           [get_ports clk_n]
set_property IOSTANDARD    LVDS           [get_ports clk_p]
set_property IOSTANDARD    LVDS           [get_ports clk_n]
set_property DIFF_TERM_ADV TERM_100       [get_ports clk_p]

# Single-ended clock (for evaluation boards without diff input)
# set_property PACKAGE_PIN  AH18          [get_ports clk]
# set_property IOSTANDARD   LVCMOS18      [get_ports clk]

# ---------------------------------------------------------------------------
# Reset — Active-low push-button or GPIO
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN   AR13           [get_ports rst_n]
set_property IOSTANDARD    LVCMOS18       [get_ports rst_n]
set_property PULLUP        TRUE           [get_ports rst_n]

# ---------------------------------------------------------------------------
# Status LEDs
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN   AP8            [get_ports stat_payload_fifo_full]
set_property IOSTANDARD    LVCMOS18       [get_ports stat_payload_fifo_full]

set_property PACKAGE_PIN   AP9            [get_ports stat_meta_fifo_full]
set_property IOSTANDARD    LVCMOS18       [get_ports stat_meta_fifo_full]

set_property PACKAGE_PIN   AR8            [get_ports stat_rate_limited_flag]
set_property IOSTANDARD    LVCMOS18       [get_ports stat_rate_limited_flag]

# ---------------------------------------------------------------------------
# AXI4-Stream Ingress — Connected to CMAC hard IP via AXI4-Stream bridge
# In a SmartNIC shell, these are internal connections, not external pins.
# Document here for traceability to the shell/BSP.
# ---------------------------------------------------------------------------
# s_axis_tdata[63:0]   → CMAC RX AXIS TDATA
# s_axis_tkeep[7:0]    → CMAC RX AXIS TKEEP
# s_axis_tvalid        → CMAC RX AXIS TVALID
# s_axis_tlast         → CMAC RX AXIS TLAST
# s_axis_tready        → CMAC RX AXIS TREADY (backpressure)

# AXI4-Stream Egress — Connected to CMAC hard IP TX path
# m_axis_tdata[63:0]   → CMAC TX AXIS TDATA
# m_axis_tkeep[7:0]    → CMAC TX AXIS TKEEP
# m_axis_tvalid        → CMAC TX AXIS TVALID
# m_axis_tlast         → CMAC TX AXIS TLAST
# m_axis_tready        → CMAC TX AXIS TREADY

# ---------------------------------------------------------------------------
# FIB Write Port — Connected to PCIe/AXI4-Lite host interface (V2.0 feature)
# Currently stubbed out; listed here for future PCIe BAR mapping.
# ---------------------------------------------------------------------------
# fib_wr_en            → AXI4-Lite slave write-enable (V2.0)
# fib_wr_addr[9:0]     → AXI4-Lite address [11:2]
# fib_wr_data[95:0]    → AXI4-Lite write data

# ---------------------------------------------------------------------------
# CONFIGURATION MEMORY (for persistent FIB contents across power cycles)
# The FIB can be initialized from QSPI flash on startup via a configuration
# controller — not yet implemented.  Reserved pin assignments below.
# ---------------------------------------------------------------------------
# QSPI_CS_N     → AM12  LVCMOS18
# QSPI_DQ[0]    → AN12  LVCMOS18
# QSPI_DQ[1]    → AP12  LVCMOS18
# QSPI_DQ[2]    → AL12  LVCMOS18
# QSPI_DQ[3]    → AM11  LVCMOS18
