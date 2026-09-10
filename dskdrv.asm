;*[ Start ]*********************************************************************
        MACEXP  off
        CPU     6800            ; That's what asl has
        include "asl.inc"       ;

        NAM     dskdrv
;*-------------------------------------------------------------------
;*
;* FLEX 3.0 disk driver for a SWTPC 6800 using an MP-S serial board
;*    in I/O slot 2 in place of a disk controller. The MP-S board
;*    connects to a PC-based serial disk server instead of disk
;*    drives. This driver works with existing SSSD FLEX 2/3 disk
;*    images for the SWTPC 6800.
;*
;*    Rev      Date	    Desc
;*    1.0    12/28/2024    Original
;*
;*-------------------------------------------------------------------
NUMDRV	equ  4		;* ;number of drives supported XXXXXXXX
;*
;* Flex is hard coded to Sector Size of 256 bytes
;* The maximum number of tracks is 256
;* The maximum number of sectors is 256
;* 256^3 = 16M
;*
;* https://www.waveguide.se/?article=reading-flex-disk-images
;*
        IFDEF   PT681
        ;;
        ;; Careful, there is a masking of drives(?) in the top
        ;; nible of something
        ;;
MAXTRK	equ  256	;* maximum track number XXXXXXXX
NUMSEC	equ  256	;* sectors per side XXXXXXXX
        ELSE
MAXTRK	equ  39		;* maximum track number XXXXXXXX
NUMSEC	equ  10		;* sectors per side XXXXXXXX
        ENDIF
;
;* Serial port equates
;
        IFDEF   PT681
        ;;
        ;; On the PT68-1, the second serial port is at $8004
        ;; The IDE is at $8008-$800F
        ;;
SRVRCTL	equ  $8004	;* disk MP-S control/status XXXXXXXX
SRVRDAT	equ  $8005	;* disk MP-S data register XXXXXXXX
        ELSE
SRVRCTL	equ  $8008	;* disk MP-S control/status XXXXXXXX
SRVRDAT	equ  $8009	;* disk MP-S data register XXXXXXXX
        ENDIF
SIORDRF	equ  $01	;* receive data available mask XXXXXXXX
SIOTDRE	equ  $02	;* ready to transmit mask XXXXXXXX
;
;* FLEX equates
;
PRCNT	equ  $AC34	;* ;non-zero if spool task executing XXXXXXXX
SPACT	equ  $ACFC	;* ;non-zero if spooling (task active or not) XXXXXXXX
CRCERR	equ  $08	;* ;1=CRC error (from 1771) XXXXXXXX
;
;* Two byte strings (difficult due to assembler limitations)
;
W	equ  256*'W'	;*
WR	equ  W+'R'	;* 'WR'
WS	equ  W+'S'	;* 'WS'
;
;*-------------------------------------------------------------------
;* Disk driver jump table
;*-------------------------------------------------------------------
	org  $BE80	;* 
	jmp  read	;* ;read a sector
	jmp  write	;* ;write a sector
	jmp  exit0	;* ;verify sector (always true)
	jmp  select	;* ;restore to track zero
	jmp  select	;* ;select drive
	jmp  select	;* ;check if drive ready
	jmp  select	;* ;quick check if ready
	jmp  cldInit	;* ;cold start init
	jmp  exit0	;* ;warm start init
	jmp  exit0	;* ;seek to track (does nothing)
;
;*-------------------------------------------------------------------
;* cldInit - Cold start initialization. Initialize the 6850 on
;*   the disk MP-S board in I/O slot 2 for disk data transfer.
;*-------------------------------------------------------------------
cldInit	ldaa #$03	;* ;reset the 6850 XXXXXXXX
	staa SRVRCTL	;* 
	ldaa #$15	;* ;8N1
	staa SRVRCTL	;* 
	rts		;* 
;
;*-------------------------------------------------------------------
;* read - Read sector entry point
;*    Read sector B of track A into (X).
;*-------------------------------------------------------------------
read	bsr  initIo	;* ;init for I/O XXXXXXXX
	staa rcDrv	;* ;drive # and MSN of track
	ldaa #rcLen	;* ;A=length of command
	ldx  #readCmd	;* ;X->command buffer
	jsr  srvrSnd	;* ;issue the command
;
	clra ;receive	;* 256 byte sector
	ldx  reqBuf	;* ;X->caller's buffer
	jsr  srvrRcv	;* ;receive sector
	beq  success	;* ;exit with no error
;
retErr	jsr  srb3ms	;* ;discard received bytes until 3ms passes XXXXXXXX
	beq  retErr	;* ;   with no data received
;
	cli		;* 
	ldab #CRCERR	;* ;exit with CRC error (a valid 1771 error)
	rts		;* 
