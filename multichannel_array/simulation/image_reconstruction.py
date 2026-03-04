"""
image_reconstruction.py – Convert beamformed RF data to a displayable B-scan.

This module provides two entry points:

1.  reconstruct_from_rf(beam_rf_lines)
        Input  : 2-D array (FOCAL_POINTS × n_lines) of beamformed RF data.
        Output : 2-D uint8 image, log-compressed, 60 dB dynamic range.

2.  reconstruct_from_file(path)
        Reads a binary or CSV file of beamformed RF lines produced by the
        FPGA host interface, then calls reconstruct_from_rf.

Usage (standalone)
------------------
    # Generate fresh RF data and reconstruct
    python image_reconstruction.py

    # Or from previously saved NPZ file:
    python image_reconstruction.py --input beamformed_rf.npz
"""

import argparse
import os
import sys

import numpy as np

# ── Constants ────────────────────────────────────────────────────────────────
FS        = 40.0e6   # Hz
C_SOUND   = 1540.0   # m/s
DYN_RANGE = 60.0     # dB dynamic range for display


def envelope_detect(rf_line: np.ndarray) -> np.ndarray:
    """
    Envelope detection via Hilbert transform magnitude.

    Parameters
    ----------
    rf_line : 1-D array of RF samples (float)

    Returns
    -------
    envelope : 1-D array, same length, real-valued ≥ 0
    """
    from scipy.signal import hilbert
    return np.abs(hilbert(rf_line))


def log_compress(env: np.ndarray, dynamic_range_db: float = DYN_RANGE) -> np.ndarray:
    """
    Apply log compression and normalise to [0, 255] (uint8).

    Parameters
    ----------
    env             : envelope image, shape (depth, n_lines), values ≥ 0
    dynamic_range_db: display dynamic range in dB

    Returns
    -------
    img : uint8 ndarray, shape (depth, n_lines)
    """
    max_val = env.max() if env.max() > 0 else 1.0
    compressed = 20.0 * np.log10(env / max_val + 1e-7)
    compressed = np.clip(compressed + dynamic_range_db, 0, dynamic_range_db)
    return (compressed / dynamic_range_db * 255).astype(np.uint8)


def reconstruct_from_rf(
    beam_rf_lines: np.ndarray,
    dynamic_range_db: float = DYN_RANGE,
) -> np.ndarray:
    """
    Convert beamformed RF data to a log-compressed B-scan image.

    Parameters
    ----------
    beam_rf_lines    : ndarray (FOCAL_POINTS, n_lines) – beamformed RF lines
    dynamic_range_db : display dynamic range in dB

    Returns
    -------
    image : uint8 ndarray (FOCAL_POINTS, n_lines)
    """
    n_focal, n_lines = beam_rf_lines.shape
    envelope_image = np.zeros_like(beam_rf_lines)

    for li in range(n_lines):
        envelope_image[:, li] = envelope_detect(beam_rf_lines[:, li])

    return log_compress(envelope_image, dynamic_range_db)


def reconstruct_from_file(path: str) -> np.ndarray:
    """
    Load beamformed RF data from disk and reconstruct a B-scan image.

    Supported formats:
        .npz  – NumPy archive with key 'beam_rf'
        .npy  – NumPy binary array
        .csv  – CSV, rows = focal points, columns = scan lines

    Returns
    -------
    image : uint8 ndarray
    """
    ext = os.path.splitext(path)[1].lower()
    if ext == ".npz":
        data = np.load(path)
        beam_rf = data["beam_rf"]
    elif ext == ".npy":
        beam_rf = np.load(path)
    elif ext == ".csv":
        beam_rf = np.loadtxt(path, delimiter=",")
    else:
        raise ValueError(f"Unsupported file format: {ext}")

    return reconstruct_from_rf(beam_rf)


def save_image(image: np.ndarray, path: str) -> None:
    """Save a uint8 image array as PNG."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.imsave(path, image, cmap="gray", vmin=0, vmax=255)
        print(f"Image saved: {path}")
    except ImportError:
        print("matplotlib not installed – cannot save PNG.")
        print("Install with: pip install matplotlib")


def display_image(
    image: np.ndarray,
    depth_max_mm: float | None = None,
    n_lines: int | None = None,
) -> None:
    """Display the B-scan image in an interactive window."""
    try:
        import matplotlib.pyplot as plt
        n_focal, n_cols = image.shape
        dm  = depth_max_mm or (n_focal / FS * C_SOUND / 2 * 1e3)
        nl  = n_cols

        plt.figure(figsize=(8, 6))
        plt.imshow(image, cmap="gray", aspect="auto",
                   extent=[-nl/2, nl/2, dm, 0])
        plt.xlabel("Scan line index")
        plt.ylabel("Depth (mm)")
        plt.title(f"B-scan ({DYN_RANGE:.0f} dB dynamic range)")
        plt.colorbar(label="Intensity (a.u.)")
        plt.tight_layout()
        plt.show()
    except ImportError:
        print("matplotlib not available – cannot display image.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ultrasound image reconstruction")
    parser.add_argument(
        "--input", type=str, default=None,
        help="Path to beamformed RF data file (.npz / .npy / .csv). "
             "If omitted, a synthetic scene is generated.",
    )
    parser.add_argument(
        "--output", type=str, default="reconstructed_image.png",
        help="Output PNG file path (default: reconstructed_image.png)",
    )
    parser.add_argument("--show", action="store_true", help="Open interactive window")
    args = parser.parse_args()

    if args.input:
        print(f"Loading RF data from {args.input}…")
        image = reconstruct_from_file(args.input)
    else:
        # Generate synthetic data via beamforming_sim
        print("No input file specified – generating synthetic scene…")
        sys.path.insert(0, os.path.dirname(__file__))
        from beamforming_sim import make_rf_data, build_bscan_image, DEPTH_MAX

        np.random.seed(42)
        reflectors = [
            (0.000, 0.030, 1.0),
            (0.005, 0.020, 0.6),
        ]
        rf    = make_rf_data(reflectors, noise_std=0.02)
        image = build_bscan_image(rf, n_lines=64)

    out_path = os.path.join(os.path.dirname(__file__), args.output)
    save_image(image, out_path)

    if args.show:
        display_image(image)


if __name__ == "__main__":
    main()
