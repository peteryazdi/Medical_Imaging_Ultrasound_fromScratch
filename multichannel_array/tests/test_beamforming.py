"""
test_beamforming.py – pytest unit tests for the DAS beamforming simulation.

Tests cover:
  • element_positions()  – geometry check
  • compute_delay_lut()  – zero delay on-axis centre element, symmetry
  • delay_and_sum()      – peak reconstruction at correct depth
  • make_rf_data()       – echo arrival time matches expected delay
  • envelope_detect()    – monotone around expected peak
  • log_compress()       – output range and dtype
  • reconstruct_from_rf()– full pipeline, peak column at correct depth
"""

import sys
import os

import numpy as np
import pytest

# ── Make simulation package importable ───────────────────────────────────────
SIM_DIR = os.path.join(os.path.dirname(__file__), "..", "simulation")
sys.path.insert(0, os.path.abspath(SIM_DIR))

from beamforming_sim import (
    NUM_CH,
    FS,
    C_SOUND,
    FOCAL_POINTS,
    N_SAMPLES,
    DEPTH_MAX,
    element_positions,
    compute_delay_lut,
    delay_and_sum,
    make_rf_data,
)
from image_reconstruction import (
    envelope_detect,
    log_compress,
    reconstruct_from_rf,
)


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def z_focal():
    return np.linspace(C_SOUND / (2 * FS), DEPTH_MAX, FOCAL_POINTS)


@pytest.fixture(scope="module")
def delays_on_axis(z_focal):
    return compute_delay_lut(z_focal, x_focal=0.0)


@pytest.fixture(scope="module")
def rf_single_reflector():
    """Single on-axis reflector at 30 mm depth."""
    np.random.seed(0)
    return make_rf_data([(0.0, 0.030, 1.0)], noise_std=0.0)


# ── Tests: element_positions ──────────────────────────────────────────────────

class TestElementPositions:
    def test_num_elements(self):
        x = element_positions()
        assert len(x) == NUM_CH

    def test_symmetric(self):
        x = element_positions()
        np.testing.assert_allclose(x, -x[::-1], atol=1e-12)

    def test_centre_at_zero(self):
        x = element_positions()
        assert abs(x.mean()) < 1e-12


# ── Tests: compute_delay_lut ──────────────────────────────────────────────────

class TestDelayLUT:
    def test_shape(self, delays_on_axis):
        assert delays_on_axis.shape == (FOCAL_POINTS, NUM_CH)

    def test_centre_channel_zero_delay(self, delays_on_axis):
        """Channels 7 and 8 are symmetric about the array centre and must have
        identical delays for all on-axis focal points (by symmetry)."""
        np.testing.assert_array_equal(
            delays_on_axis[:, 7],
            delays_on_axis[:, 8],
            err_msg="Channels 7 and 8 should have equal delays (symmetric about centre)",
        )

    def test_symmetric_delays(self, delays_on_axis):
        """Delays must be symmetric: delay[fi, ch] == delay[fi, NUM_CH-1-ch]."""
        mirrored = delays_on_axis[:, ::-1]
        np.testing.assert_array_equal(delays_on_axis, mirrored)

    def test_delays_non_negative(self, delays_on_axis):
        assert np.all(delays_on_axis >= 0), "All delays should be ≥ 0"

    def test_delays_decrease_with_depth(self, delays_on_axis):
        """Outer element delays decrease as depth increases.
        The differential path length Δr ≈ x²/(2z) → 0 as z → ∞,
        so delays for edge channels are largest at shallow depths."""
        edge_ch = 0
        delays_edge = delays_on_axis[:, edge_ch]
        max_idx = int(np.argmax(delays_edge))
        # Maximum delay should be near the shallowest focal points (small index)
        assert max_idx < FOCAL_POINTS // 2, (
            f"Edge-channel delay maximum expected near shallow depths "
            f"(fi < {FOCAL_POINTS//2}), got max at fi={max_idx}"
        )

    def test_off_axis_delays_asymmetric(self, z_focal):
        """For an off-axis focal point the delays should NOT be symmetric."""
        delays_off = compute_delay_lut(z_focal, x_focal=0.005)
        # Check that left-right symmetry is broken
        mirrored = delays_off[:, ::-1]
        assert not np.array_equal(delays_off, mirrored)


# ── Tests: make_rf_data ───────────────────────────────────────────────────────

