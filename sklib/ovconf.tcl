#/usr/bin/env tclsh
package provide ovconf 0.0.0


# Manipulating OpenVPN configuration string
# ovconf canonical representation is a string of "--key val" pairs where val may be empty or multi-word string
# Example:
# --client --pull --dev tun --proto tcp --remote 11.22.33.44 9999 --resolv-retry infinite --nobind --persist-key --persist-tun --mute-replay-warnings --ca ca.crt --cert client.crt --key client.key --ns-cert-type server --comp-lzo --verb 3 --keepalive 5 28 --route-delay 3 --management localhost 8888

# parse (from multiline), get $opt, set $opt $val, del $opt, extract , save, zip, unzip 

namespace eval ::ovconf {
    variable win_specific_opts {ip-win32 route-method dhcp-option tap-sleep show-net-up dhcp-renew dhcp-release pause-exit service show-adapters show-valid-subnets show-net}
    variable deprecated_opts {win-sys}
    namespace export *
    namespace ensemble create
}

# Prepend with double dash if not present
proc ::ovconf::ddash {key} {
    if {[string first "--" $key] == 0} {
        return $key
    } else {
        return --$key
    }
}
 
# return index of first key with matching value if given
# or index of first key with any value (including none) if value not given
proc ::ovconf::index {conf key {value ""}} {
    ::set key [::ovconf::ddash $key]
    ::set i [lsearch -exact $conf $key]
    while {$i != -1} {
        # following --option index
        ::set fi [lsearch -glob -start [expr {$i+1}] $conf --*]
        if {$fi == -1} {
            ::set endi end
        } else {
            ::set endi [expr {$fi-1}]
        }
        ::set v [lrange $conf [expr {$i+1}] $endi]
        if {$value eq "" || $value eq $v} {
            return $i
        } else {
            ::set i [lsearch -exact -start [expr {$i+1}] $conf $key]
        }
    }
    return -1
}


# <option_name/key> may contain optional "--" prefix
# Return list of values. Multi-word values are represented as nested lists.
proc ::ovconf::get {conf key} {
    ::set res ""
    ::set key [::ovconf::ddash $key]
    ::set ki [lsearch -exact -all $conf $key]
    foreach i $ki {
        # following --option index
        ::set fi [lsearch -glob -start [expr {$i+1}] $conf --*]
        if {$fi == -1} {
            ::set endi end
        } else {
            ::set endi [expr {$fi-1}]
        }
        lappend res [lrange $conf [expr {$i+1}] $endi]
    }
    return $res
}

# return copy of $conf with given $key/$value deleted
# If $value not given delete $key/$value regardless of value
proc ::ovconf::del {conf key {value ""}} {
    ::set key [::ovconf::ddash $key]
    ::set i [::ovconf::index $conf $key $value]
    while {$i != -1} {
         # following --option index
        ::set fi [lsearch -glob -start [expr {$i+1}] $conf --*]
        if {$fi == -1} {
            ::set endi end
        } else {
            ::set endi [expr {$fi-1}]
        }
        ::set conf [lreplace $conf $i $endi]
        ::set i [::ovconf::index $conf $key $value]
    }
    return $conf
}


proc ::ovconf::set {conf key {value ""}} {
    ::set key [::ovconf::ddash $key]
    # save current index of first key...
    ::set i [::ovconf::index $conf $key]
    if {$i == -1} {
        ::set i end
    }
    ::set conf [::ovconf::del $conf $key]
    # ...in order to insert new value without changing order
    return [linsert $conf $i $key {*}$value]
}

# add only makes sense when value is nonempty (otherwise use set), so value is mandatory
proc ::ovconf::add {conf key value} {
    lappend conf [::ovconf::ddash $key]
    lappend conf {*}$value
    return $conf
}

proc ::ovconf::strip-comments {s_var {comment_chars "#"}} {
    upvar $s_var s
    # Switch the RE engine into line-respecting mode instead of the default whole-string mode
    regsub -all -line "\[$comment_chars\].*$" $s "" temp
    # Now strip the whitespace
    regsub -all -line {^(.*\S)?[ \t\r]*$} $temp {\1} s
}



#TODO test it on Windows with \r\n
proc ::ovconf::strip-headtail-blank-lines {s_var} {
    upvar $s_var s
    regsub -all {^\s*\n+} $s "" s
    regsub -all {\s*\n+$} $s "" s
}

#TODO test it on Windows with \r\n
proc ::ovconf::strip-blank-lines {s_var} {
    upvar $s_var s
    regsub -all {\s*\n(\s*\n)+} $s "\n" s
    ::ovconf::strip-headtail-blank-lines s
}




