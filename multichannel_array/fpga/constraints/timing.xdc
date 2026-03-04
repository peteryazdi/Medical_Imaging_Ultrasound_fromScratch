# timing.xdc – Example Xilinx Artix-7 timing constraints
# Adjust pin locations and I/O standards for your specific PCB.

# ── Primary system clock: 100 MHz ────────────────────────────────────────
create_clock -period 10.000 -name clk_sys [get_ports clk_sys]

# ── ADC SPI clock (derived from clk_sys / 5 = 20 MHz SCLK) ──────────────
# The adc_interface module generates sclk internally; mark it as generated.
create_generated_clock -name adc_sclk \
    -source [get_ports clk_sys] \
    -divide_by 5 \
    [get_pins {gen_adc[*].u_adc/sclk_reg/Q}]

# ── Input delay for MISO lines (SPI Mode 0, ~10 ns data valid after SCLK) ─
set_input_delay -clock adc_sclk -max 8.0 [get_ports {adc_miso[*]}]
set_input_delay -clock adc_sclk -min 2.0 [get_ports {adc_miso[*]}]

# ── Output delay for SPI CS and SCLK ─────────────────────────────────────
set_output_delay -clock clk_sys -max 2.0 [get_ports {adc_csn[*]}]
set_output_delay -clock clk_sys -min 0.5 [get_ports {adc_csn[*]}]

# ── TX trigger (single-cycle pulse, relaxed timing) ───────────────────────
set_output_delay -clock clk_sys -max 5.0 [get_ports tx_trigger]

# ── False paths across acquisition / beamform boundary ───────────────────
# The acq_done flag crosses from write-domain to read-domain with a
# registered handshake; treat as a false path for timing analysis.
set_false_path -from [get_cells {u_seq/acq_done_reg}] \
               -to   [get_cells {u_beam/*}]
