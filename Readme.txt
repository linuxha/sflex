This folder contains the files required to run FLEX 3.0 on a SWTPC 6800
computer. Instead of using a disk controller, disk data is transferred
through an MP-S serial board in I/O slot 2 ($8008). Instead of disk drives,
a serial disk server running on a PC serves disk content.

To learn more, see this video: https://youtu.be/vaHdJzc_0NI

The serial disk server for Windows can be found here: 
	https://deramp.com/downloads/altair/hardware/fdc+/

Linux:
        https://github.com/linuxha/fdc-sds
        10046.13 1584.70 / DUP 1584.70 6 * DUP 10046.13 SWAP -

ESP32:
        https://github.com/linuxha/fdc-sds-esp32

The boot disk (drive 0) should be SERFLEX.DSK. Other disk images can be
loaded into other drives (or drive 0 once FLEX is booted). Numerous
additional disk images are available at the link below. The disk images
at this link expect a disk controller, so they won't boot, however, most
programs on these disks will work, other than programs that might access
the floppy controller directly.

https://deramp.com/downloads/swtpc/software/FLEX/FLEX%202.0%20and%203.0%20Disk%20Images/

Use only disk images that are 88K or 100K. The 200K disk images will
not work.

---------------------------------------------------------------------

Hardware considerations

Put 56.8K baud on the 600 baud line as shown for the MP-A CPU board in the document
document linked below:

https://deramp.com/downloads/swtpc/hardware/MP_A%206800%20CPU%20Board/MP-A%209600-56.8K%20Baud.pdf

The original MP-S can be marginal at 56.8K. Decreasing R7 to 1K can help.
If issues still persist, try a 68B50 in place of the original 6850. Finally,
a modern drop-in equivalent like the Corsham serial board will work:

https://peripheraltech.com/Corsham-MP-S.htm

Notes:

https://www.waveguide.se/?article=reading-flex-disk-images

https://joels-programming-fun.blogspot.com/2024/03/alpp-assembly-language-programming.html
