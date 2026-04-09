// =============================================================================
// axi_stream_ingress.v
// AXI-Stream Ingress Skid Buffer
// =============================================================================
// One-entry skid buffer to register the ready path and break the
// combinatorial loop between upstream MAC and the pipeline.
// Supports full throughput (II=1) with registered m_tready.
// =============================================================================

`timescale 1ns / 1ps

module axi_stream_ingress #(
    parameter DATA_WIDTH = 64
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Slave port (from MAC)
    input  wire [DATA_WIDTH-1:0]   s_tdata,
    input  wire                    s_tvalid,
    input  wire                    s_tlast,
    input  wire [DATA_WIDTH/8-1:0] s_tkeep,
    output reg                     s_tready,

    // Master port (to pipeline)
    output reg  [DATA_WIDTH-1:0]   m_tdata,
    output reg                     m_tvalid,
    output reg                     m_tlast,
    output reg  [DATA_WIDTH/8-1:0] m_tkeep,
    input  wire                    m_tready
);

// Skid registers
reg [DATA_WIDTH-1:0]   skid_data;
reg                    skid_valid;
reg                    skid_last;
reg [DATA_WIDTH/8-1:0] skid_keep;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_tready   <= 1'b1;
        m_tvalid   <= 1'b0;
        m_tdata    <= {DATA_WIDTH{1'b0}};
        m_tlast    <= 1'b0;
        m_tkeep    <= {DATA_WIDTH/8{1'b0}};
        skid_valid <= 1'b0;
        skid_data  <= {DATA_WIDTH{1'b0}};
        skid_last  <= 1'b0;
        skid_keep  <= {DATA_WIDTH/8{1'b0}};
    end else begin
        if (m_tready) begin
            // Downstream is ready - drain skid or accept directly
            if (skid_valid) begin
                m_tdata  <= skid_data;
                m_tkeep  <= skid_keep;
                m_tlast  <= skid_last;
                m_tvalid <= 1'b1;
                skid_valid <= 1'b0;
                s_tready   <= 1'b1;
            end else if (s_tvalid && s_tready) begin
                m_tdata  <= s_tdata;
                m_tkeep  <= s_tkeep;
                m_tlast  <= s_tlast;
                m_tvalid <= 1'b1;
            end else begin
                m_tvalid <= 1'b0;
            end
        end else begin
            // Downstream stalled - save incoming beat to skid register
            if (s_tvalid && s_tready) begin
                skid_data  <= s_tdata;
                skid_keep  <= s_tkeep;
                skid_last  <= s_tlast;
                skid_valid <= 1'b1;
                s_tready   <= 1'b0; // apply backpressure upstream
            end
        end
    end
end

endmodule