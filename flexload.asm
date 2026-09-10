*[ Start ]**********************************************************************
;*-------------------------------------------------------------------
;* FLEXLOAD.ASM
;*    FLEX boot loader for FLEX running on a SWTPC 6800 through
;*    an MP-S serial board in I/O slot 2 instead of through a
;*    floppy controller.
;*
;*    Mike Douglas, 12/28/24
;*-------------------------------------------------------------------
LOADLOC	equ  $A100	;* ;this code loaded here by boot ROM XXXXXXXX
SRVRLOC	equ  $A300	;* ;location of server I/O routines XXXXXXXX
SSTACK	equ  $A07F	;* ;system stack location XXXXXXXX
;
srvrSnd	equ  SRVRLOC	;* ;send command to the server XXXXXXXX
srvrRcv	equ  SRVRLOC+2	;* ;receive a sector from the server XXXXXXXX
srvrClr	equ  SRVRLOC+4	;* ;clear the receive line XXXXXXXX
;
SRVRCTL	equ  $8008	;* ;MP-S 6850 control/status XXXXXXXX
SRVRDAT	equ  $8009	;* ;MP-S 6850 data register XXXXXXXX
SIORDRF	equ  $01	;* ;receive data available mask XXXXXXXX
SIOTDRE	equ  $02	;* ;ready to transmit mask XXXXXXXX
;
;*-------------------------------------------------------------------
;* Boot ROM jumps here after loading this code from track 0
;*-------------------------------------------------------------------
	org  LOADLOC	;* ;boot ROM loads us here
;
flxBoot	bra  loadFlx	;* ;go load FLEX XXXXXXXX
	rmb  3 	;* ;align track/sector bytes
;
;* The starting track and sector for the FLEX system file are
;*   patched into the next two bytes by the LINK command
;
flexTrk	fcb  0		;* ;starting track for FLEX.SYS XXXXXXXX
flexSec	fcb  0		;* ;starting sector for FLEX.SYS XXXXXXXX
;			
pFlex	rmb  2		;* ;pointer to FLEX entry point XXXXXXXX
pDest	rmb  2		;* ;pointer to destination XXXXXXXX
pSource	rmb  2		;* ;pointer to data in secBuf XXXXXXXX
times2	rmb  1		;* ;track x 2 temp result XXXXXXXX
;
;*-------------------------------------------------------------------
;* load - Loop for loading FLEX
;*-------------------------------------------------------------------
load	jsr  getByte	;* ;get next byte XXXXXXXX
	cmpa #$02	;* ;data record header?
	beq  load2	;* 
;
	cmpa #$16	;* ;transfer address header?
	bne  load	;* ;loop if neither
;
	jsr  getByte	;* ;get transfer address
	staa pFlex	;* ;MSB
	jsr  getByte	;* ;LSB
	staa pFlex+1	;* 
;
	ldx  pFlex	;* ;jump to FLEX
	jmp  0,x 	;* 
;
load2	jsr  getByte	;* ;A=load address MSB XXXXXXXX
	psha		;* 
	jsr  getByte	;* ;A=load address LSB
	pulb ;B=load	;* address MSB
;
	staa pDest+1	;* ;save load address LSB
	stab pDest	;* ;MSB
;
	jsr  getByte	;* ;A=byte count
	tab  ;B=byte	;* count
	beq  load	;* ;byte count was zero
;
load3	pshb		;* (LABEL/NM only?)
	jsr  getByte	;* ;get next data byte
	pulb		;* 
;
	ldx  pDest	;* ;X->where to put the data
	staa 0,x 	;* 
	inx		;* 
	stx  pDest	;* 
;
	decb		;* 
	bne  load3	;* ;loop for byte count in B
;
	bra  load	;* ;get next record
;
;*-------------------------------------------------------------------
;* loadFlx - Entry point for loading FLEX
;*-------------------------------------------------------------------
loadFlx	lds  #SSTACK	;* ;init stack pointer XXXXXXXX
;
clear	jsr  srvrClr	;* ;discard bytes until 3ms passes XXXXXXXX
	beq  clear	;* ;   with no data received
;
	ldaa flexTrk	;* ;read 1st sector of FLEX
	ldab flexSec	;* 
	bsr  readSec	;* 
	bra  load	;* 
;
;*-------------------------------------------------------------------
;* readSec 
;*-------------------------------------------------------------------
readSec	staa rcTrk	;* ;save requested track (temp) XXXXXXXX
	decb ;zero	;* index the sector
	stab rcSec	;* ;save 0-indexed sector (temp)
;
;* Convert track, sector into an ordinal sector number from
;*    zero to the end of the disk (track*10 + sector)
;
	clrb ;msb	;* of result
	asla ;track	;* x 2
	staa times2	;* ;save the x2 result
	asla ;track	;* x 4
	asla ;track	;* x 8
	rolb ;MSB	;* (could be > 255 here)
	adda times2	;* ;track x 10
	adcb #0 	;* ;MSB
;
	adda rcSec	;* ;add sector within track
	adcb #0 	;* ;MSB
;
	staa rcTrk	;* ;save LSB of track in read command
	stab rcDrv	;* ;save drive:track MSN (drive is zero)
;
;* Issue the read command and receive the sector into secBuf
;
	ldx  #readCmd	;* ;X->command buffer
	jsr  srvrSnd	;* ;issue the command
;
	ldx  #secBuf	;* ;X->where to put data
	jsr  srvrRcv	;* ;receive sector
	bne  loadFlx	;* ;error - start over
;	
	ldx  #secBuf+4	;* ;data starts at offset 4
	stx  pSource	;* ;pSource->data in secBuf
	rts		;* 
;
;*-------------------------------------------------------------------
;* getByte - Get next byte from sector buffer. Retrieve next
;*    sector as needed.
;*-------------------------------------------------------------------
getByte	ldx  pSource	;* ;X->next byte XXXXXXXX
	cpx  #secBuf+256	;* ;reached end of sector?
	beq  nextSec	;* ;yes, get the next sector
;
	ldaa 0,x 	;* ;else, return next byte
	inx		;* 
	stx  pSource	;* ;save updated pointer
	rts		;* 
;
nextSec	ldaa secBuf	;* ;A=next track XXXXXXXX
	ldab secBuf+1	;* ;B=next sector
	bsr  readSec	;* 
	bra  getByte	;* 
;
;*-------------------------------------------------------------------
;* Data Area
;*-------------------------------------------------------------------
;
;* READ command 	
;
readCmd	fcc  'READ'	;* ;read command to server XXXXXXXX
rcTrk	fcb  0		;* ;track LSB XXXXXXXX
rcSec	equ  *		;* ;temp sector save XXXXXXXX
rcDrv	fcb  0		;* ;drive:track MSN XXXXXXXX
	fcb  0,1 	;* ;256 byte sector, little endian
rcEnd	equ  *  	;*
;
;* Sector buffer starts here
;
secBuf	equ  *  	;*
;
	end		;* 
*[ Fini ]***********************************************************************
