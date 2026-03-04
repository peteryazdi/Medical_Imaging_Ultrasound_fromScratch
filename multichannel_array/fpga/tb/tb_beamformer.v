// tb_beamformer.v – Verilog testbench for the delay-and-sum beamformer
//
// Injects synthetic echo data (a point reflector at depth z = 30 mm,
// lateral position x = 0) into 16 channel_buffer instances, then
// triggers the beamformer and checks that the peak output sample
// occurs at the correct focal-point index.

`timescale 1ns / 1ps

module tb_beamformer;

// ── Parameters matching DUT ──────────────────────────────────────────────
localparam NUM_CH       = 16;
localparam SAMPLE_WIDTH = 12;
localparam FIFO_DEPTH   = 1024;
localparam FOCAL_POINTS = 256;
localparam ADDR_W       = $clog2(FIFO_DEPTH);
localparam FOCAL_W      = $clog2(FOCAL_POINTS);
localparam SUM_W        = SAMPLE_WIDTH + 4;

// ── Physical / simulation parameters ────────────────────────────────────
localparam real C_SOUND  = 1540.0;   // m/s
localparam real FS       = 40.0e6;   // samples/s
localparam real PITCH    = 0.000385; // m  (λ/2 at 2 MHz)
localparam real Z_FOCAL  = 0.030;    // m  point reflector depth
localparam real X_FOCAL  = 0.0;      // m  on-axis

// ── Clock & reset ────────────────────────────────────────────────────────
reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;   // 100 MHz

// ── DUT signals ──────────────────────────────────────────────────────────
reg  [SAMPLE_WIDTH-1:0] ch_data   [0:NUM_CH-1];
reg  [9:0]              delay_tap [0:NUM_CH-1];
reg  [ADDR_W-1:0]       wr_ptr;
reg                     acq_done;

wire [ADDR_W-1:0]  ch_rd_addr [0:NUM_CH-1];
wire [SUM_W-1:0]   beam_sum;
wire               beam_valid;
wire [FOCAL_W-1:0] focal_idx;

// ── DUT instantiation ────────────────────────────────────────────────────
beamformer #(
    .NUM_CH       (NUM_CH),
    .SAMPLE_WIDTH (SAMPLE_WIDTH),
    .FIFO_DEPTH   (FIFO_DEPTH),
    .FOCAL_POINTS (FOCAL_POINTS)
) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .acq_done   (acq_done),
    .ch_data    (ch_data),
    .ch_rd_addr (ch_rd_addr),
    .delay_tap  (delay_tap),
    .wr_ptr     (wr_ptr),
    .beam_sum   (beam_sum),
    .beam_valid (beam_valid),
    .focal_idx  (focal_idx)
);

// ── Per-channel sample RAM (models channel_buffer) ───────────────────────
reg [SAMPLE_WIDTH-1:0] ch_mem [0:NUM_CH-1][0:FIFO_DEPTH-1];

integer i;
// Drive ch_data from ch_mem addressed by ch_rd_addr
always @(posedge clk) begin
    for (i = 0; i < NUM_CH; i = i + 1) begin
        ch_data[i] <= ch_mem[i][ch_rd_addr[i]];
    end
end

// ── Helper: compute expected sample delay for channel ch ─────────────────
function automatic integer expected_delay;
    input integer ch;
    real x_elem, r_elem, delta_r;
    begin
        x_elem   = (ch - (NUM_CH-1)/2.0) * PITCH;
        r_elem   = $sqrt(x_elem*x_elem + Z_FOCAL*Z_FOCAL);
        delta_r  = r_elem - Z_FOCAL;
        expected_delay = $rtoi(delta_r / C_SOUND * FS + 0.5);
    end
endfunction

// ── Pre-compute expected focal index for the on-axis reflector ───────────
// focal_idx maps to depth: z = focal_idx * C_SOUND / (2 * FS)
// For z=30 mm → focal_idx = round(2*FS*z/C_SOUND)
localparam integer EXPECTED_FOCAL = $rtoi(2.0 * 40.0e6 * 0.030 / 1540.0 + 0.5);

// ── Stimulus: synthesise a Gaussian pulse echo in each channel ───────────
integer ch, s;
real    x_elem, r_elem, t_echo, pulse_ctr;
integer delay_samples;

task fill_channel_memories;
    integer ch_t, s_t;
    real    x_e, r_e, t_e, pctr;
    integer d_s;
    begin
        for (ch_t = 0; ch_t < NUM_CH; ch_t = ch_t + 1) begin
            x_e  = (ch_t - (NUM_CH-1)/2.0) * PITCH;
            r_e  = $sqrt(x_e*x_e + Z_FOCAL*Z_FOCAL);
            t_e  = 2.0 * r_e / C_SOUND;   // two-way travel time
            d_s  = $rtoi(t_e * FS);        // arrival sample index
            // Fill memory with zeros, then a Gaussian pulse at d_s
            for (s_t = 0; s_t < FIFO_DEPTH; s_t = s_t + 1) begin
                // Gaussian envelope * cosine carrier at 2 MHz
                pctr = (s_t - d_s) / 4.0;   // sigma = 4 samples
                if ((s_t >= d_s - 20) && (s_t <= d_s + 20)) begin
                    ch_mem[ch_t][s_t] = $rtoi(2047.0 * $exp(-pctr*pctr) *
                                              $cos(2.0*3.14159*2.0e6/FS*s_t) + 2048);
                end else begin
                    ch_mem[ch_t][s_t] = 12'd2048;  // mid-scale (no signal)
                end
            end
            // Provide the delay_tap for this channel
            delay_tap[ch_t] = expected_delay(ch_t);
        end
        wr_ptr = FIFO_DEPTH - 1;  // buffer is full
    end
endtask

// ── Test ─────────────────────────────────────────────────────────────────
integer       fp;
integer       peak_focal;
reg [SUM_W-1:0] peak_val;

initial begin
    $dumpfile("tb_beamformer.vcd");
    $dumpvars(0, tb_beamformer);

    rst_n    = 0;
    acq_done = 0;
    for (i = 0; i < NUM_CH; i = i + 1) delay_tap[i] = 10'd0;
    wr_ptr   = {ADDR_W{1'b0}};
    @(posedge clk); @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // Load synthetic echo data into channel memories
    fill_channel_memories;

    // Signal that acquisition is done → trigger beamformer
    @(posedge clk);
    acq_done = 1;
    @(posedge clk);
    acq_done = 0;

    // Collect beamformer output and find the peak
    peak_val   = 0;
    peak_focal = 0;
    for (fp = 0; fp < FOCAL_POINTS; fp = fp + 1) begin
        @(posedge clk);
        if (beam_valid) begin
            if (beam_sum > peak_val) begin
                peak_val   = beam_sum;
                peak_focal = focal_idx;
            end
        end
    end

    // Wait a few more cycles for pipeline to flush
    repeat (20) @(posedge clk);

    // ── Check ─────────────────────────────────────────────────────────────
    $display("Expected focal index: %0d", EXPECTED_FOCAL);
    $display("Observed peak focal : %0d (beam_sum = %0d)", peak_focal, peak_val);

    if ((peak_focal >= EXPECTED_FOCAL - 2) && (peak_focal <= EXPECTED_FOCAL + 2)) begin
        $display("PASS: beamformer peak within ±2 samples of expected focal point.");
    end else begin
        $display("FAIL: peak at %0d, expected near %0d.", peak_focal, EXPECTED_FOCAL);
        $finish(1);
    end

    $finish;
end

// ── Timeout watchdog ─────────────────────────────────────────────────────
initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish(1);
end

endmodule
