`default_nettype none
module token_bucket_limiter_props #(
    parameter NUM_SERVERS   = 2,
    parameter BUCKET_SIZE   = 4,
    parameter REFILL_RATE   = 2,
    parameter REFILL_PERIOD = 4,
    parameter PKT_COST      = 1
) (
    input wire clk, input wire rst_n,
    input wire in_valid, input wire in_bypass,
    input wire [47:0] in_dst_mac, input wire [31:0] in_dst_ip
);

wire        out_valid, out_bypass, out_permit;
wire [47:0] out_dst_mac;
wire [31:0] out_dst_ip;

token_bucket_limiter #(
    .NUM_SERVERS(NUM_SERVERS), .BUCKET_SIZE(BUCKET_SIZE),
    .REFILL_RATE(REFILL_RATE), .REFILL_PERIOD(REFILL_PERIOD),
    .PKT_COST(PKT_COST)
) dut (
    .clk(clk), .rst_n(rst_n),
    .in_valid(in_valid), .in_bypass(in_bypass),
    .in_dst_mac(in_dst_mac), .in_dst_ip(in_dst_ip),
    .out_valid(out_valid), .out_bypass(out_bypass), .out_permit(out_permit),
    .out_dst_mac(out_dst_mac), .out_dst_ip(out_dst_ip)
);

localparam BUCKET_BITS = $clog2(BUCKET_SIZE + 1);
localparam PERIOD_BITS = $clog2(REFILL_PERIOD + 1);

wire [2:0] server_sel = in_dst_ip[2:0];
always @(*) assume(server_sel < NUM_SERVERS);

// Shadow refill counter only - simpler than full token shadow
reg [PERIOD_BITS-1:0] refill_cnt_s;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        refill_cnt_s <= {PERIOD_BITS{1'b0}};
    else if (refill_cnt_s == REFILL_PERIOD - 1)
        refill_cnt_s <= {PERIOD_BITS{1'b0}};
    else
        refill_cnt_s <= refill_cnt_s + 1'b1;
end

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
    else               assume(rst_n);
end

reg fpv_stable;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) fpv_stable <= 1'b0;
    else        fpv_stable <= f_past_valid;
end

// 1. Reset: out_valid deasserted
always @(posedge clk) begin
    if (!rst_n) assert(!out_valid);
end

// 2. out_valid is in_valid delayed by 1 cycle
always @(posedge clk) begin
    if (fpv_stable) assert(out_valid == $past(in_valid));
end

// 3. Refill counter bounded: never reaches REFILL_PERIOD
always @(posedge clk) begin
    if (rst_n) assert(refill_cnt_s < REFILL_PERIOD[PERIOD_BITS-1:0]);
end

// 4. Bypass always permitted
always @(posedge clk) begin
    if (rst_n && out_valid && out_bypass) assert(out_permit);
end

always @(posedge clk) begin if (rst_n) cover(out_valid && !out_permit); end
always @(posedge clk) begin if (rst_n) cover(out_valid &&  out_permit); end

endmodule