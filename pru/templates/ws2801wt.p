// APA102 Signal Generation PRU Program Template
//
// Drives up to 12 strips using a single PRU. LEDscape (in userspace) writes rendered frames into shared DDR memory
// and sets a flag to indicate how many pixels are to be written.  The PRU then bit bangs the signal out the
// 24 GPIO pins and sets a "complete" flag.
//
// To stop, the ARM can write a 0xFF to the command, which will cause the PRU code to exit.
//
// Implementation does not try and stick to any specific clock speed, just pushes out data as fast as it can (about 1.6mhz).
// 
// [ start frame ][   LED1   ][   LED2   ]...[   LEDN   ][ end frame ]
// [ 32bit x 0   ][0xFF 8 8 8][0xFF 8 8 8]...[0xFF 8 8 8][ (n/2) * 1 ]
//

// Mapping lookup

.origin 0
.entrypoint START

#include "common.p.h"

#define CLOCK_HIGH() MOV r_gpio0_addr, CONCAT3(pin_clock, PRU_NUM, _gpio) | GPIO_SETDATAOUT; \
                     MOV r_gpio0_mask, CONCAT3(pin_clock, PRU_NUM, _mask); \
                     SBBO r_gpio0_mask, r_gpio0_addr, 0, 4;

#define CLOCK_LOW() MOV r_gpio0_addr, CONCAT3(pin_clock, PRU_NUM, _gpio) | GPIO_CLEARDATAOUT; \
                    MOV r_gpio0_mask, CONCAT3(pin_clock, PRU_NUM, _mask); \
                    SBBO r_gpio0_mask, r_gpio0_addr, 0, 4;

START:
	// Enable OCP master port
	// clear the STANDBY_INIT bit in the SYSCFG register,
	// otherwise the PRU will not be able to write outside the
	// PRU memory space and to the BeagleBon's pins.
	LBCO	r0, C4, 4, 4
	CLR		r0, r0, 4
	SBCO	r0, C4, 4, 4

	// Configure the programmable pointer register for PRU0 by setting
	// c28_pointer[15:0] field to 0x0120.  This will make C28 point to
	// 0x00012000 (PRU shared RAM).
	MOV		r0, 0x00000120
	MOV		r1, CTPPR_0
	ST32	r0, r1

	// Configure the programmable pointer register for PRU0 by setting
	// c31_pointer[15:0] field to 0x0010.  This will make C31 point to
	// 0x80001000 (DDR memory).
	MOV		r0, 0x00100000
	MOV		r1, CTPPR_1
	ST32	r0, r1

	// Write a 0x1 into the response field so that they know we have started
	MOV r2, #0x1
	SBCO r2, CONST_PRUDRAM, 12, 4


	MOV r20, 0xFFFFFFFF

	// Wait for the start condition from the main program to indicate
	// that we have a rendered frame ready to clock out.  This also
	// handles the exit case if an invalid value is written to the start
	// start position.
_LOOP:
	// Let ledscape know that we're starting the loop again. It waits for this
	// interrupt before sending another frame
	RAISE_ARM_INTERRUPT

	// Load the pointer to the buffer from PRU DRAM into r0 and the
	// length (in bytes-bit words) into r1.
	// start command into r2
	LBCO      r_data_addr, CONST_PRUDRAM, 0, 12

	// Wait for a non-zero command
	QBEQ _LOOP, r2, #0

	// Reset the sleep timer
	RESET_COUNTER

	// Zero out the start command so that they know we have received it
	// This allows maximum speed frame drawing since they know that they
	// can now swap the frame buffer pointer and write a new start command.
	MOV r3, 0
	SBCO r3, CONST_PRUDRAM, 8, 4

	// Command of 0xFF is the signal to exit
	QBEQ EXIT, r2, #0xFF


