#
# sku.tcl
#
# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
}

#TODO change user to non-root when run with sudo in order to not create files owned by root


proc background-error {msg e} {
    set pref [lindex [info level 0] 0]
    puts "$pref: $msg"
    dict for {k v} $e {
        puts "$pref: $k: $v"
    }
}

interp bgerror "" background-error
#after 2000 {error "This is my bg error"}


package require skutil
package require ovconf
package require tls
package require http
package require cmdline
package require unix
package require linuxdeps
http::register https 443 [list tls::socket]

state sku {
    # SKD connection socket 
    skd_sock ""
    # User Interface (gui or cli)
    ui ""
    # Start retries
    start_retries 0
}


# Parse command line options and launch proper task
# It may set global variables
proc main {} {
    # watch out - cmdline is buggy. For example you cannot define help option, it conflicts with the implicit one
    puts "argv1: $::argv"
    set options {
            {cli            "Run command line interface (CLI) instead of GUI"}
            {generate-keys  "Generate private key and certificate signing request"}
            {version        "Print version"}
            {p              "Print anything"}
            {ra             "Print anything"}
        }
    set usage ": sku \[options]\noptions:"
    if {[catch {array set params [::cmdline::getoptions ::argv $options $usage]}]} {
        puts [cmdline::usage $options $usage]
        exit 1
    }
    parray params
    puts "argv2: $::argv"

    if {$params(generate-keys)} {
        unix relinquish-root
        main-generate-keys
        exit
    }
    if {$params(version)} {
        unix relinquish-root
        main-version
        exit
    }

    unix relinquish-root
    if {$params(cli) || ![unix is-x-running]} {
        state sku {ui cli}
    } else {
        state sku {ui gui}
    }
    set sock [SkConnect 7777]
    #TODO handle SKD connection error here - display emergency Tk dialog or cli to inform user about SKD service not running
    #in-ui error
    puts "Before main-start"
    after idle main-start
    puts "After main-start"
}

# it may be called many times by events retrying to start after lib install
proc main-start {} {

    set retries [state sku start_retries]
    state sku {start_retries [incr retries]}
    puts "start_retries: [state sku start_retries]"
    # give up after a number of retries
    if {$retries > 5} {
        in-ui error "Could not main-start after a number of retries"
        return
    }

    puts "RUNNING: check-openvpn-deps"
    # Ignore result of openvpn install - it may be handled later, when GUI is running
    # TODO save openvpn install result in state - user to be informed
    check-openvpn-deps

    if {[state sku ui] eq "gui"} {
        puts "RUNNING: check-tk-deps"
        # if no missing libs start UI
        if {![check-tk-deps]} {
            in-ui main
        }
    }
}

# Combine $fun and $ui to run proper procedure in gui or cli
proc in-ui {fun args} {
    set ui [state sku ui]
    puts "in-ui args: $args"
    if {[llength $args] == 0} {
        [join [list $fun $ui] -]
    } else {
        [join [list $fun $ui] -] {*}args
    }
}


proc error-gui {msg} {
    # if Tk not functional downgrade displaying errors to cli
    if {[is-tk-loaded]} {
        #TODO displaying GUI errors
        tk_messageBox -message $msg -type ok -icon error
    } else {
        error-cli $msg
    }
}

proc error-cli {msg} {
    puts stderr $msg
}


# Check if openvpn is installed. 
# If not send pkg-install request to SKD
# Return 1 if request sent, 0 otherwise
proc check-openvpn-deps {} {
    #TODO handle return messages from SKD
    if {![linuxdeps is-openvpn-installed]} {
        puts [state sku skd_sock] "pkg-install openvpn"
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
    puts $missing_lib
    if {[llength $missing_lib] != 0} {
        puts [state sku skd_sock] "lib-install $missing_lib"
        return 1
    } else {
        return 0
    }
}

proc main-generate-keys {} {
    puts "Generating keys"
}
proc main-version {} {
    puts "SKU Version: "
}
proc main-cli {} {
    puts "Running CLI"
}

proc main-gui {} {
    puts "Running GUI"

    package require Tk 
    package require Tkhtml

    set clientNo [get-client-no OpenVPN/config/client.crt]
    set url "https://www.securitykiss.com/sk/app/display.php?c=$clientNo&v=0.3.0"
    set ncode [curl $url welcome]
    if {$ncode != 200} {
        error "Could not retrieve ($url). HTTP code: $ncode"
    }
    #puts $welcome
    
    set url "https://www.securitykiss.com/sk/app/usage.php?c=$clientNo"
    set ncode [curl $url usage]
    if {$ncode != 200} {
        error "Could not retrieve ($url). HTTP code: $ncode"
    }
    
    set serverlist [get-server-list $welcome]
    set ::serverdesc [lindex $serverlist 0]
    set ::status "Not connected"
    
    set config [get-ovpn-config $welcome]
    set fp [open config.ovpn w]
    puts $fp $config
    close $fp
    
    
    
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
    

}

proc SkConnect {port} {
    #TODO handle error
    set sock [socket 127.0.0.1 $port]
    chan configure $sock -blocking 0 -buffering line
    chan event $sock readable [list SkRead $sock]
    state sku {skd_sock $sock}
    return $sock
}


#TODO detect disconnecting from SKD - sock monitoring?

proc SkRead {sock} {
    if {[gets $sock line] < 0} {
        if {[eof $sock]} {
            catch {close $sock}
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
                    #catch {puts $sock "config $conf"}
                }
                {^Config loaded} {
                    catch {puts $sock start}
                }
                {^pkg-install ended with result} {
                    after idle main-start
                }

            }
        }
        {^ovpn: (.*)$} {
            # Strip date from ovpn logs to display in status line
            set ::status [join [lrange [lindex $tokens 0] 6 end]]
        }
        {^pkg: (.*)$} {
            #TODO can we parse pkg-mgr output to see success/failure? Aren't messages i18ned?


        }

    }
    puts ">>$line"

}

proc get-server-list {s} {
    set res {}
    set lines [split $s \n]
    #puts [llength $lines]
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
    #puts [join $res \n]
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



proc curl {url data_var} {
    upvar $data_var data
    set tok [http::geturl $url]
    set ncode [http::ncode $tok]
    set data [http::data $tok]
    http::cleanup $tok
    return $ncode
}
 

proc ClickConnect {} {
    set localconf $::conf
    set ip [lindex $::serverdesc 1]
    set proto [lindex $::serverdesc 2]
    set port [lindex $::serverdesc 3]
    append localconf "--proto $proto --remote $ip $port"
    puts [state sku skd_sock] "config $localconf"
}

proc ClickDisconnect {} {
    puts [state sku skd_sock] "stop"
}


main
vwait forever
