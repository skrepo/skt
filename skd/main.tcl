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
    try {
        if {![unix has-root]} {
            puts stderr "You need to be root. Try again with sudo."
            exit 0
        }
        log Starting SKD server with PID [pid]
        log SKD build version: [build-version]
        log SKD build date: [build-date]
        # intercept termination signals
        signal trap {SIGTERM SIGINT SIGQUIT} main-exit
        # ignore disconnecting terminal - it's supposed to be a daemon. This is causing problem - do not enable. Use linux nohup
        #signal ignore SIGHUP


        # when starting fix resolv.conf if needed
        #TODO restore only if not connected, so mgmt check for ovpn connection status first
        #TODO call it after delay
        dns-restore
        
        log [create-pidfile "/var/run/skd.pid"]


    
        #TODO check if openvpn installed, install otherwise, retry if needed
        #TODO check if X11 running, if so try Tk. If a problem install deps, retry if needed
        #TODO make it after a delay to allow previous dpkg terminate
        #TODO sku must wait and retry 

        #linuxdeps openvpn-install
        #linuxdeps tkdeps-install
    
        model reset-ovpn-state
        # call after reseting model state
        MgmtMonitor
        socket -server SkdNewConnection -myaddr 127.0.0.1 7777
        log Listening on 127.0.0.1:7777
        CyclicSkdReportState
    } on error {e1 e2} {
        log ERROR in main: $e1 $e2
    }
}


# TODO how it works on Windows? Also pidfile
proc main-exit {} {
    log Gracefully exiting SKD
    #TODO wind up
    delete-pidfile /var/run/skd.pid
    exit 0
}

proc SkdReportVersion {} {
    catch {SkdWrite ctrl "version [build-version] [build-date]"}
}

proc SkdReportState {} {
    catch {SkdWrite stat [model model2dict]}
} 

proc CyclicSkdReportState {} {
    SkdReportState
    after 2000 CyclicSkdReportState
} 



# On new connection to SKD, close the previous one
proc SkdNewConnection {sock peerhost peerport} {
    model print 
    if {$::model::Skd_sock ne ""} {
        SkdWrite ctrl "Closing SKD connection $::model::Skd_sock. Superseded by $sock $peerhost $peerport"
        skd-conn-close
    }
    set ::model::Skd_sock $sock
    fconfigure $sock -blocking 0 -buffering line
    fileevent $sock readable SkdRead
    SkdReportVersion
    SkdReportState
}


proc skd-conn-close {} {
    if {$::model::Skd_sock eq ""} {
        return
    }
    log skd-conn-close $::model::Skd_sock
    catch {close $::model::Skd_sock}
    set ::model::Skd_sock ""
}

proc SkdWrite {prefix msg} {
    set sock $::model::Skd_sock
    if {$sock eq ""} {
        return
    }
    if {[catch {puts $sock "$prefix: $msg"; flush $sock;} out err]} {
        log $err
        log Because of error could not SkdWrite: $prefix: $msg
        skd-conn-close
    } else {
        log SkdWrite: $prefix: $msg
    }
}

