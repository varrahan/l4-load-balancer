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

reg [BUCKET_BITS-1:0] tokens_s [0:NUM_SERVERS-1];
reg [PERIOD_BITS-1:0] refill_cnt_s;
integer k;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        refill_cnt_s <= {PERIOD_BITS{1'b0}};
        for (k = 0; k < NUM_SERVERS; k = k + 1)
            tokens_s[k] <= BUCKET_SIZE[BUCKET_BITS-1:0];
    end else begin
        if (refill_cnt_s == REFILL_PERIOD - 1) begin
            refill_cnt_s <= {PERIOD_BITS{1'b0}};
            for (k = 0; k < NUM_SERVERS; k = k + 1) begin
                if (tokens_s[k] <= (BUCKET_SIZE - REFILL_RATE))
                    tokens_s[k] <= tokens_s[k] + REFILL_RATE[BUCKET_BITS-1:0];
                else
                    tokens_s[k] <= BUCKET_SIZE[BUCKET_BITS-1:0];
            end
        end else begin
            refill_cnt_s <= refill_cnt_s + 1'b1;
        end
        if (in_valid && !in_bypass && tokens_s[server_sel] >= PKT_COST)
            tokens_s[server_sel] <= tokens_s[server_sel] - PKT_COST[BUCKET_BITS-1:0];
    end
end

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
end

wire fpv_stable = f_past_valid && rst_n && $past(rst_n);

genvar g;
generate
    for (g = 0; g < NUM_SERVERS; g = g + 1) begin : token_bounds
        always @(posedge clk) begin
            if (rst_n) assert(tokens_s[g] <= BUCKET_SIZE[BUCKET_BITS-1:0]);
        end
    end
endgenerate

always @(posedge clk) begin if (!rst_n) assert(!out_valid); end
always @(posedge clk) begin
    if (fpv_stable) assert(out_valid == $past(in_valid));
end
always @(posedge clk) begin
    if (rst_n && out_valid && out_bypass) assert(out_permit);
end
always @(posedge clk) begin
    if (fpv_stable && $past(in_valid) && !$past(in_bypass)) begin
        if ($past(tokens_s[$past(server_sel)]) >= PKT_COST[BUCKET_BITS-1:0])
            assert(out_permit);
        else
            assert(!out_permit);
    end
end
always @(posedge clk) begin
    if (rst_n) assert(refill_cnt_s < REFILL_PERIOD[PERIOD_BITS-1:0]);
end
always @(posedge clk) begin if (rst_n) cover(out_valid && !out_bypass && !out_permit); end
always @(posedge clk) begin if (rst_n) cover(out_valid && !out_bypass &&  out_permit); end
always @(posedge clk) begin if (rst_n) cover(refill_cnt_s == REFILL_PERIOD - 1);       end

endmodule
