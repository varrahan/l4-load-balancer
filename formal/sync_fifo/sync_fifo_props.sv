// =============================================================================
// formal/sync_fifo/sync_fifo_props.sv
// Formal properties for sync_fifo - Yosys/SymbiYosys compatible
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

localparam PTR_W = $clog2(DEPTH) + 1;

wire [PTR_W-1:0] wr_ptr    = dut.wr_ptr;
wire [PTR_W-1:0] rd_ptr    = dut.rd_ptr;
wire [PTR_W-1:0] occupancy = wr_ptr - rd_ptr;

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
    if (rst_n && $past(full) && $past(wr_en) && !$past(rd_en))
        assert(full);
end

// 3. No underflow
always @(posedge clk) begin
    if (rst_n && $past(empty) && $past(rd_en) && !$past(wr_en))
        assert(empty);
end

// 4. Occupancy bound
always @(posedge clk) begin
    if (rst_n)
        assert(occupancy <= DEPTH[PTR_W-1:0]);
end

// 5. full and empty mutually exclusive
always @(posedge clk) begin
    if (rst_n)
        assert(!(full && empty));
end

// 6. valid only follows rd_en
always @(posedge clk) begin
    if (rst_n && !$past(rd_en))
        assert(!valid);
end

// 7. Cover: full state reachable
always @(posedge clk) begin
    if (rst_n) cover(full);
end

// 8. Cover: valid output reachable
always @(posedge clk) begin
    if (rst_n) cover(valid);
end

endmodule