;
;*-------------------------------------------------------------------
;* write - Write sector entry point
;*    Write sector B of track A from (X).
;*-------------------------------------------------------------------
write	bsr  initIo	;* ;init for I/O XXXXXXXX
	staa wcDrv	;* ;drive # and MSN of track
	ldaa #wcLen	;* ;A=length of command
	ldx  #wrtCmd	;* ;X->command buffer
	bsr  srvrSnd	;* ;issue the command
;
;* Receive and validate response to the WRIT command
;
	ldaa #respLen	;* ;length of reponse
	ldx  #cmdResp	;* ;receive response to write command
	jsr  srvrRcv	;* 
	bne  retErr	;* ;error
;
	ldx  cmdResp	;* ;verify "WR" of "WRIT" received
	cpx  #WR 	;* 
	bne  retErr	;* 
;
	ldaa crCode	;* ;verify zero (OK) response code
	bne  retErr	;* 
;
;* Server ready for write data. Send sector and verify response
;
	clra ;send	;* 256 byte sector
	ldx  reqBuf	;* ;X->caller's buffer
	bsr  srvrSnd	;* 
;
	ldaa #respLen	;* ;length of reponse
	ldx  #cmdResp	;* ;receive response to write command
	jsr  srvrRcv	;* 
	bne  retErr	;* ;error
;
	ldx  cmdResp	;* ;verify "WS" of "WSTA" received
	cpx  #WS 	;* 
	bne  retErr	;* 
;
	ldab crCode	;* ;verify zero (OK) response code
	bne  retErr	;* 
;
success	cli		;* (LABEL/NM only?)
	clrb ;no 	;* errors
	rts		;* 
;
;*-------------------------------------------------------------------
;* initIo - Save the requested track. Convert track:sector into an
;*   ordinal sector number. Updates the track byte in both the read
;*   and write command blocks. Returns drive:track MSN byte in A.
;*-------------------------------------------------------------------
initIo	tst  PRCNT	;* ;here from spooler task? XXXXXXXX
	beq  initGo	;* ;no, continue
	swi  ;else,	;* suspend spooler
	nop  ;allow	;* time for interrupts
;
initGo	stx  reqBuf	;* ;save the buffer pointer XXXXXXXX
	staa reqTrk	;* ;save requested track
	decb ;zero	;* index the sector
	bpl  iniSec	;* ;sector wasn't zero
	clrb ;sector	;* 0 remains 0
iniSec	stab reqSec	;* ;save requested sector XXXXXXXX
;
;* Convert track, sector into an ordinal sector number from
;*    zero to the end of the disk (track*10 + sector)
;
	clrb ;msb	;* of result
	asla ;x2 	;* 
	staa times2	;* ;track x 2
	asla ;x4 	;* 
	asla ;x8 	;* 
	rolb ;could	;* be > 255 here
	adda times2	;* ;x10
	adcb #0 	;* 
;
	adda reqSec	;* ;add sector within track
	adcb #0 	;* 
;
	staa rcTrk	;* ;save LSB in read and write commands
	staa wcTrk	;* 
;
	ldaa reqDrv	;* ;form drive:track MSN
	asla		;* 
	asla		;* 
	asla		;* 
	asla		;* 
	aba  ;add	;* in MSN of track
	rts		;* 
;
;*-------------------------------------------------------------------
;* select - Select drive entry point
;*    Sets the requested drive to the passed parameter. No actual 
;*    drive activity takes place.
;*-------------------------------------------------------------------
select	ldaa 3,x	;* ;get drive number XXXXXXXX
	anda #$03	;* ;limit to 0-3
	staa reqDrv	;* ;save requested drive number
;	
exit0	clrb ;no	;* error (carry clear, zero) XXXXXXXX
	rts		;* 
;
;*-------------------------------------------------------------------
;* srvrSnd - Send a data buffer to the serial disk server. Computes
;*    and sends the checksum as well.
;*
;* On Entry:
;*    X->buffer to send
;*    A=length of buffer to send
;*-------------------------------------------------------------------
srvrSnd	sei  ;disable	;* interrupts XXXXXXXX
	staa xferLen	;* 
	clr  chkSum	;* ;init checksum
	clr  chkSum+1	;* 
;
ssLoop	ldaa chkSum+1	;* ;update 16 bit checksum XXXXXXXX
	adda 0,x 	;* ;checksum LSB
	staa chkSum+1	;* 
	ldaa chkSum	;* ;checksum MSB
	adca #0 	;* 
	staa chkSum	;* 
;
	ldaa 0,x 	;* ;A=byte to send
	bsr  ssByte	;* ;server send byte
	inx  ;point	;* to next byte
	dec  xferLen	;* 
	bne  ssLoop	;* 
;
;* Send checksum (2 bytes)
;
	ldaa chkSum+1	;* ;LSB of checksum
	bsr  ssByte	;* 
	ldaa chkSum	;* ;MSB of checksum
;*			;* fall into ssByte
;
;*-------------------------------------------------------------------
;* ssByte - Send a single byte from A to the serial disk server
;*-------------------------------------------------------------------
ssByte	ldab SRVRCTL	;* ;loop until OK to send XXXXXXXX
	andb #SIOTDRE	;* 
	beq  ssByte	;* 
