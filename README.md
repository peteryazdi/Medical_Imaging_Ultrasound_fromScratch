# Medical Imaging Ultrasound System

Multi-Channel Ultrasound Imaging System – ongoing development of a portable, high-resolution
ultrasound imager progressing from a single-element prototype to a 16-channel phased array.

---

## Project Overview

### Phase 1 – Single-Transducer System (Complete)

- Custom PCB with **MSP430** microcontroller
- **5 MHz** single-element transducer
- Pulse-echo acquisition at ADC rate limits
- Amplitude (envelope) detection to produce a low-resolution A-scan / B-scan image
- Demonstrates skin-vs-bone contrast at shallow depths

### Phase 2 – 16-Channel Phased Array (In Development)

- **16-channel, 2 MHz** ultrasound transducer array
- **FPGA-based** acquisition and real-time processing pipeline
- Delay-and-sum (**DAS**) beamforming across all 16 channels
- Significantly improved lateral resolution and image quality versus the single-element prototype

---

## Repository Layout

```
.
├── single_transducer/          # Phase 1 – MSP430 single-element system
│   ├── README.md
│   └── msp430/
│       ├── ultrasound_main.c   # Main firmware (pulse-tx + ADC capture)
│       └── amplitude_detect.c  # Envelope / amplitude detection
│
└── multichannel_array/         # Phase 2 – 16-channel FPGA system
    ├── README.md
    ├── fpga/
    │   ├── src/                # Synthesisable RTL (Verilog)
    │   │   ├── top.v               # Top-level integration
    │   │   ├── adc_interface.v     # SPI/LVDS ADC front-end (×16)
    │   │   ├── channel_buffer.v    # Per-channel sample FIFO
    │   │   ├── delay_calculator.v  # Focus delay LUT generator
    │   │   ├── beamformer.v        # Delay-and-sum beamformer
    │   │   └── image_output.v      # Scan-line output / BRAM controller
    │   ├── tb/                 # Verilog test-benches
    │   │   └── tb_beamformer.v
    │   └── constraints/
    │       └── timing.xdc      # Xilinx timing constraints (example)
    ├── simulation/             # Python behavioural simulation
    │   ├── beamforming_sim.py      # DAS beamforming model
    │   └── image_reconstruction.py # B-scan image builder
    └── tests/
        └── test_beamforming.py     # pytest unit tests
```

---

## Quick Start – Python Simulation

```bash
pip install numpy scipy matplotlib
python multichannel_array/simulation/beamforming_sim.py
```

This runs a full end-to-end DAS beamforming simulation and saves `beamformed_image.png`.

---

## Hardware Overview (Phase 2)

| Parameter        | Value              |
|------------------|--------------------|
| Channels         | 16                 |
| Transducer freq. | 2 MHz              |
| Sampling rate    | 40 MSPS (20× over) |
| ADC resolution   | 12 bit             |
| FPGA family      | Xilinx Artix-7     |
| Beamforming      | Delay-and-Sum (DAS)|
| Speed of sound   | 1540 m/s (soft tissue) |

---

## License

MIT
