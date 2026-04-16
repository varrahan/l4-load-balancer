`default_nettype none
module tuple_extractor_props (
    input wire clk, input wire rst_n,
    input wire [63:0] s_tdata, input wire s_tvalid,
    input wire s_tlast, input wire [7:0] s_tkeep
);

wire [31:0] src_ip, dst_ip;
wire [15:0] src_port, dst_port;
wire [7:0]  protocol;
wire        tuple_valid, bypass;

tuple_extractor #(.DATA_WIDTH(64)) dut (
    .clk(clk), .rst_n(rst_n),
    .s_tdata(s_tdata), .s_tvalid(s_tvalid),
    .s_tlast(s_tlast), .s_tkeep(s_tkeep),
    .src_ip(src_ip), .dst_ip(dst_ip),
    .src_port(src_port), .dst_port(dst_port),
    .protocol(protocol), .tuple_valid(tuple_valid), .bypass(bypass)
);

reg [2:0] beat_cnt_s;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) beat_cnt_s <= 3'd0;
    else if (s_tvalid) begin
        if (s_tlast)             beat_cnt_s <= 3'd0;
        else if (beat_cnt_s < 7) beat_cnt_s <= beat_cnt_s + 3'd1;
    end
end

reg f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

always @(*) begin
    if (!f_past_valid) assume(!rst_n);
end

wire fpv_stable = f_past_valid && rst_n && $past(rst_n);

always @(posedge clk) begin
    if (!rst_n) begin assert(!tuple_valid); assert(!bypass); end
end
always @(posedge clk) begin
    if (rst_n) assert(!(tuple_valid && bypass));
end
always @(posedge clk) begin
    if (fpv_stable && $past(tuple_valid)) assert(!tuple_valid);
end
always @(posedge clk) begin
    if (fpv_stable && $past(bypass)) assert(!bypass);
end
always @(posedge clk) begin
    if (fpv_stable && tuple_valid) assert($past(beat_cnt_s) == 3'd4);
end
always @(posedge clk) begin
    if (fpv_stable && bypass) assert($past(beat_cnt_s) == 3'd4);
end
always @(posedge clk) begin
    if (rst_n) assert(beat_cnt_s <= 3'd7);
end
always @(posedge clk) begin
    if (fpv_stable && $past(s_tvalid) && $past(s_tlast))
        assert(beat_cnt_s == 3'd0);
end
always @(posedge clk) begin if (rst_n) cover(tuple_valid && protocol == 8'h06); end
always @(posedge clk) begin if (rst_n) cover(tuple_valid && protocol == 8'h11); end
always @(posedge clk) begin if (rst_n) cover(bypass); end

endmodule
