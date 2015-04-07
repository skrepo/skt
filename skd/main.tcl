#
# skd/main.tcl
#
# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  if {[starkit::startup] ne "sourced"} {
      rename ::source ::the-real-source
      proc ::source {args} {
          uplevel ::the-real-source [file join $starkit::topdir $args]
      }
  }
}

proc bgerror {msg} {
    puts "bgerror: $msg"
}

#TODO
# run as daemon with sudo, do initial check to report missing privileges early
# document API for SKU: config, start, stop
# config API - how to pass config with cert files? SKU to provide absolute paths, and split single ovpn file to config and certs/keys if necessary
# periodic health check
# SKU: make config file parser, various formats, canonical way of submitting to SKD
# SKD and SKU: config modifications, work on a raw string with helper functions:
#   ovconf package: canonical representation is "--opt val" string, parse (from multiline), get $opt, set $opt $val, del $opt, extract , save, zip, unzip 
# SKD: on linux replace resolv.conf, how to ensure it is restored? Copy to ".orig" file, SIGINT hook, don't copy/overwrite if resolv.conf already with correct content
# make SKD as close to plain OpenVPN functionality as possible. keep only current config, handle multiple remote, how to handle relative paths to client.crt, should we add mgmt interface listen entry if missing? Also set verbosity to standard level
# don't save config or anything from SKD, should be stateless across SKD reboots
# Linux installer: gui and cmdline version, borrow from activetcl installer script, user to enter sudo password either from gui or cmdline. Or maybe easier to tell user to run with sudo from command line. Eventually installer must be started from command line.
# SKU: check for SKD upgrades, SKU download the upgrade and call SKD to install (because SKD already has sudo)
# Do we need to secure the SKD-SKU channel?
 
# package vs source principle: sourced file may have back/circular references to the caller
package require cmd

package require skutil
package require ovconf
source skmgmt.tcl


proc ResetMgmtState {} {
    state mgmt {
        # mgmt port
        port 0
        # TUN/TAP read bytes
        vread 0
        # TUN/TAP write bytes
        vwrite 0
        # TCP/UDP read bytes
        rread 0
        # TCP/UDP write bytes
        rwrite 0
        # connection state
        connstatus ""
        # virtual IP
        vip ""
        # real IP
        rip ""
    }
}

state skd {
    # skd client socket, also indicates if skd client connected
    sock ""
}


state ovpn {
    # pid also determines openvpn status: started, stopped
    pid 0
    # current openvpn status: connected, disconnected
    connstatus disconnected
    # OpenVPN config as double-dashed one-line string
    config ""
}





proc SkdReportState {} {
    SkdWrite stat [state]
    after 2000 SkdReportState
} 

proc SkdNewConnection {sock peerhost peerport} {
    if {[state skd sock] eq ""} {
        state skd {sock $sock}
        fconfigure $sock -blocking 0 -buffering line
        fileevent $sock readable SkdRead
        catch {puts $sock "ctrl: Welcome to SKD"}
    } else {
        fconfigure $sock -blocking 0 -buffering line
        catch {puts $sock "ctrl: Only single connection allowed"}
        catch {close $sock}
    }
}
 
proc SkdConnectionClosed {} {
    set sock [state skd sock]
    if {$sock eq ""} {
        return
    }
    catch {close $sock}
    state skd {sock ""}
}

proc SkdWrite {prefix msg} {
    set sock [state skd sock]
    if {$sock eq ""} {
        return
    }
    if {[catch {puts $sock "$prefix: $msg"}]} {
        SkdConnectionClosed
    }
}

proc adjust-config {conf} {
    set mgmt [::ovconf::get $conf management]
    if {[lindex $mgmt 0] in {localhost 127.0.0.1} && [lindex $mgmt 1]>0 && [lindex $mgmt 1]<65536} {
        # it's OK
    } else {
        set conf [::ovconf::set $conf management {127.0.0.1 42385}]
    }
    set conf [::ovconf::set $conf verb 3]
    return $conf
}

proc load-config {conf} {
    #TODO add validation of cert and key file existence
    set patherror [::ovconf::check-paths-exist $conf]
    if {$patherror ne ""} {
        return $patherror
    }
    state ovpn {config $conf}
    return ""
}

