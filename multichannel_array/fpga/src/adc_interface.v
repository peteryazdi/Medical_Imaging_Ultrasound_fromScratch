// adc_interface.v – SPI front-end for one 12-bit ADC channel
//
// Supports AD7476A-style 16-bit SPI frame containing one 12-bit sample.
// SCLK is derived by dividing clk by CLK_DIV (default 40 MHz ADC rate
// from a 200 MHz SCLK would require CLK_DIV = 5 – adjust to your clock).
//
// Frame format (AD7476A):
//   Bit 15-14: leading zeros
//   Bit 13-12: null bits
//   Bit 11-0:  12-bit sample (MSB first)

`timescale 1ns / 1ps

module adc_interface #(
    parameter SAMPLE_WIDTH = 12,  // ADC resolution
    parameter CLK_DIV      = 5    // sys_clk / CLK_DIV = SCLK frequency
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   acq_en,       // start acquisition pulse

    // SPI pins
    output reg                    sclk,
    output reg                    csn,
    input  wire                   miso,

    // Parallel output
    output reg  [SAMPLE_WIDTH-1:0] sample_out,
    output reg                     sample_valid
);

// ── State machine ──────────────────────────────────────────────────────────
localparam ST_IDLE    = 2'd0;
localparam ST_CS_SETUP= 2'd1;
localparam ST_CAPTURE = 2'd2;
localparam ST_CS_HOLD = 2'd3;

reg [1:0]  state;
reg [4:0]  clk_cnt;   // clock divider counter
reg [4:0]  bit_cnt;   // counts 16 SCLK cycles
reg [15:0] shift_reg; // serial shift register
reg        sclk_en;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= ST_IDLE;
        sclk         <= 1'b1;
        csn          <= 1'b1;
        clk_cnt      <= 5'd0;
        bit_cnt      <= 5'd0;
        shift_reg    <= 16'h0;
        sample_out   <= {SAMPLE_WIDTH{1'b0}};
        sample_valid <= 1'b0;
        sclk_en      <= 1'b0;
    end else begin
        sample_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                sclk    <= 1'b1;
                csn     <= 1'b1;
                clk_cnt <= 5'd0;
                bit_cnt <= 5'd0;
                if (acq_en) begin
                    state <= ST_CS_SETUP;
                end
            end

            // Assert CSN, wait one SCLK half-period
            ST_CS_SETUP: begin
                csn <= 1'b0;
                if (clk_cnt == CLK_DIV - 1) begin
                    clk_cnt <= 5'd0;
                    state   <= ST_CAPTURE;
                end else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            // Clock 16 bits in, MSB first, capture on falling SCLK edge
            ST_CAPTURE: begin
                if (clk_cnt == CLK_DIV/2 - 1) begin
                    sclk    <= 1'b0;            // falling edge
                    shift_reg <= {shift_reg[14:0], miso}; // sample MISO
                    clk_cnt   <= clk_cnt + 1'b1;
                end else if (clk_cnt == CLK_DIV - 1) begin
                    sclk    <= 1'b1;            // rising edge
                    clk_cnt <= 5'd0;
                    bit_cnt <= bit_cnt + 1'b1;
                    if (bit_cnt == 5'd15) begin
                        state <= ST_CS_HOLD;
                    end
                end else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            // Deassert CSN, output parallel sample
            ST_CS_HOLD: begin
                csn          <= 1'b1;
                sample_out   <= shift_reg[SAMPLE_WIDTH-1:0];
                sample_valid <= 1'b1;
                state        <= ST_IDLE;
            end
        endcase
    end
end

endmodule
