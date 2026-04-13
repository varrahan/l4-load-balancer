// =============================================================================
// l4_load_balancer_top.v
// FPGA Smart Layer-4 Load Balancer - Top-Level Integrator
// Author: Varrahan Uthayan
// =============================================================================
// Fully pipelined, synthesizable Verilog targeting Xilinx UltraScale+ / Zynq 7000.
// Initiation Interval = 1 (one packet per clock cycle through header pipeline).
// Pipeline latency ≈ 12 cycles (tuple extraction → routing decision).
// =============================================================================

`timescale 1ns / 1ps

module l4_load_balancer_top #(
    // AXI-Stream bus width in bits. Set to 256 for 100 Gbps operation.
    parameter DATA_WIDTH     = 64,
    // Payload FIFO depth in 8-byte words (covers max Jumbo frame = 9000 B / 8 = 1125 words)
    parameter PAYLOAD_FIFO_D = 1024,
    // Metadata FIFO depth (must accommodate maximum pipeline latency + slack)
    parameter META_FIFO_D    = 32,
    // FIB address bits: 10 → 1024 entries
    parameter FIB_INDEX_BITS = 10,
    // Path to $readmemh FIB init file (leave "" for simulation default)
    parameter FIB_INIT_FILE  = ""
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // -------------------------------------------------------------------
    // Ingress AXI-Stream Slave (from Ethernet MAC)
    // -------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    input  wire                  s_axis_tlast,
    input  wire [DATA_WIDTH/8-1:0] s_axis_tkeep,
    output wire                  s_axis_tready,

    // -------------------------------------------------------------------
    // Egress AXI-Stream Master (to Ethernet MAC)
    // -------------------------------------------------------------------
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    output wire                  m_axis_tlast,
    output wire [DATA_WIDTH/8-1:0] m_axis_tkeep,
    input  wire                  m_axis_tready
);

// ---------------------------------------------------------------------------
// Internal wires
// ---------------------------------------------------------------------------

// Ingress → Payload FIFO
wire [DATA_WIDTH-1:0] ingress_tdata;
wire                  ingress_tvalid;
wire                  ingress_tlast;
wire [DATA_WIDTH/8-1:0] ingress_tkeep;
wire                  ingress_tready;

// Tuple extractor output
wire [31:0] tuple_src_ip;
wire [31:0] tuple_dst_ip;
wire [15:0] tuple_src_port;
wire [15:0] tuple_dst_port;
wire [7:0]  tuple_protocol;
wire        tuple_valid;
wire        tuple_bypass;   // ARP/ICMP: bypass hash and use passthrough path

// Toeplitz hash output
wire [31:0] hash_result;
wire        hash_valid;
wire        hash_bypass;

// FIB lookup output
wire [47:0] fib_dst_mac;
wire [31:0] fib_dst_ip;
wire [2:0]  fib_server_id;
wire        fib_valid;
wire        fib_bypass;

// Token bucket / rate limiter
wire        tb_permit;
wire        tb_valid;
wire        tb_bypass;
wire [47:0] tb_dst_mac;
wire [31:0] tb_dst_ip;

// Meta FIFO → Header modifier
wire [47:0] meta_dst_mac;
wire [31:0] meta_dst_ip;
wire        meta_valid;
wire        meta_bypass;
wire        meta_ready;

// Payload FIFO → Header modifier
wire [DATA_WIDTH-1:0] payload_tdata;
wire                  payload_tvalid;
wire                  payload_tlast;
wire [DATA_WIDTH/8-1:0] payload_tkeep;
wire                  payload_tready;

// Header modifier → Checksum updater
wire [DATA_WIDTH-1:0] mod_tdata;
wire                  mod_tvalid;
wire                  mod_tlast;
wire [DATA_WIDTH/8-1:0] mod_tkeep;
wire                  mod_tready;

// ---------------------------------------------------------------------------
// Stage 0 - AXI-Stream Ingress (skid buffer / flow control)
// ---------------------------------------------------------------------------
axi_stream_ingress #(
    .DATA_WIDTH(DATA_WIDTH)
) u_ingress (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_tdata      (s_axis_tdata),
    .s_tvalid     (s_axis_tvalid),
    .s_tlast      (s_axis_tlast),
    .s_tkeep      (s_axis_tkeep),
    .s_tready     (s_axis_tready),
    .m_tdata      (ingress_tdata),
    .m_tvalid     (ingress_tvalid),
    .m_tlast      (ingress_tlast),
    .m_tkeep      (ingress_tkeep),
    .m_tready     (ingress_tready)
);

// ---------------------------------------------------------------------------
// Payload sync FIFO - decouples header pipeline from packet data path
// ---------------------------------------------------------------------------
sync_fifo #(
    .DATA_WIDTH(DATA_WIDTH + DATA_WIDTH/8 + 1), // tdata + tkeep + tlast
    .DEPTH      (PAYLOAD_FIFO_D)
) u_payload_fifo (
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (ingress_tvalid & ingress_tready),
    .wr_data({ingress_tdata, ingress_tkeep, ingress_tlast}),
    .rd_en  (payload_tready & payload_tvalid),
    .rd_data({payload_tdata, payload_tkeep, payload_tlast}),
    .empty  (),
    .full   (),
    .valid  (payload_tvalid)
);

assign ingress_tready = 1'b1; // payload FIFO absorbs backpressure

// ---------------------------------------------------------------------------
// Stage 1 - Tuple Extractor (parses Ethernet/IPv4/TCP/UDP headers)
// ---------------------------------------------------------------------------
tuple_extractor #(
    .DATA_WIDTH(DATA_WIDTH)
) u_tuple_extractor (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_tdata      (ingress_tdata),
    .s_tvalid     (ingress_tvalid),
    .s_tlast      (ingress_tlast),
    .s_tkeep      (ingress_tkeep),
    .src_ip       (tuple_src_ip),
    .dst_ip       (tuple_dst_ip),
    .src_port     (tuple_src_port),
    .dst_port     (tuple_dst_port),
    .protocol     (tuple_protocol),
    .tuple_valid  (tuple_valid),
    .bypass       (tuple_bypass)
);

// ---------------------------------------------------------------------------
// Stages 2–4 - Toeplitz RSS Hash Engine
// ---------------------------------------------------------------------------
toeplitz_core u_toeplitz (
    .clk        (clk),
    .rst_n      (rst_n),
    .src_ip     (tuple_src_ip),
    .dst_ip     (tuple_dst_ip),
    .src_port   (tuple_src_port),
    .dst_port   (tuple_dst_port),
    .in_valid   (tuple_valid),
    .in_bypass  (tuple_bypass),
    .hash_out   (hash_result),
    .out_valid  (hash_valid),
    .out_bypass (hash_bypass)
);

// ---------------------------------------------------------------------------
// Stage 5 - FIB BRAM Controller (hash → server selection)
// ---------------------------------------------------------------------------
fib_bram_controller #(
    .FIB_INDEX_BITS(FIB_INDEX_BITS),
    .FIB_INIT_FILE (FIB_INIT_FILE)
) u_fib (
    .clk        (clk),
    .rst_n      (rst_n),
    .hash_in    (hash_result),
    .in_valid   (hash_valid),
    .in_bypass  (hash_bypass),
    .dst_mac    (fib_dst_mac),
    .dst_ip     (fib_dst_ip),
    .server_id  (fib_server_id),
    .out_valid  (fib_valid),
    .out_bypass (fib_bypass)
);

// ---------------------------------------------------------------------------
// Stage 6 - Token Bucket Rate Limiter (elephant flow detection)
// ---------------------------------------------------------------------------
token_bucket_limiter u_token_bucket (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_valid   (fib_valid),
    .in_bypass  (fib_bypass),
    .in_dst_mac (fib_dst_mac),
    .in_dst_ip  (fib_dst_ip),
    .out_valid  (tb_valid),
    .out_bypass (tb_bypass),
    .out_permit (tb_permit),
    .out_dst_mac(tb_dst_mac),
    .out_dst_ip (tb_dst_ip)
);

// ---------------------------------------------------------------------------
// Meta FIFO - holds routing decisions until payload data catches up
// ---------------------------------------------------------------------------
meta_fifo #(
    .DEPTH(META_FIFO_D)
) u_meta_fifo (
    .clk        (clk),
    .rst_n      (rst_n),
    .wr_en      (tb_valid & tb_permit),
    .wr_dst_mac (tb_dst_mac),
    .wr_dst_ip  (tb_dst_ip),
    .wr_bypass  (tb_bypass),
    .rd_en      (meta_ready),
    .rd_dst_mac (meta_dst_mac),
    .rd_dst_ip  (meta_dst_ip),
    .rd_bypass  (meta_bypass),
    .rd_valid   (meta_valid)
);

// ---------------------------------------------------------------------------
// Stage 7 - Header Modifier (DNAT: rewrite DST MAC + DST IP)
// ---------------------------------------------------------------------------
header_modifier #(
    .DATA_WIDTH(DATA_WIDTH)
) u_header_modifier (
    .clk        (clk),
    .rst_n      (rst_n),
    // Payload data path
    .s_tdata    (payload_tdata),
    .s_tvalid   (payload_tvalid),
    .s_tlast    (payload_tlast),
    .s_tkeep    (payload_tkeep),
    .s_tready   (payload_tready),
    // Routing metadata
    .meta_valid (meta_valid),
    .meta_bypass(meta_bypass),
    .meta_dst_mac(meta_dst_mac),
    .meta_dst_ip(meta_dst_ip),
    .meta_ready (meta_ready),
    // Modified output
    .m_tdata    (mod_tdata),
    .m_tvalid   (mod_tvalid),
    .m_tlast    (mod_tlast),
    .m_tkeep    (mod_tkeep),
    .m_tready   (mod_tready)
);

// ---------------------------------------------------------------------------
// Stage 8 - Checksum Updater (RFC 1624 incremental delta)
// ---------------------------------------------------------------------------
checksum_updater #(
    .DATA_WIDTH(DATA_WIDTH)
) u_checksum (
    .clk      (clk),
    .rst_n    (rst_n),
    .s_tdata  (mod_tdata),
    .s_tvalid (mod_tvalid),
    .s_tlast  (mod_tlast),
    .s_tkeep  (mod_tkeep),
    .s_tready (mod_tready),
    .m_tdata  (m_axis_tdata),
    .m_tvalid (m_axis_tvalid),
    .m_tlast  (m_axis_tlast),
    .m_tkeep  (m_axis_tkeep),
    .m_tready (m_axis_tready)
);

endmodule