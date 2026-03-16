# Multi-Channel Ultrasound Imaging Device

## Overview

This repository documents the design and development of an ultrasound imaging platform intended for **educational purposes**. The long-term goal is to progress from a **single-channel 5 MHz analog ultrasound front end** to a **multi-channel digital beamforming system** capable of capturing raw radio-frequency (RF) echo data, transferring that data into an FPGA, and ultimately producing a visual ultrasound image.

This project is motivated by an interest in:

- medical imaging physics
- piezoelectric transducers and wave propagation
- analog front-end design for weak, high-frequency signals
- high-voltage pulse generation
- analog-to-digital conversion at ultrasound frequencies
- FPGA-based signal processing and beamforming
- end-to-end imaging system architecture

The project is intentionally staged so that each revision builds practical understanding of a specific subsystem before the next level of complexity is introduced. The first milestone is not full imaging, but rather a **working single-channel transmit/receive analog chain up to the ADC**.

---

## Project Purpose

Modern ultrasound imaging systems are complex, highly integrated platforms that bring together acoustics, high-voltage excitation, low-noise analog electronics, high-speed data acquisition, digital signal processing, and image formation algorithms. This project is driven by the goal of understanding and developing these core subsystems from first principles rather than treating medical ultrasound as a closed, inaccessible technology. The purpose of this repository is to serve as a technical foundation for the physics, engineering, and implementation of a medical imaging ultrasound device. As development progresses, the relevant branches will contain simulations, hardware schematics, firmware, software, and supporting documentation needed to study, build, and refine the system.

---

## Physics Background

## 1. What Ultrasound Is

Ultrasound refers to acoustic waves above the range of human hearing. In imaging systems, ultrasound commonly operates in the megahertz range. These are **longitudinal pressure waves** that propagate through matter by alternating regions of compression and rarefaction.

For soft tissue, a standard approximation for sound speed is:

```text
c ≈ 1540 m/s
```

The wavelength of ultrasound is related to frequency by:

```text
λ = c / f
```

So for a 5 MHz wave in soft tissue:

```text
λ ≈ 1540 / 5,000,000 ≈ 0.308 mm
```

That small wavelength is one of the reasons ultrasound can resolve relatively fine structures.

### Why frequency matters

Frequency is one of the most important design choices in ultrasound.

- **Higher frequency** gives better spatial resolution.
- **Lower frequency** penetrates deeper into material or tissue.

This project is beginning at **5 MHz** because it is a practical frequency for learning high-frequency analog design while still being low enough to work with relatively accessible components and transducers.

---

## 2. Acoustic Impedance and Echo Formation

Ultrasound imaging works because sound reflects at boundaries where material properties change.

The key parameter is **acoustic impedance**:

```text
Z = ρc
```

where:

- `ρ` is material density,
- `c` is sound speed in that material.

When an ultrasonic wave hits a boundary between two materials with different impedances, some energy is transmitted and some is reflected. A larger impedance mismatch produces a stronger reflection.

This is why interfaces such as:

- gel to skin,
- soft tissue to bone,
- soft tissue to air,

produce very different echo strengths.

### Reflection coefficient

For normal incidence, the reflected intensity fraction is:

```text
R = ((Z2 - Z1) / (Z2 + Z1))^2
```

This principle is central to imaging. The transducer sends a pulse, listens for returning echoes, and the **arrival time** of those echoes reveals depth.

### Time-of-flight depth estimation

If an echo is received after time `t`, then the reflector depth is approximately:

```text
d = ct / 2
```

The factor of 2 is present because the wave must travel to the target and back.

---

## 3. Piezoelectric Transducers

Ultrasound transducers are based on the **piezoelectric effect**.

A piezoelectric material can:

- mechanically deform when a voltage is applied,
- generate a voltage when mechanically deformed.

That means the same physical element can act as both:

- a **transmitter** of ultrasound,
- a **receiver** of echoes.

When driven electrically, the transducer vibrates and launches an acoustic wave into the medium. When an echo returns, the incoming pressure wave deforms the element and creates a measurable electrical signal.

