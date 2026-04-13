// =============================================================================
// tb_toeplitz_core.v
// Unit Testbench - toeplitz_core
// =============================================================================
// Tests:
//   Test 1: Hash determinism - same input always gives same output
//   Test 2: Hash distinctness - different 5-tuples give different hashes
//   Test 3: Bypass flag propagation - bypass=1 passes through unchanged
//   Test 4: Back-to-back II=1 - assert in_valid every cycle, verify output cadence
// =============================================================================

`timescale 1ns / 1ps

module tb_toeplitz_core;

reg clk = 0;
always #3.2 clk = ~clk;
reg rst_n;

reg  [31:0] src_ip, dst_ip;
reg  [15:0] src_port, dst_port;
reg         in_valid, in_bypass;

wire [31:0] hash_out;
wire        out_valid;
wire        out_bypass;

toeplitz_core dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .src_ip   (src_ip),
    .dst_ip   (dst_ip),
    .src_port (src_port),
    .dst_port (dst_port),
    .in_valid (in_valid),
    .in_bypass(in_bypass),
    .hash_out (hash_out),
    .out_valid(out_valid),
    .out_bypass(out_bypass)
);

integer pass_cnt = 0;
integer fail_cnt = 0;

task drive_tuple;
    input [31:0] sip, dip;
    input [15:0] sp, dp;
    input        bypass;
    begin
        @(posedge clk);
        src_ip   <= sip;
        dst_ip   <= dip;
        src_port <= sp;
        dst_port <= dp;
        in_valid <= 1'b1;
        in_bypass <= bypass;
        @(posedge clk);
        in_valid  <= 1'b0;
        in_bypass <= 1'b0;
    end
endtask

// Wait for out_valid with timeout
function automatic [31:0] wait_hash;
    input integer timeout;
    integer i;
    begin
        wait_hash = 32'hDEAD_BEEF;
        for (i = 0; i < timeout; i = i + 1) begin
            @(posedge clk);
            if (out_valid) begin
                wait_hash = hash_out;
                i = timeout; // break
            end
        end
    end
endfunction

reg [31:0] hash_a, hash_b;
integer wait_i;

initial begin
    $dumpfile("tb_toeplitz_core.vcd");
    $dumpvars(0, tb_toeplitz_core);

    rst_n    = 0;
    in_valid = 0;
    in_bypass = 0;
    src_ip = 0; dst_ip = 0; src_port = 0; dst_port = 0;

    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(3) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 1: Hash determinism
    // -----------------------------------------------------------------------
    $display("--- Test 1: Toeplitz Hash Determinism ---");
    drive_tuple(32'h0a000001, 32'hc0a80164, 16'd1234, 16'd80, 1'b0);

    // Collect hash_a
    hash_a = 32'hDEAD_BEEF;
    wait_i = 0;
    while (hash_a == 32'hDEAD_BEEF && wait_i < 20) begin
        @(posedge clk);
        if (out_valid) hash_a = hash_out;
        wait_i = wait_i + 1;
    end

    // Wait idle
    repeat(5) @(posedge clk);

    // Send same tuple again
    drive_tuple(32'h0a000001, 32'hc0a80164, 16'd1234, 16'd80, 1'b0);

    hash_b = 32'hDEAD_BEEF;
    wait_i = 0;
    while (hash_b == 32'hDEAD_BEEF && wait_i < 20) begin
        @(posedge clk);
        if (out_valid) hash_b = hash_out;
        wait_i = wait_i + 1;
    end

    if (hash_a != 32'hDEAD_BEEF && hash_a == hash_b) begin
        $display("PASS [DETERMINISM]: hash=0x%08h reproducible", hash_a);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [DETERMINISM]: hash_a=0x%08h hash_b=0x%08h", hash_a, hash_b);
        fail_cnt = fail_cnt + 1;
    end
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 2: Distinct tuples → distinct hashes
    // -----------------------------------------------------------------------
    $display("--- Test 2: Hash Distinctness ---");
    drive_tuple(32'h0a000001, 32'hc0a80164, 16'd1234, 16'd80, 1'b0);

    hash_a = 32'hDEAD_BEEF;
    wait_i = 0;
    while (hash_a == 32'hDEAD_BEEF && wait_i < 20) begin
        @(posedge clk);
        if (out_valid) hash_a = hash_out;
        wait_i = wait_i + 1;
    end
    repeat(5) @(posedge clk);

    drive_tuple(32'h0a000002, 32'hc0a80165, 16'd9999, 16'd443, 1'b0);

    hash_b = 32'hDEAD_BEEF;
    wait_i = 0;
    while (hash_b == 32'hDEAD_BEEF && wait_i < 20) begin
        @(posedge clk);
        if (out_valid) hash_b = hash_out;
        wait_i = wait_i + 1;
    end

    if (hash_a != hash_b) begin
        $display("PASS [DISTINCT]: 0x%08h != 0x%08h", hash_a, hash_b);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [DISTINCT]: both hashes = 0x%08h", hash_a);
        fail_cnt = fail_cnt + 1;
    end
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 3: Bypass propagation
    // -----------------------------------------------------------------------
    $display("--- Test 3: Bypass Flag Propagation ---");
    drive_tuple(32'hDEADDEAD, 32'hBEEFBEEF, 16'd0, 16'd0, 1'b1); // bypass

    wait_i = 0;
    while (!out_bypass && wait_i < 20) begin
        @(posedge clk); wait_i = wait_i + 1;
    end

    if (out_bypass) begin
        $display("PASS [BYPASS]: out_bypass correctly propagated");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL [BYPASS]: out_bypass not asserted");
        fail_cnt = fail_cnt + 1;
    end
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Test 4: Back-to-back II=1 throughput
    // Send 8 tuples consecutively, verify 8 outputs appear within 8+latency cycles
    // -----------------------------------------------------------------------
    $display("--- Test 4: Back-to-Back II=1 ---");
    begin : bb_test
        integer sent, recvd, timeout_ctr;
        sent  = 0;
        recvd = 0;
        timeout_ctr = 0;

        // Send 8 consecutive valid tuples
        for (sent = 0; sent < 8; sent = sent + 1) begin
            @(posedge clk);
            src_ip   <= sent * 32'h01000001;
            dst_ip   <= 32'hc0a80100 + sent;
            src_port <= 16'd1024 + sent;
            dst_port <= 16'd80;
            in_valid  <= 1'b1;
            in_bypass <= 1'b0;
        end
        @(posedge clk);
        in_valid <= 1'b0;

        // Count outputs
        recvd = 0;
        timeout_ctr = 0;
        while (recvd < 8 && timeout_ctr < 30) begin
            @(posedge clk);
            if (out_valid) recvd = recvd + 1;
            timeout_ctr = timeout_ctr + 1;
        end

        if (recvd == 8) begin
            $display("PASS [II=1]: Received all 8 hashes in %0d cycles", timeout_ctr);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL [II=1]: Only received %0d/8 hashes in %0d cycles", recvd, timeout_ctr);
            fail_cnt = fail_cnt + 1;
        end
    end
    repeat(5) @(posedge clk);

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("");
    $display("TEST SUMMARY: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
    $finish;
end

initial begin
    #200000;
    $display("TIMEOUT");
    $finish;
end

endmodule