# Multi-Channel Ultrasound Imaging Device

## Overview

This repository documents the design and development of an educational ultrasound imaging platform built from the ground up. The long-term goal is to progress from a **single-channel 5 MHz analog ultrasound front end** to a **multi-channel digital beamforming system** capable of acquiring raw radio-frequency (RF) echo data, transferring that data into an FPGA, and ultimately producing a visual ultrasound image.

This project is motivated by an interest in:

- ultrasound and medical imaging physics
- piezoelectric transducers and pulse-echo operation
- high-voltage pulse generation and receive protection
- low-noise analog front-end design
- filtering and gain control for weak, high-frequency signals
- analog-to-digital conversion for RF data capture
- FPGA-based digital signal processing and beamforming
- end-to-end imaging system design

The project is intentionally staged so that each revision builds understanding of one subsystem before introducing the next level of complexity. The first major milestone is not full imaging, but a **working single-channel transmit/receive analog chain up to the ADC**.

---

## Project Purpose

Modern ultrasound systems combine acoustics, high-voltage excitation, low-noise analog electronics, high-speed data acquisition, digital signal processing, and image formation algorithms. This project is driven by the goal of understanding those subsystems from first principles rather than treating ultrasound as a closed commercial technology.

The purpose of this repository is to serve as a technical foundation for the physics, engineering, implementation, and testing of a custom ultrasound imaging device. As development progresses, this repository will collect theory notes, simulations, hardware documentation, software and firmware, measurements, and revision-specific design history.

---

## Physics Summary

Ultrasound imaging works by transmitting a short acoustic pulse into a medium and listening for returning echoes from boundaries where material properties change.

### Wave Propagation

Ultrasound is a mechanical longitudinal pressure wave. In soft tissue, a common approximation for sound speed is:

```text
c ≈ 1540 m/s
```

Its wavelength is given by:

```text
λ = c / f
```

For a 5 MHz wave in soft tissue:

```text
λ ≈ 1540 / 5,000,000 ≈ 0.308 mm
```

This short wavelength is one reason ultrasound can resolve relatively fine structures.

### Acoustic Impedance and Echoes

Reflections occur when a wave encounters a boundary between materials with different acoustic impedances:

```text
Z = ρc
```

A large impedance mismatch causes a stronger reflection. This is why air gaps are such a problem and why gel coupling matters.

For pulse-echo systems, echo arrival time can be converted into approximate depth using:

```text
d = ct / 2
```

where the factor of 2 accounts for the round-trip travel path.

### Piezoelectric Transducers

Piezoelectric transducers convert electrical energy into mechanical vibration during transmit, and mechanical vibration back into electrical signals during receive. In practice, real transducers also have resonance, bandwidth limits, electrical capacitance, ringing, damping behavior, and coupling losses.

### Why Pulse-Echo Matters

For imaging, the transducer is usually excited with a **short high-voltage pulse** or a **very short burst**, not a continuous sine wave. That brief excitation launches an acoustic pulse and the system then transitions into receive mode to capture echoes. Shorter pulses generally improve axial resolution, while excessive ringing can make shallow echoes harder to detect.

For deeper theory, see the `theory` branch.

---

## Engineering System Summary

The project applies several major hardware and signal-processing ideas.

### High-Voltage Transmit Pulse

The transmit side must excite the transducer strongly enough to launch a measurable acoustic pulse. Early work will focus on controlled short-pulse excitation rather than continuous drive.

### Receive Protection and Low-Noise Amplification

Echoes are often very small, so the receive path must protect sensitive electronics while amplifying weak high-frequency signals without adding too much noise.

### Band-Pass Filtering

Filtering helps suppress out-of-band noise, low-frequency drift, and transmit feedthrough while preserving the useful echo band near the transducer’s operating frequency.

### Time Gain Compensation (TGC)

As echoes arrive later in time, they often become weaker due to attenuation and propagation loss. TGC is a depth-dependent gain strategy used to boost later echoes more than earlier ones.

### Analog-to-Digital Conversion (ADC)

The ADC is the bridge between the analog and digital halves of the system. It must sample the RF waveform with enough rate, resolution, and timing quality to preserve useful information.

### FPGA Processing

An FPGA is well suited to ultrasound because it can capture multiple high-speed data streams in parallel, maintain deterministic timing, and later support filtering, delay-and-sum operations, envelope detection, and beamforming.

For deeper subsystem explanations, see the `theory`, `hardware`, `software/firmware`, and `simulations/testing` branches.

---

## System Architecture

The long-term signal path of the project is expected to resemble:

```text
Transducer(s)
   → transmit pulser / Tx-Rx switching
   → receive protection
   → low-noise amplification
   → band-pass filtering
   → optional variable gain / TGC
   → ADC
   → FPGA capture and DSP
   → beamforming / envelope detection / scan conversion
   → host PC or display visualization
```

