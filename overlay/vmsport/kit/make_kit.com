$! MAKE_KIT.COM - build the PCSI kit for this node's architecture
$!
$! Usage:  @[.VMSPORT.KIT]MAKE_KIT
$! Needs a built tree (@[.VMSPORT]BUILD): [.PROJECTS.VMS.<arch>]CURL.EXE.
$! Writes the kit to [.KIT_<arch>].  The product description, text module,
$! CA bundle and documentation were put in [.VMSPORT.KIT] by
$! tools/prepare.sh.  The product description is PRODUCT-<base>.PCSI$DESC:
$! upstream's BUILD_VMS CLEAN deletes any [...]*curl*.pcsi$desc.
$!
$ set noon
$ status = 44
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ kitdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'kitdir'
$ set default [--]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$!
$! KIT_PRODUCER, KIT_PRODUCT, PCSI_VERSION, KIT_VERSION from kit.env
$ open/read env [.VMSPORT.KIT]KIT.ENV
$env_loop:
$ read/end=env_done env line
$ name = f$element(0, "=", line)
$ 'name' = f$element(1, "=", line)
$ goto env_loop
$env_done:
$ close env
$!
$ exe = "[.PROJECTS.VMS.''arch']CURL.EXE"
$ if f$search(exe) .eqs. ""
$ then
$   write sys$error "MAKE_KIT: no ''exe'; build first"
$   goto done
$ endif
$!
$! Gather the files flat in [.KIT_<arch>.MAT]: PRODUCT PACKAGE looks each
$! one up by name in the material directory (destinations are in the PDF).
$ mat = "[.KIT_''arch'.MAT]"
$ out = "[.KIT_''arch']"
$ if f$search("KIT_''arch'.DIR") .eqs. "" then create/directory 'out'
$ if f$search("[.KIT_''arch']MAT.DIR") .eqs. "" then create/directory 'mat'
$ if f$search("''out'*.PCSI;*") .nes. "" then delete/nolog 'out'*.PCSI;*
$ if f$search("''mat'*.*;*") .nes. "" then delete/nolog 'mat'*.*;*
$ copy/nolog 'exe' 'mat'
$ copy/nolog [.VMSPORT.KIT]VMSCURL$STARTUP.COM,README.VMS,CACERT.PEM 'mat'
$ copy/nolog [.VMSPORT.KIT.DOC]*.* 'mat'
$ matspec = f$parse(mat,,,"DEVICE","NO_CONCEAL") + f$parse(mat,,,"DIRECTORY","NO_CONCEAL")
$!
$ write sys$output "MAKE_KIT: ''KIT_PRODUCER' ''base' ''KIT_PRODUCT' ''PCSI_VERSION' (curl ''KIT_VERSION')"
$ product package 'KIT_PRODUCT' -
    /producer='KIT_PRODUCER' /base_system='base' /version='PCSI_VERSION' -
    /source=[.VMSPORT.KIT]PRODUCT-'base'.PCSI$DESC -
    /material='matspec' -
    /destination='out' -
    /format=sequential -
    /options=noconfirm /log
$ status = $status
$ kit = f$search("''out'*.PCSI")
$ if kit .nes. "" then write sys$output "MAKE_KIT: kit ", kit
$ if kit .eqs. "" then status = 44
$done:
$ set default 'saved_default'
$ exit status
