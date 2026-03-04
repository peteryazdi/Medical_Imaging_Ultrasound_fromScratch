"""
beamforming_sim.py – Behavioural simulation of the 16-channel DAS beamformer.

Generates synthetic RF echo data for a point reflector, applies
delay-and-sum beamforming, and saves:
  • beamformed_image.png  – greyscale B-scan image
  • delay_lut.hex         – pre-computed delay LUT for the FPGA

Usage
-----
    python beamforming_sim.py [--plot]

The delay_lut.hex file is read by the FPGA at synthesis time
(see delay_calculator.v: $readmemh).
"""

import argparse
import os
import numpy as np

# ── System parameters ────────────────────────────────────────────────────────
NUM_CH        = 16          # number of receive channels
F_TRANSDUCER  = 2.0e6       # Hz  transducer centre frequency
FS            = 40.0e6      # Hz  ADC sample rate
C_SOUND       = 1540.0      # m/s speed of sound in soft tissue
ELEMENT_PITCH = C_SOUND / (2 * F_TRANSDUCER)  # λ/2 ≈ 0.385 mm
N_SAMPLES     = 2048        # samples per channel (depth)
FOCAL_POINTS  = 256         # depth steps for image reconstruction
DEPTH_MAX     = N_SAMPLES / FS * C_SOUND / 2  # max depth ≈ 19.7 mm


def element_positions() -> np.ndarray:
    """Return x-coordinates of the 16 elements, centred at 0."""
    indices = np.arange(NUM_CH) - (NUM_CH - 1) / 2.0
    return indices * ELEMENT_PITCH   # metres


def make_rf_data(
    reflectors: list[tuple[float, float, float]],
    noise_std: float = 0.02,
) -> np.ndarray:
    """
    Synthesise RF data for a set of point reflectors.

    Parameters
    ----------
    reflectors : list of (x_m, z_m, amplitude) tuples
    noise_std  : additive Gaussian noise level (fraction of full scale)

    Returns
    -------
    rf : ndarray, shape (NUM_CH, N_SAMPLES), dtype float64, range [-1, 1]
    """
    t = np.arange(N_SAMPLES) / FS
    x_elem = element_positions()
    rf = np.zeros((NUM_CH, N_SAMPLES))

    for x_r, z_r, amp in reflectors:
        for ch in range(NUM_CH):
            # Two-way travel distance for element ch and reflector (x_r, z_r)
            r_tx = z_r                                             # plane-wave tx
            r_rx = np.sqrt((x_elem[ch] - x_r)**2 + z_r**2)       # receive path
            t_echo = (r_tx + r_rx) / C_SOUND
            t_idx = t_echo * FS

            # Gaussian-windowed cosine pulse centred at t_idx
            sigma = 4.0   # samples
            env = amp * np.exp(-0.5 * ((t * FS - t_idx) / sigma) ** 2)
            carrier = np.cos(2 * np.pi * F_TRANSDUCER * (t - t_echo))
            rf[ch] += env * carrier

    # Additive white Gaussian noise
    rf += np.random.normal(0, noise_std, rf.shape)
    return rf


def compute_delay_lut(
    z_focal_points: np.ndarray,
    x_focal: float = 0.0,
) -> np.ndarray:
    """
    Pre-compute integer sample delays for delay-and-sum beamforming.

    For a focal point at (x_focal, z_f) the delay for element i is:
        d_i = round( (r_i - r_0) / c * fs )
    where r_i = distance from element i to the focal point,
          r_0 = z_f (on-axis reference path length).

    Parameters
    ----------
    z_focal_points : 1-D array of focal depths (metres)
    x_focal        : lateral position of the scan line (metres)

    Returns
    -------
    delays : ndarray, shape (len(z_focal_points), NUM_CH), dtype int32
    """
    x_elem = element_positions()
    delays = np.zeros((len(z_focal_points), NUM_CH), dtype=np.int32)

    for fi, z_f in enumerate(z_focal_points):
        r_ref = z_f  # on-axis reference
        for ch in range(NUM_CH):
            r_ch = np.sqrt((x_elem[ch] - x_focal) ** 2 + z_f ** 2)
            delta_r = r_ch - r_ref
            delays[fi, ch] = int(np.round(delta_r / C_SOUND * FS))

    return delays


def delay_and_sum(
    rf: np.ndarray,
    delays: np.ndarray,
    z_focal: np.ndarray | None = None,
) -> np.ndarray:
    """
    Apply delay-and-sum beamforming.

    Parameters
    ----------
    rf      : ndarray (NUM_CH, N_SAMPLES) – RF data
    delays  : ndarray (FOCAL_POINTS, NUM_CH) – integer differential sample delays
    z_focal : 1-D array of focal depths (metres).  If None the global
              ``z_focal`` linspace is reconstructed from module constants.

    Returns
    -------
    beam_rf : ndarray (FOCAL_POINTS,) – beamformed RF signal
    """
    if z_focal is None:
        z_focal = np.linspace(C_SOUND / (2 * FS), DEPTH_MAX, delays.shape[0])

    n_focal = delays.shape[0]
    n_samples = rf.shape[1]
    beam_rf = np.zeros(n_focal)

    for fi in range(n_focal):
        # Reference sample index: two-way travel time to on-axis focal depth
        ref_sample = int(round(2.0 * z_focal[fi] / C_SOUND * FS))
        total = 0.0
        for ch in range(NUM_CH):
            # Absolute sample index for this channel after applying receive delay
            t_idx = ref_sample + int(delays[fi, ch])
            if 0 <= t_idx < n_samples:
                total += rf[ch, t_idx]
        beam_rf[fi] = total / NUM_CH

    return beam_rf


