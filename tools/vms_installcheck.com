$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the VMSCURL kit, verify it,
$! run curl from it (HTTPS against the default CA bundle), check that VSI's
$! CURL kit is untouched, then remove it.  Changes the system while it runs
$! (PCSI database, SYS$COMMON:[VMSCURL], system logical VMSCURL$ROOT); leaves
$! it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ here = f$environment("DEFAULT")
$ tree = here - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ vsi_exe = "SYS$COMMON:[CURL.BIN]CURL.EXE"
$ vsi_root = f$trnlnm("CURL$ROOT")
$ vsi_ok = f$search(vsi_exe) .nes. ""
$ if vsi_ok then write sys$output "CURL_VSI_CURL_BEFORE: PASS (", vsi_root, ")"
$ if .not. vsi_ok then write sys$output "CURL_VSI_CURL_BEFORE: PASS (no VSI CURL kit)"
$ write sys$output "=== INSTALL from ", kitdir
$ product install VMSCURL /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product VMSCURL /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:VMSCURL$STARTUP.COM"), "]"
$ show logical VMSCURL$ROOT
$ directory/nohead/notrail VMSCURL$ROOT:[000000...]*.*
$ write sys$output "=== CURL FROM THE INSTALLED KIT"
$ curl = "$VMSCURL$ROOT:[BIN]CURL.EXE"
$ curl "--version"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "CURL_VERSION: PASS"
$ if sev .ne. 1 then write sys$output "CURL_VERSION: FAIL"
$! HTTPS with no --cacert: verified against VMSCURL$ROOT:[SSL]CACERT.PEM
$ curl "-sS" "-o" nla0: "-w" "http %{http_code} verify %{ssl_verify_result}\n" "https://example.com/"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "CURL_HTTPS_DEFAULT_CA: PASS"
$ if sev .ne. 1 then write sys$output "CURL_HTTPS_DEFAULT_CA: FAIL"
$ write sys$output "=== VSI CURL KIT"
$ if vsi_ok
$ then
$   if f$search(vsi_exe) .nes. "" .and. f$trnlnm("CURL$ROOT") .eqs. vsi_root
$   then
$     write sys$output "CURL_VSI_CURL_AFTER: PASS"
$   else
$     write sys$output "CURL_VSI_CURL_AFTER: FAIL"
$   endif
$ else
$   write sys$output "CURL_VSI_CURL_AFTER: PASS (no VSI CURL kit)"
$ endif
$ write sys$output "=== REMOVE"
$ product remove VMSCURL /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "VMSCURL$ROOT after removal: [", f$trnlnm("VMSCURL$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[VMSCURL...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:VMSCURL$STARTUP.COM"), "]"
$ if vsi_ok .and. f$search(vsi_exe) .eqs. "" then write sys$output "CURL_VSI_CURL_AFTER: FAIL (after removal)"
$ product show product VMSCURL /producer=ISSINOHO
