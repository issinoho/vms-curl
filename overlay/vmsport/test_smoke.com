$! TEST_SMOKE.COM - smoke test for the built curl ([.PROJECTS.VMS.<arch>]CURL.EXE)
$!
$! Usage:  @[.VMSPORT]TEST_SMOKE
$! Needs network access to example.com.  The default CA bundle is compiled
$! in as VMSCURL$ROOT:[SSL]CACERT.PEM, so the test points a process
$! VMSCURL$ROOT at a scratch tree holding the kit's CACERT.PEM.
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ saved_style = f$getjpi("", "PARSE_STYLE_PERM")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ curl = "$" + f$parse("[.PROJECTS.VMS.''arch']CURL.EXE")
$ pass = 0
$ fail = 0
$ if f$search("SMOKE.DIR") .eqs. "" then create/directory [.SMOKE]
$ if f$search("[.SMOKE]SSL.DIR") .eqs. "" then create/directory [.SMOKE.SSL]
$ if f$search("[.SMOKE]EMPTY.DIR") .eqs. "" then create/directory [.SMOKE.EMPTY]
$ copy/nolog [.VMSPORT.KIT]CACERT.PEM [.SMOKE.SSL]
$ smoke = f$parse("[.SMOKE]",,,"DEVICE","NO_CONCEAL") + -
          (f$parse("[.SMOKE]",,,"DIRECTORY","NO_CONCEAL") - "][" - "]") + ".]"
$ empty = f$parse("[.SMOKE.EMPTY]",,,"DEVICE","NO_CONCEAL") + -
          (f$parse("[.SMOKE.EMPTY]",,,"DIRECTORY","NO_CONCEAL") - "][" - "]") + ".]"
$ out = "[.SMOKE]OUT.TXT"
$ err = "[.SMOKE]ERR.TXT"
$ set process/parse_style=extended
$!
$! 1. version: OpenSSL 3, zlib and zstd linked in
$ define/user sys$output 'out'
$ curl --version
$ search/nooutput/match=and 'out' "OpenSSL/3.","zlib/","zstd/"
$ sev = $severity
$ name = "version shows OpenSSL 3, zlib and zstd"
$ gosub check_success
$!
$! 2. HTTP GET
$ curl -sS -o nla0: --fail http://example.com/
$ sev = $severity
$ name = "HTTP GET"
$ gosub check_success
$!
$! 3. HTTPS verified against the compiled-in default CA bundle
$ define/process/translation_attributes=concealed VMSCURL$ROOT 'smoke'
$ curl -sS -o nla0: --fail https://example.com/
$ sev = $severity
$ name = "HTTPS with the default CA bundle (VMSCURL$ROOT:[SSL]CACERT.PEM)"
$ gosub check_success
$!
$! 4. ... and refused when the bundle is missing
$ define/process/translation_attributes=concealed VMSCURL$ROOT 'empty'
$ define/user sys$error nla0:
$ curl -s -o nla0: https://example.com/
$ sev = $severity
$ name = "HTTPS refused without a CA bundle"
$ gosub check_failure
$ define/process/translation_attributes=concealed VMSCURL$ROOT 'smoke'
$!
$! 5. --compressed (zlib)
$ define/user sys$output 'out'
$ curl -sS -o nla0: --compressed -w "%{content_type} %{size_download}\n" https://example.com/
$ search/nooutput 'out' "text/html"
$ sev = $severity
$ name = "--compressed"
$ gosub check_success
$!
$! 5b. --compressed offers zstd (patch 0012)
$ define/user sys$error 'err'
$ curl -v -sS -o nla0: --compressed https://example.com/
$ search/nooutput 'err' "Accept-Encoding:","zstd"/match=and
$ sev = $severity
$ name = "--compressed offers zstd in Accept-Encoding"
$ gosub check_success
$!
$! 5c. a Content-Encoding: zstd response is decoded (a site that serves zstd)
$! The headers must say zstd, and the saved body must be HTML: the zstd data
$! itself, undecoded, would not start with <!DOCTYPE.
$ curl -sS --compressed -D [.SMOKE]ZSTD.HDR -o [.SMOKE]ZSTD.HTML https://www.facebook.com/
$ sev = $severity
$ if sev .eq. 1
$ then
$   search/nooutput [.SMOKE]ZSTD.HDR "content-encoding: zstd"
$   sev = $severity
$ endif
$ if sev .eq. 1
$ then
$   define/user sys$output nla0:
$   search/nooutput/limit=1 [.SMOKE]ZSTD.HTML "<!DOCTYPE"
$   sev = $severity
$ endif
$ name = "a zstd-encoded response is decoded"
$ gosub check_success
$!
$! 6. body output is written in whole records (patch 0008)
$ define/user sys$output 'out'
$ curl -sS https://example.com/
$ search/nooutput 'out' "Example Domain"
$ sev = $severity
$ name = "body written as lines, not one character per record"
$ gosub check_success
$!
$! 7. an error exit maps to a VMS error condition
$ define/user sys$error nla0:
$ curl -s -o nla0: http://nonexistent.invalid/
$ sev = $severity
$ name = "unresolvable host gives an error status"
$ gosub check_failure
$!
$! 8. TRADITIONAL parse style: the note about lowercased options (patch 0009)
$ set process/parse_style=traditional
$ define/user sys$error 'err'
$ curl -s -o nla0: https://example.com/ -F "title=two words"
$ set process/parse_style=extended
$ search/nooutput 'err' "parse style is TRADITIONAL"
$ sev = $severity
$ name = "TRADITIONAL parse style note on failure"
$ gosub check_success
$!
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed"
$ deassign/process VMSCURL$ROOT
$ delete/nolog [.SMOKE.SSL]*.*;*, [.SMOKE]*.TXT;*
$ set file/protection=o:rwed [.SMOKE]SSL.DIR, EMPTY.DIR
$ delete/nolog [.SMOKE]SSL.DIR;, EMPTY.DIR;
$ set file/protection=o:rwed SMOKE.DIR
$ delete/nolog SMOKE.DIR;
$ if saved_style .eqs. "TRADITIONAL" then set process/parse_style=traditional
$ set default 'saved_default'
$ if fail .eq. 0 then exit 1
$ exit 44
$!
$! The callers save $SEVERITY in sev straight after the command: any
$! assignment (name = ...) resets it.
$check_success:
$ if sev .eq. 1
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ")"
$ endif
$ return
$!
$check_failure:
$ if sev .eq. 2 .or. sev .eq. 4
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ", expected an error)"
$ endif
$ return
