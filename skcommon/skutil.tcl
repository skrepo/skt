package provide skutil 0.0.0

# Keep application state in global nested dictionary called ::state
# If the last argument is a list, the list should be key value pairs 
# to set in ::state under the path described by previous arguments
# If the last argument is a word, return value in ::state under the path
# described by all arguments
proc state {args} {
    # all-but-last args describe the path in nested dictionary
    set path [lrange $args 0 end-1]
    # last arg is key-value list
    set kv [lindex $args end]
    # variable, command and backslash substitution
    # upleveled - must be done in caller context
    set kv [uplevel [list subst $kv]]
    # remove comments and before-comment semicolons
    regsub -all ";*#\[^\n\]*\n" $kv "" kv
    # convert to canonical form - get rid of redundant spaces
    set kv [list {*}$kv]
    if {[llength $kv] == 1} {
        # now kv is the single key
        return [dict get $::state {*}$path $kv]
    }
    if {[llength $kv] % 2 == 1} {
        error "Missing value for key '[lindex $kv end]' in state definition"
    }
    foreach {k v} $kv {
        dict set ::state {*}$path $k $v
    }
    return $::state
}

proc ParseIp {s} {
    if {[regexp {^\d+\.\d+\.\d+\.\d+$} $s]
        && [scan $s %d.%d.%d.%d a b c d] == 4
        && 0 <= $a && $a <= 255 && 0 <= $b && $b <= 255
        && 0 <= $c && $c <= 255 && 0 <= $d && $d <= 255} {
        return [list $a $b $c $d]
    } else {
        return {}
    }
}

proc IsValidIp {s} {
    set parsed [ParseIp $s]
    return [expr {$parsed ne ""}]
}


