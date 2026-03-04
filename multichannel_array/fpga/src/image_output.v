// image_output.v – Scan-line envelope detector and BRAM image store
//
// Receives the raw beam_sum (signed, 16-bit) from the beamformer, applies a
// simple Hilbert-magnitude envelope detector (implemented here as a peak-hold
// with exponential decay – matching the single-transducer firmware approach),
// and writes the result into a dual-port BRAM.
//
// A simple ready/valid handshake streams pixels to the host (UART, USB, PCIe).

`timescale 1ns / 1ps

module image_output #(
    parameter SAMPLE_WIDTH  = 16,  // beam_sum width (SAMPLE_WIDTH + 4 from beamformer)
    parameter FOCAL_POINTS  = 256, // pixels per scan line (depth samples)
    parameter OUT_WIDTH     = 16   // output pixel width
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // From beamformer
    input  wire [SAMPLE_WIDTH-1:0] beam_sum,
    input  wire                    beam_valid,

    // To host
    output reg                     frame_valid,
    output reg  [OUT_WIDTH-1:0]    pixel_data,
    output reg                     pixel_valid,
    input  wire                    pixel_ready
);

localparam DECAY_SHIFT = 3;  // envelope decay: env -= env >> 3

// ── Envelope detector ────────────────────────────────────────────────────
// Absolute value of beam_sum, then peak-hold with decay
reg  [SAMPLE_WIDTH-1:0] envelope;
wire [SAMPLE_WIDTH-1:0] abs_beam = beam_sum[SAMPLE_WIDTH-1]
                                    ? (~beam_sum + 1'b1)
                                    : beam_sum;

// ── BRAM (single scan line, FOCAL_POINTS deep) ────────────────────────────
reg [OUT_WIDTH-1:0] line_bram [0:FOCAL_POINTS-1];

reg [$clog2(FOCAL_POINTS)-1:0] wr_addr;
reg [$clog2(FOCAL_POINTS)-1:0] rd_addr;
reg                             rd_en;
reg                             line_done;

// ── Write path: envelope detect → BRAM ───────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        envelope  <= {SAMPLE_WIDTH{1'b0}};
        wr_addr   <= {$clog2(FOCAL_POINTS){1'b0}};
        line_done <= 1'b0;
    end else begin
        line_done <= 1'b0;
        if (beam_valid) begin
            // Peak-hold with decay
            if (abs_beam > envelope)
                envelope <= abs_beam;
            else
                envelope <= envelope - (envelope >> DECAY_SHIFT);

            // Truncate / saturate to OUT_WIDTH
            line_bram[wr_addr] <= (|envelope[SAMPLE_WIDTH-1:OUT_WIDTH])
                                   ? {OUT_WIDTH{1'b1}}
                                   : envelope[OUT_WIDTH-1:0];

            if (wr_addr == FOCAL_POINTS - 1) begin
                wr_addr   <= {$clog2(FOCAL_POINTS){1'b0}};
                line_done <= 1'b1;
                envelope  <= {SAMPLE_WIDTH{1'b0}};
            end else begin
                wr_addr <= wr_addr + 1'b1;
            end
        end
    end
end

// ── Read path: stream pixels to host ─────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_addr     <= {$clog2(FOCAL_POINTS){1'b0}};
        rd_en       <= 1'b0;
        pixel_valid <= 1'b0;
        pixel_data  <= {OUT_WIDTH{1'b0}};
        frame_valid <= 1'b0;
    end else begin
        frame_valid <= 1'b0;

        if (line_done) begin
            rd_addr <= {$clog2(FOCAL_POINTS){1'b0}};
            rd_en   <= 1'b1;
        end

        if (rd_en && pixel_ready) begin
            pixel_data  <= line_bram[rd_addr];
            pixel_valid <= 1'b1;
            if (rd_addr == FOCAL_POINTS - 1) begin
                rd_en       <= 1'b0;
                frame_valid <= 1'b1;
            end else begin
                rd_addr <= rd_addr + 1'b1;
            end
        end else begin
            pixel_valid <= 1'b0;
        end
    end
end

endmodule
