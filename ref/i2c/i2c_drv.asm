;------------------------------------------------------------------------------------
;
; The following is 6502 code for an I2C driver. It acts only as master.
;
; I2C uses two bi-directional (OC) lines: clock and data. The maximum bit rate for
; slow mode is 100kbits/sec (fast mode is not supported) but with a 1.8MHz 6502 the
; best you will get is about 43kbits/sec. As the 6502, which is the master, controls
; the clock line, the processor speed should not be a problem.
;
; To work as a slave the 6502 would need extra hardware to detect the start condition,
; the stop condition and extra code to handle collisions.
; This is saved for a later project.
;
; Devices are accessed using the following four subroutines.
;
; SendAddr
;	This routine sends the slave address to the I2C bus. It can also send any
;	required register address bytes by setting them up as you would data to be sent.
;	No stop is sent so you can either read or write after calling this routine.
; SendData
;	Send data byte(s) to an addressed device. Set the count in I2cCountL/H and
;	point to the data with TxBuffL/H. No stop is sent after calling this routine.
; ReadData
;	Read data byte(s) from an addressed device. Set the count in I2cCountL/H and
;	point to the buffer with RxBuffL/H. No stop is sent after calling this routine.
; StopI2c
;	generates a stop condition on the i2c bus
;
; Each device has an 8 bit address, the lowest bit of which is a read/write bit.
;
;------------------------------------------------------------------------------------
I2CPort	=	$F121			; i2c bus port, o.c. outputs, tristate inputs
; bit 0 is data  [SDA]
; bit 1 is clock [SLC]
; bits 2 to 7 are unused
RxBuffL		=	$F1		; receive buffer pointer low byte
TxBuffL		=	RxBuffL		; the same (can't do both at once!)
RxBuffH		=	$F2		; receive buffer pointer high byte
TxBuffH		=	RxBuffH		; the same (can't do both at once!)
ByteBuff	=	$F3		; byte buffer for Tx/Rx routines
I2cAddr		=	$F4		; Tx/Rx address
I2cCountL	=	$F5		; Tx/Rx byte count low byte
I2cCountH	=	$F6		; Tx/Rx byte count high byte
;------------------------------------------------------------------------------------
*=	$2000
JMP	SendData		; vector to send data
JMP	ReadData		; vector to read data
JMP	SendAddr		; vector to send slave address
JMP	StopI2c			; vector to send stop
;------------------------------------------------------------------------------------
;
; send the slave address for an i2c device. if I2cCountL is non zero then that number
; of bytes will be sent after the address (to allow register addressing, required on
; some devices). RxBuff is a pointer, in page zero, to the transmit buffer exits with
; the clock low and Cb=0 if all ok routine entered with the i2c bus in a stopped state
; [SDA=SCL=1]
SendAddr
LDA	I2CPort			; get i2c port state
ORA	#$01			; release data
STA	I2CPort			; out to i2c port
LDA	#$03			; release clock
STA	I2CPort			; out to i2c port
LDA	#$01			; set for data test
WaitAD
BIT	I2CPort			; test the clock line
BEQ	WaitAD			; wait for the data to rise
LDA	#$02			; set for clock test
WaitAC
BIT	I2CPort			; test the clock line
BEQ	WaitAC			; wait for the clock to rise
JSR	StartI2c		; generate start condition
LDA	I2cAddr			; get address (including read/write bit)
JSR	ByteOut			; send address byte
BCS	StopI2c			; branch if no ack
LDA	I2cCountL		; get byte count
BNE	SendData		; go send if not zero
RTS				; else exit
;------------------------------------------------------------------------------------
;
; send data to an already addressed i2c device. I2cCountL/H is the number of bytes to
; send RxBuff is a pointer, in page zero, to the transmit buffer exits with Cb=0 if
; all ok. it is assumed at least one byte is to be sent routine entered with the i2c
; bus in a held state [SCL=0]
SendData
INC	I2cCountH		; increment count high byte
LDY	#$00			; set index to zero
WriteLoop
LDA	(RxBuffL),Y		; get byte from buffer
JSR	ByteOut			; send byte to device
BCS	StopI2c			; branch if no ack
INY				; increment index
BNE	NoHiWrInc		; branch if no rollover
INC	RxBuffH			; else increment pointer high byte
NoHiWrInc
DEC	I2cCountL		; decrement count low byte
BNE	WriteLoop		; loop if not all done
DEC	I2cCountH		; increment count high byte
BNE	WriteLoop		; loop if not all done
RET
;------------------------------------------------------------------------------------
;
; get data from already addressed i2c device. I2cCountL/H is the number of bytes to
; get, RxBuff is a pointer, in page zero, to the receive buffer. exits with Cb = 0 if
; all ok it is assumed at least one byte is to be received. the routine is entered
; with the i2c bus in a held state [SCL=0]
ReadData
LDY	#$00			; set index to zero
ReadLoop
DEC	I2cCountL		; decrement count low byte
JSR	ByteIn			; get byte from device
LDA	I2cCountL		; get count low byte
CMP	#$01			; compare with end count + 1
LDA	I2cCountH		; get count high byte
SBC	#$00			; subtract carry, leaves Cb = 0 for last byte
JSR	DoAck			; send ack bit
LDA	ByteBuff		; get byte from byte buffer
STA	(TxBuffL),Y		; save in device buffer
INY				; increment index
BNE	NoHiRdInc		; branch if no rollover
INC	TxBuffH			; else increment pointer high byte
NoHiRdInc
LDA	I2cCountL		; get count low byte
BNE	ReadLoop		; loop if not all done
DEC	I2cCountH		; decrement count high byte
LDA	I2cCountH		; get count high byte
CMP	#$FF			; compare with end count
BNE	ReadLoop		; loop if not all done
RTS
;------------------------------------------------------------------------------------
;
; generate stop condition on i2c bus. it is assumed only that the clock is low on
; entry to this routine.
StopI2c
LDA	#$00			; now hold the data down
STA	I2CPort			; out to i2c port
;	NOP				; need this if running &gt; 1.9MHz
LDA	#$02			; release the clock
STA	I2CPort			; out to i2c port
;	NOP				; need this if running &gt; 1.9MHz
LDA	#$03			; now release the data (stop)
STA	I2CPort			; out to i2c port
RTS
;------------------------------------------------------------------------------------
;
; generate start condition on i2c bus. it is assumed that both clock and data are
; high on entry to this routine. note, another condition is A = $02 on entry
StartI2c
STA	I2CPort			; out to i2c port
;	NOP				; need this if running &gt; 1.9MHz
LDA	#$00			; clock low, data low
STA	I2CPort			; out to i2c port
RTS
;------------------------------------------------------------------------------------
;
; output byte to 12c bus, byte is in A. returns Cb = 0 if ok. clock should be low
; after generating a start or a previously sent byte
; exits with clock held low
ByteOut
STA	ByteBuff		; save byte for transmit
LDX	#$08			; 8 bits to do
OutLoop
LDA	#$00			; unshifted clock low
ROL	ByteBuff		; bit into carry
ROL	A			; get data from carry
STA	I2CPort			; out to i2c port
;	NOP				; need this if running &gt; 1.9MHz
ORA	#$02			; clock line high
STA	I2CPort			; out to i2c port
LDA	#$02			; set for clock test
WaitT1
BIT	I2CPort			; test the clock line
BEQ	WaitT1			; wait for the clock to rise
LDA	I2CPort			; get data bit
AND	#$01			; set clock low
STA	I2CPort			; out to i2c port
DEX				; decrement count
BNE	OutLoop			; branch if not all done
;------------------------------------------------------------------------------------
;
; clock is low, data needs to be released, then the clock needs to be released then
; we need to wait for the clock to rise and get the ack bit.
GetAck
LDA	#$01			; float data
STA	I2CPort			; out to i2c port
LDA	#$03			; float clock, float data
STA	I2CPort			; out to i2c port
LDA	#$02			; set for clock test
WaitGA
BIT	I2CPort			; test the clock line
BEQ	WaitGA			; wait for the clock to rise
LDA	I2CPort			; get data
LSR	A			; data bit to Cb
LDA	#$01			; clock low, data released
STA	I2CPort			; out to i2c port
RTS
;------------------------------------------------------------------------------------
;
; input byte from 12c bus, byte is returned in A. entry should be with the clock low
; after generating a start or a previously sent byte
; exits with clock held low
ByteIn
LDX	#$08			; 8 bits to do
LDA	#$01			; release data
STA	I2CPort			; out to i2c port
InLoop
LDA	#$03			; release clock
STA	I2CPort			; out to i2c port
LDA	#$02			; set for clock test
WaitR1
BIT	I2CPort			; test the clock line
BEQ	WaitR1			; wait for the clock to rise
LDA	I2CPort			; get data
ROR	A			; bit into carry
ROL	ByteBuff		; bit into buffer
LDA	#$01			; set clock low
STA	I2CPort			; out to i2c port
DEX				; decrement count
BNE	InLoop			; branch if not all done
RTS
;------------------------------------------------------------------------------------
;
; clock is low, ack needs to be set then the clock released then we wait for the
; clock to rise before pulling it low and finishing. Ack bit is in Cb
DoAck
LDA	#$00			; unshifted clock low
ROL	A			; get ack from carry
STA	I2CPort			; out to i2c port
;	NOP				; need this if running &gt; 1.9MHz
ORA	#$02			; release clock
STA	I2CPort			; out to i2c port
LDA	#$02			; set for clock test
WaitTA
BIT	I2CPort			; test the clock line
BEQ	WaitTA			; wait for the clock to rise
LDA	I2CPort			; get ack back
AND	#$01			; hold clock
STA	I2CPort			; out to i2c port
RTS
;------------------------------------------------------------------------------------
