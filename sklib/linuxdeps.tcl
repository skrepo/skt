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
  catch {package require dksjfds} out err
  puts "OUT: $out"
  puts "ERR: $err"
# When package missing:
#OUT: can't find package dksjfds
#ERR: -code 1 -level 0 -errorstack {INNER {invokeStk1 package require dksjfds} CALL tk-missing-dep} -errorcode {TCL PACKAGE UNFOUND} -errorinfo {can't find package dksjfds
#    while executing
#"package require dksjfds"} -errorline 2

}

proc ::linuxdeps::install {} {
  set pkg [find-pkg-mgr]
  puts $pkg
  tk-missing-dep
}
