// =============================================================================
// formal/sync_fifo/sync_fifo_props.sv
// Formal properties for sync_fifo - Yosys/SymbiYosys compatible
// No hierarchical references - properties expressed via DUT output ports only
// =============================================================================

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

sync_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH     (DEPTH)
) dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (wr_en),
    .wr_data(wr_data),
    .rd_en  (rd_en),
    .rd_data(rd_data),
    .valid  (valid),
    .empty  (empty),
    .full   (full)
);

// 1. Reset: empty asserted, full and valid deasserted
always @(posedge clk) begin
    if (!rst_n) begin
        assert(empty);
        assert(!full);
        assert(!valid);
    end
end

// 2. No overflow: write into full FIFO leaves it full
always @(posedge clk) begin
    if (rst_n && $past(full) && $past(wr_en) && !$past(rd_en))
        assert(full);
end

// 3. No underflow: read from empty FIFO leaves it empty
always @(posedge clk) begin
    if (rst_n && $past(empty) && $past(rd_en) && !$past(wr_en))
        assert(empty);
end

// 4. full and empty are mutually exclusive
always @(posedge clk) begin
    if (rst_n)
        assert(!(full && empty));
end

// 5. valid only asserted the cycle after rd_en fired
always @(posedge clk) begin
    if (rst_n && !$past(rd_en))
        assert(!valid);
end

// 6. Once full, stays full unless a read occurs
always @(posedge clk) begin
    if (rst_n && $past(full) && !$past(rd_en))
        assert(full);
end

// 7. Once empty, stays empty unless a write occurs
always @(posedge clk) begin
    if (rst_n && $past(empty) && !$past(wr_en))
        assert(empty);
end

// Cover: full state reachable
always @(posedge clk) begin
    if (rst_n) cover(full);
end

// Cover: valid output reachable
always @(posedge clk) begin
    if (rst_n) cover(valid);
end

// Cover: full then empty (fill and drain)
always @(posedge clk) begin
    if (rst_n) cover($past(full) && empty);
end

endmodule