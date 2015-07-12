#
# skd/main.tcl
#
# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
}

# package vs source principle: sourced file may have back/circular references to the caller (to be avoided)
package require cmd
package require ovconf
# Tclx for signal trap
package require Tclx
# Tclx litters global namespace. Need to clean up to avoid conflict with csp
rename ::select ""
package require linuxdeps
# skutil must be last required package in order to overwrite the log proc from Tclx
# using skutil log to stdout
package require skutil

source [file join [file dir [info script]] model.tcl]
source [file join [file dir [info script]] skmgmt.tcl]

proc background-error {msg e} {
    set pref [lindex [info level 0] 0]
    log $pref: $msg
    dict for {k v} $e {
        log $pref: $k: $v
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
# make SKD as close to plain OpenVPN functionality as possible. keep only current config, handle multiple remote, how to handle relative paths to client.crt, should we add mgmt interface listen entry if missing? Also set verbosity to standard level
# don't save config or anything from SKD, should be stateless across SKD reboots
# SKU: check for SKD upgrades, SKU download the upgrade and call SKD to install (because SKD already has sudo)
# Do we need to secure the SKD-SKU channel? only for upgrades (installing arbitrary code) - the signature must be verified - public key distributed with skt. Check signatures with openssl
#
 
 
proc main {} {
    log Starting SKD server
    # intercept termination signals
    signal trap {SIGTERM SIGINT SIGQUIT} main-exit
    # ignore disconnecting terminal - it's supposed to be a daemon. This is causing problem - do not enable. Use linux nohup
    #signal ignore SIGHUP
    
    create-pidfile /var/run/skd.pid

    #TODO check if openvpn installed, install otherwise, retry if needed
    #TODO check if X11 running, if so try Tk. If a problem install deps, retry if needed
    linuxdeps openvpn-install
    linuxdeps tkdeps-install

    model reset-ovpn-state
    socket -server SkdNewConnection -myaddr 127.0.0.1 7777
}


# TODO how it works on Windows? Also pidfile
proc main-exit {} {
    log Gracefully exiting SKD
    #TODO wind up
    delete-pidfile /var/run/skd.pid
    exit 0
}


proc SkdReportState {} {
    SkdWrite stat [model model2dict]
    after 2000 SkdReportState
} 

proc SkdNewConnection {sock peerhost peerport} {
    set prev_client $::model::skd_sock
    # if previous saved socked is not open do cleanup
    if {$prev_client ne "" && ![chan-is-open $prev_client]} {
        SkdConnectionClosed
    }
    if {$prev_client eq ""} {
        set ::model::skd_sock $sock
        fconfigure $sock -blocking 0 -buffering line
        fileevent $sock readable SkdRead
        catch {puts $sock "ctrl: Welcome to SKD"}
    } else {
        fconfigure $sock -blocking 0 -buffering line
        catch {puts $sock "ctrl: Only a single connection allowed"}
        catch {close $sock}
    }
}


proc SkdConnectionClosed {} {
    set sock $::model::skd_sock
    if {$sock eq ""} {
        return
    }
    log SkdConnectionClosed 
    catch {close $sock}
    set ::model::skd_sock ""
}

proc SkdWrite {prefix msg} {
    set sock $::model::skd_sock
    if {$sock eq ""} {
        log Because of empty sock could not SkdWrite: $prefix: $msg
        return
    }
    if {[catch {puts $sock "$prefix: $msg"} out err]} {
        log $err
        log Because of error could not SkdWrite: $prefix: $msg
        SkdConnectionClosed
    } else {
        log SkdWrite: $prefix: $msg
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
    # add suppressing timestamps
    set conf [::ovconf::set $conf suppress-timestamps]
    # adjust windows specific options
    if {$::tcl_platform(platform) ne "windows"} {
        set conf [::ovconf::del-win-specific $conf]
    }
    # adjust deprecated options
    set conf [::ovconf::del-deprecated $conf]
    return $conf
}

# validate config paths and store config in state
proc load-config {conf} {
    set patherror [::ovconf::check-paths-exist $conf]
    if {$patherror ne ""} {
        return $patherror
    }
    set ::model::ovpn_config $conf
    return ""
}

proc SkdRead {} {
    set sock $::model::skd_sock
    if {$sock eq ""} {
        return
    }
    if {[gets $sock line] < 0} {
        if {[eof $sock]} {
            SkdConnectionClosed
        }
        return
    }
    
    log SkdRead: $line
    switch -regexp -matchvar tokens $line {
        {^stop$} {
            set pid $::model::ovpn_pid
            if {$pid != 0} {
                exec kill $pid
                OvpnExit 0
            } else {
                SkdWrite ctrl "Nothing to be stopped"
                return
            }
        }
        {^start$} {
            if {$::model::ovpn_config eq ""} {
                SkdWrite ctrl "No OpenVPN config loaded"
                return
            }
            set pid $::model::ovpn_pid
            if {$pid != 0} {
                SkdWrite ctrl "OpenVPN already running with pid $pid"
                return
            } else {
                model reset-ovpn-state
                set ovpncmd "openvpn $::model::ovpn_config"
                set chan [cmd invoke $ovpncmd OvpnExit OvpnRead OvpnErrRead]
                set pid [pid $chan]
                set ::model::ovpn_pid $pid
                set ::model::ovpn_connstatus connecting
                SkdWrite ctrl "OpenVPN with pid $pid started"
                SkdReportState
                return
            }
        }
        {^status$} {
            # TODO there is redundant information in pid (started,stopped) and connstatus (disconnected,connecting,connected)- make sure they are in sync
            # TODO get that information in real time: check mgmt connection, run state command
            SkdWrite ctrl "OpenVPN status $::model::ovpn_connstatus"
        }
        {^config (.+)$} {
            # TODO pass meta info in config (city, country, etc) for sending info back to SKU. Also to have a first hand info about connection to display
            set config [lindex $tokens 1]
            set config [adjust-config $config]
            set configerror [load-config $config]
            log config $config
            if {$configerror eq ""} {
                SkdWrite ctrl "Config loaded"
            } else {
                SkdWrite ctrl $configerror
            }
            return
        }
        {^upgrade (.+)$} {
            log $line
            set pkg [lindex $tokens 1]
            if {[upgrade $pkg]} {
                SkdWrite ctrl "Upgraded $pkg"
            } else {
                SkdWrite ctrl "Could not upgrade $pkg"
            }
        }
        default {
            SkdWrite ctrl "Unknown command"
        }

    }
}

proc replace-dns {} {
    set dnsip $::model::ovpn_dnsip
    # Do nothing if DNS was not pushed by the server
    if {$dnsip eq ""} {
        return
    }
    # Read existing resolv.conf
    if {[catch {set resolv [slurp /etc/resolv.conf]} out err]} {
        # log and ignore error
        log $err
        set resolv ""
    }
    # Do not backup resolv.conf if existing resolv.conf was SKD generated
    # It prevents overwriting proper backup
    if {![string match "*DO NOT MODIFY - SKD generated*" $resolv]} {
        if {[catch {file rename -force /etc/resolv.conf /etc/resolv-skd.conf} out err]} {
            log $err
            return
        }
    }
    spit /etc/resolv.conf "#DO NOT MODIFY - SKD generated\nnameserver $dnsip"
}

proc restore-dns {} {
    if {[catch {file copy -force /etc/resolv-skd.conf /etc/resolv.conf} out err]} {
        # Not really an error, resolv-skd.conf may be non-existing for many reasons
        log "INFO: /etc/resolv-skd.conf does not exist"
    }
}

# again reduce SKD functionality to minimum
# SKD only to verify signature and install package
# install only deb/rpm - it simplifies packaging (eliminate zipping), signature verification and autorun 
proc upgrade {filepath} {
    if {[verify-signature /etc/skd/keys/skt_public.pem $filepath]} {
        switch -regexp -matchvar tokens $filepath {
            {.+\.(deb|rpm)$} {
                set inst [linuxdeps ext2installer [lindex $tokens 1]]
                if {[catch {exec $inst -i $filepath} out err]} {
                    log $out
                    log $err
                    return 0
                } else {
                    log $out
                    log $filepath installed with $inst
                    return 1
                }
            }
            default {
                log Wrong upgrading file $filepath. It should be deb or rpm package
                return 0
            }
        }
    } else {
        log Upgrade failed because signature verification failed
        return 0
    }
}


proc OvpnRead {line} {
    set ignoreline 0
    switch -regexp -matchvar tokens $line {
        {MANAGEMENT: TCP Socket listening on \[AF_INET\]127\.0\.0\.1:(\d+)} {
            set ::model::mgmt_port [lindex $tokens 1]
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
            log Management client disconnected
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
            after idle MgmtStarted $::model::mgmt_port
        }
        {TUN/TAP device (tun\d+) opened} {
        }
        {Initialization Sequence Completed} {
            set ::model::ovpn_connstatus connected
            replace-dns
        }
        {Network is unreachable} {
        }
        {ERROR:.*Operation not permitted} {
            OvpnExit 1
        }
        {SIGTERM.*received, process exiting} {
            OvpnExit 0
        }
        {PUSH: Received control message} {
            # We need to handle PUSH commands from the openvpn server. Primarily DNS because we need to change resolv.conf
            #PUSH: Received control message: 'PUSH_REPLY,redirect-gateway def1 bypass-dhcp,dhcp-option DNS 10.10.0.1,route 10.10.0.1,topology net30,ping 5,ping-restart 28,ifconfig 10.10.0.66 10.10.0.65'
            if {[regexp {dhcp-option DNS (\d+\.\d+\.\d+\.\d+)} $line _ dnsip]} {
                set ::model::ovpn_dnsip $dnsip
            }
        }
        default {
            #log OPENVPN: $line
        }
    }
    if {!$ignoreline} {
        SkdWrite ovpn $line
        log OPENVPN: $line
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


proc OvpnErrRead {line} {
    #TODO communicate error to user. gui and cli
    log openvpn stderr: $line
    SkdWrite ovpn "stderr: $line"
}

# should be idempotent, as may be called many times on openvpn shutdown
proc OvpnExit {code} {
    set ::model::ovpn_connstatus disconnected
    set pid $::model::ovpn_pid
    if {$pid != 0} {
        SkdWrite ctrl "OpenVPN with pid $pid stopped"
        after cancel SkdReportState
    }
    restore-dns
    model reset-ovpn-state
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

main

vwait forever