def build_bscan_image(
    rf: np.ndarray,
    n_lines: int = 64,
    x_range: tuple[float, float] = (-0.01, 0.01),
) -> np.ndarray:
    """
    Build a full B-scan image by sweeping the focal point laterally.

    Parameters
    ----------
    rf      : RF data (NUM_CH, N_SAMPLES)
    n_lines : number of lateral scan lines
    x_range : (x_min, x_max) in metres

    Returns
    -------
    image : ndarray (FOCAL_POINTS, n_lines), envelope-detected, 0–255
    """
    z_focal = np.linspace(C_SOUND / (2 * FS),
                          DEPTH_MAX,
                          FOCAL_POINTS)
    x_lines = np.linspace(x_range[0], x_range[1], n_lines)
    image   = np.zeros((FOCAL_POINTS, n_lines))

    for li, x_f in enumerate(x_lines):
        delays  = compute_delay_lut(z_focal, x_focal=x_f)
        beam_rf = delay_and_sum(rf, delays, z_focal)
        # Envelope detection via Hilbert transform magnitude
        from scipy.signal import hilbert
        envelope = np.abs(hilbert(beam_rf))
        image[:, li] = envelope

    # Log-compression and normalise to [0, 255]
    image = 20 * np.log10(image / (image.max() + 1e-12) + 1e-6)
    image = np.clip(image + 60, 0, 60)  # 60 dB dynamic range
    image = (image / 60 * 255).astype(np.uint8)
    return image


def save_delay_lut_hex(delays: np.ndarray, path: str) -> None:
    """
    Write the delay LUT to a $readmemh-compatible hex file.

    File layout: one value per line, row-major (focal_idx * NUM_CH + ch).
    """
    with open(path, "w") as f:
        for fi in range(delays.shape[0]):
            for ch in range(delays.shape[1]):
                f.write(f"{delays[fi, ch] & 0x3FF:03X}\n")  # 10-bit delay


def main() -> None:
    parser = argparse.ArgumentParser(description="16-channel DAS beamforming simulation")
    parser.add_argument("--plot", action="store_true", help="Display image in a window")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    np.random.seed(args.seed)

    # ── Define scene: two point reflectors ───────────────────────────────
    reflectors = [
        (0.000,  0.030, 1.0),    # on-axis,   30 mm depth
        (0.005,  0.020, 0.6),    # 5 mm off-axis, 20 mm depth
    ]

    print(f"Generating synthetic RF data for {NUM_CH} channels, {N_SAMPLES} samples…")
    rf = make_rf_data(reflectors, noise_std=0.02)

    # ── Compute focal-point depths ────────────────────────────────────────
    z_focal = np.linspace(C_SOUND / (2 * FS), DEPTH_MAX, FOCAL_POINTS)

    # ── Compute and save delay LUT ────────────────────────────────────────
    print("Computing delay LUT…")
    delays_lut = compute_delay_lut(z_focal, x_focal=0.0)
    lut_path = os.path.join(os.path.dirname(__file__),
                            "../fpga/src/delay_lut.hex")
    save_delay_lut_hex(delays_lut, lut_path)
    print(f"Delay LUT saved to: {os.path.abspath(lut_path)}")

    # ── Run DAS beamforming (on-axis line) ────────────────────────────────
    print("Running delay-and-sum beamforming…")
    beam_rf = delay_and_sum(rf, delays_lut, z_focal)

    # ── Build full B-scan image ───────────────────────────────────────────
    print("Building B-scan image…")
    image = build_bscan_image(rf, n_lines=64)

    # ── Save PNG ──────────────────────────────────────────────────────────
    out_path = os.path.join(os.path.dirname(__file__), "beamformed_image.png")
    try:
        import matplotlib
        if not args.plot:
            matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, axes = plt.subplots(1, 2, figsize=(12, 5))

        # A-scan (on-axis beamformed line)
        from scipy.signal import hilbert
        envelope = np.abs(hilbert(beam_rf))
        z_mm = z_focal * 1e3
        axes[0].plot(z_mm, beam_rf,  label="RF signal",  alpha=0.5)
        axes[0].plot(z_mm, envelope, label="Envelope",   lw=2)
        axes[0].set_xlabel("Depth (mm)")
        axes[0].set_ylabel("Amplitude (normalised)")
        axes[0].set_title("Beamformed A-scan (on-axis)")
        axes[0].legend()
        axes[0].grid(True)

        # B-scan image
        axes[1].imshow(image, cmap="gray", aspect="auto",
                       extent=[-10, 10, DEPTH_MAX * 1e3, 0])
        axes[1].set_xlabel("Lateral (mm)")
        axes[1].set_ylabel("Depth (mm)")
        axes[1].set_title("B-scan (DAS, 64 lines, 60 dB dynamic range)")

        plt.tight_layout()
        plt.savefig(out_path, dpi=150)
        print(f"Image saved to: {os.path.abspath(out_path)}")
        if args.plot:
            plt.show()
    except ImportError:
        print("matplotlib not available – skipping PNG output.")
        print("Install with: pip install matplotlib")


if __name__ == "__main__":
    main()
