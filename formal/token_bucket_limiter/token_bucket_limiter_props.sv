`default_nettype none
module fib_bram_controller_props #(parameter FIB_INDEX_BITS = 4) (
    input wire clk, input wire rst_n,
    input wire [31:0] hash_in,
    input wire in_valid, input wire in_bypass
);

wire [47:0] dst_mac;
wire [31:0] dst_ip;
wire [2:0]  server_id;
wire        out_valid, out_bypass;

fib_bram_controller #(.FIB_INDEX_BITS(FIB_INDEX_BITS), .FIB_INIT_FILE("")) dut (
    .clk(clk), .rst_n(rst_n),
    .hash_in(hash_in), .in_valid(in_valid), .in_bypass(in_bypass),
    .dst_mac(dst_mac), .dst_ip(dst_ip),
    .server_id(server_id), .out_valid(out_valid), .out_bypass(out_bypass)
);

localparam FIB_DEPTH = 1 << FIB_INDEX_BITS;

reg [FIB_INDEX_BITS-1:0] addr_r_s;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) addr_r_s <= {FIB_INDEX_BITS{1'b0}};
    else        addr_r_s <= hash_in[FIB_INDEX_BITS-1:0];
end

// Hold reset long enough to flush the 2-stage pipeline
reg f_past_valid, fpv2, fpv3;
initial begin f_past_valid = 1'b0; fpv2 = 1'b0; fpv3 = 1'b0; end
always @(posedge clk) begin
    f_past_valid <= 1'b1;
    fpv2 <= f_past_valid;
    fpv3 <= fpv2;
end

// Hold reset for 3 cycles so pipeline is flushed before latency assertions fire
always @(*) begin
    if (!fpv2) assume(!rst_n);
end

always @(posedge clk) begin
    if (!rst_n) begin assert(!out_valid); assert(!out_bypass); end
end

// Latency assertions need 3 clean post-reset cycles of history
always @(posedge clk) begin
    if (fpv3 && rst_n) assert(out_valid  == $past(in_valid,  2));
end
always @(posedge clk) begin
    if (fpv3 && rst_n) assert(out_bypass == $past(in_bypass, 2));
end

always @(posedge clk) begin
    if (rst_n) assert(addr_r_s < FIB_DEPTH[FIB_INDEX_BITS-1:0]);
end
always @(posedge clk) begin
    if (rst_n && out_valid) assert(server_id <= 3'd7);
end
always @(posedge clk) begin if (rst_n) cover(out_valid && !out_bypass); end
always @(posedge clk) begin if (rst_n) cover(out_valid &&  out_bypass); end

endmodule