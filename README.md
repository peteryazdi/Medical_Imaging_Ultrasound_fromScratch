# Multi-Channel Ultrasound Imaging Device

## Overview

This repository documents the design and development of an educational ultrasound imaging platform built from the ground up. The long-term goal is to progress from a **single-channel 5 MHz analog ultrasound front end** to a **multi-channel digital beamforming system** capable of acquiring raw radio-frequency (RF) echo data, transferring that data into an FPGA, and ultimately producing a visual ultrasound image.

This project is motivated by an interest in:

- ultrasound and medical imaging physics
- piezoelectric transducer characterization and pulse-echo operation
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

Filtering helps suppress out-of-band noise, low-frequency drift, and transmit feedthrough while preserving the useful echo band near the transducer's operating frequency.

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
Transducer Array
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

## Array Size Considerations

Before committing to an array architecture, a few basic calculations help frame the design space. These are rough first-order estimates to guide Rev 0 characterization goals and inform the Rev 2 multi-channel expansion.

### Wavelength and Element Pitch

At 5 MHz in soft tissue:

```text
λ = c / f = 1540 / 5,000,000 ≈ 0.308 mm
```

The Nyquist spatial sampling criterion for a phased array requires element pitch ≤ λ/2 to avoid grating lobes:

```text
pitch ≤ λ/2 ≈ 0.154 mm
```

For a linear array, a looser pitch of ~λ (≈ 0.3 mm) is often acceptable if the array is not steered to large angles.

### Element Count and Field of View

The lateral resolution and field of view both scale with array aperture. For a simple linear scan, the active aperture determines lateral beamwidth at depth. As a rough guide:

```text
lateral resolution ≈ λ × (depth / aperture)
```

For example, targeting ~1 mm lateral resolution at 30 mm depth:

```text
aperture ≈ λ × depth / resolution = 0.308 × 30 / 1 ≈ 9.2 mm
```

At a pitch of ~0.3 mm (≈ λ), this implies roughly **30 elements** for that aperture. At λ/2 pitch (~0.154 mm), the same aperture would require ~60 elements.

A practical minimum for meaningful multi-element beamforming experiments is typically **8–16 elements**. A first useful imaging array might target **16–32 elements** as a manageable scope before scaling further.

### Starting Point for This Project

The current hardware (2× single-element 5 MHz transducers) supports:

- **Rev 0**: single-element characterization and crude 2-element cross-coupling tests
- **Rev 1**: single-channel analog chain validated end-to-end
- **Rev 2**: expand to a small multi-element array (target TBD after Rev 0 measurements, likely 4–16 elements)

The exact element count and array format for Rev 2 will be determined based on measured transducer behavior, available PCB area, and analog channel complexity.

---

## Planned Development Roadmap

### Rev 0 — Probe Characterization and Transmit Circuit Bring-Up

Before committing to a final analog architecture, the purchased probes are characterized experimentally and a first crude transmit circuit is developed to drive higher-voltage excitation than the AD2 can supply.

**Probe characterization objectives**

- identify connector wiring and confirm whether Tx and Rx lines are separate
- verify continuity and basic electrical behavior of both purchased elements
- apply low-voltage test excitation (AD2) and observe resonance and ringing on the oscilloscope
- estimate center frequency, bandwidth, and damping from the ring-down response
- perform cross-coupling test: drive one element, receive on the other through a gel path
- confirm both purchased units function as expected before committing to a circuit architecture
- begin evaluating transducer specifications (impedance, capacitance, frequency response) needed to inform the Tx driver design
- assess what element count and array geometry is feasible based on the characterized element behavior

**Transmit circuit objectives (crude Tx for characterization)**

- design a variable-voltage, variable-pulse-width impulse transmit circuit to replace the AD2 for excitation
- target enough voltage swing to produce a clearly observable acoustic pulse (typically 50–200 V for these transducer types, to be confirmed)
- keep the design intentionally simple: the goal is characterization, not production
- verify that the crude Tx can drive the transducer without damage
- use the crude Tx + oscilloscope scope Rx to observe real echo responses and inform Rev 1 design

**Expected outputs**

- measured center frequency and ring-down time for both transducers
- estimated electrical impedance at resonance
- oscilloscope captures of Tx pulse and Rx echo waveform with gel coupling
- first estimate of usable element count and array pitch for Rev 2
- a working variable-gain/variable-pulse Tx circuit as a characterization tool

This revision exists to ensure the purchased hardware is fully understood before designing the complete analog front end.

---

### Rev 1 — Single-Channel Analog Front End (Tx + Rx)

This is the first complete analog hardware revision. The design must be forward-compatible with multi-channel expansion in Rev 2 — channel architecture, gain structure, filtering, and layout should all be planned with replication in mind.

**Transmit chain**

- build a single-channel high-voltage transmit circuit capable of driving the characterized transducer
- design a short, controlled excitation pulse at the transducer's resonant frequency
- implement Tx/Rx switching or protection to isolate the receive path during transmit

**Receive chain**

