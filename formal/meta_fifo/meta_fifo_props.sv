`default_nettype none
module meta_fifo_props #(parameter DEPTH = 4) (
    input wire clk, input wire rst_n,
    input wire wr_en, input wire [47:0] wr_dst_mac,
    input wire [31:0] wr_dst_ip, input wire wr_bypass,
    input wire rd_en
);

wire [47:0] rd_dst_mac;
wire [31:0] rd_dst_ip;
wire        rd_bypass, rd_valid;

meta_fifo #(.DEPTH(DEPTH)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wr_dst_mac(wr_dst_mac),
    .wr_dst_ip(wr_dst_ip), .wr_bypass(wr_bypass),
    .rd_en(rd_en), .rd_dst_mac(rd_dst_mac),
    .rd_dst_ip(rd_dst_ip), .rd_bypass(rd_bypass), .rd_valid(rd_valid)
);

reg [$clog2(DEPTH):0] occupancy;
wire do_wr = wr_en && (occupancy < DEPTH);
wire do_rd = rd_en && (occupancy > 0);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) occupancy <= 0;
    else        occupancy <= occupancy + do_wr - do_rd;
end
wire fifo_full  = (occupancy == DEPTH);
wire fifo_empty = (occupancy == 0);

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
end

wire fpv_stable = f_past_valid && rst_n && $past(rst_n);

always @(posedge clk) begin
    if (!rst_n) begin assert(fifo_empty); assert(!rd_valid); end
end
always @(posedge clk) begin
    if (fpv_stable && $past(fifo_full) && $past(wr_en) && !$past(rd_en))
        assert(fifo_full);
end
always @(posedge clk) begin
    if (fpv_stable && $past(fifo_empty) && $past(rd_en) && !$past(wr_en))
        assert(!rd_valid);
end
always @(posedge clk) begin
    if (rst_n) assert(occupancy <= DEPTH);
end
always @(posedge clk) begin
    if (rst_n) assert(!(fifo_full && fifo_empty));
end
always @(posedge clk) begin
    if (fpv_stable && !$past(rd_en)) assert(!rd_valid);
end
always @(posedge clk) begin if (rst_n) cover(fifo_full); end
always @(posedge clk) begin if (rst_n) cover(rd_valid);  end

endmodule
