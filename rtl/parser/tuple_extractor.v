// =============================================================================
// tuple_extractor.v
// Layer-4 Tuple Extractor - Verilog-2001
// =============================================================================
// Extracts {src_ip, dst_ip, src_port, dst_port, protocol} from an
// Ethernet/IPv4/TCP/UDP AXI-Stream packet (DATA_WIDTH=64, 8 bytes/beat).
//
// Beat layout (AXI-S convention: tdata[63:56] = wire byte 0):
//   Beat 0 (B0 -B7 ): DST_MAC[47:0]        = tdata[63:16]
//                     SRC_MAC[47:32]        = tdata[15:0]
//   Beat 1 (B8 -B15): SRC_MAC[31:0]        = tdata[63:32]
//                     EtherType             = tdata[31:16]
//                     IPv4 ver/ihl/dscp     = tdata[15:0]
//   Beat 2 (B16-B23): IPv4 len/id/flags/ttl = tdata[63:8]
//                     Protocol              = tdata[7:0]
//   Beat 3 (B24-B31): IPv4 csum             = tdata[63:48]
//                     SRC_IP[31:0]          = tdata[47:16]
//                     DST_IP[31:16]         = tdata[15:0]
//   Beat 4 (B32-B39): DST_IP[15:0]          = tdata[63:48]
//                     SRC_PORT              = tdata[47:32]
//                     DST_PORT              = tdata[31:16]
//                     (payload bytes        = tdata[15:0])
//
// ARP (EtherType 0x0806) and ICMP (proto 0x01): bypass=1, tuple_valid=0.
// tuple_valid and bypass are asserted for exactly ONE clock cycle.
// =============================================================================

`timescale 1ns / 1ps

module tuple_extractor #(
    parameter DATA_WIDTH = 64
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire [DATA_WIDTH-1:0]   s_tdata,
    input  wire                    s_tvalid,
    input  wire                    s_tlast,
    input  wire [DATA_WIDTH/8-1:0] s_tkeep,

    output reg  [31:0] src_ip,
    output reg  [31:0] dst_ip,
    output reg  [15:0] src_port,
    output reg  [15:0] dst_port,
    output reg  [7:0]  protocol,
    output reg         tuple_valid,
    output reg         bypass
);

// Beat counter increments each valid beat, resets on tlast
reg [2:0] beat_cnt;

// Sticky inter-beat state
reg [15:0] ethertype_r;
reg [7:0]  protocol_r;
reg [31:0] src_ip_r;
reg [15:0] dst_ip_hi_r;

wire beat_fire = s_tvalid; // no backpressure on ingress parser path

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        beat_cnt    <= 3'd0;
        ethertype_r <= 16'd0;
        protocol_r     <= 8'd0;
        src_ip_r    <= 32'd0;
        dst_ip_hi_r <= 16'd0;
        src_ip      <= 32'd0;
        dst_ip      <= 32'd0;
        src_port    <= 16'd0;
        dst_port    <= 16'd0;
        protocol    <= 8'd0;
        tuple_valid <= 1'b0;
        bypass      <= 1'b0;
    end else begin
        // Default: de-assert single-cycle outputs
        tuple_valid <= 1'b0;
        bypass      <= 1'b0;

        if (beat_fire) begin
            case (beat_cnt)
                // ----------------------------------------------------------
                // Beat 0: DST MAC + SRC MAC hi - nothing to extract yet
                // ----------------------------------------------------------
                3'd0: begin
                    // Nothing needed
                end

                // ----------------------------------------------------------
                // Beat 1: SRC MAC lo [63:32] | EtherType [31:16] | IPv4 hdr0 [15:0]
                // ----------------------------------------------------------
                3'd1: begin
                    ethertype_r <= s_tdata[31:16];
                end

                // ----------------------------------------------------------
                // Beat 2: IPv4 len/id/flags/ttl [63:8] | Protocol [7:0]
                // ----------------------------------------------------------
                3'd2: begin
                    protocol_r <= s_tdata[7:0];
                end

                // ----------------------------------------------------------
                // Beat 3: csum [63:48] | SRC_IP [47:16] | DST_IP hi [15:0]
                // ----------------------------------------------------------
                3'd3: begin
                    src_ip_r    <= s_tdata[47:16];
                    dst_ip_hi_r <= s_tdata[15:0];
                end

                // ----------------------------------------------------------
                // Beat 4: DST_IP lo [63:48] | SRC_PORT [47:32] | DST_PORT [31:16]
                // Output decision here.
                // ----------------------------------------------------------
                3'd4: begin
                    if (ethertype_r == 16'h0800) begin
                        // IPv4
                        case (protocol_r)
                            8'h06, 8'h11: begin   // TCP or UDP
                                src_ip      <= src_ip_r;
                                dst_ip      <= {dst_ip_hi_r, s_tdata[63:48]};
                                src_port    <= s_tdata[47:32];
                                dst_port    <= s_tdata[31:16];
                                protocol    <= protocol_r;
                                tuple_valid <= 1'b1;
                            end
                            default: begin         // ICMP, etc. - bypass
                                bypass <= 1'b1;
                            end
                        endcase
                    end else begin
                        // ARP, IPv6, etc. - bypass
                        bypass <= 1'b1;
                    end
                end

                // Additional payload beats - ignore
                default: begin end
            endcase

            // Advance beat counter; reset on last beat of packet
            if (s_tlast)
                beat_cnt <= 3'd0;
            else if (beat_cnt < 3'd7)
                beat_cnt <= beat_cnt + 3'd1;
        end
    end
end

endmodule