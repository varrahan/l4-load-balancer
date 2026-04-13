// =============================================================================
// fib_bram_controller.v
// Forwarding Information Base - BRAM Controller
// =============================================================================
// 1024-entry single-port BRAM FIB.
// Each entry: { dst_mac[47:0], dst_ip[31:0], server_id[2:0] } = 83 bits
// Stored as 96-bit words (padded) for BRAM word-alignment.
//
// Lookup pipeline:
//   Cycle 0: present hash-derived index to BRAM addr port
//   Cycle 1: BRAM output registered (1-cycle BRAM read latency)
//   Cycle 2: parse fields, assert out_valid
//
// FIB initialization: loaded from FIB_INIT_FILE via $readmemh if set.
// Default: round-robin across 8 servers (used in simulation).
// =============================================================================

`timescale 1ns / 1ps

module fib_bram_controller #(
    parameter FIB_INDEX_BITS = 10,
    parameter FIB_INIT_FILE  = ""
) (
    input  wire                      clk,
    input  wire                      rst_n,

    input  wire [31:0]               hash_in,
    input  wire                      in_valid,
    input  wire                      in_bypass,

    output reg  [47:0]               dst_mac,
    output reg  [31:0]               dst_ip,
    output reg  [2:0]                server_id,
    output reg                       out_valid,
    output reg                       out_bypass
);

localparam FIB_DEPTH = 1 << FIB_INDEX_BITS; // 1024
localparam FIB_WIDTH = 96;                  // 48+32+3 padded to 96

// ---------------------------------------------------------------------------
// BRAM storage
// ---------------------------------------------------------------------------
reg [FIB_WIDTH-1:0] fib_mem [0:FIB_DEPTH-1];

// Default FIB: server_id = index[2:0], dst_ip = 10.0.0.(server_id+1)
// dst_mac = 02:00:00:00:00:(server_id+1)
integer j;
initial begin
    if (FIB_INIT_FILE != "") begin
        $readmemh(FIB_INIT_FILE, fib_mem);
    end else begin
        for (j = 0; j < FIB_DEPTH; j = j + 1) begin
            // server_id = j % 8
            // dst_ip = 10.0.0.(server_id+1)
            // dst_mac = 02:00:00:00:00:(server_id+1)
            fib_mem[j] = {
                48'h020000000001 + (j[2:0]),   // dst_mac (approx for sim)
                8'd10, 8'd0, 8'd0, (8'd1 + j[2:0]),  // 10.0.0.(sid+1)
                j[2:0],                              // server_id
                13'd0                                // padding
            };
        end
    end
end

// ---------------------------------------------------------------------------
// Pipeline stage 0: register index and valid
// ---------------------------------------------------------------------------
wire [FIB_INDEX_BITS-1:0] fib_addr = hash_in[FIB_INDEX_BITS-1:0];

reg [FIB_INDEX_BITS-1:0] addr_r;
reg valid_r0, bypass_r0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        addr_r   <= {FIB_INDEX_BITS{1'b0}};
        valid_r0 <= 1'b0;
        bypass_r0<= 1'b0;
    end else begin
        addr_r   <= fib_addr;
        valid_r0 <= in_valid;
        bypass_r0<= in_bypass;
    end
end

// ---------------------------------------------------------------------------
// Pipeline stage 1: BRAM read (1-cycle latency)
// ---------------------------------------------------------------------------
reg [FIB_WIDTH-1:0] bram_out;
reg valid_r1, bypass_r1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bram_out  <= {FIB_WIDTH{1'b0}};
        valid_r1  <= 1'b0;
        bypass_r1 <= 1'b0;
    end else begin
        bram_out  <= fib_mem[addr_r];
        valid_r1  <= valid_r0;
        bypass_r1 <= bypass_r0;
    end
end

// ---------------------------------------------------------------------------
// Pipeline stage 2: parse fields and register output
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dst_mac   <= 48'd0;
        dst_ip    <= 32'd0;
        server_id <= 3'd0;
        out_valid <= 1'b0;
        out_bypass<= 1'b0;
    end else begin
        dst_mac   <= bram_out[95:48];
        dst_ip    <= bram_out[47:16];
        server_id <= bram_out[15:13];
        out_valid <= valid_r1;
        out_bypass<= bypass_r1;
    end
end

endmodule