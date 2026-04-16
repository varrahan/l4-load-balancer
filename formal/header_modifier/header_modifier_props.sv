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

wire beat_fire = s_tvalid && s_tready;

reg        in_packet_s;
reg [2:0]  beat_cnt_s;
reg [47:0] lat_dst_mac_s;
reg [31:0] lat_dst_ip_s;
reg        lat_bypass_s;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_packet_s <= 1'b0; beat_cnt_s <= 3'd0;
        lat_dst_mac_s <= 48'd0; lat_dst_ip_s <= 32'd0; lat_bypass_s <= 1'b0;
    end else if (beat_fire) begin
        if (!in_packet_s) begin
            in_packet_s   <= 1'b1;   beat_cnt_s    <= 3'd1;
            lat_dst_mac_s <= meta_dst_mac; lat_dst_ip_s <= meta_dst_ip;
            lat_bypass_s  <= meta_bypass;
        end else begin
            if (beat_cnt_s < 3'd7) beat_cnt_s <= beat_cnt_s + 3'd1;
        end
        if (s_tlast) begin in_packet_s <= 1'b0; beat_cnt_s <= 3'd0; end
    end
end

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
end

wire fpv_stable = f_past_valid && rst_n && $past(rst_n);

always @(posedge clk) begin if (!rst_n) assert(!m_tvalid); end
always @(posedge clk) begin
    if (rst_n && s_tvalid && !in_packet_s && !meta_valid) assert(!s_tready);
end
always @(posedge clk) begin
    if (fpv_stable && m_tvalid && lat_bypass_s)
        assert(m_tdata == $past(s_tdata));
end
always @(posedge clk) begin
    if (fpv_stable && m_tvalid && !lat_bypass_s && !$past(in_packet_s))
        assert(m_tdata[63:16] == lat_dst_mac_s);
end
always @(posedge clk) begin
    if (fpv_stable && m_tvalid && !lat_bypass_s && $past(beat_cnt_s) == 3'd3)
        assert(m_tdata[15:0] == lat_dst_ip_s[31:16]);
end
always @(posedge clk) begin
    if (fpv_stable && m_tvalid && !lat_bypass_s && $past(beat_cnt_s) == 3'd4)
        assert(m_tdata[63:48] == lat_dst_ip_s[15:0]);
end
always @(posedge clk) begin
    if (fpv_stable && $past(meta_ready)) assert(!meta_ready);
end
always @(posedge clk) begin if (rst_n) assert(beat_cnt_s <= 3'd7); end
always @(posedge clk) begin if (rst_n) cover(m_tvalid && m_tlast &&  lat_bypass_s); end
always @(posedge clk) begin if (rst_n) cover(m_tvalid && m_tlast && !lat_bypass_s); end

endmodule
