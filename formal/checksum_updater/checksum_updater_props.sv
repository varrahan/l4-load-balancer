// =============================================================================
// formal/checksum_updater/checksum_updater_props.sv
// Formal property STUB for checksum_updater
// =============================================================================
// STATUS: NOT CONNECTED TO CI
//
// The V1 checksum_updater explicitly defers the RFC 1624 patch (see beat-4
// comment in rtl/rewrite/checksum_updater.v). The full invariant requires a
// two-packet look-ahead buffer that is slated for V2.
//
// This file documents the INTENDED invariant so it can be wired into CI
// once the V2 implementation is committed.
//
// Intended properties:
//   1. RFC 1624 invariant  - output checksum equals HC' = ~(~HC + ~m + m')
//                            where HC = old checksum, m = old dst_ip half-word,
//                            m' = new dst_ip half-word
//   2. Bypass passthrough  - bypass packets pass through with zero modification
//   3. Non-bypass checksum is patched at beat 3, not earlier or later
//   4. m_tvalid mirrors s_tvalid with 0 or 1 cycle latency (pass-through path)
// =============================================================================

`default_nettype none

module checksum_updater_props #(
    parameter DATA_WIDTH = 64
) (
    input wire                    clk,
    input wire                    rst_n,
    input wire [DATA_WIDTH-1:0]   s_tdata,
    input wire                    s_tvalid,
    input wire                    s_tlast,
    input wire [DATA_WIDTH/8-1:0] s_tkeep,
    input wire                    m_tready
);

wire [DATA_WIDTH-1:0]   m_tdata;
wire                    m_tvalid, m_tlast;
wire [DATA_WIDTH/8-1:0] m_tkeep;
wire                    s_tready;

checksum_updater #(.DATA_WIDTH(DATA_WIDTH)) dut (
    .clk     (clk),
    .rst_n   (rst_n),
    .s_tdata (s_tdata),
    .s_tvalid(s_tvalid),
    .s_tlast (s_tlast),
    .s_tkeep (s_tkeep),
    .s_tready(s_tready),
    .m_tdata (m_tdata),
    .m_tvalid(m_tvalid),
    .m_tlast (m_tlast),
    .m_tkeep (m_tkeep),
    .m_tready(m_tready)
);

// --------------------------------------------------------------------------
// Reset
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n)
        assert_reset_mvalid: assert (!m_tvalid);
end

// --------------------------------------------------------------------------
// STUB: RFC 1624 invariant (DISABLED - requires V2 implementation)
//
// Once V2 lands, the intended check is:
//
//   When m_tvalid is high on beat 3 of a non-bypass packet:
//     let HC  = old checksum (captured at beat 2)
//     let m   = {old_dst_ip[31:16], old_dst_ip[15:0]}  (two 16-bit halves)
//     let m'  = {new_dst_ip[31:16], new_dst_ip[15:0]}  (from header_modifier)
//     then m_tdata[63:48] == ones_complement_sum(~HC, ~m[31:16], m'[31:16])
//
// Encoding as SVA once the RTL exposes old_dst_ip and new_dst_ip as ports
// or as internal signals accessible via hierarchical reference:
//
//   assert property (
//     @(posedge clk) disable iff (!rst_n)
//     (m_tvalid && dut.beat_cnt == 3'd3 && !dut.bypass_flag) |->
//       (m_tdata[63:48] == rfc1624(dut.old_csum, dut.old_dst_ip, dut.new_dst_ip))
//   );
//
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Cover: beat 3 of a non-bypass packet is reachable
// --------------------------------------------------------------------------
beat3_reached: cover property (
    @(posedge clk) disable iff (!rst_n)
    m_tvalid && (dut.beat_cnt == 3'd3)
);

endmodule
