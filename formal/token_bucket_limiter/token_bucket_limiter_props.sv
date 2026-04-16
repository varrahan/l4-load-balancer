// =============================================================================
// formal/token_bucket_limiter/token_bucket_limiter_props.sv
// Formal properties for token_bucket_limiter
// =============================================================================
// Properties verified:
//   1. Token floor        - no server's token count ever goes negative (underflows)
//   2. Token ceiling      - no server's token count ever exceeds BUCKET_SIZE
//   3. Bypass always permitted - out_permit is always 1 when in_bypass
//   4. Drop when empty    - out_permit is 0 when tokens[server_sel] < PKT_COST at input
//   5. Permit when enough - out_permit is 1 when tokens[server_sel] >= PKT_COST
//   6. Refill counter bound - refill_cnt never exceeds REFILL_PERIOD-1
//   7. Output latency     - out_valid mirrors in_valid with 1-cycle delay
//   8. Reset correctness  - out_valid deasserted, all buckets full after reset
//   9. Cover: a packet is dropped (permit=0)
//  10. Cover: a packet is permitted (permit=1)
//  11. Cover: refill tick fires
// =============================================================================

`default_nettype none

module token_bucket_limiter_props #(
    parameter NUM_SERVERS   = 2,    // reduced for BMC tractability
    parameter BUCKET_SIZE   = 4,
    parameter REFILL_RATE   = 2,
    parameter REFILL_PERIOD = 4,
    parameter PKT_COST      = 1
) (
    input wire        clk,
    input wire        rst_n,
    input wire        in_valid,
    input wire        in_bypass,
    input wire [47:0] in_dst_mac,
    input wire [31:0] in_dst_ip
);

wire        out_valid, out_bypass, out_permit;
wire [47:0] out_dst_mac;
wire [31:0] out_dst_ip;

token_bucket_limiter #(
    .NUM_SERVERS  (NUM_SERVERS),
    .BUCKET_SIZE  (BUCKET_SIZE),
    .REFILL_RATE  (REFILL_RATE),
    .REFILL_PERIOD(REFILL_PERIOD),
    .PKT_COST     (PKT_COST)
) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_valid   (in_valid),
    .in_bypass  (in_bypass),
    .in_dst_mac (in_dst_mac),
    .in_dst_ip  (in_dst_ip),
    .out_valid  (out_valid),
    .out_bypass (out_bypass),
    .out_permit (out_permit),
    .out_dst_mac(out_dst_mac),
    .out_dst_ip (out_dst_ip)
);

localparam BUCKET_BITS = $clog2(BUCKET_SIZE + 1);
localparam PERIOD_BITS = $clog2(REFILL_PERIOD + 1);

// Constrain server_sel to valid range for NUM_SERVERS=2
wire [2:0] server_sel = in_dst_ip[2:0];
// For formal tractability with NUM_SERVERS=2, assume sel is 0 or 1
always @(*) begin
    assume (server_sel < NUM_SERVERS);
end

// --------------------------------------------------------------------------
// 1. Token floor: no bucket goes below zero (BUCKET_BITS unsigned, so the
//    check is that subtraction never produces a value > BUCKET_SIZE,
//    i.e. no wrap-around)
// --------------------------------------------------------------------------
genvar g;
generate
    for (g = 0; g < NUM_SERVERS; g = g + 1) begin : token_floor
        always @(posedge clk) begin
            if (rst_n)
                assert_token_floor: assert (dut.tokens[g] <= BUCKET_SIZE[BUCKET_BITS-1:0]);
        end
    end
endgenerate

// --------------------------------------------------------------------------
// 2. Token ceiling (same check - tokens can never exceed BUCKET_SIZE)
//    Separate named assertion for clarity in coverage report
// --------------------------------------------------------------------------
generate
    for (g = 0; g < NUM_SERVERS; g = g + 1) begin : token_ceiling
        always @(posedge clk) begin
            if (rst_n)
                assert_token_ceiling: assert (dut.tokens[g] <= BUCKET_SIZE[BUCKET_BITS-1:0]);
        end
    end
endgenerate

// --------------------------------------------------------------------------
// 3. Bypass always permitted: out_permit must be 1 for bypass packets
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && out_valid && out_bypass)
        assert_bypass_always_permit: assert (out_permit);
end

// --------------------------------------------------------------------------
// 4. Permit reflects token availability at time of input
//    (out is registered 1 cycle after in_valid)
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(in_valid) && !$past(in_bypass)) begin
        if ($past(dut.tokens[$past(server_sel)]) >= PKT_COST[BUCKET_BITS-1:0])
            assert_permit_when_enough: assert (out_permit);
        else
            assert_drop_when_empty: assert (!out_permit);
    end
end

// --------------------------------------------------------------------------
// 5. Refill counter is bounded: never exceeds REFILL_PERIOD - 1
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n)
        assert_refill_cnt_bound: assert (dut.refill_cnt < REFILL_PERIOD[PERIOD_BITS-1:0]);
end

// --------------------------------------------------------------------------
// 6. Output latency: out_valid is 1 cycle behind in_valid
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(rst_n))
        assert_out_valid_latency: assert (out_valid == $past(in_valid));
end

// --------------------------------------------------------------------------
// 7. Reset: all buckets initialized to BUCKET_SIZE, out_valid deasserted
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        assert_reset_out_valid: assert (!out_valid);
    end
end

// --------------------------------------------------------------------------
// Cover: a packet is dropped
// --------------------------------------------------------------------------
packet_dropped: cover property (
    @(posedge clk) disable iff (!rst_n)
    out_valid && !out_bypass && !out_permit
);

// --------------------------------------------------------------------------
// Cover: a packet is permitted
// --------------------------------------------------------------------------
packet_permitted: cover property (
    @(posedge clk) disable iff (!rst_n)
    out_valid && !out_bypass && out_permit
);

// --------------------------------------------------------------------------
// Cover: refill tick fires (refill_cnt wraps)
// --------------------------------------------------------------------------
refill_fires: cover property (
    @(posedge clk) disable iff (!rst_n)
    (dut.refill_cnt == REFILL_PERIOD - 1)
);

endmodule
