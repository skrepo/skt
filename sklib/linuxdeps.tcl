package provide linuxdeps 0.0.0

namespace eval ::linuxdeps {
  namespace export install
  namespace ensemble create
}


#In Debian: /etc/debian_version
#In Ubuntu: lsb_release -a or /etc/debian_version
#In Redhat: cat /etc/redhat-release
#In Fedora: cat /etc/fedora-release
#Read cat /proc/version

# Prefer feature detection over distro detection

proc ::linuxdeps::find-pkg-mgr {} {
  # detect in order: zypper, apt-get, yum (others: pacman, portage, urpmi, dnf, slapt-geti emerge)
  set candidates {zypper apt-get yum}
  foreach c $candidates {
    if {![catch {exec $c --version}]} {
      return $c
    }
  }
  return ""
}


proc ::linuxdeps::tk-missing-dep {} {
  if {[catch {package require Tk} out err]} {
    #puts "OUT: $out"
    #puts "ERR: $err"

  switch -regexp -matchvar tokens $out {
    {^can't find package (.*)} {
      #the entire Tk package is missing - propagate the error
      package require [lindex $tokens 1]
    }
    {^couldn't load file ".*": (.*): cannot open shared object file.*} {
      return [lindex $tokens 1]
    }
    {^$} {
      return ""
    }
  }
# When Tk package missing:
#OUT: can't find package dksjfds
#ERR: -code 1 -level 0 -errorstack {INNER {invokeStk1 package require dksjfds} CALL tk-missing-dep} -errorcode {TCL PACKAGE UNFOUND} -errorinfo {can't find package dksjfds
#    while executing
#"package require dksjfds"} -errorline 2

# When OS library is missing:
#OUT: couldn't load file "/tmp/tcl_CJ5xeo": libXss.so.1: cannot open shared object file: No such file or directory
#ERR: -code 1 -level 0 -errorstack {INNER {load /home/sk/skt/build/sandbox/linux-ix86/sandbox.bin/lib/libtk8.6.so Tk} UP 2 CALL tk-missing-dep} -errorcode NONE -errorinfo {couldn't load file "/tmp/tcl_CJ5xeo": libXss.so.1: cannot open shared object file: No such file or directory
#    while executing
#"load /home/sk/skt/build/sandbox/linux-ix86/sandbox.bin/lib/libtk8.6.so Tk"
#    ("package ifneeded Tk 8.6.3" script)
#    invoked from within
#"package require Tk"} -errorline 2

  
}

proc ::linuxdeps::install {} {
  set pkg [find-pkg-mgr]
  puts $pkg
  set missing_dep [tk-missing-dep]
  puts $missing_dep
}
