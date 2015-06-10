package provide unix 0.0.0
package require Tclx

namespace eval ::unix {
    namespace export relinquish-root is-x-running
    namespace ensemble create
}


# Best effort drop superuser rights
# If Unix user originally was logged as non-root (from logname)
# drop root privileges by changing uid and gid and return that user name
# Do nothing if root from the ground up, return "root" then
# Also do nothing if currently non-root
proc ::unix::relinquish-root {} {
    # id command from Tclx package
    if {[id user] ne "root"} {
        return [id user]
    }
    # When running starpack in background (with &) logname may error with "logname: no login name"
    if {[catch {exec logname} user]} {
        # Fall back to checking SUDO_USER
        set user $::env(SUDO_USER)
        # If empty then I don't know, assume root
        if {[llength $user] == 0} {
            set user root
        }
    }
    if {$user eq "root"} {
        return root
    }
    set primary_group [exec id -g -n $user]
    # the order is relevant - first change gid then uid
    id group $primary_group
    id user $user
    return $user
}


# Check if X11 server is running
# by probing existence of $DISPLAY env variable
proc ::unix::is-x-running {} {
    return [expr {[array get ::env DISPLAY] ne ""}]
}
