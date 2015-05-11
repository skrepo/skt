#
# sku.tcl
#
# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
}

package require ovconf
package require tls
#package require http
package require cmdline
package require unix
package require linuxdeps
#http::register https 443 [list tls::socket]
# skutil must be last required package in order to overwrite the log proc from Tclx
package require skutil
package require https

set ::LOGFILE ~/.sku/sku.log

proc fatal {msg err} {
    log $err
    in-ui error $msg
    main-exit
}

proc background-error {msg err} {
    fatal $msg [dict get $err -errorinfo]
}

interp bgerror "" background-error
#after 4000 {error "This is my bg error"}


namespace eval tolog {
    variable fh
    proc initialize {args} {
        variable fh
        # if for some reason cannot log to file, log to stderr
        if {[catch {mk-head-dir $::LOGFILE} out err] || [catch {set fh [open $::LOGFILE w]} out err]} {
            set fh stderr
            puts stderr $err
        }
        info procs
    }
    proc finalize {args} {
        variable fh
        catch {close $fh}
    }
    proc clear {args} {}
    proc flush {handle} {
        variable fh
        if {[catch {::flush $fh} out err]} {
            set fh stderr
            puts stderr $err
        }
    }
    proc write {handle data} {
        variable fh
        # again, downgrade to logging to stderr if problems with writing to file
        if {[catch {puts -nonewline $fh $data} out err]} {
            set fh stderr
            puts stderr $err
        }
        flush $fh
    }
    namespace export *
    namespace ensemble create
}



proc redirect-stdout {} {
    chan push stdout tolog
}



# Parse command line options and launch proper task
# It may set global variables
proc main {} {
    set user [unix relinquish-root]
    redirect-stdout
    dbg user
    

    state sku {
        # SKD connection socket 
        skd_sock ""
        # User Interface (gui or cli)
        ui ""
        # Start retries
        start_retries 0
        # Embedded bootstrap vigo list
        vigos ""
        # Index of last attempted/next vigo from the list
        vigo_next 0
        # Attempt counter for welcome message requests
        welcome_retry 1
    }


    # watch out - cmdline is buggy. For example you cannot define help option, it conflicts with the implicit one
    set options {
            {cli            "Run command line interface (CLI) instead of GUI"}
            {generate-keys  "Generate private key and certificate signing request"}
            {version        "Print version"}
            {p              "Print anything"}
            {ra             "Print anything"}
        }
    set usage ": sku \[options]\noptions:"
    if {[catch {array set params [::cmdline::getoptions ::argv $options $usage]}]} {
        log [cmdline::usage $options $usage]
        exit 1
    }
    log Params:
    parray params

    # embedded bootstrap vigo list
    set lst [slurp [file join $starkit::topdir bootstrap_ips.lst]]
    set vigos ""
    foreach v $lst {
        set v [string trim $v]
        if {[is-valid-ip $v]} {
            lappend vigos $v
        }
    }
    state sku {vigos $vigos}
    puts "vigos: $vigos"
    #TODO use vigos to get current time - why do we need it before welcome?.
    #TODO isn't certificate signing start date a problem in case of vigos in different timezones? Consider signing with golang crypto libraries
    
    # Copy cadir because it  must be accessible from outside of starkit
    # Overwrites certs on every run
    set cadir [file normalize ~/.sku/certs]
    copy-merge [file join $::starkit::topdir certs] $cadir
    https init -cadir $cadir
 

    if {$params(generate-keys)} {
        main-generate-keys
        main-exit
    }
    if {$params(version)} {
        main-version
        main-exit
    }

    if {$params(cli) || ![unix is-x-running]} {
        state sku {ui cli}
    } else {
        state sku {ui gui}
    }

    if {[catch {create-pidfile ~/.sku/sku.pid} out err]} {
        fatal "Could not create ~/.sku/sku.pid file" $err
    }
    skd-connect 7777
    after idle main-start
}


proc main-exit {} {
    if {[catch {delete-pidfile ~/.sku/sku.pid} out err]} {
        # don't use fatal here to avoid endless loop
        puts stderr "Could not delete ~/.sku/sku.pid file"
        puts stderr $err
    }
    set ::until_exit 1
    #TODO Disconnect and clean up
    catch {close [state sku skd_sock]}
    catch {destroy .}
    exit
}


