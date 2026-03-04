# Single-Transducer Ultrasound System (Phase 1)

## Hardware

- **MCU**: Texas Instruments MSP430 (custom PCB)
- **Transducer**: 5 MHz single-element piezoelectric
- **Excitation**: Single-cycle negative-pulse generated via GPIO + gate driver
- **Reception**: T/R switch → LNA → ADC (on-chip, 200 kSPS max)

## Operation

1. MSP430 fires a short transmit pulse on `TX_PIN`.
2. T/R switch flips to receive mode after a blanking period.
3. ADC samples the echo signal at its maximum rate.
4. Firmware applies a simple amplitude (envelope) detector to produce an A-scan.
5. Multiple A-scans are collected while mechanically scanning the transducer to
   form a 2-D B-scan image.

## Files

| File | Description |
|------|-------------|
| `msp430/ultrasound_main.c` | Firmware entry point – pulse TX, ADC capture, UART output |
| `msp430/amplitude_detect.c` | Software envelope detector (peak-hold / moving average) |

## Limitations

- ADC rate is limited to ~200 kSPS, giving an effective depth resolution of ~3.8 mm.
- Single element → no lateral focusing; lateral resolution limited by beam width.
- These limitations motivate the Phase 2 16-channel FPGA system.