In practice, a transducer is not an ideal source. It has:

- a resonant frequency,
- finite bandwidth,
- mechanical ringing,
- electrical capacitance,
- coupling losses,
- sensitivity limits,
- dependence on backing, damping, and matching layers.

---

## 4. Why Coupling Gel Matters

Air is a very poor acoustic coupling medium for most ultrasound applications because the impedance mismatch between air and solids/soft tissue is extreme. Much of the acoustic energy reflects immediately at an air gap.

Ultrasound gel is used to reduce that mismatch by replacing trapped air with a material that transmits sound much more effectively.

In this project, gel will be used for:

- improving contact between probe and test object,
- reducing front-surface losses,
- making echo experiments more repeatable.

---

## 5. Ringing, Pulses, and Resonance

A transducer is generally not driven with continuous AC for pulse-echo imaging. Instead, it is usually excited by a **very short high-voltage pulse** or a **very short burst**. That brief excitation causes the piezoelectric element to ring near its resonant frequency.

This is important:

- the **transmit circuit** does not need to output a long 5 MHz sine wave,
- instead, it needs to produce a fast, energetic excitation that launches a short ultrasonic pulse,
- after that, the system should quickly stop driving and begin listening.

A shorter transmit event generally helps produce a shorter acoustic pulse, which improves **axial resolution**. However, excessive ringing can make it harder to hear shallow echoes right after transmit.

---

## 6. A-Scan, B-Scan, and Beamforming

Ultrasound images are built from echoes.

### A-scan

An A-scan is the most basic ultrasound measurement. It shows echo amplitude versus time, or equivalently versus depth. This is the first imaging-style output this project should aim to obtain.

### B-scan

A B-scan is formed by collecting many A-scans across different lateral positions and mapping echo amplitude to brightness. This creates a 2D grayscale image.

At early stages, B-scan data can be obtained by:

- mechanically moving a single probe,
- or later by using a multi-element array.

### Beamforming

Beamforming is the process of delaying and summing signals from multiple elements to steer and focus the effective beam electronically. This is one of the major long-term digital goals of the project and the reason an FPGA is planned for later revisions.

---

## Engineering Concepts Being Applied

## 1. High-Voltage Transmit Pulse Generation

The transducer must be excited strongly enough to launch a detectable acoustic pulse. Because piezoelectric elements are relatively stiff electromechanical devices, transmit performance often benefits from fast, high-voltage pulses.

The transmit side of this project will investigate:

- how to generate a short, clean excitation pulse,
- how large that pulse must be for the purchased probe,
- whether a unipolar or bipolar pulser is more appropriate later,
- how to keep transmit energy from overwhelming the receive chain.

### Initial design philosophy

For early revisions, the focus is not yet on a production-grade pulser, but on a controlled experimental pulser that can:

- start at lower voltages,
- be measured safely on an oscilloscope,
- be increased gradually,
- and be correlated with received echo quality.

Because the transducer has no accessible full datasheet, the transmit voltage should not be assumed. It should be characterized experimentally.

---

## 2. Tx/Rx Switching

In many ultrasound systems, the same element is used for both transmission and reception. In that case, a **Tx/Rx switch** is required to:

- connect the transducer to the high-voltage pulser during transmit,
- isolate the low-noise receive path from the transmit pulse,
- reconnect the transducer to the receiver immediately after transmit.

For this project, an important practical note is that the currently purchased 5 MHz probe may already expose separate transmit and receive leads, as is common with some thickness-gauge-style probes. If that is confirmed experimentally, then the first revision may not require a traditional Tx/Rx switch.

That would simplify Rev 1 significantly and allow earlier focus on analog receive design.

---

## 3. Low-Noise Amplification (LNA)

Echoes received from a transducer are often very small compared with the transmit event that created them. The receive chain must recover weak high-frequency signals without burying them in circuit noise.

A **low-noise amplifier** is used near the front end to:

- boost very small signals early,
- improve signal-to-noise ratio,
- preserve weak echoes before later processing stages.

A good receive front end needs more than gain. It also needs:

