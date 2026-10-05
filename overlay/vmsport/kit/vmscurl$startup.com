$! VMSCURL$STARTUP.COM - system startup for curl (vms-curl) on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! VMSCURL$ROOT, pointing at the installed [VMSCURL] directory.  curl finds
$! its default CA bundle through it (VMSCURL$ROOT:[SSL]CACERT.PEM), so it
$! must be defined before curl makes HTTPS requests.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:VMSCURL$STARTUP.COM
$!
$! The names differ from VSI's CURL kit (CURL$ROOT, [CURL]) so that both can
$! be installed.
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign VMSCURL$ROOT instead (PCSI runs it so at removal).
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("VMSCURL$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode VMSCURL$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[VMSCURL].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.VMSCURL.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "VMSCURL.]"
$ if root .eqs. dir + "VMSCURL.]"
$ then
$   write sys$error "VMSCURL$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed VMSCURL$ROOT 'dev''root'
$ if f$search("VMSCURL$ROOT:[BIN]CURL.EXE") .eqs. ""
$ then
$   write sys$error "VMSCURL$STARTUP: CURL.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for curl (vms-curl)"
$ say ""
$ say "    At system startup: to define VMSCURL$ROOT at every boot, add this"
$ say "    line to SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:VMSCURL$STARTUP.COM"
$ say "    For each user: to define the curl command, add this line to LOGIN.COM"
$ say "    (or SYLOGIN.COM, for everyone):"
$ say "    $ @VMSCURL$ROOT:[000000]VMSCURL$SETUP.COM"
$ say "    In batch jobs and other TRADITIONAL parse-style processes, quote"
$ say "    options that use capital letters (""-F"", ""-O"") or first use"
$ say "    SET PROCESS/PARSE_STYLE=EXTENDED.  See VMSCURL$ROOT:[DOC]README.VMS."
$ say ""
$ say "    PRODUCT REMOVE VMSCURL removes the product and deassigns VMSCURL$ROOT."
$ say ""
$ exit 1
