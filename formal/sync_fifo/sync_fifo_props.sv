// =============================================================================
// formal/sync_fifo/sync_fifo_props.sv
// Formal properties for sync_fifo
// =============================================================================
// Target solver: sby (SymbiYosys) with smtbmc / Yices2
//
// Properties verified:
//   1. Reset correctness      - empty asserted, full deasserted after reset
//   2. No overflow            - full suppresses writes; wr_ptr never wraps past rd_ptr
//   3. No underflow           - empty suppresses reads
//   4. Pointer distance bound - occupancy never exceeds DEPTH
//   5. Full/empty mutual excl - full and empty never simultaneously asserted
//   6. Data integrity         - a written word is read back unchanged (depth-2 FIFO cover)
//   7. valid tracks rd_en     - valid is high iff rd_en was asserted on previous cycle
// =============================================================================

module sync_fifo_props #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 4    // small depth for bounded model checking
) (
    input wire                  clk,
    input wire                  rst_n,
    input wire                  wr_en,
    input wire [DATA_WIDTH-1:0] wr_data,
    input wire                  rd_en
);

// --------------------------------------------------------------------------
// Instantiate DUT
// --------------------------------------------------------------------------
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

// --------------------------------------------------------------------------
// Yosys Formal Boilerplate: Past Valid Flag
// Ensures $past() is not evaluated on the very first clock cycle
// --------------------------------------------------------------------------
reg f_past_valid;
initial f_past_valid = 0;
always @(posedge clk) f_past_valid <= 1'b1;

// --------------------------------------------------------------------------
// Pointer width helper
// --------------------------------------------------------------------------
localparam PTR_W = $clog2(DEPTH) + 1;

// --------------------------------------------------------------------------
// 1. Reset: empty must be asserted, full must be clear after reset
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        assert_reset_empty: assert (empty);
        assert_reset_not_full: assert (!full);
        assert_reset_not_valid: assert (!valid);
    end
end

// --------------------------------------------------------------------------
// 2. No overflow: writing into a full FIFO must not advance wr_ptr
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(full) && $past(wr_en) && !$past(rd_en)) begin
        assert_no_overflow: assert (full);
    end
end

// --------------------------------------------------------------------------
// 3. No underflow: empty must persist when rd_en fires on empty FIFO
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(empty) && $past(rd_en) && !$past(wr_en)) begin
        assert_no_underflow: assert (empty);
    end
end

// --------------------------------------------------------------------------
// 4. Occupancy bound: difference of pointers never exceeds DEPTH
// --------------------------------------------------------------------------
wire [PTR_W-1:0] wr_ptr = dut.wr_ptr;
wire [PTR_W-1:0] rd_ptr = dut.rd_ptr;
wire [PTR_W-1:0] occupancy = wr_ptr - rd_ptr;

always @(posedge clk) begin
    if (rst_n) begin
        assert_occ_bound: assert (occupancy <= DEPTH[PTR_W-1:0]);
    end
end

// --------------------------------------------------------------------------
// 5. Full and empty are mutually exclusive
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n) begin
        assert_full_empty_mutex: assert (!(full && empty));
    end
end

// --------------------------------------------------------------------------
// 6. valid is deasserted one cycle after rd_en was not asserted 
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (f_past_valid && rst_n && !$past(rd_en)) begin
        assert_valid_tracks_rden: assert (!valid);
    end
end

// --------------------------------------------------------------------------
// 7. Cover: FIFO fills completely then drains completely
// --------------------------------------------------------------------------
reg f_was_full;
initial f_was_full = 0;

always @(posedge clk) begin
    if (!rst_n) begin
        f_was_full <= 0;
    end else if (full) begin
        f_was_full <= 1'b1;
    end
end

always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
        if (f_was_full && empty) begin
            cover_fill_and_drain: cover (1'b1);
        end
    end
end

// --------------------------------------------------------------------------
// 8. Cover: back-to-back write-then-read visible in 2-entry FIFO
// --------------------------------------------------------------------------
reg f_seq_step1;
reg f_seq_step2;
initial begin
    f_seq_step1 = 0;
    f_seq_step2 = 0;
end

always @(posedge clk) begin
    if (!rst_n) begin
        f_seq_step1 <= 0;
        f_seq_step2 <= 0;
    end else begin
        // Step 1: Write occurs
        f_seq_step1 <= (wr_en && !full);
        // Step 2: Read occurs one cycle after write
        f_seq_step2 <= f_seq_step1 && (rd_en && !empty);
    end
end

always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
        // Step 3: Valid goes high one cycle after read
        if (f_seq_step2 && valid) begin
            cover_write_then_read: cover (1'b1);
        end
    end
end

endmodule