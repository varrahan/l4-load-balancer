// =============================================================================
// sync_fifo.v
// Synchronous FIFO - Payload / Generic Buffer
// =============================================================================
// Standard synchronous FIFO with:
//   - Registered read data (1-cycle read latency)
//   - Full/empty flags
//   - valid signal tracking read data validity
//   - Depth must be a power of 2
// =============================================================================

`timescale 1ns / 1ps

module sync_fifo #(
    parameter DATA_WIDTH = 73,   // 64 + 8 + 1
    parameter DEPTH      = 1024  // must be power of 2
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,

    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output wire                  valid,
    output wire                  empty,
    output wire                  full
);

localparam PTR_WIDTH = $clog2(DEPTH);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
reg [PTR_WIDTH:0]    wr_ptr;
reg [PTR_WIDTH:0]    rd_ptr;

wire [PTR_WIDTH-1:0] wr_addr = wr_ptr[PTR_WIDTH-1:0];
wire [PTR_WIDTH-1:0] rd_addr = rd_ptr[PTR_WIDTH-1:0];

assign empty = (wr_ptr == rd_ptr);
assign full  = (wr_ptr[PTR_WIDTH] != rd_ptr[PTR_WIDTH]) && (wr_ptr[PTR_WIDTH-1:0] == rd_ptr[PTR_WIDTH-1:0]);

// Write
always @(posedge clk) begin
    if (wr_en && !full)
        mem[wr_addr] <= wr_data;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
        wr_ptr <= {(PTR_WIDTH+1){1'b0}};
    else if (wr_en && !full) 
        wr_ptr <= wr_ptr + 1'b1;
end

// Read - registered output (1-cycle latency)
reg rd_valid;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr   <= {(PTR_WIDTH+1){1'b0}};
        rd_valid <= 1'b0;
        rd_data  <= {DATA_WIDTH{1'b0}};
    end else begin
        if (rd_en && !empty) begin
            rd_data  <= mem[rd_addr];
            rd_ptr   <= rd_ptr + 1'b1;
            rd_valid <= 1'b1;
        end else begin
            rd_valid <= 1'b0;
        end
    end
end

assign valid = rd_valid;

endmodule