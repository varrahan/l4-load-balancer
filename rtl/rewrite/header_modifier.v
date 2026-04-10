// =============================================================================
// header_modifier.v
// Header Modifier - DNAT: Destination MAC + IP Rewrite
// =============================================================================
// Rewrites the Ethernet DST MAC (bytes 0-5) and IPv4 DST IP (bytes 30-33)
// of the packet payload as it streams through.
//
// Beat assignments (DATA_WIDTH=64, 8 bytes/beat):
//   Beat 0 (bytes 0-7):  DST MAC[47:0] + SRC MAC[15:8]  ← rewrite DST MAC
//   Beat 3 (bytes 24-31): SRC IP + DST IP[31:16]
//   Beat 4 (bytes 32-39): DST IP[15:0] + SRC PORT + DST PORT ← rewrite DST IP lo
//
// Since the meta FIFO provides {dst_mac, dst_ip, bypass} registered ahead
// of time, we can rewrite combinatorially on the correct beat.
//
// For bypass packets (ARP/ICMP): data passes through unmodified.
// =============================================================================

`timescale 1ns / 1ps

module header_modifier #(
    parameter DATA_WIDTH = 64
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Payload AXI-Stream input (from payload sync FIFO)
    input  wire [DATA_WIDTH-1:0]   s_tdata,
    input  wire                    s_tvalid,
    input  wire                    s_tlast,
    input  wire [DATA_WIDTH/8-1:0] s_tkeep,
    output wire                    s_tready,

    // Routing metadata (from meta FIFO)
    input  wire                    meta_valid,
    input  wire                    meta_bypass,
    input  wire [47:0]             meta_dst_mac,
    input  wire [31:0]             meta_dst_ip,
    output reg                     meta_ready,

    // Modified output
    output reg  [DATA_WIDTH-1:0]   m_tdata,
    output reg                     m_tvalid,
    output reg                     m_tlast,
    output reg  [DATA_WIDTH/8-1:0] m_tkeep,
    input  wire                    m_tready
);

// ---------------------------------------------------------------------------
// Beat counter - reset on tlast
// ---------------------------------------------------------------------------
reg [2:0]  beat_cnt;
reg        in_packet;  // high while processing a packet

// Latch meta at packet start
reg [47:0] lat_dst_mac;
reg [31:0] lat_dst_ip;
reg        lat_bypass;
reg        meta_latched;

// Saved upper DST IP for beat 3→4 carry
reg [15:0] new_dst_ip_hi;

// s_tready: stall if we don't have meta yet at the start of a packet
assign s_tready = (!s_tvalid) ? 1'b1 :
                  (!in_packet && !meta_valid) ? 1'b0 :
                  m_tready;

wire beat_fire = s_tvalid && s_tready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        beat_cnt    <= 3'd0;
        in_packet   <= 1'b0;
        meta_ready  <= 1'b0;
        meta_latched<= 1'b0;
        lat_dst_mac <= 48'd0;
        lat_dst_ip  <= 32'd0;
        lat_bypass  <= 1'b0;
        new_dst_ip_hi <= 16'd0;
        m_tvalid    <= 1'b0;
        m_tdata     <= {DATA_WIDTH{1'b0}};
        m_tlast     <= 1'b0;
        m_tkeep     <= {DATA_WIDTH/8{1'b0}};
    end else begin
        meta_ready <= 1'b0;
        m_tvalid   <= 1'b0;

        if (beat_fire) begin
            // Latch meta on first beat of each packet
            if (!in_packet) begin
                in_packet    <= 1'b1;
                lat_dst_mac  <= meta_dst_mac;
                lat_dst_ip   <= meta_dst_ip;
                lat_bypass   <= meta_bypass;
                meta_ready   <= 1'b1;  // consume meta FIFO entry
                beat_cnt     <= 3'd1;
            end else begin
                if (beat_cnt < 3'd7)
                    beat_cnt <= beat_cnt + 3'd1;
            end

            // Modify header or pass through
            m_tvalid <= 1'b1;
            m_tlast  <= s_tlast;
            m_tkeep  <= s_tkeep;

            if (lat_bypass) begin
                // Bypass: forward unmodified
                m_tdata <= s_tdata;
            end else begin
                case (in_packet ? beat_cnt : 3'd0)
                    // Beat 0: rewrite DST MAC (bytes 0-5), keep bytes 6-7
                    3'd0: m_tdata <= {lat_dst_mac, s_tdata[15:0]};

                    // Beat 3: rewrite DST IP [31:16] (bytes 28-29)
                    // bytes24-27 = src_ip (keep), bytes28-29 = dst_ip[31:16]
                    3'd3: begin
                        new_dst_ip_hi <= lat_dst_ip[31:16];
                        m_tdata <= {s_tdata[63:16], lat_dst_ip[31:16]};
                    end

                    // Beat 4: rewrite DST IP [15:0] (bytes 30-31)
                    3'd4: m_tdata <= {lat_dst_ip[15:0], s_tdata[47:0]};

                    default: m_tdata <= s_tdata;
                endcase
            end

            if (s_tlast) begin
                in_packet <= 1'b0;
                beat_cnt  <= 3'd0;
            end
        end
    end
end

endmodule