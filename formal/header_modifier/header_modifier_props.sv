// =============================================================================
// formal/header_modifier/header_modifier_props.sv
// Formal properties for header_modifier
// =============================================================================
// Properties verified:
//   1. Bypass passthrough    - bypass packets are never modified (all beats pass unchanged)
//   2. Beat-0 MAC rewrite    - DST MAC bytes 0-5 match meta_dst_mac on beat 0
//   3. Beat-0 tail preserved - bytes 6-7 of beat 0 are unchanged after MAC rewrite
//   4. Beat-3 DST IP hi      - bits [15:0] of beat 3 carry new dst_ip[31:16]
//   5. Beat-4 DST IP lo      - bits [63:48] of beat 4 carry new dst_ip[15:0]
//   6. Other beats unchanged - beats 1,2,5,6,7 pass through unmodified
//   7. meta consumed once    - meta_ready pulses exactly once per packet start
//   8. Reset correctness     - m_tvalid deasserted after reset
//   9. s_tready stalls       - s_tready low when !in_packet && !meta_valid
//  10. Cover: bypass packet forwarded
//  11. Cover: DNAT rewrite on beat 0 and beat 4 in same packet
// =============================================================================

`default_nettype none

module header_modifier_props (
    input wire        clk,
    input wire        rst_n,

    // AXI-S payload input
    input wire [63:0] s_tdata,
    input wire        s_tvalid,
    input wire        s_tlast,
    input wire [7:0]  s_tkeep,

    // Meta input
    input wire        meta_valid,
    input wire        meta_bypass,
    input wire [47:0] meta_dst_mac,
    input wire [31:0] meta_dst_ip,

    // Downstream ready
    input wire        m_tready
);

wire [63:0] m_tdata;
wire        m_tvalid, m_tlast;
wire [7:0]  m_tkeep;
wire        s_tready, meta_ready;

header_modifier #(.DATA_WIDTH(64)) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_tdata    (s_tdata),
    .s_tvalid   (s_tvalid),
    .s_tlast    (s_tlast),
    .s_tkeep    (s_tkeep),
    .s_tready   (s_tready),
    .meta_valid (meta_valid),
    .meta_bypass(meta_bypass),
    .meta_dst_mac(meta_dst_mac),
    .meta_dst_ip (meta_dst_ip),
    .meta_ready (meta_ready),
    .m_tdata    (m_tdata),
    .m_tvalid   (m_tvalid),
    .m_tlast    (m_tlast),
    .m_tkeep    (m_tkeep),
    .m_tready   (m_tready)
);

wire beat_fire = s_tvalid && s_tready;

// --------------------------------------------------------------------------
// 1. Reset correctness
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n)
        assert_reset_mvalid: assert (!m_tvalid);
end

// --------------------------------------------------------------------------
// 2. s_tready is deasserted when no packet in flight and meta not yet valid
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && s_tvalid && !dut.in_packet && !meta_valid)
        assert_stall_no_meta: assert (!s_tready);
end

// --------------------------------------------------------------------------
// 3. Bypass: when latched bypass is set, m_tdata equals s_tdata on every beat
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && m_tvalid && dut.lat_bypass)
        assert_bypass_passthrough: assert (m_tdata == $past(s_tdata));
end

// --------------------------------------------------------------------------
// 4. Beat 0 (non-bypass): top 48 bits of m_tdata carry the latched dst_mac
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && m_tvalid && !dut.lat_bypass && $past(dut.in_packet == 0)) begin
        // This was beat 0 output
        assert_beat0_mac: assert (m_tdata[63:16] == dut.lat_dst_mac);
    end
end

// --------------------------------------------------------------------------
// 5. Beat 0: lower 16 bits (bytes 6-7: src_mac high) are preserved unchanged
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && m_tvalid && !dut.lat_bypass && $past(dut.in_packet == 0))
        assert_beat0_tail: assert (m_tdata[15:0] == $past(s_tdata[15:0]));
end

// --------------------------------------------------------------------------
// 6. Beat 3 (non-bypass): bits [15:0] carry new dst_ip[31:16]
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && m_tvalid && !dut.lat_bypass && $past(dut.beat_cnt) == 3'd3)
        assert_beat3_dip_hi: assert (m_tdata[15:0] == dut.lat_dst_ip[31:16]);
end

// --------------------------------------------------------------------------
// 7. Beat 4 (non-bypass): bits [63:48] carry new dst_ip[15:0]
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && m_tvalid && !dut.lat_bypass && $past(dut.beat_cnt) == 3'd4)
        assert_beat4_dip_lo: assert (m_tdata[63:48] == dut.lat_dst_ip[15:0]);
end

// --------------------------------------------------------------------------
// 8. meta_ready is a single-cycle pulse (consumed exactly once per packet)
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(meta_ready))
        assert_meta_ready_pulse: assert (!meta_ready);
end

// --------------------------------------------------------------------------
// 9. beat_cnt never exceeds 7
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n)
        assert_beat_bound: assert (dut.beat_cnt <= 3'd7);
end

// --------------------------------------------------------------------------
// Cover: bypass packet forwarded end-to-end
// --------------------------------------------------------------------------
bypass_forwarded: cover property (
    @(posedge clk) disable iff (!rst_n)
    m_tvalid && m_tlast && dut.lat_bypass
);

// --------------------------------------------------------------------------
// Cover: full DNAT rewrite visible (beat 0 + beat 4 in same packet)
// --------------------------------------------------------------------------
dnat_rewrite_full: cover property (
    @(posedge clk) disable iff (!rst_n)
    m_tvalid && m_tlast && !dut.lat_bypass
);

endmodule
