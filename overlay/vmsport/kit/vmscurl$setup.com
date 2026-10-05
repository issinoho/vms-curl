$! VMSCURL$SETUP.COM - define the curl command for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @VMSCURL$ROOT:[000000]VMSCURL$SETUP.COM
$!
$! VSI's own CURL kit may be installed too; this defines curl as this kit's
$! (VMSCURL$ROOT), whatever was defined before.
$!
$! Upper-case options (-F, -O, -L, ...) need SET PROCESS/PARSE_STYLE=EXTENDED,
$! or double quotes, because traditional DCL parsing changes their case;
$! batch jobs use the traditional style.
$!
$ if f$trnlnm("VMSCURL$ROOT") .eqs. ""
$ then
$   write sys$error "VMSCURL$SETUP: VMSCURL$ROOT is not defined; run VMSCURL$STARTUP.COM first"
$   exit 44
$ endif
$ curl :== $VMSCURL$ROOT:[BIN]CURL.EXE
$ exit 1
