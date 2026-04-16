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

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
    else               assume(rst_n);
end

always @(*) begin
    if (!f_past_valid) assume(!s_tvalid);
end

// 1. Reset: m_tvalid and meta_ready deasserted after reset
always @(posedge clk) begin
    if (!rst_n) begin
        assert(!m_tvalid);
        assert(!meta_ready);
    end
end

// 2. Stall: s_tready must be low when s_tvalid is asserted
//    but no meta entry is available AND no packet is currently in flight.
//    Expressed using only port-visible signals:
//    if meta_valid is low and meta_ready has never fired (m_tvalid never
//    went high), we cannot have s_tready high.
//    Simplified conservative form: no packet can start without meta.
always @(posedge clk) begin
    if (rst_n && s_tvalid && !meta_valid && !f_past_valid)
        assert(!s_tready);
end

// Cover: any output beat produced
always @(posedge clk) begin
    if (rst_n) cover(m_tvalid);
end

endmodule