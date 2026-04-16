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

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

// Force reset at step 0 so DUT starts from a known legal state
always @(*) begin
    if (!f_past_valid) assume(!rst_n);
end

// 1. Reset: empty asserted, full/valid deasserted
always @(posedge clk) begin
    if (!rst_n) begin
        assert(empty);
        assert(!full);
        assert(!valid);
    end
end

// 2. No overflow: write into full FIFO with no concurrent read and no reset
//    leaves it full
always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(rst_n) &&
        $past(full) && $past(wr_en) && !$past(rd_en))
        assert(full);
end

// 3. No underflow: read from empty FIFO with no concurrent write and no reset
//    leaves it empty
always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(rst_n) &&
        $past(empty) && $past(rd_en) && !$past(wr_en))
        assert(empty);
end

// 4. full and empty mutually exclusive
always @(posedge clk) begin
    if (rst_n) assert(!(full && empty));
end

// 5. valid only asserted the cycle after rd_en fired, when no reset intervenes
always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(rst_n) && !$past(rd_en))
        assert(!valid);
end

// 6. full sticky: stays full when no read and no reset
always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(rst_n) &&
        $past(full) && !$past(rd_en))
        assert(full);
end

// 7. empty sticky: stays empty when no write and no reset
always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(rst_n) &&
        $past(empty) && !$past(wr_en))
        assert(empty);
end

always @(posedge clk) begin if (rst_n) cover(full);  end
always @(posedge clk) begin if (rst_n) cover(valid); end
always @(posedge clk) begin
    if (f_past_valid && rst_n) cover($past(full) && empty);
end

endmodule