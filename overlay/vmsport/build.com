$! BUILD.COM - build curl for OpenVMS with upstream's [.PROJECTS.VMS]BUILD_VMS.COM
$!
$! Usage:  @[.VMSPORT]BUILD [CLEAN] [extra BUILD_VMS options]
$!
$! curl ships its OpenVMS build in [.PROJECTS.VMS], maintained upstream; this
$! procedure runs it with our choices:
$!   - TLS from VSI's SSL3 kit (OpenSSL 3.0): OPENSSL is defined as
$!     SSL3$INCLUDE: for the build (patch 0001 makes BUILD_VMS link
$!     SYS$SHARE:SSL3$LIBSSL_SHR32 and SSL3$LIBCRYPTO_SHR32);
$!   - zlib linked statically from ZLIB$ROOT, a rooted logical for a
$!     github.com/issinoho/vms-zlib install tree.  Define it first, e.g.
$!       $ DEFINE/TRANSLATION=CONCEALED ZLIB$ROOT dev:[dir.ZLIB-1_3_2.INSTALL_IA64.]
$!   - the default CA bundle is VMSCURL$ROOT:[SSL]CACERT.PEM, where the kit
$!     installs curl.se's bundle (patch 0010 reads CURL_CA_BUNDLE_DEFAULT).
$!     It is compiled into config_vms.h, so change it only with CLEAN.
$! Output: [.PROJECTS.VMS.<arch>]CURL.EXE
$!
$ status = 44
$ on control_y then goto done
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ target = f$edit(p1, "UPCASE")
$ if target .eqs. "" .or. target .eqs. "ALL" then target = ""
$ write sys$output "BUILD: ''p1' for ''arch' in ''f$environment("DEFAULT")'"
$ if f$trnlnm("SSL3$INCLUDE") .eqs. ""
$ then
$   write sys$error "BUILD: VSI's SSL3 kit (SSL3$INCLUDE) is not installed"
$   goto done
$ endif
$ if f$trnlnm("ZLIB$ROOT") .eqs. "" .and. target .nes. "CLEAN"
$ then
$   write sys$error "BUILD: define ZLIB$ROOT for the vms-zlib install tree first"
$   goto done
$ endif
$ define/process OPENSSL SSL3$INCLUDE:
$ define/process CURL_CA_BUNDLE_DEFAULT "VMSCURL$ROOT:[SSL]CACERT.PEM"
$! NOKERBEROS: GSS-API is in VMS, but its gssapi_krb5.h headers are not installed.
$ @[.projects.vms]build_vms.com 'target' NOKERBEROS 'p2' 'p3'
$ status = $status
$ deassign/process OPENSSL
$ deassign/process CURL_CA_BUNDLE_DEFAULT
$ if target .nes. "CLEAN" .and. -
     f$search("[.projects.vms.''arch']CURL.EXE") .eqs. "" then status = 44
$ if status then write sys$output "BUILD: done"
$done:
$ set default 'saved_default'
$ exit status
