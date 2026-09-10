*[ Start ]**********************************************************************
;*-------------------------------------------------------------------
;* ROMBOOT.ASM
;*    Loads sector 1 from track 0 into RAM at $A100 and jumps to
;*    it. The program loaded is the FLEX loader for serial FLEX
;*    on the SWTPC 6800. The FLEX loader expects the server serial
;*    I/O routines left by this code in RAM at $A300
;*
;*    Mike Douglas, 12/28/24
;*-------------------------------------------------------------------
ROMLOC	equ  $E600	;* ;PROM address XXXXXXXX
LOADLOC	equ  $A100	;* ;where to put loaded boot sector XXXXXXXX
SRVRLOC	equ  $A300	;* ;address of server subroutines XXXXXXXX
STACK	equ  $A07F	;* ;system stack XXXXXXXX
;
sendCmd	equ  SRVRLOC	;* ;send command to server XXXXXXXX
rcvSect	equ  SRVRLOC+2	;* ;receive sector from server XXXXXXXX
srvrClr	equ  SRVRLOC+4	;* ;clear receive line XXXXXXXX
;
SRVRCTL	equ  $8008	;* ;MP-S 6850 control/status XXXXXXXX
SRVRDAT	equ  $8009	;* ;MP-S 6850 data register XXXXXXXX
SIORDRF	equ  $01	;* ;receive data available mask XXXXXXXX
SIOTDRE	equ  $02	;* ;ready to transmit mask XXXXXXXX
;
;*-------------------------------------------------------------------
;* This code executes from PROM in memory space at ROMLOC. The PROM 
;*   copies the server I/O routines from PROM to RAM at $A300.
;*-------------------------------------------------------------------
	org  SRVRLOC-2	;* 
	bra  jump1	;* ;two relative jumps required to
;*				;get to the entry point
;
;*-------------------------------------------------------------------
;* Server I/O routines at $A300. These remain in RAM for the FLEX
;*    loader to use when it exeuctes
;*-------------------------------------------------------------------
	bra  srvrSnd	;* ;send a command
	bra  srvrRcv	;* ;receive a 256 byte sector
	bra  srb3ms	;* ;receive byte with 3ms timeout
;
;*-------------------------------------------------------------------
;* srvrSnd - Send the read command block to the serial disk server.
;*    Computes and sends the checksum as well.
;*
;* On Entry:
;*    X->buffer to receive
;*-------------------------------------------------------------------
srvrSnd	clr  chkSum	;* ;init checksum XXXXXXXX
	clr  chkSum+1	;* 
	ldab #8 	;* ;length of read command
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
	decb ;loop	;* until all bytes sent
	bne  ssLoop	;* 
;
;* Send checksum (2 bytes)
;
	ldaa chkSum+1	;* ;send LSB of checksum
	bsr  ssByte	;* 
	ldaa chkSum	;* ;send MSB of checksum
;
ssByte	psha ;preserve	;* byte to send XXXXXXXX
;
ssbLoop	ldaa SRVRCTL	;* ;loop until OK to send XXXXXXXX
	anda #SIOTDRE	;* 
	beq  ssbLoop	;* 
;
	pula ;get	;* back the byte to send
	staa SRVRDAT	;* ;send the byte
	rts		;* 
;
;*-------------------------------------------------------------------
;* srvrRcv - Receive a 256 byte sector from the serial disk server.
;*    Computes and verifies the checksum as well.
;*
;* On Entry:
;*    X->buffer to receive (must be secBuf)
;*
;* On Exit:
;*    Zero true if received without error
;*    Zero false for timeout or checksum error
;*-------------------------------------------------------------------
srvrRcv	clr  chkSum	;* ;init checksum XXXXXXXX
	clr  chkSum+1	;* 
	clrb ;receive	;* 256 bytes
;
srLoop	bsr  srByte	;* ;get a byte XXXXXXXX
	bne  srExit	;* ;timeout error
	staa 0,x 	;* ;save byte in the buffer
;
	adda chkSum+1	;* ;update checksum
	staa chkSum+1	;* 
	ldaa chkSum	;* ;checksum MSB
	adca #0 	;* 
	staa chkSum	;* 
;
	inx  ;increment	;* buffer pointer
	decb ;loop	;* for 256 bytes
	bne  srLoop	;* 
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
;* jump1 - This branch used to get to the ROM entry point
;
jump1	bra  start	;*
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
;* READ command for server
;*-------------------------------------------------------------------
readCmd	fcc  'READ'	;* ;read command to server XXXXXXXX
rcTrk	fcb  0		;* ;track LSB XXXXXXXX
rcDrv	fcb  0		;* ;drive:track MSN XXXXXXXX
	fcb  0,1 	;* ;read 256 bytes, little endian
;
SRVRLEN	equ  *-SRVRLOC	;*
;
;*-------------------------------------------------------------------
;* Data area
;*-------------------------------------------------------------------
chkSum	rmb  2		;* ;checksum with server XXXXXXXX
saveX	rmb  2		;* ;temp save for X XXXXXXXX
;
;
;*-------------------------------------------------------------------
;* Boot loader - Copy the server I/O code to RAM at $A300. Then
;*   Initialize the server UART, wait for the serial line from
;*   the server to be idle, then read sector 1 from track 0 into
;*   RAM at $A100 and jump to it.
;*-------------------------------------------------------------------
start	lds  #ROMLOC+1	;* ;start of server code in ROM - 1 XXXXXXXX
	ldx  #SRVRLOC	;* ;X->where to put server in RAM
	ldab #SRVRLEN	;* ;length to move
;
movSrvr	pula ;get	;* byte from ROM XXXXXXXX
	staa 0,x 	;* ;store in RAM
	inx		;* 
	decb		;* 
	bne  movSrvr	;* 
;
;* Load sector 1 from track 0 into RAM at $A100 and then jump to it
;
	lds  #STACK	;* 
	ldaa #$03	;* ;reset the 6850
	staa SRVRCTL	;* 
	ldaa #$15	;* ;8N1
	staa SRVRCTL	;* 
;
clear	jsr  srvrClr	;* ;discard bytes until 3ms passes XXXXXXXX
	beq  clear	;* ;   with no data receive
;
	ldx  #readCmd	;* ;X->READ command block
	jsr  sendCmd	;* ;send the command
	ldx  #LOADLOC	;* 
	jsr  rcvSect	;* ;receive the sector
	bne  clear	;* ;error - start over
;
	jmp  LOADLOC	;* ;execute the loaded sector
;
	end		;* 
*[ Fini ]***********************************************************************
