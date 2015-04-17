package provide unix 0.0.0
package require Tclx

namespace eval ::unix {
    namespace export relinquish-root
    namespace ensemble create
}


# Best effort drop superuser rights
# If Unix user originally was logged as non-root (from logname)
# drop root privileges by changing uid and gid and return that user name
# Do nothing if root from the ground up, return "root" then
# Also do nothing if currently non-root
proc ::unix::relinquish-root {} {
    if {[id user] ne "root"} {
        return [id user]
    }
    set logname [exec logname]
    if {$logname eq "root"} {
        return root
    }
    set primary_group [exec id -g -n $logname]
    # the order is relevant - first change gid then uid
    id group $primary_group
    id user $logname
    return $logname
}
