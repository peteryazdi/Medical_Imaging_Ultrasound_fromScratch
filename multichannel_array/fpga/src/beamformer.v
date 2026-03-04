// beamformer.v – Delay-and-sum (DAS) beamformer for 16-channel ultrasound
//
// Algorithm
// ---------
// For each focal point z (indexed 0 … FOCAL_POINTS-1):
//   1. Fetch the pre-computed delay d_i for every channel i from delay_calculator.
//   2. Read sample[i][wr_ptr - d_i] from channel_buffer (read-address = wr_ptr - d_i).
//   3. Sum all 16 delayed samples → beam_sum (combinational adder tree in ST_SUM).
//   4. Assert beam_valid and advance focal_idx.
//
// The output beam_sum is fed to image_output for envelope detection and display.

`timescale 1ns / 1ps

module beamformer #(
    parameter NUM_CH        = 16,
    parameter SAMPLE_WIDTH  = 12,
    parameter FIFO_DEPTH    = 1024,
    parameter FOCAL_POINTS  = 256
)(
    input  wire        clk,
    input  wire        rst_n,

    // Start signal: raised by acq_sequencer after all channels are captured
    input  wire        acq_done,

    // Per-channel sample data (from channel_buffer read ports)
    input  wire [SAMPLE_WIDTH-1:0] ch_data  [0:NUM_CH-1],

    // Per-channel read address to channel_buffer
    output reg  [$clog2(FIFO_DEPTH)-1:0] ch_rd_addr [0:NUM_CH-1],

    // Delay values from delay_calculator (one per channel)
    input  wire [9:0]  delay_tap [0:NUM_CH-1],

    // Write-pointer from any channel buffer (all advance in lockstep)
    input  wire [$clog2(FIFO_DEPTH)-1:0] wr_ptr,

    // Output
    output reg  [SAMPLE_WIDTH+4-1:0] beam_sum,   // sum of 16 samples
    output reg                        beam_valid,

    // Focal point index (fed back to delay_calculator)
    output reg  [$clog2(FOCAL_POINTS)-1:0] focal_idx
);

localparam ADDR_W  = $clog2(FIFO_DEPTH);
localparam FOCAL_W = $clog2(FOCAL_POINTS);
localparam SUM_W   = SAMPLE_WIDTH + 4; // 16 channels → 4 extra bits

// ── State machine ──────────────────────────────────────────────────────────
localparam ST_IDLE    = 2'd0;
localparam ST_ADDR    = 2'd1;  // compute read addresses + wait 1 cycle RAM latency
localparam ST_SUM     = 2'd2;  // register combinational sum
localparam ST_OUTPUT  = 2'd3;  // output and advance focal point

reg [1:0] state;
integer k;

// ── Combinational adder tree ───────────────────────────────────────────────
// All NUM_CH sign-extended samples are summed in one combinational block.
// This synthesises to an efficient adder tree and avoids the Verilog
// for-loop register-assignment issue where only the last iteration wins.
reg signed [SUM_W-1:0] acc_comb;
always @(*) begin
    acc_comb = {SUM_W{1'b0}};
    for (k = 0; k < NUM_CH; k = k + 1) begin
        acc_comb = acc_comb + {{(SUM_W-SAMPLE_WIDTH){ch_data[k][SAMPLE_WIDTH-1]}},
                               ch_data[k]};
    end
end

// ── Registered control path ────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= ST_IDLE;
        focal_idx  <= {FOCAL_W{1'b0}};
        beam_sum   <= {SUM_W{1'b0}};
        beam_valid <= 1'b0;
        for (k = 0; k < NUM_CH; k = k + 1)
            ch_rd_addr[k] <= {ADDR_W{1'b0}};
    end else begin
        beam_valid <= 1'b0;

        case (state)
            // Wait for acquisition to complete
            ST_IDLE: begin
                if (acq_done) begin
                    focal_idx <= {FOCAL_W{1'b0}};
                    state     <= ST_ADDR;
                end
            end

            // Issue read addresses for all channels (wr_ptr - delay_tap[i])
            // All addresses issued in one cycle; RAM has 1-cycle latency → ST_SUM
            ST_ADDR: begin
                for (k = 0; k < NUM_CH; k = k + 1) begin
                    ch_rd_addr[k] <= wr_ptr - delay_tap[k];
                end
                state <= ST_SUM;
            end

            // Sample data now valid; register the combinational sum
            ST_SUM: begin
                beam_sum <= acc_comb;
                state    <= ST_OUTPUT;
            end

            // Output sum, advance focal point
            ST_OUTPUT: begin
                beam_valid <= 1'b1;

                if (focal_idx == FOCAL_POINTS - 1) begin
                    state <= ST_IDLE;    // done with this scan line
                end else begin
                    focal_idx <= focal_idx + 1'b1;
                    state     <= ST_ADDR;
                end
            end
        endcase
    end
end

endmodule
