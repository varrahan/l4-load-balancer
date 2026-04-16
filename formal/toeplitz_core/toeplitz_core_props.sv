`default_nettype none
module toeplitz_core_props (
    input wire clk, input wire rst_n,
    input wire [31:0] src_ip, input wire [31:0] dst_ip,
    input wire [15:0] src_port, input wire [15:0] dst_port,
    input wire in_valid, input wire in_bypass
);

wire [31:0] hash_out;
wire        out_valid, out_bypass;

toeplitz_core dut (
    .clk(clk), .rst_n(rst_n),
    .src_ip(src_ip), .dst_ip(dst_ip),
    .src_port(src_port), .dst_port(dst_port),
    .in_valid(in_valid), .in_bypass(in_bypass),
    .hash_out(hash_out), .out_valid(out_valid), .out_bypass(out_bypass)
);

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

reg fpv2, fpv3;
initial begin fpv2 = 1'b0; fpv3 = 1'b0; end
always @(posedge clk) begin fpv2 <= f_past_valid; fpv3 <= fpv2; end

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
end

// For 3-cycle latency checks we need rst_n stable for 4 cycles
// Use fpv3 (true from step 3 onward) plus current rst_n
always @(posedge clk) begin
    if (!rst_n) begin assert(!out_valid); assert(!out_bypass); end
end
always @(posedge clk) begin
    if (fpv3 && rst_n) assert(out_valid  == $past(in_valid,  3));
end
always @(posedge clk) begin
    if (fpv3 && rst_n) assert(out_bypass == $past(in_bypass, 3));
end
always @(posedge clk) begin
    if (rst_n) assert(!(out_valid && out_bypass));
end
always @(posedge clk) begin if (rst_n)       cover(out_valid && hash_out != 32'd0); end
always @(posedge clk) begin if (f_past_valid && rst_n && $past(rst_n))
    cover(out_valid && $past(out_valid)); end

endmodule
