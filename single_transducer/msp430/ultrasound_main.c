/*
 * ultrasound_main.c  –  Single-transducer ultrasound firmware (MSP430)
 *
 * Pulse-echo acquisition:
 *   1. Fire a short TX pulse via GPIO.
 *   2. Blank the receiver for BLANKING_CYCLES ADC ticks.
 *   3. Capture ADC_SAMPLES samples at maximum ADC rate.
 *   4. Compute the amplitude envelope (amplitude_detect.c).
 *   5. Stream the A-scan over UART for offline B-scan reconstruction.
 *
 * Target: MSP430F5529 (can be ported to any MSP430 with on-chip ADC12).
 */

#include <msp430.h>
#include <stdint.h>
#include <string.h>
#include "amplitude_detect.h"

/* ---- compile-time configuration ---------------------------------------- */
#define ADC_SAMPLES      256      /* samples per A-scan                       */
#define BLANKING_CYCLES   20      /* ADC ticks to ignore after TX pulse       */
#define TX_PIN           BIT0     /* P1.0 – transmit gate                     */
#define TX_PORT_OUT      P1OUT
#define TX_PORT_DIR      P1DIR
#define UART_BAUD        115200
#define SMCLK_HZ         16000000UL

/* ---- globals ------------------------------------------------------------ */
static uint16_t adc_buf[ADC_SAMPLES];
static uint16_t envelope[ADC_SAMPLES];
static volatile uint16_t adc_idx = 0;
static volatile uint8_t  capture_done = 0;

/* ---- prototypes --------------------------------------------------------- */
static void clock_init(void);
static void uart_init(void);
static void adc_init(void);
static void tx_pulse(void);
static void uart_send_ascan(const uint16_t *env, uint16_t len);

/* ======================================================================== */
int main(void)
{
    WDTCTL = WDTPW | WDTHOLD;   /* stop watchdog */

    clock_init();
    uart_init();
    adc_init();

    TX_PORT_DIR |= TX_PIN;
    TX_PORT_OUT &= ~TX_PIN;

    while (1) {
        /* --- transmit phase --- */
        tx_pulse();

        /* --- wait for ADC capture to finish --- */
        capture_done = 0;
        adc_idx      = 0;
        ADC12CTL0   |= ADC12ENC | ADC12SC;   /* start conversion sequence */
        while (!capture_done) {
            __bis_SR_register(LPM0_bits | GIE);
        }

        /* --- compute envelope --- */
        amplitude_envelope(adc_buf, envelope, ADC_SAMPLES);

        /* --- stream A-scan over UART --- */
        uart_send_ascan(envelope, ADC_SAMPLES);
    }
}

/* ---- clock: SMCLK = 16 MHz from DCO ------------------------------------- */
static void clock_init(void)
{
    UCSCTL3 = SELREF__REFOCLK;
    UCSCTL4 = SELA__REFOCLK | SELS__DCOCLKDIV | SELM__DCOCLKDIV;
    __bis_SR_register(SCG0);
    UCSCTL0 = 0x0000;
    UCSCTL1 = DCORSEL_5;
    UCSCTL2 = FLLD_1 + 487;   /* 16 MHz */
    __bic_SR_register(SCG0);
    while (UCSCTL7 & DCOFFG) {
        UCSCTL7 &= ~DCOFFG;
        SFRIFG1 &= ~OFIFG;
    }
}

/* ---- UART: 115200-8N1 on USCI_A1 ---------------------------------------- */
static void uart_init(void)
{
    P4SEL |= BIT4 | BIT5;
    UCA1CTL1 |= UCSWRST;
    UCA1CTL1  = UCSSEL__SMCLK | UCSWRST;
    UCA1BR0   = (uint8_t)(SMCLK_HZ / UART_BAUD);
    UCA1BR1   = (uint8_t)((SMCLK_HZ / UART_BAUD) >> 8);
    UCA1MCTL  = UCBRS_0 | UCBRF_0;
    UCA1CTL1 &= ~UCSWRST;
}

/* ---- ADC12: single-channel, repeat-sequence, DMA-free ------------------- */
static void adc_init(void)
{
    ADC12CTL0  = ADC12SHT0_2 | ADC12ON;
    ADC12CTL1  = ADC12SHP | ADC12CONSEQ_2;   /* repeat-single-channel       */
    ADC12MCTL0 = ADC12INCH_0;               /* A0 input                    */
    ADC12IE    = ADC12IE0;
}

/* ---- fire a ~100 ns TX pulse -------------------------------------------- */
static void tx_pulse(void)
{
    TX_PORT_OUT |= TX_PIN;
    __delay_cycles(2);           /* ~125 ns at 16 MHz */
    TX_PORT_OUT &= ~TX_PIN;
}

/* ---- stream 16-bit envelope values as raw bytes over UART --------------- */
static void uart_send_ascan(const uint16_t *env, uint16_t len)
{
    /* simple framing: 0xAA 0x55 <len_lo> <len_hi> <data…> */
    uint8_t  header[4] = {0xAA, 0x55,
                          (uint8_t)(len & 0xFF),
                          (uint8_t)((len >> 8) & 0xFF)};
    uint16_t i;

    for (i = 0; i < 4; i++) {
        while (!(UCA1IFG & UCTXIFG));
        UCA1TXBUF = header[i];
    }
    for (i = 0; i < len; i++) {
        while (!(UCA1IFG & UCTXIFG));
        UCA1TXBUF = (uint8_t)(env[i] & 0xFF);
        while (!(UCA1IFG & UCTXIFG));
        UCA1TXBUF = (uint8_t)((env[i] >> 8) & 0xFF);
    }
}

/* ---- ADC12 ISR ---------------------------------------------------------- */
#pragma vector=ADC12_VECTOR
__interrupt void adc12_isr(void)
{
    if (ADC12IV == ADC12IV_ADC12IFG0) {
        if (adc_idx < BLANKING_CYCLES) {
            (void)ADC12MEM0;   /* discard blanking samples */
        } else {
            adc_buf[adc_idx - BLANKING_CYCLES] = ADC12MEM0;
            if ((adc_idx - BLANKING_CYCLES) == ADC_SAMPLES - 1) {
                ADC12CTL0 &= ~(ADC12ENC | ADC12SC);
                capture_done = 1;
                __bic_SR_register_on_exit(LPM0_bits);
            }
        }
        adc_idx++;
    }
}