# For config with inline certificates, extract <$tag></$tag> section 
# and save in created directory with the _key suffix
# Return path to created section file
# Delete that section from given config variable and add proper tag option with path as value
proc ::ovconf::csection {config_var filepath tag} {
    upvar $config_var config
    ::set path ""
    ::set istart [string first "<$tag>" $config]
    ::set iend [string first "</$tag>" $config]
    if {$istart != -1 && $iend != -1 && $istart < $iend} {
        ::set section [string range $config [expr {$istart+[string length "<$tag>"]}] [expr {$iend-1}]]
        ::ovconf::strip-headtail-blank-lines section
        ::set keydir [file join [file dirname $filepath] [file rootname $filepath]_keys]
        file mkdir $keydir
        ::set path [file join $keydir $tag]
        ::set fp [open $path w]
        puts -nonewline $fp $section
        ::set config [string replace $config $istart [expr {$iend+[string length "</$tag"]}]]
        append config "$tag \"$path\"\n"
        close $fp
    }
    return $path
}


proc lfilter {x l body} {
    upvar $x localx
    lmap localx $l {
        ::set pred [uplevel $body]
        if {$pred} {
            ::set localx
        } else {
            continue
        }
    }
}


# Parse config file
# If inline certs and keys, create directory and extract them to separate files and adjust config entries
proc ::ovconf::parse {config_file} {
    ::set config_file [file normalize $config_file]
    ::set fp [open $config_file r]
    ::set config [read $fp]
    close $fp
    ::ovconf::strip-comments config
    # first try to extract inline cert sections
    ::set snames {dh extra-certs pkcs12 secret tls-auth ca cert key}
    ::set paths [lmap sn $snames {
        ::ovconf::csection config $config_file $sn
    }]
    ::set paths [lfilter path $paths {
        expr {$path ne ""}
    }]
    ::ovconf::strip-blank-lines config
    # if has inline sections
    if {[llength $paths] > 0} {
        # save also config
        ::set fname [file join [file dirname [lindex $paths 0]] config]
        ::set fp [open $fname w]
        puts -nonewline $fp $config
        close $fp
    }
    # convert config to dashed one-line format
    regsub -all -line {^} $config "--" config
    regsub -all {\n} $config " " config

    # convert relative paths to absolute
    foreach sn $snames {
        ::set sv [::ovconf::get $config $sn]
        if {$sv ne "" && [file pathtype $sv] ne "absolute"} {
            ::set abs [file join [file dirname $config_file] $sv]
            ::set config [::ovconf::set $config $sn [file normalize $abs]]
        }
    }
    return $config
}

# Check if cert file paths exist
proc ::ovconf::check-paths-exist {conf} {
    ::set keys {dh extra-certs pkcs12 secret tls-auth ca cert key}
    foreach k $keys {
        ::set v [::ovconf::get $conf $k]
        if {$v ne "" && ![file isfile $v]} {
            return "The $k file $v does not exist"
        }
    }
    return ""
}

proc ::ovconf::del-win-specific {conf} {
    variable win_specific_opts
    foreach k $win_specific_opts {
        ::set conf [::ovconf::del $conf $k]
    }
    return $conf
}

proc ::ovconf::del-deprecated {conf} {
    variable deprecated_opts
    foreach k $deprecated_opts {
        ::set conf [::ovconf::del $conf $k]
    }
    return $conf
}


proc ::ovconf::del-meta {conf} {
    return [::ovconf::del $conf --meta]
}


if 0 {
::set c {--client --pull --dev tun --proto tcp --remote 46.165.208.40 443 --resolv-retry infinite --remote 1.2.3.4 9876 --nobind --persist-key --persist-tun --mute-replay-warnings --ca ca.crt --cert client.crt --key client.key --ns-cert-type server --comp-lzo --verb 3 --keepalive 5 28 --route-delay 3 --management localhost 8888}

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

puts "del"
puts "orig:"
puts "$c"
puts [::ovconf::del $c dev]
puts [::ovconf::del $c nobind]
puts [::ovconf::del $c --remote "46.165.208.40 443"]
puts [::ovconf::del $c --remote "1.2.3.4 9876"]
puts [::ovconf::del $c --remote]
puts [::ovconf::del $c --remote blabla]

puts [::ovconf::index $c --remote "46.165.208.40 443"]
puts [::ovconf::index $c --remote "1.2.3.4 9876"]
puts [::ovconf::index $c --remote]
puts [::ovconf::index $c --remote "blabla"]

puts "orig2:"
puts "$c"
puts [::ovconf::set $c remote "5.5.5.5 9999"]
puts [::ovconf::set $c dev tap]
puts [::ovconf::set $c dev]
puts [::ovconf::set $c blabla]

puts [::ovconf::parse /home/sk/openvpn/Lodz_193_107_90_205_tcp_443.ovpn]

}

