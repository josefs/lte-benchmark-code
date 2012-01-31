/*******************************************************************************
 *                      LTE UPLINK RECEIVER PHY BENCHMARK                      *
 *                                                                             *
 * This file is distributed under the license terms given by LICENSE.TXT       *
 ******************************************************************************/

#define WIDTH  (8 * sizeof(char))
#define TOPBIT (1 << (WIDTH - 1))
#define POLYNOMIAL 0xD8  

unsigned char crcTable[256];

void crcInit(void) {
  unsigned char  remainder;
  int dividend;
  unsigned char bit;

  /*
   * Compute the remainder of each possible dividend.
   */
  for (dividend = 0; dividend < 256; ++dividend) {
    /*
     * Start with the dividend followed by zeros.
     */
    remainder = dividend << (WIDTH - 8);

    /*
     * Perform modulo-2 division, a bit at a time.
     */
    for (bit = 8; bit > 0; --bit) {
      /*
       * Try to divide the current data bit.
       */			
      if (remainder & TOPBIT) {
	remainder = (remainder << 1) ^ POLYNOMIAL;
      } else {
	remainder = (remainder << 1);
      }
    }

    /*
     * Store the result into the table.
     */
    crcTable[dividend] = remainder;
  }
}

unsigned char crcFast(unsigned char const message[], int nBytes) {
  unsigned char data;
  unsigned char remainder = 0;
  int byte;

  /*
   * Divide the message by the polynomial, a byte at a time.
   */
  for (byte = 0; byte < nBytes; ++byte) {
    data = message[byte] ^ (remainder >> (WIDTH - 8));
    remainder = crcTable[data] ^ (remainder << 8);
  }

  /*
   * The final remainder is the CRC.
   */
  return (remainder);

}
