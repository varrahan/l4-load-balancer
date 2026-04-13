// =============================================================================
// toeplitz_core.v
// Toeplitz RSS Hash Engine
// =============================================================================
// Microsoft RSS Toeplitz hashing - 40-byte reference key.
// Input: 96-bit tuple {src_ip, dst_ip, src_port, dst_port}
// Pipeline: 4 registered stages (input latch + 2 XOR stages + output combine)
// Initiation Interval: 1
// Verilog-2001 compatible - uses genvar for constant part-selects.
// =============================================================================

`timescale 1ns / 1ps

module toeplitz_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] src_ip,
    input  wire [31:0] dst_ip,
    input  wire [15:0] src_port,
    input  wire [15:0] dst_port,
    input  wire        in_valid,
    input  wire        in_bypass,
    output reg  [31:0] hash_out,
    output reg         out_valid,
    output reg         out_bypass
);

// ---------------------------------------------------------------------------
// RSS key - 40 bytes = 320 bits MSB-first
// ---------------------------------------------------------------------------
localparam [159:0] KEY_HI = 160'h6D5A56DA255B0EC24167253D43A38FB0D0CA2BCB;
localparam [159:0] KEY_LO = 160'hAE7B30B477CB2DA38030F20C6A42B73BBEAC01FA;
wire [319:0] K = {KEY_HI, KEY_LO};

// Pre-compute 96 constant 32-bit key windows at elaboration time
wire [31:0] kw [0:95];
genvar gi;
generate
    for (gi = 0; gi < 96; gi = gi + 1) begin : GEN_KW
        assign kw[gi] = K[319 - gi -: 32];
    end
endgenerate

// ---------------------------------------------------------------------------
// Stage 0: input registration
// ---------------------------------------------------------------------------
reg [31:0] r0_src_ip, r0_dst_ip;
reg [15:0] r0_sport,  r0_dport;
reg        r0_valid,  r0_bypass;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r0_src_ip <= 0; 
        r0_dst_ip <= 0;
        r0_sport  <= 0;
        r0_dport  <= 0;
        r0_valid  <= 0; 
        r0_bypass <= 0;
    end else begin
        r0_src_ip <= src_ip;   
        r0_dst_ip <= dst_ip;
        r0_sport  <= src_port; 
        r0_dport  <= dst_port;
        r0_valid  <= in_valid; 
        r0_bypass <= in_bypass;
    end
end

// ---------------------------------------------------------------------------
// Stage 1: XOR contribution of src_ip (bits 0-31) and dst_ip (bits 32-63)
// ---------------------------------------------------------------------------
reg [31:0] s1_ip;
reg        s1_valid, s1_bypass;
reg [15:0] s1_sport, s1_dport;

integer i;
reg [31:0] ip_acc;
always @(*) begin
    ip_acc = 32'd0;
    for (i = 0; i < 32; i = i + 1) begin
        if (r0_src_ip[31-i]) 
            ip_acc = ip_acc ^ kw[i];
        if (r0_dst_ip[31-i]) 
            ip_acc = ip_acc ^ kw[32+i];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_ip <= 0; 
        s1_valid <= 0; 
        s1_bypass <= 0;
        s1_sport <= 0; 
        s1_dport <= 0;
    end else begin
        s1_ip    <= ip_acc;
        s1_valid <= r0_valid; 
        s1_bypass <= r0_bypass;
        s1_sport <= r0_sport; 
        s1_dport  <= r0_dport;
    end
end

// ---------------------------------------------------------------------------
// Stage 2: XOR contribution of src_port (bits 64-79), dst_port (bits 80-95)
// ---------------------------------------------------------------------------
reg [31:0] s2_ports, s2_ip;
reg        s2_valid, s2_bypass;

reg [31:0] p_acc;
always @(*) begin
    p_acc = 32'd0;
    for (i = 0; i < 16; i = i + 1) begin
        if (s1_sport[15-i]) 
            p_acc = p_acc ^ kw[64+i];
        if (s1_dport[15-i]) 
            p_acc = p_acc ^ kw[80+i];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s2_ports <= 0; 
        s2_ip <= 0;
        s2_valid <= 0; 
        s2_bypass <= 0;
    end else begin
        s2_ports  <= p_acc;
        s2_ip     <= s1_ip;
        s2_valid  <= s1_valid; 
        s2_bypass <= s1_bypass;
    end
end

// ---------------------------------------------------------------------------
// Stage 3: combine and register output
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hash_out <= 0; 
        out_valid <= 0; 
        out_bypass <= 0;
    end else begin
        hash_out   <= s2_ip ^ s2_ports;
        out_valid  <= s2_valid;
        out_bypass <= s2_bypass;
    end
end

endmodule