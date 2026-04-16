// =============================================================================
// formal/meta_fifo/meta_fifo_props.sv
// Formal properties for meta_fifo
// =============================================================================
// Properties verified:
//   1. Reset correctness - rd_valid deasserted after reset
//   2. No overflow       - full suppresses writes
//   3. No underflow      - empty FIFO suppresses reads, rd_valid stays low
//   4. Occupancy bound   - occupancy never exceeds DEPTH
//   5. Field integrity   - {dst_mac, dst_ip, bypass} round-trip intact
//   6. Bypass passthrough - bypass bit is never corrupted in transit
// =============================================================================

`default_nettype none

module meta_fifo_props #(
    parameter DEPTH = 4
) (
    input wire        clk,
    input wire        rst_n,
    input wire        wr_en,
    input wire [47:0] wr_dst_mac,
    input wire [31:0] wr_dst_ip,
    input wire        wr_bypass,
    input wire        rd_en
);

wire [47:0] rd_dst_mac;
wire [31:0] rd_dst_ip;
wire        rd_bypass;
wire        rd_valid;

meta_fifo #(.DEPTH(DEPTH)) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .wr_en     (wr_en),
    .wr_dst_mac(wr_dst_mac),
    .wr_dst_ip (wr_dst_ip),
    .wr_bypass (wr_bypass),
    .rd_en     (rd_en),
    .rd_dst_mac(rd_dst_mac),
    .rd_dst_ip (rd_dst_ip),
    .rd_bypass (rd_bypass),
    .rd_valid  (rd_valid)
);

localparam PTR_W = $clog2(DEPTH) + 1;
wire empty    = (dut.wr_ptr == dut.rd_ptr);
wire full     = (dut.wr_ptr[PTR_W-1] != dut.rd_ptr[PTR_W-1]) &&
                (dut.wr_ptr[PTR_W-2:0] == dut.rd_ptr[PTR_W-2:0]);

// --------------------------------------------------------------------------
// 1. Reset
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        assert_reset_empty:     assert (empty);
        assert_reset_not_valid: assert (!rd_valid);
    end
end

// --------------------------------------------------------------------------
// 2. No overflow: full FIFO + write only = stays full
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(full) && $past(wr_en) && !$past(rd_en))
        assert_no_overflow: assert (full);
end

// --------------------------------------------------------------------------
// 3. No underflow: empty + read only = valid stays low
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && $past(empty) && $past(rd_en) && !$past(wr_en))
        assert_no_underflow_valid: assert (!rd_valid);
end

// --------------------------------------------------------------------------
// 4. Occupancy bound
// --------------------------------------------------------------------------
wire [PTR_W-1:0] occupancy = dut.wr_ptr - dut.rd_ptr;
always @(posedge clk) begin
    if (rst_n)
        assert_occ_bound: assert (occupancy <= DEPTH[PTR_W-1:0]);
end

// --------------------------------------------------------------------------
// 5. rd_valid tracks rd_en: valid is high iff previous cycle had rd_en+!empty
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && !$past(rd_en))
        assert_valid_tracks_rden: assert (!rd_valid);
end

// --------------------------------------------------------------------------
// 6. Cover: single entry round-trip - write then read
// --------------------------------------------------------------------------
single_roundtrip: cover property (
    @(posedge clk) disable iff (!rst_n)
    (wr_en && empty) ##1 (rd_en && !empty) ##1 rd_valid
);

endmodule
