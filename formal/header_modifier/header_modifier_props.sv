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

// 2. Stall: when no packet is in flight and no meta is ready,
//    s_tready must be deasserted to prevent packet ingestion
always @(posedge clk) begin
    if (rst_n && s_tvalid && !meta_valid && !m_tvalid)
        assert(!s_tready);
end

// 3. AXI-S output never asserts tvalid without tready having been high
//    (no data is produced without input being accepted)
//    Expressed as: if s_tvalid was never seen, m_tvalid cannot be high
always @(posedge clk) begin
    if (rst_n && !f_past_valid) assert(!m_tvalid);
end

// Cover: packet forwarded end-to-end
always @(posedge clk) begin
    if (rst_n) cover(m_tvalid && m_tlast);
end

endmodule