# it may be called many times by events retrying to start after lib install
proc main-start {} {

    set retries [state sku start_retries]
    state sku {start_retries [incr retries]}
    log start_retries: [state sku start_retries]
    # give up after a number of retries
    if {$retries > 5} {
        in-ui error "Could not main-start after a number of retries"
        return
    }

    # Ignore result of openvpn install - it may be handled later, when GUI is running
    check-openvpn-deps

    if {[state sku ui] eq "gui"} {
        log Running check-tk-deps
        # if no missing libs start UI
        if {![check-tk-deps]} {
            in-ui main
        }
    }
}

# Combine $fun and $ui to run proper procedure in gui or cli
proc in-ui {fun args} {
    set ui [state sku ui]
    [join [list $fun $ui] -] {*}$args
}


proc error-gui {msg} {
    # if Tk not functional downgrade displaying errors to cli
    if {[is-tk-loaded]} {
        # hide toplevel window. Use wm deiconify to restore later
        catch {wm withdraw .}
        log $msg
        tk_messageBox -title "SKU error" -type ok -icon error -message ERROR -detail "$msg\n\nPlease check ~/.sku/sku.log for details"
    } else {
        error-cli $msg
    }
}

proc error-cli {msg} {
    log $msg
    puts stderr $msg
}


# Check if openvpn is installed. 
# If not send pkg-install request to SKD
# Return 1 if request sent, 0 otherwise
proc check-openvpn-deps {} {
    if {![linuxdeps is-openvpn-installed]} {
        skd-write "pkg-install openvpn"
        return 1
    } else {
        return 0
    }
}

# Check if there is a missing lib that Tk depends on
# If so send lib-install request to SKD
# Return 1 if request sent, 0 otherwise
proc check-tk-deps {} {
    set missing_lib [linuxdeps tk-missing-lib]
    if {[llength $missing_lib] != 0} {
        skd-write "lib-install $missing_lib"
        return 1
    } else {
        # hide toplevel window. Use wm deiconify to restore later
        wm withdraw .
        return 0
    }
}


