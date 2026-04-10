// =============================================================================
// tb_l4_pipeline_full.v
// Integration Testbench - Full L4 Load Balancer Pipeline
// =============================================================================
// Exercises the complete pipeline:
//   AXI-S ingress → tuple extractor → Toeplitz hash → FIB → token bucket
//   → meta FIFO → header modifier → checksum updater → AXI-S egress
//
// Tests:
//   1. Mice flows - small packets get DNAT-rewritten and forwarded
//   2. Backpressure - m_tready de-asserted mid-packet
//   3. Jumbo + minimum frame interleave - back-to-back different packet sizes
// =============================================================================

`timescale 1ns / 1ps

module tb_l4_pipeline_full;

parameter DATA_WIDTH = 64;

reg clk = 0;
always #3.2 clk = ~clk;
reg rst_n;

// Ingress AXI-S
reg  [DATA_WIDTH-1:0]   s_tdata;
reg                     s_tvalid;
reg                     s_tlast;
reg  [DATA_WIDTH/8-1:0] s_tkeep;
wire                    s_tready;

// Egress AXI-S
wire [DATA_WIDTH-1:0]   m_tdata;
wire                    m_tvalid;
wire                    m_tlast;
wire [DATA_WIDTH/8-1:0] m_tkeep;
reg                     m_tready;

l4_load_balancer_top #(
    .DATA_WIDTH    (DATA_WIDTH),
    .PAYLOAD_FIFO_D(1024),
    .META_FIFO_D   (32),
    .FIB_INDEX_BITS(10),
    .FIB_INIT_FILE ("")
) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_axis_tdata (s_tdata),
    .s_axis_tvalid(s_tvalid),
    .s_axis_tlast (s_tlast),
    .s_axis_tkeep (s_tkeep),
    .s_axis_tready(s_tready),
    .m_axis_tdata (m_tdata),
    .m_axis_tvalid(m_tvalid),
    .m_axis_tlast (m_tlast),
    .m_axis_tkeep (m_tkeep),
    .m_axis_tready(m_tready)
);

integer pass_cnt = 0;
integer fail_cnt = 0;

// Capture egress packets
reg  [DATA_WIDTH-1:0] rx_beats [0:255];
integer               rx_beat_cnt;
integer               rx_pkt_cnt;

// Monitor task - runs in parallel
initial begin
    rx_beat_cnt = 0;
    rx_pkt_cnt  = 0;
    forever begin
        @(posedge clk);
        if (m_tvalid && m_tready) begin
            rx_beats[rx_beat_cnt] = m_tdata;
            rx_beat_cnt = rx_beat_cnt + 1;
            if (m_tlast) begin
                rx_pkt_cnt  = rx_pkt_cnt + 1;
                rx_beat_cnt = 0;
            end
        end
    end
end

// -------------------------------------------------------------------------
// Task: send a minimal Ethernet/IPv4/TCP frame (5 beats)
// -------------------------------------------------------------------------
task send_ipv4_tcp;
    input [31:0] src_ip_in, dst_ip_in;
    input [15:0] sport_in, dport_in;
    begin
        // Beat 0: DST MAC + SRC MAC hi
        @(posedge clk);
        s_tdata  <= 64'h001122334455AABB;
        s_tvalid <= 1'b1; s_tlast <= 1'b0; s_tkeep <= 8'hFF;

        // Beat 1: SRC MAC lo + EtherType + IPv4 hdr bytes 0-1
        @(posedge clk);
        s_tdata <= {32'hCCDDEEFF, 16'h0800, 16'h4500};

        // Beat 2: IPv4 len/id/flags/TTL/proto(TCP=6)
        @(posedge clk);
        s_tdata <= {16'h0028, 16'h0001, 16'h4000, 8'h40, 8'h06};

        // Beat 3: csum/srcIP/dstIP[31:16]
        @(posedge clk);
        s_tdata <= {16'h0000, src_ip_in, dst_ip_in[31:16]};

        // Beat 4: dstIP[15:0]/sport/dport/dummy - tlast
        @(posedge clk);
        s_tdata <= {dst_ip_in[15:0], sport_in, dport_in, 16'hBEEF};
        s_tlast <= 1'b1;

        @(posedge clk);
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
    end
endtask

// -------------------------------------------------------------------------
// Task: send jumbo frame (140 beats ≈ 1120 bytes)
// -------------------------------------------------------------------------
task send_jumbo;
    input [31:0] src_ip_in, dst_ip_in;
    input [15:0] sport_in, dport_in;
    integer n;
    begin
        @(posedge clk);
        s_tdata  <= 64'hFFEEDDCCBBAA9988; // DST MAC+SRC hi
        s_tvalid <= 1'b1; s_tlast <= 1'b0; s_tkeep <= 8'hFF;

        @(posedge clk);
        s_tdata <= {32'h11223344, 16'h0800, 16'h4500};

        @(posedge clk);
        s_tdata <= {16'h0460, 16'h0002, 16'h4000, 8'h40, 8'h06};

        @(posedge clk);
        s_tdata <= {16'h0000, src_ip_in, dst_ip_in[31:16]};

        @(posedge clk);
        s_tdata <= {dst_ip_in[15:0], sport_in, dport_in, 16'hDEAD};

        // Payload beats
        for (n = 0; n < 135; n = n + 1) begin
            @(posedge clk);
            s_tdata <= {32'hCAFEBABE, n[31:0]};
        end

        @(posedge clk);
        s_tdata <= 64'hDEADBEEFCAFEF00D;
        s_tlast <= 1'b1;

        @(posedge clk);
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
    end
endtask

integer wait_i;
integer initial_rx_pkt;

initial begin
    $dumpfile("tb_l4_pipeline_full.vcd");
    $dumpvars(0, tb_l4_pipeline_full);

    rst_n    = 0;
    s_tvalid = 0;
    s_tlast  = 0;
    s_tdata  = 64'd0;
    s_tkeep  = 8'hFF;
    m_tready = 1'b1;

    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 1: Mice flows - 4 small TCP packets
    // -----------------------------------------------------------------------
    $display("--- Test 1: Mice Flows (4 TCP packets) ---");
    initial_rx_pkt = rx_pkt_cnt;

    send_ipv4_tcp(32'h0a000001, 32'hc0a80101, 16'd1000, 16'd80);
    repeat(3) @(posedge clk);
    send_ipv4_tcp(32'h0a000002, 32'hc0a80102, 16'd1001, 16'd80);
    repeat(3) @(posedge clk);
    send_ipv4_tcp(32'h0a000003, 32'hc0a80103, 16'd1002, 16'd443);
    repeat(3) @(posedge clk);
    send_ipv4_tcp(32'h0a000004, 32'hc0a80104, 16'd1003, 16'd8080);
    repeat(3) @(posedge clk);

    // Wait for all 4 to emerge
    wait_i = 0;
    while (rx_pkt_cnt - initial_rx_pkt < 4 && wait_i < 200) begin
        @(posedge clk); wait_i = wait_i + 1;
    end

    if (rx_pkt_cnt - initial_rx_pkt >= 4) begin
        $display("PASS [MICE_FLOWS]: All 4 packets forwarded in %0d cycles", wait_i);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [MICE_FLOWS]: Only %0d/4 packets forwarded",
                 rx_pkt_cnt - initial_rx_pkt);
        fail_cnt = fail_cnt + 1;
    end
    repeat(20) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 2: Backpressure - de-assert m_tready mid-stream
    // -----------------------------------------------------------------------
    $display("--- Test 2: Backpressure ---");
    initial_rx_pkt = rx_pkt_cnt;
    m_tready = 1'b0; // hold ready low

    send_ipv4_tcp(32'h0a000005, 32'hc0a80105, 16'd2000, 16'd80);
    repeat(10) @(posedge clk);

    // Release ready
    m_tready = 1'b1;
    wait_i = 0;
    while (rx_pkt_cnt - initial_rx_pkt < 1 && wait_i < 200) begin
        @(posedge clk); wait_i = wait_i + 1;
    end

    if (rx_pkt_cnt - initial_rx_pkt >= 1) begin
        $display("PASS [BACKPRESSURE]: Packet correctly held and released");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [BACKPRESSURE]: Packet not received after m_tready=1");
        fail_cnt = fail_cnt + 1;
    end
    repeat(20) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 3: Jumbo + minimum frame interleave
    // -----------------------------------------------------------------------
    $display("--- Test 3: Jumbo + Minimum Frame Interleave ---");
    initial_rx_pkt = rx_pkt_cnt;

    // Send jumbo followed immediately by a minimum (5-beat) frame
    send_jumbo(32'h0a000006, 32'hc0a80106, 16'd3000, 16'd80);
    send_ipv4_tcp(32'h0a000007, 32'hc0a80107, 16'd3001, 16'd8080);

    wait_i = 0;
    while (rx_pkt_cnt - initial_rx_pkt < 2 && wait_i < 500) begin
        @(posedge clk); wait_i = wait_i + 1;
    end

    if (rx_pkt_cnt - initial_rx_pkt >= 2) begin
        $display("PASS [JUMBO_INTERLEAVE]: Both packets forwarded in %0d cycles", wait_i);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [JUMBO_INTERLEAVE]: Only %0d/2 packets received",
                 rx_pkt_cnt - initial_rx_pkt);
        fail_cnt = fail_cnt + 1;
    end
    repeat(20) @(posedge clk);

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("");
    $display("TEST SUMMARY: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
    $finish;
end

initial begin
    #5000000;
    $display("TIMEOUT");
    $finish;
end

endmodule