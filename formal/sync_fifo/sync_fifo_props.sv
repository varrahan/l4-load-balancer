`default_nettype none
module sync_fifo_props #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 4
) (
    input wire                  clk,
    input wire                  rst_n,
    input wire                  wr_en,
    input wire [DATA_WIDTH-1:0] wr_data,
    input wire                  rd_en
);

wire [DATA_WIDTH-1:0] rd_data;
wire                  valid, empty, full;

sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wr_data(wr_data), .rd_en(rd_en),
    .rd_data(rd_data), .valid(valid), .empty(empty), .full(full)
);

// stable: registered flag - high only when rst_n was high last cycle too
reg stable;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) stable <= 1'b0;
    else        stable <= 1'b1;
end

// 1. Reset
always @(posedge clk) begin
    if (!rst_n) begin
        assert(empty);
        assert(!full);
        assert(!valid);
    end
end

// 2. No overflow
always @(posedge clk) begin
    if (stable && $past(full) && $past(wr_en) && !$past(rd_en))
        assert(full);
end

// 3. No underflow
always @(posedge clk) begin
    if (stable && $past(empty) && $past(rd_en) && !$past(wr_en))
        assert(empty);
end

// 4. Mutual exclusion
always @(posedge clk) begin
    if (rst_n) assert(!(full && empty));
end

// 5. valid only follows rd_en
always @(posedge clk) begin
    if (stable && !$past(rd_en)) assert(!valid);
end

// 6. full sticky without read
always @(posedge clk) begin
    if (stable && $past(full) && !$past(rd_en)) assert(full);
end

// 7. empty sticky without write
always @(posedge clk) begin
    if (stable && $past(empty) && !$past(wr_en)) assert(empty);
end

always @(posedge clk) begin
    if (rst_n) cover(full);
end
always @(posedge clk) begin
    if (rst_n) cover(valid);
end
always @(posedge clk) begin
    if (stable) cover($past(full) && empty);
end

endmodule