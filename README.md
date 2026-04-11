# Multi-Channel Ultrasound Imaging Device

## Overview

This repository documents the design and development of a custom ultrasound imaging platform. The system progresses from a single-channel 5 MHz analog front end to a multi-channel digital beamforming system capable of acquiring raw RF echo data, processing it on an FPGA, and producing ultrasound images.

The project covers transducer characterization, high-voltage pulse generation, low-noise receive electronics, analog-to-digital conversion, and FPGA-based signal processing.

---

## Current Status

**Rev 0 complete. Rev 1 schematic complete — PCB layout in progress.**

### Completed

- Two 5 MHz thickness-gauge transducers purchased and characterized
- Center frequency confirmed at 5.000 MHz via oscilloscope cursor measurement
- Both channels verified functional using AD2 impulse excitation
- Ring-down and cross-coupling observed through gel-coupled water path
- Rev 1 8-channel Tx/Rx schematic designed and ERC-clean in KiCad

### Rev 1 Hardware Design

The Rev 1 board is an 8-channel transmit pulser with passive receive protection, designed around the MD1213 gate driver and TC6320 complementary MOSFET pair (Microchip).

**Per channel:**
- MD1213 dual MOSFET gate driver (VQFN-12, ±5V bipolar supply)
- TC6320 N+P MOSFET pair (SOIC-8, 200V BVDSS)
- 10nF/200V AC coupling capacitors (OUTA→GP, OUTB→GN)
- 1μF/200V storage capacitors per HV rail with 1MΩ bleed resistors
- 0.47μF/16V bypass capacitors on ±5V driver supply
- Back-to-back clamp diodes (300V rated) for Tx protection
- 200Ω series resistor + back-to-back clamp diodes to GND for Rx protection
- 1MΩ DC bias resistor on Tx/Rx node
- 10kΩ pull-down on OE (outputs disabled by default)
- SMA vertical connector per channel (SMA-to-Lemo adapter for current transducers)

**Power supply (bench supply fed via screw terminals):**
- ±100V HV rails: 10μF electrolytic + 1μF ceramic + 1MΩ bleed per rail
- ±5V LV rails: 10μF ceramic per rail
- Dedicated GND screw terminal

**Control and I/O:**
- 2×14 pin header for FPGA connection (8× INA, INB, OE + TRIG_OUT, TRIG_IN, GND)
- 33Ω series resistors on all logic inputs
- 2×8 pin header for Rx output (8 channels with alternating GND pins)
- LED indicators: +5V power (green), +100V power (red), trigger activity (yellow), OE status (blue)

---

## Key Specifications

| Parameter | Value |
|---|---|
| Transducer frequency | 5 MHz |
| Pulse type | Bipolar, 1 cycle (200 ns) |
| HV supply range | ±5V to ±100V (variable via bench supply) |
| Number of Tx/Rx channels | 8 |
| MOSFET breakdown voltage | 200V (TC6320) |
| Gate drive swing | ±5V (10V total, AC coupled) |
| Rise time (500pF load) | ~8 ns |
| Peak current (100V, 7Ω RDS) | 14.3A instantaneous |
| Rx clamp voltage | ±0.7V |
| Dead zone (200Ω Rx series) | < 0.1 mm |
| Max imaging depth at 7700 Hz PRF | 10 cm |
| Axial resolution (theoretical) | 0.154 mm |
| Power dissipation per TC6320 | ~17 mW |

---

## Development Roadmap

| Revision | Scope | Status |
|---|---|---|
| Rev 0 | Transducer characterization, initial impulse testing | Complete |
| Rev 1 | 8-channel Tx pulser + passive Rx protection, scope-based echo measurement | Schematic complete, PCB layout in progress |
| Rev 2 | Multi-channel Rx analog chain (LNA, bandpass filter, TGC) on separate board | Planned |
| Rev 3 | ADC integration, digitization of RF echo data | Planned |
| Rev 4 | FPGA DSP pipeline: filtering, envelope detection, delay-and-sum beamforming | Planned |
| Rev 5 | A-scan and B-scan visualization, phantom imaging | Planned |

---

## Hardware

### Transducers
- 5 MHz thickness-gauge transducers (Amazon, 2 units)
- Lemo connectors, connected via SMA-to-Lemo adapter cables
- Used for both Tx and Rx in pitch-catch configuration

### Test Equipment
- Digilent Analog Discovery 2 (AD2) — initial low-voltage impulse source
- Tektronix TDS 2014 oscilloscope — waveform capture and measurement
- Ultrasound coupling gel

---

## Physics Reference

| Quantity | Formula | Value at 5 MHz |
|---|---|---|
| Wavelength | λ = c / f | 0.308 mm |
| Axial resolution | c / (2f) per cycle | 0.154 mm |
| Depth from echo time | d = ct / 2 | 0.77 mm/μs |
| Max PRF | c / (2 × d_max) | 7700 Hz at 10 cm |
| Attenuation | ~0.5 dB/cm/MHz | 2.5 dB/cm |
| Sound speed (soft tissue) | — | 1540 m/s |

---

## Safety

This is an educational project, not a certified medical device. The system is not intended for diagnostic or clinical use. High-voltage circuits require appropriate safety practices. All testing is performed on phantoms, water-path setups, and non-clinical targets.

---

## Author

Peter Yazdi — peteryazdi@gmail.com