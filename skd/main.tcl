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

proc background-error {msg e} {
    set pref [lindex [info level 0] 0]
    puts "$pref: $msg"
    dict for {k v} $e {
        puts "$pref: $k: $v"
    }
}

interp bgerror "" background-error
#after 2000 {error "This is my bg error"}





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
package require Expect
#package require cmdline
source skmgmt.tcl


proc create-pidfile {} {
    set fd [open /var/run/skd.pid w]
    puts $fd [pid]
    close $fd
}

proc delete-pidfile {} {
    file delete /var/run/skd.pid
}
 
# TODO how it works on Windows? Also pidfile
proc sigint_handler {} {
    puts "Gracefully exiting SKD"
    #TODO wind up
    delete-pidfile
    exit 0
}
 
# intercept termination signals
trap sigint_handler {SIGINT SIGTERM SIGQUIT}
# ignore disconnecting terminal - it's supposed to be a daemon. This is causing problem - do not enable. Use linux nohup
#trap SIG_IGN SIGHUP



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
    # adjust management port
    set mgmt [::ovconf::get $conf management]
    if {[lindex $mgmt 0] in {localhost 127.0.0.1} && [lindex $mgmt 1]>0 && [lindex $mgmt 1]<65536} {
        # it's OK
    } else {
        set conf [::ovconf::set $conf management {127.0.0.1 42385}]
    }
    # adjust verbosity
    set conf [::ovconf::set $conf verb 3]
    # adjust windows specific options
    if {$::tcl_platform(platform) ne "windows"} {
        set conf [::ovconf::del-win-specific $conf]
    }
    # adjust deprecated options
    set conf [::ovconf::del-deprecated $conf]
    return $conf
}

proc load-config {conf} {
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



#>>ovpn: Wed Apr 08 09:26:43 2015 TAP-WIN32 device [Local Area Connection 2] opened: \\.\Global\{BDCE36A3-CE0B-4370-900A-03F12CDD67C5}.tap
#>>ovpn: Wed Apr 08 09:26:43 2015 TAP-Windows Driver Version 9.8
#>>ovpn: Wed Apr 08 09:26:43 2015 MANAGEMENT: Client disconnected
#>>ovpn: Wed Apr 08 09:26:43 2015 ERROR:  This version of OpenVPN requires a TAP-Windows driver that is at least version 9.9 -- If you recently upgraded your OpenVPN distribution, a reboot is probably required at this point to get Windows to see the new driver.

#Ethernet adapter Local Area Connection 3:
#
#        Media State . . . . . . . . . . . : Media disconnected
#        Description . . . . . . . . . . . : TAP-Win32 Adapter V9 #2
#        Physical Address. . . . . . . . . : 00-FF-3E-A0-C7-D3
#
#Ethernet adapter Local Area Connection 2:
#
#        Connection-specific DNS Suffix  . :
#        Description . . . . . . . . . . . : TAP-Win32 Adapter V9
#        Physical Address. . . . . . . . . : 00-FF-BD-CE-36-A3
#        Dhcp Enabled. . . . . . . . . . . : Yes
#        Autoconfiguration Enabled . . . . : Yes
#        IP Address. . . . . . . . . . . . : 10.11.5.22
#        Subnet Mask . . . . . . . . . . . : 255.255.255.252
#        Default Gateway . . . . . . . . . : 10.11.5.21
#        DHCP Server . . . . . . . . . . . : 10.11.5.21
#        DNS Servers . . . . . . . . . . . : 10.11.0.1
#        Lease Obtained. . . . . . . . . . : 8 kwietnia 2015 09:35:58
#        Lease Expires . . . . . . . . . . : 7 kwietnia 2016 09:35:58


# On Windows to check installed drivers:
# driverquery /FO list /v
# sample output:
# ...
#Link Date:         2008-04-13 20:15:55
#Path:              C:\WINDOWS\system32\drivers\sysaudio.sys
#Init(bytes):       2˙816,00
#
#Module Name:       tap0901
#Display Name:      TAP-Win32 Adapter V9
#Description:       TAP-Win32 Adapter V9
#Driver Type:       Kernel 
#Start Mode:        Manual
#State:             Running
#Status:            OK
#Accept Stop:       TRUE
#Accept Pause:      FALSE
#Paged Pool(bytes): 0,00
#Code(bytes):       20˙480,00
#BSS(bytes):        0,00
#Link Date:         2011-03-24 21:20:11
#Path:              C:\WINDOWS\system32\DRIVERS\tap0901.sys
#Init(bytes):       4˙096,00
#
#Module Name:       Tcpip
#Display Name:      TCP/IP Protocol Driver
#Description:       TCP/IP Protocol Driver
#...

# After tun/tap driver update to OpenVPN 2.3.6 the only things that have changed in driver data:
#Code(bytes):       19˙968,00
#Link Date:         2013-08-22 13:40:00
#Path:              C:\WINDOWS\system32\DRIVERS\tap0901.sys
#Init(bytes):       1˙664,00

# Consider including sysinternals sigcheck in deployment that will produce the following:
#        Verified:       Signed
#        Signing date:   13:40 2013-08-22
#        Publisher:      OpenVPN Technologies
#        Description:    TAP-Windows Virtual Network Driver
#        Product:        TAP-Windows Virtual Network Driver
#        Prod version:   9.9.2 9/9
#        File version:   9.9.2 9/9 built by: WinDDK
#        MachineType:    32-bit


# cmdline options not really needed yet
#set options {
#            {a             "set the atime only"}
#            {m             "set the mtime only"}
#            {p.arg  57328  "skd port"}
#            {r.arg  ""     "use time from ref_file"}
#            {t.arg  -1     "use specified time"}
#        }
#set usage ": skd \[options]\noptions:"
#if {[catch {array set params [::cmdline::getoptions argv $options $usage]}]} {
#    puts [cmdline::usage $options $usage]
#    exit -1
#}
#
#set has_t [expr {$params(t) != -1}]
#set has_r [expr {[string length $params(r)] > 0}]
#if {$has_t && $has_r} {
#    return -code error "Cannot specify both -r and -t"
#} elseif {$has_t} {
#...
#}
#parray params

#set SKDPORT $params(p)

create-pidfile

ResetMgmtState
puts "Starting SKD server"
socket -server SkdNewConnection 7777
vwait forever
delete-pidfile

