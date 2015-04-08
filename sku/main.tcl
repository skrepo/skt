#
# sku.tcl
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


package require skutil
package require ovconf

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
            #set conf [::ovconf::parse /home/sk/openvpn/Lodz_193_107_90_205_tcp_443.ovpn]
            set conf [::ovconf::parse /home/sk/openvpn/securitykiss_winopenvpn_client00000001/openvpn.conf]
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