- enough bandwidth for 5 MHz operation,
- low input-referred noise,
- stability,
- protection against overload,
- good power-supply decoupling,
- careful grounding and layout.

This project will study not only which amplifier topology is appropriate, but also how much gain should be distributed across stages.

---

## 4. Band-Pass Filtering

A receive signal contains not only useful echoes but also:

- electrical feedthrough from the transmit event,
- broadband noise,
- out-of-band interference,
- ringing and parasitic response.

A **band-pass filter** centered around the probe’s effective operating band helps:

- suppress low-frequency drift,
- suppress high-frequency noise,
- isolate the echo band of interest,
- improve downstream ADC usage.

In this project, the filter design should eventually be informed by measured probe behavior rather than assumed nominal behavior.

---

## 5. Time Gain Compensation (TGC)

As ultrasound travels deeper into a medium, echo amplitude strength tends to decrease due to attenuation and spreading losses. A fixed-gain receiver may therefore represent shallow echoes well while burying deeper echoes in noise.

**Time Gain Compensation (TGC)** is a depth-dependent gain strategy. It increases gain as time passes after transmit so that later, deeper echoes are amplified more than early echoes.

Why this matters:

- shallow reflectors often produce strong echoes,
- deeper reflectors often produce much weaker echoes,
- without TGC, the dynamic range of the image can be poorly balanced.

---

## 6. Analog-to-Digital Conversion (ADC)

The ADC is the bridge between the analog and digital halves of the system.

Its job is to sample the RF echo waveform with enough:

- speed,
- resolution,
- timing integrity,
- and channel consistency.

### Why the ADC matters so much

If the sampling rate is too low, the RF waveform will be lost or aliased.
If the resolution is too low, weak echoes may disappear into quantization noise.
If clock quality is poor, timing jitter can significantly degrade measurements.


## 7. FPGA Processing

A microcontroller is useful for many embedded tasks, but high-speed multi-channel ultrasound processing rapidly becomes a parallel data problem.

An FPGA is attractive because it can:

- capture multiple high-speed digital streams in parallel,
- implement deterministic timing,
- apply channel delays for beamforming,
- perform filtering and envelope detection,
- support custom imaging pipelines.

---

## Proposed System Architecture

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

## Development Roadmap

The roadmap below reflects the intended progression of the project and is expected to evolve as real hardware data is collected.

## Rev 0 — Probe Characterization

Before committing to a final analog architecture, the purchased probe should be characterized experimentally.

### Objectives

- identify the wiring and determine whether Tx and Rx lines are truly separate,
- verify continuity and basic electrical behavior,
- apply low-voltage test excitation first,
- observe whether one transducer can excite the other in a controlled setup,
- estimate center frequency and ringing behavior on the oscilloscope,
- determine how strongly the probe couples through gel and simple test media,
- build confidence that the purchased hardware actually functions.

### Why this revision matters

This is the best way to avoid repeating a common failure mode from earlier ultrasound prototyping work: building too much circuitry around an unverified transducer.

---

## Rev 1 — Single-Channel Analog Front End Up to the ADC node

This is the first major hardware revision.

### Goals

- build a single-channel 5 MHz transmit circuit,
- excite the probe using a short high-voltage pulse,
- use the same physical probe housing for transmit and receive,
- exploit separate Tx/Rx leads if the probe already provides them,
- design a receive chain with:
  - input protection,
  - low-noise amplification,
  - band-pass filtering,
  - optional gain staging,
- produce a clean analog signal suitable for digitization (right up to the ADC)

### Key notes

- The transmit source should be a **short pulse**, not continuous AC drive.
- The transmit voltage must be determined experimentally because the probe lacks a reliable datasheet.
- Breadboarding high-frequency analog receive stages is likely to be unreliable; early PCB or at least very compact construction is preferred.
- If separate Tx and Rx leads are confirmed, a conventional Tx/Rx switch can be deferred.

### Expected output of Rev 1

- repeatable excitation waveform,
- measurable receive waveform,
- known gain structure,
- scoped analog echo response,
- candidate signal ready for digitization.

