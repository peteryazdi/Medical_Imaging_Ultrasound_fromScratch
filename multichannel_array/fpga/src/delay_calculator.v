// delay_calculator.v – Focal-delay LUT for delay-and-sum beamforming
//
// Pre-computes the integer sample delay for each (channel, focal_point) pair
// and stores the results in a Block RAM LUT.
//
// Delay formula (receive focusing, 1-D linear array):
//   d_i = round( (r_i - r_0) / c * fs )
//
// where:
//   r_i = sqrt( (x_focal - x_i)^2 + z_focal^2 )  – distance from element i to focal point
//   r_0 = z_focal                                 – axial distance (on-axis reference)
//   c   = 1540 m/s (speed of sound)
//   fs  = 40e6 Hz (sample rate)
//
// At synthesis time the LUT is loaded from an initialisation file generated
// by the Python script `simulation/beamforming_sim.py`.
// At run time the beamformer simply reads the delay for each channel given
// the current focal_idx (depth step index).

`timescale 1ns / 1ps

module delay_calculator #(
    parameter NUM_CH       = 16,
    parameter FOCAL_POINTS = 256,
    parameter DELAY_WIDTH  = 10    // max delay in samples (2^10 = 1024)
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Current focal point index (from beamformer)
    input  wire [$clog2(FOCAL_POINTS)-1:0] focal_idx,

    // Delay outputs: one per channel, registered
    output reg  [DELAY_WIDTH-1:0]   delay_out [0:NUM_CH-1]
);

// ── Block RAM holding the pre-computed delay LUT ──────────────────────────
// Layout: address = focal_idx * NUM_CH + ch_idx
// Data width: DELAY_WIDTH bits
// Total words: FOCAL_POINTS * NUM_CH = 256 * 16 = 4096

localparam LUT_DEPTH = FOCAL_POINTS * NUM_CH;
localparam ADDR_W    = $clog2(LUT_DEPTH);

reg [DELAY_WIDTH-1:0] lut_ram [0:LUT_DEPTH-1];

// Initialise from generated file (produced by beamforming_sim.py)
initial begin
    $readmemh("delay_lut.hex", lut_ram);
end

// ── Pipeline: register one delay per channel each clock cycle ─────────────
// We read NUM_CH consecutive addresses starting at focal_idx * NUM_CH.
// A small counter sequences through the channels and the beamformer
// waits NUM_CH cycles for all delays to be valid.

reg [$clog2(NUM_CH)-1:0] ch_cnt;
reg                       lut_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch_cnt    <= {$clog2(NUM_CH){1'b0}};
        lut_valid <= 1'b0;
    end else begin
        // Continuously cycle through channels for the current focal point
        ch_cnt <= ch_cnt + 1'b1;
        delay_out[ch_cnt] <= lut_ram[focal_idx * NUM_CH + ch_cnt];
        if (ch_cnt == NUM_CH - 1) begin
            lut_valid <= 1'b1;
        end
    end
end

endmodule
