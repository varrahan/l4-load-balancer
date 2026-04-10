// =============================================================================
// tb_tuple_extractor.v
// Unit Testbench - tuple_extractor
// =============================================================================
// Tests:
//   Test 1: IPv4/TCP packet tuple extraction
//   Test 2: IPv4/UDP packet tuple extraction
//   Test 3: ARP bypass (EtherType 0x0806)
// Expected output: 3 PASS / 0 FAIL
// =============================================================================

`timescale 1ns / 1ps

module tb_tuple_extractor;

// Clock
reg clk = 0;
always #3.2 clk = ~clk; // 156.25 MHz
reg rst_n;

// DUT signals
reg  [63:0] s_tdata;
reg         s_tvalid;
reg         s_tlast;
reg  [7:0]  s_tkeep;

wire [31:0] src_ip;
wire [31:0] dst_ip;
wire [15:0] src_port;
wire [15:0] dst_port;
wire [7:0]  protocol;
wire        tuple_valid;
wire        bypass;

tuple_extractor #(.DATA_WIDTH(64)) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_tdata    (s_tdata),
    .s_tvalid   (s_tvalid),
    .s_tlast    (s_tlast),
    .s_tkeep    (s_tkeep),
    .src_ip     (src_ip),
    .dst_ip     (dst_ip),
    .src_port   (src_port),
    .dst_port   (dst_port),
    .protocol   (protocol),
    .tuple_valid(tuple_valid),
    .bypass     (bypass)
);

// Counters
integer pass_cnt = 0;
integer fail_cnt = 0;

// -------------------------------------------------------------------------
// Task: send_beat - drives one AXI-S beat
// -------------------------------------------------------------------------
task send_beat;
    input [63:0] data;
    input        last;
    input [7:0]  keep;
    begin
        @(posedge clk);
        s_tdata  <= data;
        s_tvalid <= 1'b1;
        s_tlast  <= last;
        s_tkeep  <= keep;
        @(posedge clk);
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
    end
endtask

// -------------------------------------------------------------------------
// Task: check_tuple
// -------------------------------------------------------------------------
task check_tuple;
    input [31:0] exp_src_ip;
    input [31:0] exp_dst_ip;
    input [15:0] exp_sport;
    input [15:0] exp_dport;
    input [7:0]  exp_proto;
    input [127:0] test_name; // 16 chars
    begin
        // Wait up to 20 cycles for tuple_valid
        repeat(20) begin
            @(posedge clk);
            if (tuple_valid) disable check_tuple;
        end
        $display("FAIL [%0s]: tuple_valid never asserted", test_name);
        fail_cnt = fail_cnt + 1;
    end
endtask

// -------------------------------------------------------------------------
// Build a minimal Ethernet/IPv4/TCP frame (5 beats × 8 bytes = 40 bytes)
// Layout:
//   B0-5:   DST MAC  = 00:11:22:33:44:55
//   B6-11:  SRC MAC  = AA:BB:CC:DD:EE:FF
//   B12-13: EtherType = 0x0800 (IPv4)
//   B14-15: IPv4 ver/ihl/dscp = 0x4500
//   B16-17: Total Length = 0x0028 (40 bytes)
//   B18-19: ID = 0x0001
//   B20-21: Flags/Frag = 0x4000
//   B22:    TTL = 64 (0x40)
//   B23:    Protocol = 6 (TCP) or 17 (UDP) or 1 (ICMP)
//   B24-25: Header Checksum = 0x0000 (not computed for tb)
//   B26-29: SRC IP
//   B30-33: DST IP
//   B34-35: SRC PORT
//   B36-37: DST PORT
//   B38-39: TCP/UDP len/seq (dummy)
// -------------------------------------------------------------------------
task send_ipv4_packet;
    input [31:0] src_ip_in;
    input [31:0] dst_ip_in;
    input [15:0] sport_in;
    input [15:0] dport_in;
    input [7:0]  proto_in;
    begin
        // Beat 0: bytes 0-7 = DST MAC[47:0] + SRC MAC[15:0]hi
        send_beat(64'h001122334455AABB, 1'b0, 8'hFF);
        // Beat 1: bytes 8-15 = SRC MAC[31:0] + EtherType + IPv4 byte0-1
        send_beat({32'hCCDDEEFF, 16'h0800, 16'h4500}, 1'b0, 8'hFF);
        // Beat 2: bytes 16-23 = IPv4 len/id/flags/ttl/proto
        send_beat({16'h0028, 16'h0001, 16'h4000, 8'h40, proto_in}, 1'b0, 8'hFF);
        // Beat 3: bytes 24-31 = csum/src_ip/dst_ip[31:16]
        send_beat({16'h0000, src_ip_in, dst_ip_in[31:16]}, 1'b0, 8'hFF);
        // Beat 4: bytes 32-39 = dst_ip[15:0]/sport/dport/dummy
        send_beat({dst_ip_in[15:0], sport_in, dport_in, 16'hBEEF}, 1'b1, 8'hFF);
    end
endtask

task send_arp_packet;
    begin
        // Beat 0: DST MAC broadcast + SRC MAC hi
        send_beat(64'hFFFFFFFFFFFF0011, 1'b0, 8'hFF);
        // Beat 1: SRC MAC lo + EtherType ARP
        send_beat(64'h22334455FFFF0806, 1'b0, 8'hFF);
        // ARP payload (dummy) - 3 more beats
        send_beat(64'h0001080006040001, 1'b0, 8'hFF);
        send_beat(64'h001122334455C0A8, 1'b0, 8'hFF);
        send_beat(64'h0001FFFFFFFFFFFF, 1'b1, 8'hFF);
    end
endtask

// -------------------------------------------------------------------------
// Main stimulus
// -------------------------------------------------------------------------
integer wait_clk;

initial begin
    $dumpfile("tb_tuple_extractor.vcd");
    $dumpvars(0, tb_tuple_extractor);

    rst_n    = 0;
    s_tvalid = 0;
    s_tlast  = 0;
    s_tdata  = 64'd0;
    s_tkeep  = 8'hFF;

    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(3) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 1: IPv4/TCP
    // -----------------------------------------------------------------------
    $display("--- Test 1: IPv4/TCP Packet ---");
    send_ipv4_packet(32'h0a000001, 32'hc0a80164, 16'd12345, 16'd80, 8'h06);

    // Wait and check
    wait_clk = 0;
    while (!tuple_valid && wait_clk < 30) begin
        @(posedge clk); wait_clk = wait_clk + 1;
    end
    if (tuple_valid && src_ip == 32'h0a000001 && dst_ip == 32'hc0a80164 &&
        src_port == 16'd12345 && dst_port == 16'd80 && protocol == 8'h06) begin
        $display("PASS [TCP_TEST]: SRC=%08h DST=%08h SPORT=%0d DPORT=%0d PROTO=%0d",
                 src_ip, dst_ip, src_port, dst_port, protocol);
        pass_cnt = pass_cnt + 1;
    end else if (!tuple_valid) begin
        $display("FAIL [TCP_TEST]: tuple_valid never asserted");
        fail_cnt = fail_cnt + 1;
    end else begin
        $display("FAIL [TCP_TEST]: Got SRC=%08h DST=%08h SPORT=%0d DPORT=%0d PROTO=%0d",
                 src_ip, dst_ip, src_port, dst_port, protocol);
        fail_cnt = fail_cnt + 1;
    end
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 2: IPv4/UDP
    // -----------------------------------------------------------------------
    $display("--- Test 2: IPv4/UDP Packet ---");
    send_ipv4_packet(32'hac100503, 32'h0a0a0a0a, 16'd53, 16'd53, 8'h11);

    wait_clk = 0;
    while (!tuple_valid && wait_clk < 30) begin
        @(posedge clk); wait_clk = wait_clk + 1;
    end
    if (tuple_valid && src_ip == 32'hac100503 && dst_ip == 32'h0a0a0a0a &&
        src_port == 16'd53 && dst_port == 16'd53 && protocol == 8'h11) begin
        $display("PASS [UDP_TEST]: SRC=%08h DST=%08h SPORT=%0d DPORT=%0d PROTO=%0d",
                 src_ip, dst_ip, src_port, dst_port, protocol);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [UDP_TEST]: Got SRC=%08h DST=%08h SPORT=%0d DPORT=%0d PROTO=%0d",
                 src_ip, dst_ip, src_port, dst_port, protocol);
        fail_cnt = fail_cnt + 1;
    end
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 3: ARP bypass
    // -----------------------------------------------------------------------
    $display("--- Test 3: ARP Bypass ---");
    send_arp_packet();

    wait_clk = 0;
    while (!bypass && !tuple_valid && wait_clk < 30) begin
        @(posedge clk); wait_clk = wait_clk + 1;
    end
    if (bypass && !tuple_valid) begin
        $display("PASS [ARP_BYPASS]: tuple_valid correctly not asserted");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [ARP_BYPASS]: bypass=%0b tuple_valid=%0b", bypass, tuple_valid);
        fail_cnt = fail_cnt + 1;
    end
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("");
    $display("TEST SUMMARY: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
    $finish;
end

// Timeout watchdog
initial begin
    #100000;
    $display("TIMEOUT: simulation exceeded limit");
    $finish;
end

endmodule