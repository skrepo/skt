#
# skd/skmgmt.tcl
#

proc MgmtConnect {port} {
    #TODO handle error
    set sock [socket 127.0.0.1 $port]
    chan configure $sock -blocking 0 -buffering line
    chan event $sock readable [list MgmtRead $sock]
    return $sock
}

proc MgmtRead {sock} {
    if {[gets $sock line] >= 0} {
        switch -regexp -matchvar tokens $line {
            {^TUN/TAP read bytes,(\d+)$} {
                state mgmt {vread [lindex $tokens 1]}
            }
            {^TUN/TAP write bytes,(\d+)$} {
                state mgmt {vwrite [lindex $tokens 1]}
            }
            {^TCP/UDP read bytes,(\d+)$} {
                state mgmt {rread [lindex $tokens 1]}
            }
            {^TCP/UDP write bytes,(\d+)$} {
                state mgmt {rwrite [lindex $tokens 1]}
            }
            {(\d+),(.+),(.*),(.*),(.*)} {
                set connstatus [lindex $tokens 2]
                set vip [lindex $tokens 4]
                set rip [lindex $tokens 5]
                # it's a state cmd update only if vip and rip are IPs or empty
                if {([is-valid-ip $vip] || $vip eq "") && ([is-valid-ip $rip] || $rip eq "")} {
                    state mgmt {connstatus [lindex $tokens 2]}
                    state mgmt {vip [lindex $tokens 4]}
                    state mgmt {rip [lindex $tokens 5]}
                }
            }
            {FATAL:ERROR:.*Operation not permitted} {
                #when run without sudo, should be handled from direct ovpn logs
            }
            "OpenVPN Management Interface Version" -
            pre-compress -
            post-compress -
            pre-decompress -
            post-decompress -
            "OpenVPN STATISTICS" -
            Updated, -
            "Auth read bytes" -
            END {
                #ignore
            }
            default {
                #unrecognized openvpn mgmt interface output
                puts "MGMT UNRECOGNIZED: $line"
            }
        }
    }
    if {[eof $sock]} {
        MgmtClosed $sock
    }
}


proc MgmtWrite {sock} {
    if {[catch {puts $sock status; puts $sock state}]} {
        MgmtClosed $sock
    } else {
        after 2000 MgmtWrite $sock
    }
}

proc MgmtStarted {port} {
    set sock [MgmtConnect $port]
    after idle MgmtWrite $sock
}

proc MgmtClosed {sock} {
    catch {close $sock}
    #TODO what to do with mgmt closed?
}

proc MgmtCantStart {port} {
    #TODO
}

