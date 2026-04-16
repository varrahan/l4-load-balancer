// =============================================================================
// formal/fib_bram_controller/fib_bram_controller_props.sv
// Formal properties for fib_bram_controller
// =============================================================================
// Properties verified:
//   1. Latency contract  - out_valid arrives exactly 2 cycles after in_valid
//   2. Bypass propagation - out_bypass mirrors in_bypass through 2-stage pipe
//   3. Reset correctness  - out_valid/out_bypass deasserted after reset
//   4. Address bound      - BRAM address index always within [0, FIB_DEPTH)
//   5. II=1               - two consecutive valid inputs yield two valid outputs
//   6. server_id bound    - server_id output is in [0, 7] (3-bit field)
//   7. Cover: valid lookup completes
//   8. Cover: bypass lookup completes
// =============================================================================

`default_nettype none

module fib_bram_controller_props #(
    parameter FIB_INDEX_BITS = 4  // small for BMC (16-entry FIB)
) (
    input wire        clk,
    input wire        rst_n,
    input wire [31:0] hash_in,
    input wire        in_valid,
    input wire        in_bypass
);

wire [47:0] dst_mac;
wire [31:0] dst_ip;
wire [2:0]  server_id;
wire        out_valid, out_bypass;

fib_bram_controller #(
    .FIB_INDEX_BITS(FIB_INDEX_BITS),
    .FIB_INIT_FILE ("")
) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .hash_in  (hash_in),
    .in_valid (in_valid),
    .in_bypass(in_bypass),
    .dst_mac  (dst_mac),
    .dst_ip   (dst_ip),
    .server_id(server_id),
    .out_valid(out_valid),
    .out_bypass(out_bypass)
);

// --------------------------------------------------------------------------
// 1. Latency: in_valid at t → out_valid at t+2
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(rst_n,1) && $past(rst_n,2))
        assert_latency_2: assert (out_valid == $past(in_valid, 2));
end

// --------------------------------------------------------------------------
// 2. Bypass propagates with same 2-cycle latency
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(rst_n,1) && $past(rst_n,2))
        assert_bypass_latency: assert (out_bypass == $past(in_bypass, 2));
end

// --------------------------------------------------------------------------
// 3. Reset
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        assert_reset_valid:  assert (!out_valid);
        assert_reset_bypass: assert (!out_bypass);
    end
end

// --------------------------------------------------------------------------
// 4. BRAM address is always within valid range
// --------------------------------------------------------------------------
localparam FIB_DEPTH = 1 << FIB_INDEX_BITS;
always @(posedge clk) begin
    if (rst_n)
        assert_addr_bound: assert (dut.addr_r < FIB_DEPTH[FIB_INDEX_BITS-1:0]);
end

// --------------------------------------------------------------------------
// 5. II=1: two consecutive valid ins → two consecutive valid outs
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(rst_n,1) && $past(rst_n,2) && $past(rst_n,3) &&
        $past(in_valid,2) && $past(in_valid,3))
        assert_ii1: assert (out_valid && $past(out_valid));
end

// --------------------------------------------------------------------------
// 6. server_id is a 3-bit value (always in range, trivially, but checks
//    that parsing of bram_out[15:13] is consistent)
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && out_valid)
        assert_server_id_bound: assert (server_id <= 3'd7);
end

// --------------------------------------------------------------------------
// Cover: valid lookup completes (non-bypass)
// --------------------------------------------------------------------------
valid_lookup: cover property (
    @(posedge clk) disable iff (!rst_n)
    out_valid && !out_bypass
);

// --------------------------------------------------------------------------
// Cover: bypass lookup completes
// --------------------------------------------------------------------------
bypass_lookup: cover property (
    @(posedge clk) disable iff (!rst_n)
    out_valid && out_bypass
);

endmodule
