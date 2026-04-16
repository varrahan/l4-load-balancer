// =============================================================================
// formal/tuple_extractor/tuple_extractor_props.sv
// Formal properties for tuple_extractor
// =============================================================================
// Properties verified:
//   1. Mutual exclusion       - tuple_valid and bypass never both asserted
//   2. Single-cycle pulse     - tuple_valid is asserted for exactly 1 cycle
//   3. Single-cycle pulse     - bypass is asserted for exactly 1 cycle
//   4. IPv4/TCP triggers valid - EtherType=0x0800, proto=0x06 → tuple_valid
//   5. IPv4/UDP triggers valid - EtherType=0x0800, proto=0x11 → tuple_valid
//   6. ARP triggers bypass    - EtherType=0x0806 → bypass (not tuple_valid)
//   7. ICMP triggers bypass   - proto=0x01 → bypass (not tuple_valid)
//   8. tuple_valid only on beat 4 - cannot fire on beats 0-3
//   9. Reset clears outputs
//  10. Cover: valid TCP extraction reachable
//  11. Cover: ARP bypass reachable
// =============================================================================

`default_nettype none

module tuple_extractor_props (
    input wire        clk,
    input wire        rst_n,
    input wire [63:0] s_tdata,
    input wire        s_tvalid,
    input wire        s_tlast,
    input wire [7:0]  s_tkeep
);

wire [31:0] src_ip, dst_ip;
wire [15:0] src_port, dst_port;
wire [7:0]  protocol;
wire        tuple_valid, bypass;

tuple_extractor #(.DATA_WIDTH(64)) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_tdata    (s_tdata),
    .s_tvalid   (s_tvalid),
    .s_tlast    (s_tlast),
    .s_tkeep    (s_tkeep),
    .src_ip     (src_ip),
    .dst_ip     (dst_ip),
    .src_port   (src_port),
    .dst_port   (dst_port),
    .protocol   (protocol),
    .tuple_valid(tuple_valid),
    .bypass     (bypass)
);

// --------------------------------------------------------------------------
// 1. tuple_valid and bypass are mutually exclusive
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n)
        assert_mutex: assert (!(tuple_valid && bypass));
end

// --------------------------------------------------------------------------
// 2. tuple_valid is a single-cycle pulse: cannot be high two cycles running
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(tuple_valid))
        assert_valid_pulse: assert (!tuple_valid);
end

// --------------------------------------------------------------------------
// 3. bypass is a single-cycle pulse
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(bypass))
        assert_bypass_pulse: assert (!bypass);
end

// --------------------------------------------------------------------------
// 4. Reset clears all outputs
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        assert_reset_valid:  assert (!tuple_valid);
        assert_reset_bypass: assert (!bypass);
    end
end

// --------------------------------------------------------------------------
// 5. tuple_valid only possible when beat_cnt was 4 on previous cycle
//    (because outputs are registered one cycle after beat 4 fires)
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && tuple_valid)
        assert_valid_at_beat4: assert ($past(dut.beat_cnt) == 3'd4);
end

// --------------------------------------------------------------------------
// 6. bypass only possible when beat_cnt was 4 on previous cycle
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && bypass)
        assert_bypass_at_beat4: assert ($past(dut.beat_cnt) == 3'd4);
end

// --------------------------------------------------------------------------
// 7. beat_cnt never exceeds 7
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n)
        assert_beat_bound: assert (dut.beat_cnt <= 3'd7);
end

// --------------------------------------------------------------------------
// 8. beat_cnt resets to 0 after tlast
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(s_tvalid) && $past(s_tlast))
        assert_beat_reset_on_tlast: assert (dut.beat_cnt == 3'd0);
end

// --------------------------------------------------------------------------
// Cover: TCP extraction reached
// --------------------------------------------------------------------------
tcp_valid_reached: cover property (
    @(posedge clk) disable iff (!rst_n)
    tuple_valid && (protocol == 8'h06)
);

// --------------------------------------------------------------------------
// Cover: UDP extraction reached
// --------------------------------------------------------------------------
udp_valid_reached: cover property (
    @(posedge clk) disable iff (!rst_n)
    tuple_valid && (protocol == 8'h11)
);

// --------------------------------------------------------------------------
// Cover: ARP bypass reached
// --------------------------------------------------------------------------
arp_bypass_reached: cover property (
    @(posedge clk) disable iff (!rst_n)
    bypass
);

endmodule