- input protection against transmit feedthrough and cable transients
- low-noise amplifier (LNA) sized for the transducer's source impedance and expected echo levels
- band-pass filter centered near 5 MHz to reject out-of-band noise and low-frequency drift
- optional additional gain stage or TGC-compatible gain control

**Design constraints for multi-channel compatibility**

- single-supply or dual-supply architecture that can scale to multiple channels without redesign
- grounding and shielding approach evaluated for channel-to-channel isolation
- signal path gain and bandwidth consistent across future replicated channels
- connectorization and layout planned to support a modular or daughterboard expansion in Rev 2

**Expected outputs**

- repeatable excitation waveform on scope
- measurable receive waveform with identifiable echo
- documented gain structure from transducer to analog output
- clean analog output signal ready for ADC digitization
- Rev 1 design confirmed compatible with multi-channel expansion

---

### Rev 2 — Multi-Channel Analog Expansion and Comparative Testing

Once the single-channel analog path is trusted, the architecture is replicated and verified across multiple channels. This revision also serves as the first opportunity to compare single-channel and multi-channel acquisition side by side.

**Expansion goals**

- replicate the Rev 1 single-channel front end across N channels (target count informed by Rev 0 array analysis, likely 4–16 channels)
- confirm that gain, bandwidth, and noise floor remain consistent channel to channel
- evaluate power distribution, common-mode interference, and grounding at multi-channel scale
- test channel-to-channel isolation: verify that transmit on one channel does not corrupt receive on adjacent channels

**Single vs. multi-channel comparison**

- acquire data with one active channel and with multiple channels simultaneously
- compare SNR, echo amplitude consistency, and noise floor between configurations
- identify any channel-dependent gain or phase mismatches that will need correction in beamforming
- document what improves with more channels (lateral resolution, SNR after coherent summation) versus what stays the same

**Expected outputs**

- multi-channel analog board with documented per-channel performance
- side-by-side single vs. multi-channel waveform captures
- gain and phase characterization per channel
- architecture confirmed ready for ADC integration

---

### Rev 3 — ADC Integration and Communication Protocol to FPGA

This revision introduces real digitization and establishes the communication link between the ADC and FPGA.

**ADC selection and bring-up**

- choose an ADC appropriate for 5 MHz RF sampling (minimum ~4× oversampling → 20+ MSPS; 40–80 MSPS preferred for signal quality)
- validate sample fidelity: compare digitized waveforms against oscilloscope captures
- confirm SNR, SFDR, and aliasing behavior with known test signals
- verify timing, logic levels, and data format before integrating with FPGA

**Communication protocol**

- select and implement a data interface between ADC and FPGA (SPI, LVDS parallel, or similar)
- verify data integrity end-to-end: ADC input → interface → FPGA receive buffer
- confirm interface bandwidth is sufficient for multi-channel data rates
- save captured raw RF frames for offline analysis and algorithm development

**Expected outputs**

- digitized RF waveforms from at least one channel
- verified ADC-to-FPGA data link
- raw sample files suitable for offline processing
- communication architecture documented and confirmed scalable to multi-channel

---

### Rev 4 — FPGA Learning, Pipeline Development, Beamforming, and Visualization

This final revision builds out the digital signal processing pipeline and produces the first interpretable imaging outputs.

**FPGA learning and setup**

- establish the FPGA development environment and toolchain
- learn HDL fundamentals relevant to data capture and DSP pipelines
- implement raw sample capture: buffer data, confirm read/write correctness
- build a simple loopback or pattern-check test to validate the receive pipeline before processing real data

**DSP pipeline**

- implement digital band-pass filtering on captured RF data
- build envelope detection (Hilbert transform or rectify + low-pass)
- implement delay-and-sum beamforming across channels
- learn how timing delays map to array geometry and steering angle

**Visualization**

- display A-scan (single-line time-domain) data first as a sanity check
- progress toward B-scan (2D image) reconstruction
- display results on a host computer via USB/Ethernet or on a connected display
- compare raw RF, filtered, envelope-detected, and beamformed outputs to build intuition for what each processing stage contributes
- validate that the system produces a recognizable image of a simple phantom or test target

This revision represents the full transition from ultrasound electronics to ultrasound imaging.

---

## Current Starting Point

- two purchased 5 MHz single-element transducers for Rev 0 characterization
- initial low-voltage characterization performed with an AD2 (resonance observed, both channels functional)
- need for higher-voltage excitation identified; crude variable-gain Tx circuit to be designed in Rev 0
- theory and architecture work in progress in parallel with hardware

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

Current status: **Rev 0 — probe characterization and crude Tx circuit design in progress**.

Near-term work:

- complete transducer characterization (frequency, impedance, damping)
- design variable-voltage impulse Tx circuit for higher-excitation characterization
- document all Rev 0 measurements before beginning Rev 1 design
- begin outlining Rev 1 analog front-end architecture based on measured data

---

## Author

**Peter Yazdi**

For questions, please feel free to email: `peteryazdi@gmail.com`