# This is blocking procedure to be run from command line
# ruturn 1 on success, 0 otherwise
# Print to stderr for user-visible messages. Use log for detailed info written to log file
proc main-generate-keys {} {
    log Generating RSA keys
    set privkey [file normalize ~/.sku/keys/client_private.pem]
    if {[file exists $privkey]} {
        log RSA key $privkey already exists
    } else {
        if {![generate-rsa $privkey]} {
            return 0
        }
    }
    set csr [file normalize ~/.sku/keys/client.csr]
    if {[file exists $csr]} {
        log CSR $csr already exists
    } else {
        set cn [generate-cn]
        if {![generate-csr $privkey $csr $cn]} {
            return 0
        }
    }


    # Now try to POST csr and save cert
    #set csrdata [slurp $csr]
    for {set i 0} {$i<[llength [state sku vigos]]} {incr i} {
        if {[catch {open $csr r} fd err]} {
            log "Failed to open $csr for reading"
            log $err
        }
        set next [expr {[state sku vigo_next] + $i}]
        set vigo [lindex [state sku vigos] $next]
        puts -nonewline stderr "Trying vigo $next...\t"
        #TODO expected-hostname should not be needed - ensure that vigo provides proper certificate with IP common name
        if {[catch {https curl https://$vigo:10443/sign-cert -timeout 8000 -method POST -type text/plain -querychannel $fd -expected-hostname www.securitykiss.com} crtdata err]} {
            puts stderr FAILED
            log $err
            close $fd
        } else {
            puts stderr OK
            puts stderr "Received the signed certificate"
            log crtdata: $crtdata
            spit [file normalize ~/.sku/keys/client.crt] $crtdata
            state sku {vigo_next $next}
            close $fd
            break
        }
    }
    return 1
}


#TODO generate from HD UUID/dbus machine-id and add sha256 for checksum/proof of work
proc generate-cn {} {
    return [join [lmap i [seq 8] {rand-byte-hex}] ""]
}

proc main-version {} {
    log SKU Version:
    #TODO
}

proc main-cli {} {
    log Running CLI
    #TODO
}

proc main-gui {} {
    log Running GUI

    package require Tk 
    package require Tkhtml

    wm deiconify .
    wm protocol . WM_DELETE_WINDOW {
        #TODO improve the message
        if {[tk_messageBox -message "Quit?" -type yesno] eq "yes"} {
            main-exit
        }
    }

    set clientNo [get-client-no OpenVPN/config/client.crt]

    #TODO remove caching
    if 0 {
    set url "https://www.securitykiss.com/sk/app/display.php?c=$clientNo&v=0.3.0"
    set ncode [curl $url welcome]
    if {$ncode != 200} {
        error "Could not retrieve ($url). HTTP code: $ncode"
    }
    spit display.htm $welcome
    } else {
        set welcome [slurp display.htm]
    }
    
    #TODO remove caching
    if 0 {
    set url "https://www.securitykiss.com/sk/app/usage.php?c=$clientNo"
    set ncode [curl $url usage]
    if {$ncode != 200} {
        error "Could not retrieve ($url). HTTP code: $ncode"
    }
    spit usage.htm $usage
    } else {
        set usage [slurp usage.htm]
    }
 
    
    set serverlist [get-server-list $welcome]
    set ::serverdesc [lindex $serverlist 0]
    set ::status "Not connected"
    
    set config [get-ovpn-config $welcome]
    spit config.ovpn $config
    
    ttk::label .p1 -text $clientNo
    grid .p1 -pady 5
    html .p2 -shrink 1
    .p2 parse -final $usage
    grid .p2
    ttk::frame .p3
    ttk::button .p3.connect -text Connect -command ClickConnect
    ttk::button .p3.disconnect -text Disconnect -command ClickDisconnect
    ttk::combobox .p3.combo -width 35 -textvariable ::serverdesc
    .p3.combo configure -values $serverlist
    .p3.combo state readonly
    grid .p3.connect .p3.disconnect .p3.combo -padx 10 -pady 10
    grid .p3
    ttk::label .p4 -textvariable ::status
    grid .p4 -sticky w -padx 5 -pady 5
    
    
    set ::conf [::ovconf::parse config.ovpn]
    
    after idle ReceiveWelcome
}


proc ReceiveWelcome {{tok ""}} {
    # Unfortunately http is catching callback errors and they don't propagate to our background-error, so we need to catch them all here and log
    if {[catch {
        set vigo_next [state sku vigo_next]
    
        if {$tok ne ""} {
            set ncode [http::ncode $tok]
            set status [http::status $tok]
            set data [http::data $tok]
            if {$status eq "ok" && $ncode == 200} {
                tk_messageBox -message "Welcome received: $data" -type ok
                puts "welcome: $data"
                return
            } else {
                # if request failed increment and save next candidate vigo index
                upvar #0 $tok state
                log Request $state(url) failed
                set vigo_next [expr {($vigo_next + 1) % [llength [state sku vigos]]}]
                state sku {vigo_next $vigo_next}
            }
            http::cleanup $tok
        } else {
            # reset retry counter when called initially
            state sku {welcome_retry 1}
        }
     
        # We are here only if welcome request did not succeed yet
        # Try again if max retries not exceeded
        if {[state sku welcome_retry] < [llength [state sku vigos]]} {
            set vigo [lindex [state sku vigos] [state sku vigo_next]]
            https curl https://$vigo:10443/welcome?cn=2345 -timeout 8000 -expected-hostname www.securitykiss.com -command ReceiveWelcome
            state sku {welcome_retry [incr welcome_retry]}
        } else {
            # ReceiveWelcome failed for all vigos   
            tk_messageBox -message "Could not receive Welcome message" -type ok
        }
    } out err]} {
        error $err
    }
}




proc skd-connect {port} {
    #TODO handle error
    if {[catch {set sock [socket 127.0.0.1 $port]} out err]} {
        skd-close $err
    }
    state sku {skd_sock $sock}
    chan configure $sock -blocking 0 -buffering line
    chan event $sock readable skd-read
}


proc skd-write {msg} {
    if {[catch {puts [state sku skd_sock] $msg} out err]} {
        skd-close $err
    }
}

proc skd-close {err} {
    catch {close [state sku skd_sock]}
    fatal "Could not communicate with SKD. Please check if skd service is running and check logs in /var/log/skd.log" $err
}


#TODO detect disconnecting from SKD - sock monitoring?
proc skd-read {} {
    set sock [state sku skd_sock]
    if {[gets $sock line] < 0} {
        if {[eof $sock]} {
            skd-close "skd_sock EOF. Connection terminated"
        }
        return
    }
    switch -regexp -matchvar tokens $line {
        {^ctrl: (.*)$} {
            switch -regexp -matchvar details [lindex $tokens 1] {
                {^Welcome to SKD} {
                    if {$::tcl_platform(platform) eq "windows"} {
                        #set conf [::ovconf::parse {c:\temp\Warsaw_195_162_24_220_tcp_443.ovpn}]
                        #set conf [::ovconf::parse {c:\temp\securitykiss_winopenvpn_client00000001\openvpn.conf}]
                        #set conf [::ovconf::parse config.ovpn]
                    } else {
                        #set conf [::ovconf::parse /home/sk/openvpn/Lodz_193_107_90_205_tcp_443.ovpn]
                        #set conf [::ovconf::parse /home/sk/openvpn/securitykiss_winopenvpn_client00000001/openvpn.conf]
                        #set conf [::ovconf::parse config.ovpn]
                    }
                    #skd-write "config $conf"
                }
                {^Config loaded} {
                    skd-write start
                }
                {^pkg-install ended with result} {
                    after idle main-start
                }

            }
        }
        {^ovpn: (.*)$} {
            set ::status [lindex $tokens 0]
        }
        {^pkg: (.*)$} {
            #TODO can we parse pkg-mgr output to see success/failure? Aren't messages i18ned?


        }

    }
    log SKD>> $line
}

# Extract server list from welcome message
# Return multi-line string with each line representing a server like:
# LosAngeles 23.19.26.250 UDP 123
proc get-server-list {s} {
    set res {}
    set lines [split $s \n]
    foreach l $lines {
        if {[string first "<!-- " $l] != 0} {
            continue
        }
        set l [join [lrange $l 1 end-1]]
        if {[string first "#remote" $l] == 0} {
            set tokens [split $l ,]
            set serv [join [lindex $tokens 2] ""]
            append serv " "
            append serv [join [lrange $tokens 3 4]]
            append serv " "
            append serv [lindex [lindex $tokens 5] 1]
            lappend res $serv
        }
    }
    return $res
}

proc get-ovpn-config {s} {
    set res {}
    set lines [split $s \n]
    foreach l $lines {
        if {[string first "<!-- " $l] != 0} {
            continue
        }
        set l [join [lrange $l 1 end-1]]
        if {[string first "#" $l] == 0} {
            continue
        }
        if {[string first "SecurityKISS" $l] == 0} {
            continue
        }
        if {[string first "proto" $l] == 0} {
            continue
        }
        if {[string first "remote" $l] == 0} {
            continue
        }
        lappend res $l
    }
    return [join $res \n]
}

proc get-client-no {crtpath} {
    set crt [slurp $crtpath]
    regexp {CN=(client\d{8})} $crt _ cn
    return $cn
}



#proc curl {url data_var} {
#    upvar $data_var data
#    set tok [http::geturl $url]
#    set ncode [http::ncode $tok]
#    set data [http::data $tok]
#    http::cleanup $tok
#    return $ncode
#}
 

proc ClickConnect {} {
    set localconf $::conf
    set ip [lindex $::serverdesc 1]
    set proto [lindex $::serverdesc 2]
    set port [lindex $::serverdesc 3]
    append localconf "--proto $proto --remote $ip $port"
    skd-write "config $localconf"
}

proc ClickDisconnect {} {
    skd-write stop
}

proc check-for-upgrades {} {
    # TODO check and save latest version with signature
}


# SKD only to verify signature and run executable
# the rest in SKU
proc upgrade {} {
    # check latest version and checksum
    # compare to current version
    # check if downloaded
    # download if necessary / wget
}


main

vwait ::until_exit
