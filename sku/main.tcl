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

package require skutil

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
            catch {puts $sock {config --client --pull --dev tun --proto tcp --remote 46.165.208.40 443 --resolv-retry infinite --nobind --persist-key --persist-tun --mute-replay-warnings --ca ca.crt --cert client.crt --key client.key --ns-cert-type server --comp-lzo --verb 3 --keepalive 5 28 --route-delay 3 --management localhost 8888}}
        }
        {Config loaded} {
            catch {puts $sock start}
        }

    }
    puts ">>$line"

}

set sock [SkConnect 7777]

vwait forever