l_word_loop:

	#if CONCAT3(pin_clock, PRU_NUM, _exists) == 1

	// for bit in 24 to 0
	MOV r_bit_num, 24

	l_bit_loop:
		DECREMENT r_bit_num

		// Zero out the registers
		RESET_GPIO_ONES()

		///////////////////////////////////////////////////////////////////////
		// Load data and test bits

		// First 16 channels
		LOAD_CHANNEL_DATA(24, 0, 16)

		// Test for ones
		TEST_BIT_ONE(r_data0,  0)
		TEST_BIT_ONE(r_data1,  1)
		TEST_BIT_ONE(r_data2,  2)
		TEST_BIT_ONE(r_data3,  3)
		TEST_BIT_ONE(r_data4,  4)
		TEST_BIT_ONE(r_data5,  5)
		TEST_BIT_ONE(r_data6,  6)
		TEST_BIT_ONE(r_data7,  7)
		TEST_BIT_ONE(r_data8,  8)
		TEST_BIT_ONE(r_data9,  9)
		TEST_BIT_ONE(r_data10, 10)
		TEST_BIT_ONE(r_data11, 11)
		TEST_BIT_ONE(r_data12, 12)
		TEST_BIT_ONE(r_data13, 13)
		TEST_BIT_ONE(r_data14, 14)
		TEST_BIT_ONE(r_data15, 15)

		// Last 8 channels
		LOAD_CHANNEL_DATA(24, 16, 8)
		TEST_BIT_ONE(r_data0, 16)
		TEST_BIT_ONE(r_data1, 17)
		TEST_BIT_ONE(r_data2, 18)
		TEST_BIT_ONE(r_data3, 19)
		TEST_BIT_ONE(r_data4, 20)
		TEST_BIT_ONE(r_data5, 21)
		TEST_BIT_ONE(r_data6, 22)
		TEST_BIT_ONE(r_data7, 23)

		// Data loaded
		///////////////////////////////////////////////////////////////////////

		///////////////////////////////////////////////////////////////////////
		// Send the bits

		// Clock LOW
		CLOCK_LOW()
		SLEEPNS 3600, 1, wait_clock_low		

		// set all data LOW
		PREP_GPIO_ADDRS_FOR_CLEAR()
		PREP_GPIO_MASK_NAMED(all)
		GPIO_APPLY_MASK_TO_ADDR()

		// Data 1s HIGH
		PREP_GPIO_ADDRS_FOR_SET()
		GPIO_APPLY_ONES_TO_ADDR()

		// Clock HIGH
		CLOCK_HIGH()
		SLEEPNS 3600, 1, wait_clock_high

		// Bits sent
		///////////////////////////////////////////////////////////////////////

		QBNE l_bit_loop, r_bit_num, #0
	//end l_bit_loop

	// The RGB streams have been clocked out
	// Move to the next pixel on each row
	ADD r_data_addr, r_data_addr, 48 * 4
	DECREMENT r_data_len
	QBNE l_word_loop, r_data_len, #0

	// Final clear for the word
	PREP_GPIO_MASK_NAMED(all)
	PREP_GPIO_ADDRS_FOR_CLEAR()

	WAITNS 1200, end_of_frame_clear_wait
	CLOCK_LOW()
	GPIO_APPLY_MASK_TO_ADDR()

	#else
	#warning No clock pin defined for this mapping
	#endif

	// Delay at least 500 usec; this is the required reset
	// time for the LED strip to update with the new pixels.
	SLEEPNS 1000000, 1, reset_time

	// Write out that we are done!
	// Store a non-zero response in the buffer so that they know that we are done
	// aso a quick hack, we write the counter so that we know how
	// long it took to write out.
	MOV r8, PRU_CONTROL_ADDRESS // control register
	LBBO r2, r8, 0xC, 4
	SBCO r2, CONST_PRUDRAM, 12, 4

	// Go back to waiting for the next frame buffer
	QBA _LOOP

EXIT:
	// Write a 0xFF into the response field so that they know we're done
	MOV r2, #0xFF
	SBCO r2, CONST_PRUDRAM, 12, 4

	RAISE_ARM_INTERRUPT

	HALT

