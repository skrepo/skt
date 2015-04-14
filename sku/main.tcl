#
# sku.tcl
#
# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
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


package require skutil
package require ovconf
package require Tk 
package require Tkhtml
package require tls
package require http
http::register https 443 [list tls::socket]




proc curl {url data_var} {
    upvar $data_var data
    set tok [http::geturl $url]
    set ncode [http::ncode $tok]
    set data [http::data $tok]
    http::cleanup $tok
    return $ncode
}
 

set url "https://www.securitykiss.com/sk/app/display.php?c=client00000001&v=0.3.0"
set ncode [curl $url welcome]
if {$ncode != 200} {
    error "Could not retrieve ($url). HTTP code: $ncode"
}
puts $welcome

set url "https://www.securitykiss.com/sk/app/usage.php?c=client00000001"
set ncode [curl $url usage]
if {$ncode != 200} {
    error "Could not retrieve ($url). HTTP code: $ncode"
}


# Create and populate an html widget.
  html .p1 -shrink 1
  .p1 parse -final $welcome
  grid .p1
  html .p2 -shrink 1
  .p2 parse -final $usage
  grid .p2
  frame .p3
  button .p3.connect -text Connect
  button .p3.disconnect -text Disconnect
  grid .p3.connect .p3.disconnect -ipadx 5 -ipady 5 -padx 10 -pady 10
  grid .p3
  label .p4 -text Status
  grid .p4 -sticky w -padx 5 -pady 5



vwait forever


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
                set conf [::ovconf::parse {c:\temp\securitykiss_winopenvpn_client00000001\openvpn.conf}]
            } else {
                #set conf [::ovconf::parse /home/sk/openvpn/Lodz_193_107_90_205_tcp_443.ovpn]
                set conf [::ovconf::parse /home/sk/openvpn/securitykiss_winopenvpn_client00000001/openvpn.conf]
            }
            catch {puts $sock "config $conf"}
        }
        {Config loaded} {
            catch {puts $sock start}
        }

    }
    puts ">>$line"

}

set sock [SkConnect 7777]

vwait forever