proc adjust-config {conf} {
    # adjust management port
    set mgmt [::ovconf::get $conf management]
    #TODO replace port to specific number
    if {[lindex $mgmt 0] in {localhost 127.0.0.1} && [lindex $mgmt 1]>0 && [lindex $mgmt 1]<65536} {
        # it's OK
    } else {
        set conf [::ovconf::set $conf management [list 127.0.0.1 $::model::mgmt_port]]
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
    # delete meta info
    set conf [::ovconf::del-meta $conf]
    return $conf
}

# validate config paths and store config in state
proc load-config {conf} {
    # every attempt to load config should reset the previous one
    set ::model::ovpn_config ""
    # sanitize config input
    if {![regexp {^[\d\w\s_:/\-]*$} $config]} {
        return "Config contains illegal characters"
    }
    set patherror [::ovconf::check-paths-exist $conf]
    if {$patherror ne ""} {
        return $patherror
    }
    set ::model::ovpn_config $conf
    return ""
}

proc SkdRead {} {
    try {
        set sock $::model::Skd_sock
        if {$sock eq ""} {
            return
        }
        if {[gets $sock line] < 0} {
            if {[eof $sock]} {
                skd-conn-close
            }
            return
        }
        
        log SkdRead: $line
        switch -regexp -matchvar tokens $line {
            {^stop$} {
                if {[ovpn-pid] != 0} {
                    if {[catch {exec kill [ovpn-pid]} out err]} {
                        log "kill [ovpn-pid] failed"
                        log $out \n $err
                    }
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
                if {[ovpn-pid] != 0} {
                    SkdWrite ctrl "OpenVPN already running with pid [ovpn-pid]"
                    return
                } else {
                    model reset-ovpn-state
                    set config [adjust-config $::model::ovpn_config]
                         

                    set ovpncmd "openvpn $config"
                    set chan [cmd invoke $ovpncmd OvpnExit OvpnRead OvpnErrRead]
                    set ::model::Start_pid [pid $chan]
                    # this call is necessary to update ovpn_pid
                    ovpn-pid
                    SkdWrite ctrl "OpenVPN with pid [ovpn-pid] started"
                    return
                }
            }
            {^config (.+)$} {
                set config [lindex $tokens 1]
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
                # $dir should contain skd, sku.bin and their signatures
                set dir [lindex $tokens 1]
                # if upgrade is successfull it never returns (execl replace program)
                set err [upgrade $dir]
                SkdWrite ctrl [log "Could not upgrade from $dir: $err"]
            }
            default {
                SkdWrite ctrl "Unknown command"
            }
    
        }
    } on error {e1 e2} {
        log "$e1 $e2"
    } finally {
        SkdReportState
    }
}

proc dns-replace {} {
    set dnsip $::model::ovpn_dnsip
    # Do nothing if DNS was not pushed by the server
    if {$dnsip eq ""} {
        return
    }
    # Do not backup resolv.conf if existing resolv.conf was SKD generated
    # It prevents overwriting proper backup
    if {![dns-is-resolv-skd-generated]} {
        if {[catch {file rename -force /etc/resolv.conf /etc/resolv-skd.conf} out err]} {
            log $err
            return
        }
    }
    spit /etc/resolv.conf "$::model::Resolv_marker\nnameserver $dnsip"
}

proc dns-restore {} {
    if {[dns-is-resolv-skd-generated]} {
        if {[catch {file copy -force /etc/resolv-skd.conf /etc/resolv.conf} out err]} {
            # Not really an error, resolv-skd.conf may be non-existing for many reasons
            log "INFO: /etc/resolv-skd.conf does not exist"
        }
    }
}

proc dns-read-resolv {} {
    # Read existing resolv.conf
    if {[catch {set resolv [slurp /etc/resolv.conf]} out err]} {
        # log and ignore error
        log $err
        set resolv ""
    }
    return $resolv
}

proc dns-is-resolv-skd-generated {} {
    return [string match *$::model::Resolv_marker* [dns-read-resolv]]
}


# again reduce SKD functionality to minimum
# SKD only to verify signature and replace skd and sku.bin
# dir - folder where new skd and sku.bin and signatures are placed
proc upgrade {dir} {
    # replace the current program with new version - effectively restart from the new binary, PID is preserved
    try {
        if {![file isdirectory $dir]} {
            return [log Upgrade failed because there is no $dir directory]
        }
        # backup id
        set bid [rand-big]
        set skdpath /usr/local/sbin/skd.bin
        set newskd [file join $dir skd.bin]
        set bskd /tmp/skd.bin-backup-$bid
        set skupath /usr/local/bin/sku.bin
        set newsku [file join $dir sku.bin]
        set bsku /tmp/sku.bin-backup-$bid

        if {![verify-signature /etc/skd/keys/skt_public.pem $newskd]} {
            return [log Upgrade failed because SKD signature verification failed]
        }
        if {![verify-signature /etc/skd/keys/skt_public.pem $newsku]} {
            return [log Upgrade failed because SKU signature verification failed]
        }
        # replace skd
        # rename is necessary to prevent "cannot create regular file ...: Text file busy" error
        # we must use external system commands for skd since the file command does not work on the currently running program
        exec mv $skdpath $bskd
        exec cp -f $newskd $skdpath
        exec chmod u+rwx,go+rx $skdpath
        # replace sku.bin
        # so sku.bin is deployed here with root rights, but sku must restart itself
        file rename -force $skupath $bsku
        file copy -force $newsku $skupath
        file attributes $skupath -permissions u+rwx,go+rx
        # replace sku.bin

        # if this does not fail it never returns
        execl /usr/local/sbin/skd.bin
    } on error {e1 e2} {
        # restore SKD and SKU from the backup path
        catch {
            if {[file isfile $bskd]} {
                file delete -force $skdpath
                file rename -force $bskd $skdpath
            }
        }
        catch {
            if {[file isfile $bsku]} {
                file delete -force $skupath
                file rename -force $bsku $skupath
            }
        }
        log $e1 $e2
        return $e1
    }
    return "upgrade unexpected error"
}


proc OvpnRead {line} {
    try {
        set ignoreline 0
        switch -regexp -matchvar tokens $line {
            {MANAGEMENT: TCP Socket listening on \[AF_INET\]127\.0\.0\.1:(\d+)} {
                # update the mgmt port in case we had to choose another port than default from the model
                set ::model::mgmt_port [lindex $tokens 1]
                #we should call MgmtStart here, but it was moved after "TCP connection established" 
                #because connecting to mgmt interface too early caused OpenVPN to hang
            }
            {MANAGEMENT: Client connected from \[AF_INET\]127\.0\.0\.1:\d+} {
                #
            }
            {MANAGEMENT: Socket bind failed on local address \[AF_INET\]127\.0\.0\.1:(\d+) Address already in use} {
                # TODO what to do? 
                # busy mgmt port most likely means that openvpn is already running
                # on rare occasions it may be occupied by other application
                #retry/alter port
            }
            {Exiting due to fatal error} {
                OvpnExit 1
            }
            {MANAGEMENT: Client disconnected} {
                log Management client disconnected
            }
            {MANAGEMENT: CMD 'state'} {
                set ignoreline 1
            }
            {MANAGEMENT: CMD 'status'} {
                set ignoreline 1
            }
            {MANAGEMENT: CMD 'pid'} {
                set ignoreline 1
            }
            {TCP connection established with \[AF_INET\](\d+\.\d+\.\d+\.\d+):(\d+)} {
                # this only occurs for TCP tunnels = useless for general use
            }
            {TLS: Initial packet from \[AF_INET\](\d+\.\d+\.\d+\.\d+):(\d+)} {
                #after idle MgmtStarted $::model::mgmt_port
            }
            {TUN/TAP device (tun\d+) opened} {
            }
            {Initialization Sequence Completed} {
                MgmtStatus
                dns-replace
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
    } on error {e1 e2} {
        log $e1 $e2
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
    if {[ovpn-pid] != 0} {
        SkdWrite ctrl "OpenVPN with pid [ovpn-pid] stopped"
    }
    dns-restore
    model reset-ovpn-state
}


proc build-version {} {
    memoize
    return [string trim [slurp [file join [file dir [info script]] buildver.txt]]]
}

proc build-date {} {
    memoize
    return [string trim [slurp [file join [file dir [info script]] builddate.txt]]]
}

proc ovpn-pid {} {
    # if Mgmt_pid up to date
    if {$::model::Mgmt_pid != 0 && [clock milliseconds] - $::model::Mgmt_pid_tstamp < 2000} {
        set ::model::ovpn_pid $::model::Mgmt_pid
    } else {
        set ::model::ovpn_pid $::model::Start_pid
    }
    return $::model::ovpn_pid
}



# TODO
proc ovpn-is-connected {} {
#    if {[dict get $stat ovpn_pid] == 0} 
#        set connstatus disconnected
#    elseif {[dict get $stat mgmt_connstatus] eq "CONNECTED"} 
}

# TODO
proc mgmt-is-connected {} {
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
