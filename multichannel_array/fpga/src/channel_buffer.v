// channel_buffer.v – Per-channel sample FIFO
//
// Stores up to DEPTH samples from one ADC channel after each firing event.
// The beamformer reads back samples with programmable delay by addressing
// an internal RAM (acts as a circular buffer / delay line).
//
// Write port: driven by adc_interface at 40 MSPS.
// Read port:  driven by beamformer; rd_addr is the (current_depth - delay).

`timescale 1ns / 1ps

module channel_buffer #(
    parameter DATA_WIDTH = 12,
    parameter DEPTH      = 1024  // must be a power of 2
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Write port
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,

    // Read port (random access for delay-and-sum)
    input  wire [$clog2(DEPTH)-1:0] rd_addr,
    output wire [DATA_WIDTH-1:0]    rd_data,

    // Control
    input  wire                  acq_done,   // latch: freeze buffer for reading
    output reg  [$clog2(DEPTH)-1:0] wr_ptr,  // expose write pointer
    output reg                   buf_ready   // high when buffer is frozen
);

localparam ADDR_W = $clog2(DEPTH);

// ── Simple dual-port RAM ──────────────────────────────────────────────────
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Write side
always @(posedge clk) begin
    if (wr_en && !buf_ready) begin
        mem[wr_ptr] <= wr_data;
    end
end

// Read side (1-cycle latency)
reg [DATA_WIDTH-1:0] rd_data_r;
always @(posedge clk) begin
    rd_data_r <= mem[rd_addr];
end
assign rd_data = rd_data_r;

// ── Write pointer ─────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr    <= {ADDR_W{1'b0}};
        buf_ready <= 1'b0;
    end else if (acq_done) begin
        // Freeze: stop writing, signal ready
        buf_ready <= 1'b1;
    end else if (!buf_ready && wr_en) begin
        if (wr_ptr == DEPTH - 1)
            wr_ptr <= {ADDR_W{1'b0}};
        else
            wr_ptr <= wr_ptr + 1'b1;
    end else if (!acq_done && !wr_en) begin
        // Reset for next firing
        wr_ptr    <= {ADDR_W{1'b0}};
        buf_ready <= 1'b0;
    end
end

endmodule