proc SkdRead {} {
    set sock [state skd sock]
    if {$sock eq ""} {
        return
    }
    if {[gets $sock line] < 0} {
        if {[eof $sock]} {
            SkdConnectionClosed
        }
        return
    }
    switch -regexp -matchvar tokens $line {
        {^stop$} {
            set pid [state ovpn pid]
            if {$pid != 0} {
                exec kill $pid
                OvpnExit 0
            } else {
                SkdWrite ctrl "Nothing to be stopped"
                return
            }
        }
        {^start$} {
            if {[state ovpn config] eq ""} {
                SkdWrite ctrl "No OpenVPN config loaded"
                return
            }
            set pid [state ovpn pid]
            if {$pid != 0} {
                SkdWrite ctrl "OpenVPN already running with pid $pid"
                return
            } else {
                set ovpncmd "openvpn [state ovpn config]"
                set chan [cmd invoke $ovpncmd OvpnExit OvpnRead OvpnErrRead]
                set pid [pid $chan]
                state ovpn {pid $pid}
                SkdWrite ctrl "OpenVPN with pid $pid started"
                SkdReportState
                return
            }
        }
        {^config (.*)$} {
            set config [lindex $tokens 1]
            set config [adjust-config $config]
            set configerror [load-config $config]
            puts "config $config"
            if {$configerror eq ""} {
                SkdWrite ctrl "Config loaded"
            } else {
                SkdWrite ctrl $configerror
            }
            return
        }

    }
}



proc OvpnRead {line} {
    set ignoreline 0
    switch -regexp -matchvar tokens $line {
        {MANAGEMENT: TCP Socket listening on \[AF_INET\]127\.0\.0\.1:(\d+)} {
            state mgmt {port [lindex $tokens 1]}
            #we should call MgmtStarted here, but it was moved after "TCP connection established" 
            #because connecting to mgmt interface too early caused OpenVPN to hang
        }
        {MANAGEMENT: Client connected from \[AF_INET\]127\.0\.0\.1:\d+} {
            #
        }
        {MANAGEMENT: Socket bind failed on local address \[AF_INET\]127\.0\.0\.1:(\d+) Address already in use} {
            #retry/alter port
            MgmtCantStart [lindex $tokens 1]
        }
        {Exiting due to fatal error} {
            OvpnExit 1
        }
        {MANAGEMENT: Client disconnected} {
            #OvpnExit 1
            puts "Client disconnected"
        }
        {MANAGEMENT: CMD 'state'} {
            set ignoreline 1
        }
        {MANAGEMENT: CMD 'status'} {
            set ignoreline 1
        }
        {TCP connection established with \[AF_INET\](\d+\.\d+\.\d+\.\d+):(\d+)} {
            # this only occurs for TCP tunnels = useless for general use
        }
        {TLS: Initial packet from \[AF_INET\](\d+\.\d+\.\d+\.\d+):(\d+)} {
            after idle MgmtStarted [state mgmt port]
        }
        {TUN/TAP device (tun\d+) opened} {
        }
        {Initialization Sequence Completed} {
            state ovpn {connstatus connected}
        }
        {Network is unreachable} {
        }
        {ERROR:.*Operation not permitted} {
            OvpnExit 1
        }
        {SIGTERM.*received, process exiting} {
            OvpnExit 0
        }
        default {
            #puts "OPENVPN UNRECOGNIZED: $line"
        }
    }
    if {!$ignoreline} {
        SkdWrite ovpn $line
        #puts "stdout: $line"
    }
}

#event_wait : Interrupted system call (code=4)
#/sbin/route del -net 10.10.0.1 netmask 255.255.255.255
#/sbin/route del -net 46.165.208.40 netmask 255.255.255.255
#/sbin/route del -net 0.0.0.0 netmask 128.0.0.0
#/sbin/route del -net 128.0.0.0 netmask 128.0.0.0
#Closing TUN/TAP interface
#/sbin/ifconfig tun0 0.0.0.0
#SIGTERM[hard,] received, process exiting
 

#MANAGEMENT: Socket bind failed on local address [AF_INET]127.0.0.1:8888: Address already in use


# this happens after starting openvpn after previous kill -9. It means that the:
# 46.165.208.40   192.168.1.1     255.255.255.255 UGH   0      0        0 wlan0
# route is not removed, others are removed by system because tun0 is destroyed
#ovpn: Mon Mar 30 15:15:52 2015 /sbin/route add -net 46.165.208.40 netmask 255.255.255.255 gw 192.168.1.1
#ovpn: Mon Mar 30 15:15:52 2015 ERROR: Linux route add command failed: external program exited with error status: 7


proc OvpnErrRead {s} {
    puts "stderr: $s"
}

# should be idempotent, as may be called many times on openvpn shutdown
proc OvpnExit {code} {
    #TODO research OpenVPN exit codes and possibly use for troubleshooting
    set pid [state ovpn pid]
    if {$pid != 0} {
        SkdWrite ctrl "OpenVPN with pid $pid stopped"
        after cancel SkdReportState
    }
    state ovpn {connstatus disconnected}
    state ovpn {pid 0}
    ResetMgmtState
}



ResetMgmtState
puts "Starting SKD server"
socket -server SkdNewConnection 7777
vwait forever

