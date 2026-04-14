// =============================================================================
// token_bucket_limiter.v
// Token Bucket Rate Limiter - Elephant Flow Detection
// =============================================================================
// Per-server token bucket:
//   - Bucket capacity: BUCKET_SIZE tokens
//   - Refill rate: REFILL_RATE tokens per REFILL_PERIOD cycles
//   - Each permitted packet consumes PKT_COST tokens
//
// If a server's bucket is empty, the packet is dropped (permit=0).
// The token_bucket also passes through the routing metadata for packets
// that are permitted.
//
// For V2.0: thresholds will be configurable via AXI4-Lite register bank.
// =============================================================================

`timescale 1ns / 1ps

module token_bucket_limiter #(
    parameter NUM_SERVERS   = 8,
    parameter BUCKET_SIZE   = 1024,  // tokens
    parameter REFILL_RATE   = 8,     // tokens per refill tick
    parameter REFILL_PERIOD = 100,   // cycles between refills
    parameter PKT_COST      = 1      // tokens consumed per packet
) (
    input  wire        clk,
    input  wire        rst_n,

    // Input from FIB
    input  wire        in_valid,
    input  wire        in_bypass,
    input  wire [47:0] in_dst_mac,
    input  wire [31:0] in_dst_ip,

    // Output to meta FIFO
    output reg         out_valid,
    output reg         out_bypass,
    output reg         out_permit,
    output reg  [47:0] out_dst_mac,
    output reg  [31:0] out_dst_ip
);

localparam BUCKET_BITS = $clog2(BUCKET_SIZE + 1);
localparam PERIOD_BITS = $clog2(REFILL_PERIOD + 1);

// ---------------------------------------------------------------------------
// Per-server token buckets
// ---------------------------------------------------------------------------
reg [BUCKET_BITS-1:0] tokens [0:NUM_SERVERS-1];
reg [PERIOD_BITS-1:0] refill_cnt;

// Server ID derived from lower bits of dst_ip
wire [2:0] server_sel = in_dst_ip[2:0]; // server_id = ip[2:0] - 1 (approx)

integer k;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        refill_cnt <= {PERIOD_BITS{1'b0}};
        for (k = 0; k < NUM_SERVERS; k = k + 1)
            tokens[k] <= BUCKET_SIZE[BUCKET_BITS-1:0];
    end else begin
        // Refill tick
        if (refill_cnt == REFILL_PERIOD - 1) begin
            refill_cnt <= {PERIOD_BITS{1'b0}};
            for (k = 0; k < NUM_SERVERS; k = k + 1) begin
                if (tokens[k] <= (BUCKET_SIZE - REFILL_RATE))
                    tokens[k] <= tokens[k] + REFILL_RATE[BUCKET_BITS-1:0];
                else
                    tokens[k] <= BUCKET_SIZE[BUCKET_BITS-1:0];
            end
        end else begin
            refill_cnt <= refill_cnt + 1'b1;
        end

        // Consume token on valid non-bypass packet
        if (in_valid && !in_bypass) begin
            if (tokens[server_sel] >= PKT_COST)
                tokens[server_sel] <= tokens[server_sel] - PKT_COST[BUCKET_BITS-1:0];
            // else: drop - token remains at 0
        end
    end
end

// ---------------------------------------------------------------------------
// Output registration
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid   <= 1'b0;
        out_bypass  <= 1'b0;
        out_permit  <= 1'b0;
        out_dst_mac <= 48'd0;
        out_dst_ip  <= 32'd0;
    end else begin
        out_valid   <= in_valid;
        out_bypass  <= in_bypass;
        out_dst_mac <= in_dst_mac;
        out_dst_ip  <= in_dst_ip;
        if (in_bypass)
            out_permit <= 1'b1; // always permit bypass (ARP/ICMP)
        else
            out_permit <= (tokens[server_sel] >= PKT_COST);
    end
end

endmodule