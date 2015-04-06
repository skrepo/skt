#/usr/bin/env tclsh
package provide ovconf 0.0.0


#   ovconf package: canonical representation is "--opt val" string, parse (from multiline), get $opt, set $opt $val, del $opt, extract , save, zip, unzip 

namespace eval ::ovconf {
    namespace export parse get set
    namespace ensemble create
}

proc ::ovconf::ddash {key} {
    if {[string first "--" $key] == 0} {
        return $key
    } else {
        return --$key
    }
}
    

# get <openvpn_config_string> <option_name/key>
# <option_name/key> may contain optional "--" prefix
# Return list of values. Values can also be lists
proc ::ovconf::get {conf key} {
    set res {}
    set key [::ovconf::ddash $key]
    set ki [lsearch -exact -all $conf $key]
    foreach i $ki {
        # following --option index
        set fi [lsearch -glob -start [expr {$i+1}] $conf --*]
        if {$fi == -1} {
            set endi end
        } else {
            set endi [expr {$fi-1}]
        }
        lappend res [lrange $conf [expr {$i+1}] $endi]
    }
    return $res
}

proc ::ovconf::del {conf key {value {}}} {

}


proc ::ovconf::set {conf key value} {

}

# add only makes sense when value is nonempty, so value is mandatory
proc ::ovconf::add {conf key value} {
    lappend conf [::ovconf::ddash $key]
    lappend conf {*}$value
    return $conf
}

proc ::ovconf::parse {mconf} {
}


set c {--client --pull --dev tun --proto tcp --remote 46.165.208.40 443 --resolv-retry infinite --remote 1.2.3.4 9876 --nobind --persist-key --persist-tun --mute-replay-warnings --ca ca.crt --cert client.crt --key client.key --ns-cert-type server --comp-lzo --verb 3 --keepalive 5 28 --route-delay 3 --management localhost 8888}

puts [::ovconf::get $c remote]
puts [::ovconf::get $c management]
puts [::ovconf::get $c proto]
puts [::ovconf::get $c client]
puts [::ovconf::get $c blabla]

puts "llengths"
puts [llength [::ovconf::get $c --remote]]
puts [llength [::ovconf::get $c --management]]
puts [llength [::ovconf::get $c --proto]]
puts [llength [::ovconf::get $c --client]]
puts [llength [::ovconf::get $c --blabla]]