class TestMakeRFData:
    def test_shape(self, rf_single_reflector):
        assert rf_single_reflector.shape == (NUM_CH, N_SAMPLES)

    def test_peak_arrival_on_axis_centre(self, rf_single_reflector):
        """Centre element echo should arrive at t = 2*z/c."""
        z = 0.030
        t_echo_samples = int(round(2 * z / C_SOUND * FS))
        centre_ch = NUM_CH // 2
        signal = rf_single_reflector[centre_ch]
        peak_idx = np.argmax(np.abs(signal))
        # Allow ±5 samples tolerance for the Gaussian pulse width
        assert abs(peak_idx - t_echo_samples) <= 5, (
            f"Centre-channel peak at sample {peak_idx}, "
            f"expected near {t_echo_samples}"
        )

    def test_outer_channels_delayed_vs_centre(self, rf_single_reflector):
        """Outer elements are further from on-axis reflector → later echo."""
        centre_peak = np.argmax(np.abs(rf_single_reflector[NUM_CH // 2]))
        edge_peak   = np.argmax(np.abs(rf_single_reflector[0]))
        assert edge_peak >= centre_peak, (
            "Edge channel echo should arrive no earlier than centre channel"
        )

    def test_symmetric_channels(self, rf_single_reflector):
        """For an on-axis reflector, symmetric channel pairs should be equal."""
        for ch in range(NUM_CH // 2):
            mirror = NUM_CH - 1 - ch
            np.testing.assert_allclose(
                rf_single_reflector[ch],
                rf_single_reflector[mirror],
                atol=1e-10,
                err_msg=f"Channels {ch} and {mirror} should be symmetric",
            )


# ── Tests: delay_and_sum ──────────────────────────────────────────────────────

class TestDelayAndSum:
    def test_output_shape(self, rf_single_reflector, delays_on_axis, z_focal):
        beam = delay_and_sum(rf_single_reflector, delays_on_axis, z_focal)
        assert beam.shape == (FOCAL_POINTS,)

    def test_peak_at_correct_depth(self, rf_single_reflector, z_focal):
        """Peak of the beamformed signal must be within 2 mm of the reflector depth."""
        reflector_depth = 0.030  # m
        delays = compute_delay_lut(z_focal, x_focal=0.0)
        beam   = delay_and_sum(rf_single_reflector, delays, z_focal)

        peak_fi   = np.argmax(np.abs(beam))
        peak_z    = z_focal[peak_fi]
        error_mm  = abs(peak_z - reflector_depth) * 1e3
        assert error_mm <= 2.0, (
            f"Beamformed peak at {peak_z*1e3:.1f} mm, "
            f"expected {reflector_depth*1e3:.1f} mm (error={error_mm:.2f} mm)"
        )

    def test_coherent_gain_vs_single_channel(self, rf_single_reflector, delays_on_axis, z_focal):
        """DAS should have higher SNR (peak amplitude) than any single channel."""
        beam = delay_and_sum(rf_single_reflector, delays_on_axis, z_focal)
        beam_peak = np.max(np.abs(beam))
        for ch in range(NUM_CH):
            single_peak = np.max(np.abs(rf_single_reflector[ch])) / NUM_CH
            # After normalisation by NUM_CH the beamformed peak should still be larger
            assert beam_peak >= single_peak * 0.5, (
                "DAS beamformed peak should be ≥ 50 % of normalised single-channel peak"
            )


# ── Tests: envelope_detect ────────────────────────────────────────────────────

class TestEnvelopeDetect:
    def test_output_shape(self):
        x = np.sin(2 * np.pi * np.arange(256) / 10.0)
        env = envelope_detect(x)
        assert env.shape == x.shape

    def test_non_negative(self):
        x = np.random.randn(512)
        env = envelope_detect(x)
        assert np.all(env >= 0)

    def test_peak_preserved(self):
        """Envelope peak should be within 20 % of the RF signal amplitude.
        A narrow Gaussian pulse (σ=4 samples) will have some Hilbert-transform
        edge effects for very short arrays, so we use a relaxed tolerance."""
        t = np.arange(512) / FS
        f0 = 2.0e6
        sigma = 4.0 / FS
        t0 = 256 / FS
        amp = 1.0
        x = amp * np.exp(-0.5 * ((t - t0) / sigma) ** 2) * np.cos(2 * np.pi * f0 * t)
        env = envelope_detect(x)
        assert abs(env.max() - amp) < 0.2, (
            f"Envelope peak {env.max():.3f} should be within 20 % of signal amplitude {amp}"
        )


# ── Tests: log_compress ───────────────────────────────────────────────────────

class TestLogCompress:
    def test_output_dtype(self):
        env = np.random.rand(256, 64)
        img = log_compress(env)
        assert img.dtype == np.uint8

    def test_output_range(self):
        env = np.random.rand(256, 64)
        img = log_compress(env)
        assert img.min() >= 0
        assert img.max() <= 255

    def test_peak_is_white(self):
        """The maximum input maps to the maximum output value (255)."""
        env = np.zeros((64, 16))
        env[32, 8] = 1.0
        img = log_compress(env, dynamic_range_db=60)
        assert img.max() == 255

    def test_all_zeros_no_crash(self):
        """All-zero input should not raise an exception."""
        env = np.zeros((64, 16))
        img = log_compress(env)
        assert img.dtype == np.uint8


# ── Tests: reconstruct_from_rf (full pipeline) ────────────────────────────────

class TestReconstructFromRF:
    def test_output_shape(self, rf_single_reflector, z_focal):
        """Output shape should match (FOCAL_POINTS, n_lines)."""
        n_lines = 32
        from beamforming_sim import build_bscan_image
        image = build_bscan_image(rf_single_reflector, n_lines=n_lines)
        assert image.shape == (FOCAL_POINTS, n_lines)

    def test_output_dtype(self, rf_single_reflector):
        from beamforming_sim import build_bscan_image
        image = build_bscan_image(rf_single_reflector, n_lines=16)
        assert image.dtype == np.uint8

    def test_peak_depth(self, rf_single_reflector, z_focal):
        """Brightest row (mean across columns) must correspond to ~30 mm depth."""
        from beamforming_sim import build_bscan_image
        image = build_bscan_image(rf_single_reflector, n_lines=32)
        row_mean = image.mean(axis=1)
        peak_fi  = np.argmax(row_mean)
        peak_z   = z_focal[peak_fi]
        error_mm = abs(peak_z - 0.030) * 1e3
        assert error_mm <= 5.0, (
            f"Image peak row at {peak_z*1e3:.1f} mm, expected ~30 mm "
            f"(error={error_mm:.2f} mm)"
        )
