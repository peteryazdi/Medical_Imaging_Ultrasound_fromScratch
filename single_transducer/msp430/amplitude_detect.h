/*
 * amplitude_detect.h  –  Envelope detection interface
 */
#ifndef AMPLITUDE_DETECT_H
#define AMPLITUDE_DETECT_H

#include <stdint.h>

void amplitude_envelope(const uint16_t *raw, uint16_t *env, uint16_t n);
void amplitude_rms(const uint16_t *raw, uint16_t *env, uint16_t n);

#endif /* AMPLITUDE_DETECT_H */
