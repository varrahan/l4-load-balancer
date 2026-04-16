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

reg f_past_valid, fpv2, fpv3, fpv4;
initial begin
    f_past_valid = 1'b0; fpv2 = 1'b0;
    fpv3 = 1'b0;         fpv4 = 1'b0;
end
always @(posedge clk) begin
    f_past_valid <= 1'b1;
    fpv2 <= f_past_valid;
    fpv3 <= fpv2;
    fpv4 <= fpv3;
end

// Reset must be asserted at step 0 to initialise DUT registers
always @(*) begin
    if (!f_past_valid) assume(!rst_n);
end

// For the latency assertions specifically, also assume rst_n stays high
// after the initial reset so the pipeline operates without interruption.
// Expressed as: once rst_n goes high it never goes low again.
// This is encoded as a past-value constraint inside a clocked block.
always @(posedge clk) begin
    if (f_past_valid && $past(rst_n)) assume(rst_n);
end

// 1. Reset: outputs deasserted
always @(posedge clk) begin
    if (!rst_n) begin assert(!out_valid); assert(!out_bypass); end
end

// 2. Latency: out_valid arrives exactly 3 cycles after in_valid
always @(posedge clk) begin
    if (fpv4) assert(out_valid == $past(in_valid, 3));
end

// 3. Bypass propagates with same 3-cycle latency
always @(posedge clk) begin
    if (fpv4) assert(out_bypass == $past(in_bypass, 3));
end

// 4. out_valid and out_bypass never simultaneously asserted
always @(posedge clk) begin
    if (rst_n) assert(!(out_valid && out_bypass));
end

always @(posedge clk) begin if (rst_n) cover(out_valid && hash_out != 32'd0); end
always @(posedge clk) begin if (fpv4)  cover(out_valid && $past(out_valid));  end

endmodule