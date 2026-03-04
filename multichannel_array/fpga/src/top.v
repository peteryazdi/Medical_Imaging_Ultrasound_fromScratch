// top.v – Top-level integration for the 16-channel ultrasound FPGA pipeline
//
// Instantiates:
//   • adc_interface    – 16-channel SPI ADC front-end
//   • channel_buffer   – per-channel sample FIFO (×16)
//   • delay_calculator – focal-delay LUT generator
//   • beamformer       – delay-and-sum across 16 channels
//   • image_output     – scan-line BRAM + host DMA interface
//
// Clock domains
//   clk_sys  100 MHz  system / logic clock
//   clk_adc   40 MHz  ADC sample clock (forwarded to all ADCs)

`timescale 1ns / 1ps

module top #(
    parameter NUM_CH        = 16,   // number of receive channels
    parameter SAMPLE_WIDTH  = 12,   // ADC resolution (bits)
    parameter FIFO_DEPTH    = 1024, // samples stored per channel per firing
    parameter FOCAL_POINTS  = 256   // depth focal points per scan line
)(
    // ── System ──────────────────────────────────────────────────────────────
    input  wire        clk_sys,       // 100 MHz system clock
    input  wire        rst_n,         // active-low reset

    // ── ADC SPI interface (shared bus, 16 CS lines) ──────────────────────
    output wire        adc_sclk,      // SPI clock  (forwarded to all ADCs)
    output wire [NUM_CH-1:0] adc_csn, // SPI chip-select (active low, per ch)
    input  wire [NUM_CH-1:0] adc_miso,// SPI data in (per channel)

    // ── Transmit trigger ────────────────────────────────────────────────
    output wire        tx_trigger,    // pulse to HV pulser / T-R switch

    // ── Host interface (AXI4-Lite or simple handshake) ───────────────────
    output wire        frame_valid,   // one full B-scan frame is ready
    output wire [15:0] pixel_data,    // pixel intensity (envelope-detected)
    output wire        pixel_valid,
    input  wire        pixel_ready
);

// ── Internal wires ──────────────────────────────────────────────────────────

// Per-channel raw samples from ADC interface
wire [SAMPLE_WIDTH-1:0] raw_sample  [0:NUM_CH-1];
wire [NUM_CH-1:0]       sample_valid;

// Per-channel FIFO read ports (to beamformer)
wire [SAMPLE_WIDTH-1:0] ch_data     [0:NUM_CH-1];
wire [$clog2(FIFO_DEPTH)-1:0] ch_rd_addr [0:NUM_CH-1]; // beamformer read addresses
wire [$clog2(FIFO_DEPTH)-1:0] ch_wr_ptr  [0:NUM_CH-1]; // per-channel write pointers

// Delay values from delay calculator (one per channel, registered)
wire [9:0]              delay_tap   [0:NUM_CH-1]; // max 1023 sample delay

// Focal point index shared between beamformer and delay_calculator
wire [$clog2(FOCAL_POINTS)-1:0] focal_idx_wire;

// Beamformer output
wire [SAMPLE_WIDTH+4-1:0] beam_sum;   // 16 samples summed → 4 extra bits
wire                      beam_valid;

// Acquisition control
wire acq_start;
wire acq_done;

// ── Acquisition sequencer (simple state machine) ─────────────────────────
acq_sequencer #(
    .NUM_CH       (NUM_CH),
    .FIFO_DEPTH   (FIFO_DEPTH)
) u_seq (
    .clk          (clk_sys),
    .rst_n        (rst_n),
    .tx_trigger   (tx_trigger),
    .acq_start    (acq_start),
    .acq_done     (acq_done)
);

// ── ADC interface ────────────────────────────────────────────────────────
genvar i;
generate
    for (i = 0; i < NUM_CH; i = i + 1) begin : gen_adc
        adc_interface #(
            .SAMPLE_WIDTH (SAMPLE_WIDTH)
        ) u_adc (
            .clk          (clk_sys),
            .rst_n        (rst_n),
            .acq_en       (acq_start),
            .sclk         (adc_sclk),
            .csn          (adc_csn[i]),
            .miso         (adc_miso[i]),
            .sample_out   (raw_sample[i]),
            .sample_valid (sample_valid[i])
        );
    end
endgenerate

// ── Per-channel FIFOs ────────────────────────────────────────────────────
generate
    for (i = 0; i < NUM_CH; i = i + 1) begin : gen_buf
        channel_buffer #(
            .DATA_WIDTH (SAMPLE_WIDTH),
            .DEPTH      (FIFO_DEPTH)
        ) u_buf (
            .clk        (clk_sys),
            .rst_n      (rst_n),
            .wr_en      (sample_valid[i]),
            .wr_data    (raw_sample[i]),
            .rd_addr    (ch_rd_addr[i]),
            .rd_data    (ch_data[i]),
            .acq_done   (acq_done),
            .wr_ptr     (ch_wr_ptr[i]),
            .buf_ready  ()
        );
    end
endgenerate

// All channels advance in lockstep; use channel-0 write pointer as the reference.
// The beamformer uses wr_ptr to compute (wr_ptr - delay_tap[i]) read addresses.
wire [$clog2(FIFO_DEPTH)-1:0] wr_ptr_ref;
assign wr_ptr_ref = ch_wr_ptr[0];

// ── Delay calculator ─────────────────────────────────────────────────────
delay_calculator #(
    .NUM_CH       (NUM_CH),
    .FOCAL_POINTS (FOCAL_POINTS),
    .DELAY_WIDTH  (10)
) u_delay (
    .clk          (clk_sys),
    .rst_n        (rst_n),
    .focal_idx    (focal_idx_wire),
    .delay_out    (delay_tap)
);

// ── Beamformer ───────────────────────────────────────────────────────────
beamformer #(
    .NUM_CH       (NUM_CH),
    .SAMPLE_WIDTH (SAMPLE_WIDTH),
    .FIFO_DEPTH   (FIFO_DEPTH),
    .FOCAL_POINTS (FOCAL_POINTS)
) u_beam (
    .clk          (clk_sys),
    .rst_n        (rst_n),
    .acq_done     (acq_done),
    .ch_data      (ch_data),
    .ch_rd_addr   (ch_rd_addr),
    .delay_tap    (delay_tap),
    .wr_ptr       (wr_ptr_ref),
    .beam_sum     (beam_sum),
    .beam_valid   (beam_valid),
    .focal_idx    (focal_idx_wire)
);

// ── Image output ─────────────────────────────────────────────────────────
image_output #(
    .SAMPLE_WIDTH  (SAMPLE_WIDTH + 4),
    .FOCAL_POINTS  (FOCAL_POINTS)
) u_img (
    .clk           (clk_sys),
    .rst_n         (rst_n),
    .beam_sum      (beam_sum),
    .beam_valid    (beam_valid),
    .frame_valid   (frame_valid),
    .pixel_data    (pixel_data),
    .pixel_valid   (pixel_valid),
    .pixel_ready   (pixel_ready)
);

endmodule