;
	staa SRVRDAT	;* ;send the byte
	rts		;* 
;
;*-------------------------------------------------------------------
;* srvrRcv - Receive a data buffer from the serial disk server. 
;*    Computes and verifies the checksum as well.
;*
;* On Entry:
;*    X->buffer to receive
;*    A=length of buffer to receive
;*
;* On Exit:
;*    Zero true if received without error
;*    Zero false for timeout or checksum error
;*
;* srLoop is 87 cycles
;*-------------------------------------------------------------------
srvrRcv	staa xferLen	;*
	clr  chkSum	;* ;init checksum
	clr  chkSum+1	;* 
;
srLoop	bsr  srByte	;* ;(43) get a byte XXXXXXXX
	bne  srExit	;* ;(4) timeout error
	staa 0,x 	;* ;(6) save byte in the buffer
;
	adda chkSum+1	;* ;(4) update checksum
	staa chkSum+1	;* ;(5)
	ldaa chkSum	;* ;(4) checksum MSB
	adca #0 	;* ;(2)
	staa chkSum	;* ;(5)
;
	inx  ;(4)	;* increment buffer pointer
	dec  xferLen	;* ;(6)
	bne  srLoop	;* ;(4)
;
;* Receive and compare 16 bit checksum
;
	bsr  srByte	;* ;get LSB of checksum
	bne  srExit	;* ;timeout error
	cmpa chkSum+1	;* ;match?
	bne  srExit	;* ;no
;		
	bsr  srByte	;* ;get MSB of checksum
	bne  srExit	;* ;timeout
	cmpa chkSum	;* ;match?
;
srExit	rts  ;return	;* with status XXXXXXXX
;
;*-------------------------------------------------------------------
;* srByte - Receive a byte from the server with 1 second timeout.
;*    Returns zero false for timeout, else true.
;*
;* srb3ms does the same thing but with a 3ms timeout
;*-------------------------------------------------------------------
srb3ms	stx  saveX	;* ;preserve X XXXXXXXX
	ldx  #83 	;* ;3ms timeout
	bra  srbLoop	;* 
;
srByte	stx  saveX	;* ;(6) preserve X XXXXXXXX
	ldx  #27778	;* ;(3) 1 second (18 cycles, 36us per loop)
;	
srbLoop	ldaa SRVRCTL	;* ;(4) new byte available? XXXXXXXX
	lsra ;(2)	;* 
	bcs  srbNew	;* ;(4) yes
	dex  ;(4)	;* 
	bne  srbLoop	;* ;(4)
;
	ldx  saveX	;* ;(5) restore X (zero is now false)
	rts  ;(5)	;* 
;
srbNew	ldaa SRVRDAT	;* ;(4) get the new byte XXXXXXXX
	ldx  saveX	;* ;(5) restore X
	bita #0 	;* ;(2) clear zero flag
	rts  ;(5)	;* 
;
;*-------------------------------------------------------------------
;* Initialized data
;*-------------------------------------------------------------------
;
;* READ command 	
;
readCmd	fcc  'READ'	;* ;read command to server XXXXXXXX
rcTrk	fcb  0		;* ;track LSB XXXXXXXX
rcDrv	fcb  0		;* ;drive:track MSN XXXXXXXX
	fcb  0,1 	;* ;256 byte sector, little endian
rcLen	equ  *-readCmd	;*
;
;* WRIT command
;
wrtCmd	fcc  'WRIT'	;* ;write command to server XXXXXXXX
wcTrk	fcb  0		;* ;track LSB XXXXXXXX
wcDrv	fcb  0		;* ;drive:track MSN XXXXXXXX
	fcb  0,1 	;* ;256 byte sector, little endian
wcLen	equ  *-wrtCmd	;*
;
;*-------------------------------------------------------------------
;* Non-initialized data
;*-------------------------------------------------------------------
reqDrv	rmb  1		;* ;requested drive XXXXXXXX
reqTrk	rmb  1		;* ;requested track XXXXXXXX
reqSec	rmb  1		;* ;requested sector XXXXXXXX
reqBuf	rmb  2		;* ;pointer to read/write buffer XXXXXXXX
;
chkSum	rmb  2		;* ;checksum of transfer buffer XXXXXXXX
saveX	rmb  2		;* ;save location for X during server receive XXXXXXXX
times2	equ  *		;* ;track x 2 temp result XXXXXXXX
xferLen	rmb  1		;* ;length of server transfer XXXXXXXX
;
cmdResp	rmb  4		;* ;server command response buffer XXXXXXXX
crCode	rmb  2		;* ;response code XXXXXXXX
crData	rmb  2		;* ;response data XXXXXXXX
respLen	equ  *-cmdResp	;*
;	
	end		;* 
*[ Fini ]***********************************************************************
