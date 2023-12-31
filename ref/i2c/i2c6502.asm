
; from https://c64os.com
; https://raw.githubusercontent.com/gnacu/i2c6502/master/i2c6502.asm
;
;----[ i2c6502.asm ]--------------------

;i2c6502 - I2C API for C64
;Copyright (c) 2020 Greg Nacu

i2cbase  = $2000

slvwait  = 50 ;wait time for slave
              ;to ack the address

datareg  = $dd01 ;CIA 2 PortB
datadir  = $dd03 ;1 = output, 0 = input

sda_p    = %00000100 ;CIA Port b2 (UP E)
scl_p    = %00001000 ;CIA Port b3 (UP F)

;response codes
ret_ok   = 0;Not an error
ret_nok  = 1

err_sdalo = 2
err_scllo = 3

;i2c address flags
writebit = 0    ;in i2c address byte
readbit  = 1    ;in i2c address byte
purebyte = $ff  ;don't modify data byte

         *= i2cbase

;-----------------------
;--[ jump table ]-------
;-----------------------

         jmp i2c_init
         jmp i2c_reset ;TODO: needed?

         jmp i2c_prep_rw
         jmp i2c_readreg
         jmp i2c_writereg

;-----------------------
;--[ helpers ]----------
;-----------------------

delay   ;jsr ;6
         nop ;2
         nop ;2
         nop ;2
         nop ;2
         nop ;2
         rts ;6
;            --
;            22 ;todo: long enough?

;read/write size and buffer pointer

regsz    .byte 0
regbuf   .word 0

;device address and register number

addr     .byte 0
reg      .byte 0

;-----------------------
;--[ set data direct ]--
;-----------------------

sda_out  lda datadir
         ora #sda_p
         bne *+7

sda_in   lda datadir
         and #sda_p:$ff

         sta datadir
         rts

both_out jsr sda_out
         ;fallthrough

scl_out  lda datadir
         ora #scl_p
         bne *+7

scl_in   lda datadir
         and #scl_p:$ff

         sta datadir
         rts

;-----------------------
;--[ bit reads ]--------
;-----------------------

sda_read
         .block
         ;c <- bit value
         lda datareg
         and #sda_p
         beq clr

         sec
         rts

clr      clc
         rts
         .bend

scl_read
         .block
         ;c <- bit value
         lda datareg
         and #scl_p
         beq clr

         sec
         rts

clr      clc
         rts
         .bend

;-----------------------
;--[ bit writes ]-------
;-----------------------

sda_write
         .block
         ;c -> bit value
         ;c <- same as it came in
         lda datareg

         bcc clr
         ora #sda_p
         bne write

clr      and #sda_p:$ff
         ;fallthrough

write    sta datareg
         rts
         .bend

scl_write
         .block
         ;c -> bit value
         ;c <- same as it came in
         lda datareg

         bcc clr
         ora #scl_p
         bne write

clr      and #scl_p:$ff
         ;fallthrough

write    sta datareg
         rts
         .bend

;-----------------------
;--[ bus management ]---
;-----------------------

i2c_init
         .block
         ;A <- response code
         lda #ret_ok
         sta status

         ;TODO: does it make sense to
         ;write these before setting
         ;the bits as outputs?

         sec
         jsr sda_write
         jsr scl_write

         jsr both_out

         jsr delay

         jsr sda_in
         jsr scl_in

chksda   jsr sda_read
         bcs chkscl

         lda #err_sdalo
         sta status
         bne init

chkscl   jsr scl_read
         bcs init

         lda #err_scllo
         sta status

init     jsr both_out

         sec
         jsr sda_write
         jsr scl_write

         ;Send stop just in case...
         ;st2 = write_stop_bit();
         ;if (status == RET_OK)
         ;status = st2;

         lda status
         rts

status   .byte 0
         .bend

i2c_reset
         jsr both_out

         jsr delay

         clc
         jsr scl_write

         jsr delay

         sec
         jsr scl_write

         jmp i2c_stop

;-----------------------
;--[ bus signaling ]----
;-----------------------

i2c_start
         jsr both_out

         ;make sure that
         ;sda and scl are high
         sec
         jsr sda_write
         jsr scl_write

         jsr delay

         ;pull down sda while
         ;scl is still high
         clc
         jsr sda_write

         jsr delay

         ;then pull down scl also
         jmp scl_write


i2c_stop
         .block
         ;A <- ok/nok response

         jsr both_out

         clc
         jsr sda_write

         jsr delay

         sec
         jsr scl_write

         jsr delay

         sec
         jsr sda_write

         jsr delay

         jsr sda_in
         jsr scl_out ;TODO: needed?

         ;see if sda really went up or
         ;if slave keeps sda low

         jsr sda_read
         bcs ok

         lda #ret_nok
         rts

ok       lda #ret_ok
         rts
         .bend


i2c_ack  ;master acknowledge
         jsr both_out

         clc
         jsr sda_write
         sec
         jsr scl_write

         jsr delay

         clc
         jmp scl_write
         ;note: sda and scl are left low


i2c_nack ;master no acknowledge
         jsr both_out

         sec
         jsr sda_write
         jsr scl_write

         jsr delay

         clc
         jsr scl_write

         jsr delay

         jmp sda_write
         ;note: sda and scl are left low

