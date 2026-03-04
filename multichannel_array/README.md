# 16-Channel Phased-Array Ultrasound System (Phase 2)

## System Architecture

```
16 × transducer elements (2 MHz)
        │
        ▼
16 × ADC (12-bit, 40 MSPS)  ←── SPI / LVDS interface
        │
        ▼ (adc_interface.v – per channel)
16 × channel_buffer.v   (FIFO, 1024 samples deep per channel)
        │
        ▼ (delay_calculator.v – focus point LUT)
  beamformer.v          (delay-and-sum across 16 channels)
        │
        ▼
  image_output.v        (scan-line accumulation → BRAM → host)
        │
        ▼
     Host PC            (Python image reconstruction)
```

## FPGA RTL Modules

| Module | File | Function |
|--------|------|----------|
| Top-level | `fpga/src/top.v` | Integration & clock generation |
| ADC interface | `fpga/src/adc_interface.v` | 16-ch SPI front-end, sample clock |
| Channel buffer | `fpga/src/channel_buffer.v` | Per-channel FIFO, depth-gated |
| Delay calculator | `fpga/src/delay_calculator.v` | Focus-delay LUT for each (ch, focal_pt) |
| Beamformer | `fpga/src/beamformer.v` | Delay-and-sum, output one scan line |
| Image output | `fpga/src/image_output.v` | Accumulate lines → BRAM, DMA to host |

## Python Simulation

| Script | Purpose |
|--------|---------|
| `simulation/beamforming_sim.py` | Full DAS simulation – generates synthetic echoes, applies delays, sums |
| `simulation/image_reconstruction.py` | Convert beamformed RF lines to envelope-detected B-scan image |

## Parameters

| Parameter | Value |
|-----------|-------|
| Channels | 16 |
| Transducer frequency | 2 MHz |
| ADC sample rate | 40 MSPS |
| ADC resolution | 12 bit |
| Focal points per line | 256 |
| Speed of sound | 1540 m/s |
| Element pitch | 0.385 mm (λ/2 at 2 MHz) |
| FPGA | Xilinx Artix-7 (XC7A100T) |

## Running the Python Simulation

```bash
pip install numpy scipy matplotlib
# Full beamforming simulation → saves beamformed_image.png
python multichannel_array/simulation/beamforming_sim.py

# Image reconstruction only (reads beamformed RF data from file)
python multichannel_array/simulation/image_reconstruction.py
```

## Running Tests

```bash
pip install pytest numpy scipy
pytest multichannel_array/tests/
```
