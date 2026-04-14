// =============================================================================
// meta_fifo.v
// Metadata FIFO - Routing Decision Buffer
// =============================================================================
// Stores {dst_mac[47:0], dst_ip[31:0], bypass[0]} routing decisions
// from the pipeline until the corresponding packet payload arrives
// at the header_modifier.
//
// Width: 48 + 32 + 1 = 81 bits
// Depth: configurable (default 32, must cover pipeline latency ≈ 12 cycles + slack)
// =============================================================================

`timescale 1ns / 1ps

module meta_fifo #(
    parameter DEPTH = 32
) (
    input  wire        clk,
    input  wire        rst_n,

    // Write port
    input  wire        wr_en,
    input  wire [47:0] wr_dst_mac,
    input  wire [31:0] wr_dst_ip,
    input  wire        wr_bypass,

    // Read port
    input  wire        rd_en,
    output wire [47:0] rd_dst_mac,
    output wire [31:0] rd_dst_ip,
    output wire        rd_bypass,
    output wire        rd_valid
);

localparam DATA_WIDTH = 81; // 48 + 32 + 1
localparam PTR_BITS   = $clog2(DEPTH);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
reg [PTR_BITS:0]     wr_ptr;
reg [PTR_BITS:0]     rd_ptr;

wire [PTR_BITS-1:0] wr_addr = wr_ptr[PTR_BITS-1:0];
wire [PTR_BITS-1:0] rd_addr = rd_ptr[PTR_BITS-1:0];
wire empty = (wr_ptr == rd_ptr);
wire full = (wr_ptr[PTR_BITS] != rd_ptr[PTR_BITS]) && (wr_ptr[PTR_BITS-1:0] == rd_ptr[PTR_BITS-1:0]);

// Write
always @(posedge clk) begin
    if (wr_en && !full)
        mem[wr_addr] <= {wr_dst_mac, wr_dst_ip, wr_bypass};
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
        wr_ptr <= {(PTR_BITS+1){1'b0}};
    else if (wr_en && !full) 
        wr_ptr <= wr_ptr + 1'b1;
end

// Read - registered
reg [DATA_WIDTH-1:0] rd_data;
reg                  rd_data_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr        <= {(PTR_BITS+1){1'b0}};
        rd_data       <= {DATA_WIDTH{1'b0}};
        rd_data_valid <= 1'b0;
    end else begin
        if (rd_en && !empty) begin
            rd_data       <= mem[rd_addr];
            rd_ptr        <= rd_ptr + 1'b1;
            rd_data_valid <= 1'b1;
        end else begin
            rd_data_valid <= 1'b0;
        end
    end
end

assign rd_dst_mac = rd_data[80:33];
assign rd_dst_ip  = rd_data[32:1];
assign rd_bypass  = rd_data[0];
assign rd_valid   = rd_data_valid;

endmodule