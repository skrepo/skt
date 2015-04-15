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
package require Tk 
package require Tkhtml
package require tls
package require http
http::register https 443 [list tls::socket]


#TODO move to sklib
proc slurp {path} {
    set fd [open $path r]
    set data [read $fd]
    close $fd
    return $data
}



proc SkConnect {port} {
    #TODO handle error
    set sock [socket 127.0.0.1 $port]
    chan configure $sock -blocking 0 -buffering line
    chan event $sock readable [list SkRead $sock]
    state skd {sock $sock}
    return $sock
}

proc SkRead {sock} {
    if {[gets $sock line] < 0} {
        if {[eof $sock]} {
            catch {close $sock}
        }
        return
    }
    switch -regexp -matchvar tokens $line {
        {Welcome to SKD} {
            if {$::tcl_platform(platform) eq "windows"} {
                #set conf [::ovconf::parse {c:\temp\Warsaw_195_162_24_220_tcp_443.ovpn}]
                #set conf [::ovconf::parse {c:\temp\securitykiss_winopenvpn_client00000001\openvpn.conf}]
                #set conf [::ovconf::parse config.ovpn]
            } else {
                #set conf [::ovconf::parse /home/sk/openvpn/Lodz_193_107_90_205_tcp_443.ovpn]
                #set conf [::ovconf::parse /home/sk/openvpn/securitykiss_winopenvpn_client00000001/openvpn.conf]
                #set conf [::ovconf::parse config.ovpn]
            }
            catch {puts $sock "config $conf"}
        }
        {Config loaded} {
            catch {puts $sock start}
        }
        {^ovpn:(.*)} {
            set ::status [join [lrange [lindex $tokens 0] 6 end]]
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
set serverdesc [lindex $serverlist 0]
set status "Not connected"

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
ttk::combobox .p3.combo -width 35 -textvariable serverdesc
.p3.combo configure -values $serverlist
.p3.combo state readonly
grid .p3.connect .p3.disconnect .p3.combo -padx 10 -pady 10
grid .p3
ttk::label .p4 -textvariable status
grid .p4 -sticky w -padx 5 -pady 5


set sock [SkConnect 7777]
set conf [::ovconf::parse config.ovpn]

proc ClickConnect {} {
    set localconf $::conf
    set ip [lindex $::serverdesc 1]
    set proto [lindex $::serverdesc 2]
    set port [lindex $::serverdesc 3]
    append localconf "--proto $proto --remote $ip $port"
    puts $::sock "config $localconf"
}

proc ClickDisconnect {} {
    puts $::sock "stop"
}
