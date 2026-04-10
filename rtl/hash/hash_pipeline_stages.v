// =============================================================================
// hash_pipeline_stages.v
// Hash Pipeline Stage - FIB Index Derivation
// =============================================================================
// Takes the 32-bit Toeplitz hash and derives the FIB lookup index.
// For 8 servers: fib_index = hash[9:0] (mod 1024 → maps to server via FIB).
// Adds one pipeline register stage to ease timing.
// =============================================================================

`timescale 1ns / 1ps

module hash_pipeline_stages #(
    parameter FIB_INDEX_BITS = 10
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [31:0]               hash_in,
    input  wire                      in_valid,
    input  wire                      in_bypass,
    output reg  [FIB_INDEX_BITS-1:0] fib_index,
    output reg                       out_valid,
    output reg                       out_bypass
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fib_index  <= {FIB_INDEX_BITS{1'b0}};
        out_valid  <= 1'b0;
        out_bypass <= 1'b0;
    end else begin
        fib_index  <= hash_in[FIB_INDEX_BITS-1:0];
        out_valid  <= in_valid;
        out_bypass <= in_bypass;
    end
end

endmodule