;-----------------------
;--[ byte read ]--------
;-----------------------

i2c_readb ;read byte
         .block
         ;A <- data byte

         lda #0    ;initialize data byte
         sta data

         jsr sda_in
         jsr scl_out

         ldx #7

loop     jsr delay

;todo: should this be in the loop?
;this causes two delays in a row
;between loop iterations.

         sec
         jsr scl_write

         jsr delay

         jsr sda_read
         rol data

         ;carry low from rol
         jsr scl_write

         jsr delay
         dex
         bpl loop

         lda data
         rts

data     .byte 0
         .bend

;-----------------------
;--[ byte write ]-------
;-----------------------

;0000000 0 General Call
;0000000 1 Start Byte
;0000001 X CBUS Addresses
;0000010 X Reserved for Diff Bus Formats
;0000011 X Reserved for future purposes
;00001XX X High-Speed Master Code
;11110XX X 10-bit Slave Addressing
;11111XX X Reserved for future purposes

;==> Address is 7-bits long.

;List of reserved addresses:
;0,1,2,3,4,5,6,7
;0x78,0x79,0x7A,0x7B,0x7 ,0x7D,0x7E,0x7F

i2c_writeb ;write byte
         .block
         ;a -> data byte
         ;x -> rw_bit
         ;a <- ack status

         sta data

         ;if should write an address,
         ;then rw_bit needs to be added.
         ;otherwise do not shift and no
         ;rw_bit to be added.

         txa
         bmi skiprw

         lsr a    ;rwbit -> c
         rol data ;data  <- c

skiprw   jsr both_out

         ldx #7

loop     rol data
         jsr sda_write

         jsr delay

         sec
         jsr scl_write

         jsr delay

         clc
         jsr scl_write

         jsr delay
         dex
         bpl loop

         ;get slave acknowledge

         jsr sda_in
         jsr scl_out ;TODO: needed?

         sec
         jsr sda_write
         jsr scl_write

;some chips strangely pull sd low
;(slave ack already before the clock)

         ;jmp gotack ;assume slave ack

         ;TODO: are these necessary?
         ;The pins are already in this
         ;configuration.

         jsr sda_in
         jsr scl_out

         ldx #slvwait

wait     jsr sda_read
         bcc gotack

         jsr delay

         dex
         bne wait

         ;error: wait timeout, no ack.
         lda #ret_nok
         rts

gotack   clc
         jsr scl_write

         sec
         jsr sda_write

         jsr both_out

         lda #ret_ok
         rts

data     .byte 0
         .bend

;-----------------------
;--[ register r/w ]-----
;-----------------------

;call i2c_prep_rw before either a
;read register or a write register
;to setup the buffer pointer and the
;length of data to read or write


i2c_prep_rw ;RegPtr -> pointer to buffer
            ;A      -> r/w data length
            ;          (max. 256 bytes)
         stx regbuf
         sty regbuf+1

         sta regsz
         rts

i2c_readreg
         .block
         ;init with i2c_prep_rw
         ;A -> i2c address
         ;Y -> device register
         ;C -> SET = skip reg write
         ;A <- ok/nok response

bufptr   = $fb;$fc

         sta addr
         sty reg
         bcs skipregw

         ;Some devices support
         ;sequential read with a
         ;pre-defined first address

         jsr i2c_start

         lda addr
         ldx #writebit
         jsr i2c_writeb

         beq *+3
         rts ;A <- ret_nok

         lda reg
         ldx #purebyte
         jsr i2c_writeb
skipregw

         jsr i2c_start
         lda addr
         ldx #readbit
         jsr i2c_writeb

         ;backup bufptr
         lda bufptr
         pha
         lda bufptr+1
         pha

         ;bufptr <- regbuf
         lda regbuf
         sta bufptr
         lda regbuf+1
         sta bufptr+1

         ldy #0

loop     jsr i2c_readb
         sta (bufptr),y

         iny
         cpy regsz
         beq done

         jsr i2c_ack
         jsr delay

         sec
         jsr sda_write

         ;TODO: clock stretching

         bcs loop ;branch always


done     ;restore bufptr
         pla
         sta bufptr+1
         pla
         sta bufptr

         jsr i2c_nack
         jmp i2c_stop
         .bend

i2c_writereg
         .block
         ;init with i2c_prep_rw
         ;A -> i2c address
         ;Y -> device register
         ;A <- ok/nok response

bufptr   = $fb;$fc

         sta addr
         sty reg

         lda #ret_ok
         sta status

         jsr i2c_start

         lda addr
         ldx #writebit
         jsr i2c_writeb

         lda reg
         ldx #purebyte
         jsr i2c_writeb

         ;backup bufptr
         lda bufptr
         pha
         lda bufptr+1
         pha

         ;bufptr <- regbuf
         lda regbuf
         sta bufptr
         lda regbuf+1
         sta bufptr+1

         ldy #0

loop     lda (bufptr),y
         ldx #purebyte
         jsr i2c_writeb

         ora status

         iny
         cpy regsz
         bne loop

         ;restore bufptr
         pla
         sta bufptr+1
         pla
         sta bufptr

         jsr i2c_stop
         lda status

         rts

status   .byte 0
         .bend

