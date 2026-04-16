`default_nettype none
module header_modifier_props (
    input wire clk, input wire rst_n,
    input wire [63:0] s_tdata, input wire s_tvalid,
    input wire s_tlast, input wire [7:0] s_tkeep,
    input wire meta_valid, input wire meta_bypass,
    input wire [47:0] meta_dst_mac, input wire [31:0] meta_dst_ip,
    input wire m_tready
);

wire [63:0] m_tdata;
wire        m_tvalid, m_tlast;
wire [7:0]  m_tkeep;
wire        s_tready, meta_ready;

header_modifier #(.DATA_WIDTH(64)) dut (
    .clk(clk), .rst_n(rst_n),
    .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tlast(s_tlast),
    .s_tkeep(s_tkeep), .s_tready(s_tready),
    .meta_valid(meta_valid), .meta_bypass(meta_bypass),
    .meta_dst_mac(meta_dst_mac), .meta_dst_ip(meta_dst_ip),
    .meta_ready(meta_ready),
    .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tlast(m_tlast),
    .m_tkeep(m_tkeep), .m_tready(m_tready)
);

// Shadow beat counter
reg        in_packet_s;
reg [2:0]  beat_cnt_s;

wire beat_fire = s_tvalid && s_tready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_packet_s <= 1'b0;
        beat_cnt_s  <= 3'd0;
    end else if (beat_fire) begin
        if (!in_packet_s) begin
            in_packet_s <= 1'b1;
            beat_cnt_s  <= 3'd1;
        end else if (beat_cnt_s < 3'd7) begin
            beat_cnt_s <= beat_cnt_s + 3'd1;
        end
        if (s_tlast) begin
            in_packet_s <= 1'b0;
            beat_cnt_s  <= 3'd0;
        end
    end
end

reg f_past_valid, fpv2;
initial begin f_past_valid = 1'b0; fpv2 = 1'b0; end
always @(posedge clk) begin
    f_past_valid <= 1'b1;
    fpv2         <= f_past_valid;
end

// Step 0: reset; steps 1+: run
always @(*) begin
    if (!f_past_valid) assume(!rst_n);
    else               assume(rst_n);
end

// No input data during reset
always @(*) begin
    if (!f_past_valid) assume(!s_tvalid);
end

// 1. Reset: m_tvalid deasserted
always @(posedge clk) begin
    if (!rst_n) assert(!m_tvalid);
end

// 2. Stall: s_tready deasserted when no packet in flight and no meta
always @(posedge clk) begin
    if (rst_n && s_tvalid && !in_packet_s && !meta_valid)
        assert(!s_tready);
end

// 3. meta_ready is a single-cycle pulse
// Guard with fpv2 (two clean post-reset cycles) so $past(meta_ready)
// is never looking at the reset-transition cycle
always @(posedge clk) begin
    if (fpv2 && $past(meta_ready)) assert(!meta_ready);
end

// 4. beat_cnt never exceeds 7
always @(posedge clk) begin
    if (rst_n) assert(beat_cnt_s <= 3'd7);
end

// Cover: packet forwarded end-to-end
always @(posedge clk) begin
    if (rst_n) cover(m_tvalid && m_tlast);
end

endmodule