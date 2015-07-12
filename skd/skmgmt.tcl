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
        log "MGMT: $line"
        switch -regexp -matchvar tokens $line {
            {^TUN/TAP read bytes,(\d+)$} {
                set ::model::mgmt_vread [lindex $tokens 1]
            }
            {^TUN/TAP write bytes,(\d+)$} {
                set ::model::mgmt_vwrite [lindex $tokens 1]
            }
            {^TCP/UDP read bytes,(\d+)$} {
                set ::model::mgmt_rread [lindex $tokens 1]
            }
            {^TCP/UDP write bytes,(\d+)$} {
                set ::model::mgmt_rwrite [lindex $tokens 1]
            }

            {(\d+),(.+),(.*),(.*),(.*)} {
                # For example:
                # 1436527709,AUTH,,,
                # 1436527711,GET_CONFIG,,,
                # 1436527712,ASSIGN_IP,,10.13.0.6,
                # 1436527715,CONNECTED,SUCCESS,10.13.0.6,78.129.174.84
                set connstatus [lindex $tokens 2]
                set ::model::mgmt_vip [lindex $tokens 4]
                set ::model::mgmt_rip [lindex $tokens 5]
                # immediately report the change to CONNECTED status to a client by calling SkdReportState
                if {$connstatus eq "CONNECTED" && $::model::mgmt_connstatus ne "CONNECTED"} {
                    set ::model::mgmt_connstatus $connstatus
                    SkdReportState
                } else {
                    set ::model::mgmt_connstatus $connstatus
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

