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

wire [FIB_INDEX_BITS-1:0] fib_addr = hash_in[FIB_INDEX_BITS-1:0];

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
    else               assume(rst_n);
end

always @(*) assume(!(in_valid && in_bypass));

// 1. Reset: out_valid and out_bypass deasserted
always @(posedge clk) begin
    if (!rst_n) begin
        assert(!out_valid);
        assert(!out_bypass);
    end
end

// 2. BRAM address is always a valid FIB_INDEX_BITS-wide value.
wire [FIB_INDEX_BITS:0] fib_addr_wide = {1'b0, fib_addr};
always @(posedge clk) begin
    if (rst_n) assert(fib_addr_wide[FIB_INDEX_BITS] == 1'b0);
end

always @(posedge clk) begin if (rst_n) cover(out_valid); end

endmodule