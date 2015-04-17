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
}

proc ::linuxdeps::install {} {

}