---

## Planned Development Roadmap

The roadmap below reflects the intended progression of the project and is expected to evolve as real hardware data is collected.

### Rev 0 — Probe Characterization

Before committing to a final analog architecture, the purchased probe should be characterized experimentally.

**Objectives**

- identify the wiring and determine whether Tx and Rx lines are truly separate
- verify continuity and basic electrical behavior
- apply low-voltage test excitation first
- observe whether one element can excite the other in a controlled setup
- estimate center frequency and ringing behavior on the oscilloscope
- determine how strongly the probe couples through gel and simple test media
- confirm that the purchased hardware functions as expected

This revision exists to prevent designing too much circuitry around an unverified transducer.

### Rev 1 — Single-Channel Analog Front End to the ADC

This is the first major hardware revision.

**Goals**

- build a single-channel 5 MHz transmit circuit
- excite the probe using a short high-voltage pulse
- use the same physical probe housing for transmit and receive
- exploit separate Tx/Rx leads if the probe already provides them
- design a receive chain with:
  - input protection
  - low-noise amplification
  - band-pass filtering
  - optional gain staging
- produce a clean analog signal suitable for digitization up to the ADC input

**Expected output**

- repeatable excitation waveform
- measurable receive waveform
- known gain structure
- scoped analog echo response
- candidate signal ready for digitization

### Rev 1.5 — Measurement and Test Infrastructure

This stage formalizes how the hardware will be evaluated.

**Goals**

- create repeatable test targets and phantoms
- define standard oscilloscope measurement procedures
- record pulse width, ringing time, noise floor, and echo amplitude
- save captured waveforms for offline analysis
- build scripts for plotting time-domain response

A measurement workflow is as important as the circuit itself. Without repeatable tests, later revisions become difficult to compare objectively.

### Rev 2 — Multi-Channel Analog Expansion

Once the single-channel path is trusted, the analog architecture should begin evolving toward multi-channel scalability.

**Goals**

- redesign the single-channel analog path with replication in mind
- evaluate how power, grounding, and shielding scale across channels
- preserve consistent gain and bandwidth across channels
- consider modular front-end blocks or daughterboards for easier debugging
- maintain compatibility with later ADC integration

### Rev 3 — ADC Integration

This revision introduces real digitization.

**Single-channel target**

- choose an ADC appropriate for 5 MHz RF sampling
- validate sample quality
- confirm timing, logic levels, and data extraction
- save raw RF data for offline analysis

**Multi-channel target**

- transition from one sampled channel to multiple synchronized channels
- ensure the data format and interface can scale toward FPGA capture
- verify that the communication architecture does not become the system bottleneck

### Rev 4 — FPGA Pipeline

This stage focuses on the digital interface between the ADC and FPGA, followed by the first beamforming-oriented processing pipeline.

**Goals**

- establish reliable communication between ADC and FPGA
- implement raw sample capture pipelines
- buffer and move data correctly
- begin digital filtering and basic signal conditioning
- build the foundations for delay-and-sum beamforming
- learn how raw RF data becomes an imaging pipeline

### Rev 5 — Visualization

This stage turns measured and processed data into something interpretable.

**Goals**

- visualize A-scan data first
- progress toward B-scan style outputs
- display results on a host computer or dedicated display
- compare raw RF, filtered, envelope-detected, and beamformed data
- build intuition for what the system is actually measuring

This stage represents the transition from ultrasound electronics to ultrasound imaging.

---

## Current Starting Point

The current prototype effort begins with:

- a purchased 5 MHz transducer/probe for initial characterization
- oscilloscope-based transmit/receive experiments
- gel-coupled testing and simple target validation
- development of a single-channel analog front end before digital integration
- theory and architecture work being developed in parallel while hardware is in transit

---

## Safety and Scope

This is an educational engineering project, not a certified medical device.

Important scope notes:

- this repository is not intended for diagnostic or clinical use
- high-voltage pulsing requires careful safety practices
- analog front-end circuits can be damaged easily by poor grounding or excessive transmit energy
- early testing should be performed on phantoms, water-path setups, or simple non-clinical targets
- development decisions should be based on measured hardware behavior rather than assumptions whenever possible

---

## Repository Status

Current status: **planning and architecture phase**.

Near-term work includes:

- organizing the theory branch
- documenting the key physics and engineering concepts
- defining measurement and characterization plans
- preparing for Rev 0 probe testing when the transducer arrives
- outlining the first single-channel analog front-end design path

---

## Author

**Peter Yazdi**

For questions, please feel free to email: `peteryazdi@gmail.com`