---

## Rev 1.5 — Measurement and Test Infrastructure

### Goals

- create repeatable test targets and phantoms,
- define standard oscilloscope measurement procedures,
- record pulse width, ringing time, noise floor, and echo amplitude,
- save captured waveforms for offline analysis,
- build scripts for plotting time-domain response.

### Why this should exist

A measurement workflow is as important as the circuit itself. Without repeatable tests, later changes in gain, filtering, layout, or transmit pulse shape will be difficult to compare objectively.

---

## Rev 2 — Multi-Channel-Capable Analog Expansion

Once the single-channel path is trusted, the analog architecture should begin evolving toward multi-channel scalability.

### Goals

- redesign the single-channel analog path with replication in mind,
- evaluate how power, grounding, and shielding scale across channels,
- preserve consistent gain and bandwidth across channels,
- consider whether separate daughterboards or modular front-end blocks improve debugging,
- maintain compatibility with later high-speed ADC integration.

### Design philosophy

Even if only one or two channels are populated initially, the analog architecture should be able to support multi-channel use.

---

## Rev 3 — ADC Integration

This revision introduces real digitization.

### Single-channel target

- choose an ADC appropriate for 5 MHz RF sampling,
- validate sample quality,
- confirm timing, logic levels, and data extraction,
- save raw RF data for offline analysis.

### Multi-channel target

- transition from one sampled channel to multiple synchronized channels,
- ensure the data format and interface can scale toward FPGA capture,
- verify that the communication architecture does not become the system bottleneck.

### Expected output

- stored digital RF traces,
- verified timing relationship between transmit and sampled receive data,
- understanding of data throughput requirements.

---

## Rev 4 — FPGA Communication and Beamforming Foundations

This stage includes looking into communication protocals and what is the appropiate peripheral for this project. After there will be FPGA programming to allow for beamforming the incoming raw RF data. 

### Goals

- establish reliable communication between ADC and FPGA,
- implement raw sample capture pipelines,
- buffer and move data correctly,
- begin digital filtering and basic signal conditioning,
- build the foundations for delay-and-sum beamforming,
- learn how raw RF data becomes an image pipeline.

### Why FPGA here

By this point, the project is no longer only analog electronics. It becomes a real-time digital system problem, and the FPGA becomes central to scaling the platform into a true imaging device.

---

## Rev 5 — Visualization

This stage turns measured and processed data into something interpretable.

### Goals

- visualize A-scan data first,
- progress toward B-scan style images,
- display results on a host computer or dedicated display,
- compare raw RF, envelope-detected, and beamformed outputs,
- build intuition for what the system is actually measuring.

This stage represents the transition from “ultrasound electronics” to “ultrasound imaging.”

---

## Branching and Repository Philosophy

This repository is expected to evolve using multiple development branches.

The structure will be the following:

- `main` will hold general readme
- `theory` will involve the theory behind the phsyics and engineering concepts required to understand this project
- `simulations/testing` will involve all simulations and tests with results during development
- `hardware` will involve hardware schematics and information of current status of project
- `software/firmware` will involve all SW and FW needed for project

To see the revisions stage by stage, there will be the following branches involving all relevant data:

- `rev0_characterization`
- `rev1_single_channel_analog`
- `rev2_multi_channel_analog`
- `rev3_adc_integration`
- `rev4_fpga_pipeline`
- `rev5_visualization`

This would allow another student or builder to walk through the project historically and understand how the design matured from one stage to the next.

---

## Safety and Scope

This is an educational engineering project, not a certified medical device.

Important scope notes:

- this repository is not intended for diagnostic or clinical use,
- high-voltage pulsing requires careful safety practices,
- analog front-end circuits can be damaged easily by poor grounding or excessive transmit energy,
- early testing should be performed on phantoms, water-path setups, or simple non-clinical targets.

---

## Repository Status

Current status: **planning and architecture phase**.

This README will be updated as the project progresses to include:

---

## Author

**Peter Yazdi**

For any questions, please feel free to email me at :  peteryazdi@gmail.com