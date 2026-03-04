/*
 * amplitude_detect.c  –  Software envelope detector
 *
 * Implements two methods:
 *   1. amplitude_envelope()  – peak-hold with exponential decay
 *   2. amplitude_rms()       – short-window RMS
 *
 * These are used to convert the raw RF A-scan into a smoothed
 * amplitude profile suitable for B-scan display.
 */

#include <stdint.h>
#include <string.h>
#include "amplitude_detect.h"

/* ---- compile-time knobs ------------------------------------------------- */
#define DECAY_SHIFT    3    /* peak-hold decay: env -= env >> DECAY_SHIFT     */
#define RMS_WINDOW     8    /* samples in the short-window RMS                */

/* ======================================================================== */

/*
 * amplitude_envelope  –  peak-hold envelope detector
 *
 * For each sample the running envelope is updated:
 *   if (|sample| > env)  env = |sample|
 *   else                 env -= env >> DECAY_SHIFT
 *
 * @param raw    input raw ADC samples (unsigned 12-bit, mid-scale = 2048)
 * @param env    output envelope buffer (same length as raw)
 * @param n      number of samples
 */
void amplitude_envelope(const uint16_t *raw, uint16_t *env, uint16_t n)
{
    uint16_t i;
    uint16_t running = 0;
    int32_t  centered;

    for (i = 0; i < n; i++) {
        /* remove ADC mid-scale offset and take absolute value */
        centered = (int32_t)raw[i] - 2048;
        if (centered < 0) centered = -centered;

        if ((uint16_t)centered > running) {
            running = (uint16_t)centered;
        } else {
            running -= (running >> DECAY_SHIFT);
        }
        env[i] = running;
    }
}

/*
 * amplitude_rms  –  short-window RMS envelope
 *
 * env[i] = sqrt( mean( raw[i - W/2 .. i + W/2]^2 ) )
 * using integer approximation (no floating point).
 *
 * @param raw    input raw ADC samples (unsigned 12-bit)
 * @param env    output envelope buffer
 * @param n      number of samples
 */
void amplitude_rms(const uint16_t *raw, uint16_t *env, uint16_t n)
{
    uint16_t i, j;
    uint32_t sum;
    int32_t  centered;
    uint16_t half = RMS_WINDOW / 2;

    for (i = 0; i < n; i++) {
        sum = 0;
        for (j = 0; j < RMS_WINDOW; j++) {
            uint16_t idx = (i >= half) ? (i - half + j) : j;
            if (idx >= n) idx = n - 1;
            centered = (int32_t)raw[idx] - 2048;
            sum += (uint32_t)(centered * centered);
        }
        /* integer square root via Newton's method */
        uint32_t x = sum / RMS_WINDOW;
        if (x == 0) {
            env[i] = 0;
            continue;
        }
        uint32_t est = x;
        uint32_t prev;
        do {
            prev = est;
            est  = (est + x / est) >> 1;
        } while (est < prev);
        env[i] = (uint16_t)prev;
    }
}
