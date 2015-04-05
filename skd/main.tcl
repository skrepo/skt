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

#TODO
# don't save config or anything from SKD, should be stateless across SKD reboots
# run as daemon with sudo, do initial check to report missing privileges early
# document API for SKU: config, start, stop
# config API - how to pass config with cert files? SKU to provide absolute paths, and split single ovpn file to config and certs/keys if necessary
# (OpenVPN allows including files in the main configuration for the --ca, --cert, --dh, --extra-certs, --key, --pkcs12, --secret and --tls-auth options.)
# periodic health check
# make the config file parser, various formats, canonical way of submitting them to SKD - this should be on SKU client
# make SKD as close to plain OpenVPN functionality as possible. keep only current config, handle multiple remote, how to handle relative paths to client.crt, should we add mgmt interface listen entry if missing? Also set verbosity to standard level
 
# package vs source principle: sourced file may have back/circular references to the caller
package require cmd

package require skutil
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
    # config dictionary, initially empty
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

# return error description on parse error, otherwise empty string
# TODO consider storing config as a string and write accessor/mutator functions
proc ParseOvpnConfig {s} {
    set s [string trim $s]
    if {[regexp -- {^--} $s]} {
        set k ""
        set v ""
        foreach w $s {
            if {[regexp -- {^(--.+)$} $w _ option]} {
                if {$k ne ""} {
                    state ovpn config [list $k $v]
                }
                set k $option
                set v ""
            } else {
                set v [string trim "$v $w"]
            }
        }
        state ovpn config [list $k $v]
    } else {
        return "OpenVPN config line should start with '--'"
    }
    #TODO add validation of cert and key file existence
    #TODO add adjustments: verbosity, management port
    #puts [state ovpn config]
    return
}

proc SerializeOvpnConfig {c} {
    return [join $c]
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
                set config [state ovpn config]
                #set ovpncmd {openvpn --client --pull --dev tun --proto tcp --remote 46.165.208.40 443 --resolv-retry infinite --nobind --persist-key --persist-tun --mute-replay-warnings --ca ca.crt --cert client.crt --key client.key --ns-cert-type server --comp-lzo --verb 3 --keepalive 5 28 --route-delay 3 --management localhost 8888}
                #set ovpncmd {openvpn --client --pull --dev tun --proto udp --remote 46.165.208.40 123 --resolv-retry infinite --nobind --persist-key --persist-tun --mute-replay-warnings --ca ca.crt --cert client.crt --key client.key --ns-cert-type server --comp-lzo --verb 3 --keepalive 5 28 --route-delay 3 --management localhost 8888}
                set ovpncmd "openvpn [SerializeOvpnConfig $config]"
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
            set parseerror [ParseOvpnConfig $config]
            if {$parseerror eq ""} {
                #config accepted
                SkdWrite ctrl "Config loaded"
            } else {
                SkdWrite ctrl $parseerror
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

